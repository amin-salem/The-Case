"""Check one or more case files the way CI would, and write the PUBLIC copy for the blind test.

    python3 server/tools/check_case.py c071 c072                 # nightly cases
    python3 server/tools/check_case.py w008                      # a weekend case (validate_weekly + format 3)
    python3 server/tools/check_case.py c071 --public /tmp/blind  # also write /tmp/blind/c071_public.json (no hints, no solution)
    python3 server/tools/check_case.py w008 --public /tmp/blind --day1      # the day-1-only copy (no newcomer, no day-2 cards)
    python3 server/tools/check_case.py w008 --public /tmp/blind --reactions # keep the suspects' `reactions` in the public copy

Runs on a machine without the server dependencies (a tiny stand-in for `pydantic_settings` is installed when it is missing).
CI (`server`, `server-postgres`) stays the final judge; this is the fast local check a writer runs after every edit.
Exit code 1 when anything fails. It prints the problems; it never edits a case.
"""
from __future__ import annotations

import json
import sys
import types
from collections import Counter
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))

try:  # the server settings are not needed to validate a case
    import pydantic_settings  # noqa: F401
except ModuleNotFoundError:
    stub = types.ModuleType("pydantic_settings")

    class _BaseSettings:
        def __init__(self, **kw):
            pass

    stub.BaseSettings = _BaseSettings
    stub.SettingsConfigDict = lambda **kw: dict(kw)
    sys.modules["pydantic_settings"] = stub

from app import content  # noqa: E402

CONTENT = ROOT / "server" / "app" / "content"
SECRET = ("hints", "solution", "night1")
TITLES = {"دکتر", "مهندس", "سرهنگ", "سرگرد", "سروان", "استاد", "حاج", "حاجی", "سردار", "خانم", "آقای", "پروفسور", "دکترِ"}


def name_parts(name: str) -> list[str]:
    """First name and surname words of a suspect name, without a leading title (دکتر, مهندس, ...)."""
    parts = name.split()
    while len(parts) > 1 and parts[0] in TITLES:
        parts = parts[1:]
    return parts



def _path(cid: str) -> Path:
    folder = "intro" if cid.startswith("intro") else ("weekly" if cid.startswith("w") else "cases")
    return CONTENT / folder / f"{cid}.json"


def _others(cid: str):
    for f in sorted([*(CONTENT / "cases").glob("c*.json"), *(CONTENT / "weekly").glob("w*.json")]):
        if f.stem != cid:
            yield json.loads(f.read_text(encoding="utf-8"))


def check(cid: str) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []
    path = _path(cid)
    if not path.exists():
        return [f"{path} does not exist"], notes
    d = json.loads(path.read_text(encoding="utf-8"))
    weekend = cid.startswith("w")
    try:
        (content.validate_weekly if weekend else content.validate)(d)
    except Exception as e:  # CaseError and anything the validator trips on
        problems.append(f"validator: {e}")
    if d.get("id") != cid:
        problems.append(f"id in the file is {d.get('id')}, expected {cid}")
    sol = d.get("solution", {})
    cards = d.get("evidence", [])
    if len(sol.get("proof", [])) > max(1, len(cards) // 2):
        problems.append(f"proof has {len(sol.get('proof', []))} of {len(cards)} cards (at most half)")
    if len(cards) < 5:
        problems.append("fewer than 5 evidence cards")
    intro = cid.startswith("intro")
    if intro:
        if d.get("difficulty") not in (1, 2):
            problems.append(f"difficulty {d.get('difficulty')}: the free intro case is difficulty 1 or 2")
    elif d.get("difficulty") not in (3, 4, 5):
        problems.append(f"difficulty {d.get('difficulty')}: new cases are 4 or 5 (3 only when the blind test measured it, rules section 9)")
    # one case per night, contiguous publish dates
    if not weekend and not intro:
        n = int(cid[1:])
        prev = _path(f"c{n - 1:03d}")
        if prev.exists():
            pd = date.fromisoformat(json.loads(prev.read_text(encoding="utf-8"))["publish"])
            if date.fromisoformat(d["publish"]) - pd != timedelta(days=1):
                problems.append(f"publish {d['publish']} is not the day after {prev.stem} ({pd})")
    # notification teaser
    notify = json.loads((CONTENT / "notify.json").read_text(encoding="utf-8"))
    entry = notify.get(cid)
    if intro:
        pass  # the intro case is never announced
    elif not entry:
        problems.append("no entry in server/app/content/notify.json")
    else:
        if entry.get("title") != d.get("title"):
            problems.append("notify.json title differs from the case title")
        if sum(1 for k, v in notify.items() if v.get("head") == entry.get("head")) > 1:
            problems.append("notify.json head is not unique")
        if len(entry.get("head", "")) > 40 or len(entry.get("body", "")) > 110:
            problems.append("notify.json head/body too long (head ~35, body ~90 characters)")
    # portraits: shipped file, release date, unique culprit face, no repeat inside the case
    portraits = ROOT / "app" / "assets" / "portraits"
    rel = json.loads((ROOT / "docs" / "portrait-release.json").read_text(encoding="utf-8"))
    seen = Counter()
    for s in d.get("suspects", []):
        p = s.get("avatar", {}).get("portrait")
        if p:
            seen[p] += 1
            if not (portraits / f"{p}.webp").exists():
                problems.append(f"{s['id']}: portrait {p} is not shipped")
            if p in rel["portraits"] and d.get("publish", "") < rel["portraits"][p]["usable_from"]:
                problems.append(f"{s['id']}: portrait {p} is usable only from {rel['portraits'][p]['usable_from']}")
        if s.get("avatar", {}).get("gender") == "f" and s.get("avatar", {}).get("hair") != "hijab":
            problems.append(f"{s['id']}: a woman must have hair=hijab")
        if not isinstance(s.get("age"), int):
            problems.append(f"{s['id']}: age must be an integer")
    problems += [f"portrait {p} used {n} times inside the case" for p, n in seen.items() if n > 1]
    culprit = next((s for s in d.get("suspects", []) if s["id"] == sol.get("culprit")), None)
    if culprit:
        cp = culprit.get("avatar", {}).get("portrait")
        pool = {p.stem for p in portraits.glob("*.webp")}
        used = {}
        for o in _others(cid):
            oc = next((s for s in o.get("suspects", []) if s["id"] == o.get("solution", {}).get("culprit")), None)
            if oc and oc.get("avatar", {}).get("portrait"):
                used[oc["avatar"]["portrait"]] = o["id"]
        if cp in used:
            problems.append(f"culprit portrait {cp} is already the culprit of {used[cp]}")
    # names: a name used by a case published within a week is an error (players meet them in the same fortnight);
    # a name used further away is only a note (the pool of Persian names is finite)
    me = date.fromisoformat(d["publish"])
    near_f, near_l, far_f, far_l = {}, {}, {}, {}
    for o in _others(cid):
        close = abs((date.fromisoformat(o["publish"]) - me).days) <= 7
        for s in o.get("suspects", []):
            parts = name_parts(s["name"])
            (near_f if close else far_f).setdefault(parts[0], o["id"])
            for l in parts[1:]:
                (near_l if close else far_l).setdefault(l, o["id"])
    inside = Counter(name_parts(s["name"])[0] for s in d.get("suspects", []))
    for s in d.get("suspects", []):
        parts = name_parts(s["name"])
        if parts[0] in near_f:
            problems.append(f"{s['id']}: first name {parts[0]} is also used in {near_f[parts[0]]} (published within a week)")
        elif parts[0] in far_f:
            notes.append(f"{s['id']}: first name {parts[0]} also in {far_f[parts[0]]}")
        for l in parts[1:]:
            if l in near_l:
                problems.append(f"{s['id']}: surname {l} is also used in {near_l[l]} (published within a week)")
            elif l in far_l:
                notes.append(f"{s['id']}: surname {l} also in {far_l[l]}")
        if inside[parts[0]] > 1:
            problems.append(f"{s['id']}: first name {parts[0]} repeats inside the case")
    # tool lines on every suspect (rules 10b)
    for s in d.get("suspects", []):
        for k in ("camera", "print"):
            v = s.get(k)
            if not v:
                problems.append(f"{s['id']}: no {k} line")
                continue
            for line in ([v] if isinstance(v, str) else v):
                if not 20 <= len(line) <= 160:
                    problems.append(f"{s['id']}: {k} line is {len(line)} characters (20-160)")
    return problems, notes


def public_copy(cid: str, day1: bool, reactions: bool) -> dict:
    d = json.loads(_path(cid).read_text(encoding="utf-8"))
    for k in SECRET:
        d.pop(k, None)
    if not reactions:
        for s in d.get("suspects", []):
            s.pop("reactions", None)
    if day1 and cid.startswith("w"):
        chapters = d.get("chapters", [])
        later = {e for c in chapters[1:] for e in c.get("evidence", [])}
        d["chapters"] = chapters[:1]
        d["evidence"] = [e for e in d["evidence"] if e["id"] not in later]
        d["suspects"] = [s for s in d["suspects"] if s.get("appears_chapter", 0) == 0]
        for s in d["suspects"]:
            if "reactions" in s:
                s["reactions"] = {k: v for k, v in s["reactions"].items() if k not in later}
    return d


def main(argv: list[str]) -> int:
    ids = [a for a in argv if (a[:1] in "cw" and a[1:].isdigit()) or (a.startswith("intro") and a[5:].isdigit())]
    if not ids:
        print(__doc__)
        return 2
    out_dir = None
    if "--public" in argv:
        out_dir = Path(argv[argv.index("--public") + 1])
        out_dir.mkdir(parents=True, exist_ok=True)
    bad = 0
    for cid in ids:
        problems, notes = check(cid)
        print(f"{cid}: {'OK' if not problems else 'FAIL'}")
        for p in problems:
            print("   -", p)
        for n in notes:
            print("   note:", n)
        bad += bool(problems)
        if out_dir and _path(cid).exists():
            day1 = "--day1" in argv
            f = out_dir / f"{cid}_public{'_day1' if day1 else ''}.json"
            f.write_text(json.dumps(public_copy(cid, day1, "--reactions" in argv), ensure_ascii=False, indent=1), encoding="utf-8")
            print(f"   public copy: {f}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
