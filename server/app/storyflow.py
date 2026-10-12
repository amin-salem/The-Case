"""Story choices (docs/story-mode.md): pure functions over a chapter's scenes and a player's state.
The server decides which options exist; the client only shows them."""
from __future__ import annotations

from . import content
from .content import _as_list, story_scenes

RELATION_TEXT = {"unmet": "هنوز ندیده‌ای", "neutral": "بی‌طرف", "friendly": "با تو راحت است", "suspicious": "مشکوک به تو"}


_FA = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def new_state() -> dict:
    return {"scene": None, "chosen": [], "clues": [], "relations": {}, "done": False}


def _scene(flow: dict, scene_id: str) -> dict | None:
    return next((s for s in flow["scenes"] if s["id"] == scene_id), None)


def _held(state: dict, needs) -> bool:
    return all(c in state["clues"] for c in _as_list(needs))


def option_view(o: dict, state: dict, chapter: int) -> dict:
    locked = not _held(state, o.get("needs_clue"))
    out = {"id": o["id"], "title": o["title"], "sub": o.get("sub", ""), "locked": locked}
    if locked:
        out["reason"] = f"قفل است: به یک سرنخ از فصل {str(chapter).translate(_FA)} نیاز داری"
    return out


def scene_view(flow: dict, state: dict, chapter: int) -> dict:
    """The scene the player is in (or the ending once done), without any option's destination."""
    if state["done"]:
        e = flow["ending"]
        return {"id": e["id"], "text": e["text"], "speaker": e.get("speaker"), "options": [], "ending": True}
    s = _scene(flow, state["scene"])
    return {"id": s["id"], "text": s["text"], "speaker": s.get("speaker"), "ending": False,
            "options": [option_view(o, state, chapter) for o in s["options"]]}


def _obtainable(flow: dict, scene_id: str, memo: dict) -> set[str]:
    """Clues that some option from this scene onward can still give."""
    if scene_id in memo:
        return memo[scene_id]
    s = _scene(flow, scene_id)
    out: set[str] = set()
    if s is not None:
        for o in s["options"]:
            out |= set(_as_list(o.get("gives_clue")))
            out |= _obtainable(flow, o["goes_to"], memo)
    memo[scene_id] = out
    return out


def board_clues(d: dict, state: dict, flow: dict) -> list[dict]:
    """Every clue of the chapter: held (with text), still open (title hidden) or missed (title shown, gray)."""
    titles = {e["id"]: (e["title"], e.get("text", "")) for e in d["evidence"]}
    for c in flow["board"].get("clues", []):
        titles[c["id"]] = (c["title"], c.get("text", ""))
    order = [c["id"] for c in flow["board"].get("clues", [])] + [i for i in titles if i not in
             {c["id"] for c in flow["board"].get("clues", [])}]
    # only clues some option can give appear on the board (evidence the scenes never mention is not a choice clue)
    giveable = set()
    for s in flow["scenes"]:
        for o in s["options"]:
            giveable |= set(_as_list(o.get("gives_clue")))
    left = set() if state["done"] else _obtainable(flow, state["scene"], {})
    out = []
    for cid in order:
        if cid not in giveable:
            continue
        title, text = titles[cid]
        if cid in state["clues"]:
            out.append({"id": cid, "title": title, "text": text, "status": "held", "by_choice": True})
        elif cid in left:
            out.append({"id": cid, "title": None, "text": None, "status": "open", "by_choice": False})
        else:
            out.append({"id": cid, "title": title, "text": None, "status": "missed", "by_choice": False})
    return out


def board_people(flow: dict, state: dict) -> list[dict]:
    return [{"id": p["id"], "name": p["name"], "role": p.get("role", ""),
             "state": state["relations"].get(p["id"], "unmet"),
             "text": RELATION_TEXT[state["relations"].get(p["id"], "unmet")]}
            for p in flow["board"].get("people", [])]


def _longest(flow: dict, scene_id: str, memo: dict) -> int:
    """Number of scenes on the longest path from this scene (the ending is not counted)."""
    if scene_id not in memo:
        s = _scene(flow, scene_id)
        memo[scene_id] = 0 if s is None else 1 + max(_longest(flow, o["goes_to"], memo) for o in s["options"])
    return memo[scene_id]


def state_out(c: content.Case, state: dict) -> dict:
    flow = story_scenes(c.data)
    n = _longest(flow, flow["scenes"][0]["id"], {})
    idx = len(state["chosen"])
    return {"chapter_id": c.id, "chapter": c.number, "done": state["done"], "scene": scene_view(flow, state, c.number),
            "step": min(idx + 1, n), "total": n, "clues": list(state["clues"]),
            "relations": dict(state["relations"]), "board": {"people": board_people(flow, state),
                                                             "clues": board_clues(c.data, state, flow)}}


def apply_choice(c: content.Case, state: dict, scene_id: str, option_id: str):
    """(new_state, None) or (None, error_code). Idempotent repeats are handled by the caller."""
    flow = story_scenes(c.data)
    if state["done"] or state["scene"] != scene_id:
        return None, "wrong_scene"
    s = _scene(flow, scene_id)
    o = next((x for x in s["options"] if x["id"] == option_id), None) if s else None
    if o is None:
        return None, "no_option"
    if not _held(state, o.get("needs_clue")):
        return None, "locked"
    if len(state["chosen"]) >= content.MAX_CHOICES:
        return None, "too_many_choices"
    new = {"scene": state["scene"], "chosen": [*state["chosen"], [scene_id, option_id]],
           "clues": list(state["clues"]), "relations": dict(state["relations"]), "done": False}
    for cl in _as_list(o.get("gives_clue")):
        if cl not in new["clues"]:
            new["clues"].append(cl)
    new["relations"].update(o.get("relations") or {})
    if o["goes_to"] == flow["ending"]["id"]:
        new["done"] = True
    else:
        new["scene"] = o["goes_to"]
    return new, None
