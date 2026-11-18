"""«شکار سه‌روزه»: a special case played in real time over about two days (Amin, 18 Nov 2026).

Eight suspects; evidence drops arrive on a schedule; every few hours one suspect leaves town (gone for good: once the
culprit leaves, the hunt is lost); the killer sends messages from the victim's phone; the player accuses ONCE (suspect
and the evidence that proves it). When the time is up, the share of detectives who found the killer decides the ending.

Everything is computed from the start time in the remote config key `hunt` and the player's own row (HuntState):
- `minute` = minutes of hunt time since the start (`speed` > 1 only for the owner's quick test runs);
- a suspect leaves at their `leave` minute, later by `hold_minutes` per «منع خروج» bought for them;
- a drop is open at its minute or earlier when bought with coins; a message arrives at its minute.
The answer (culprit, strong evidence, ending) never leaves the server before the player accused or the hunt ended.
"""
from __future__ import annotations

import json
import math
import re
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any

from . import gameclock

HUNTS_DIR = Path(__file__).resolve().parent / "content" / "hunts"
HUNT_ID = re.compile(r"^h\d{3}$")
IMG_NAME = re.compile(r"^[a-z0-9_]{1,40}$")
AUDIENCES = ("off", "testers", "all")
DEFAULT_CONFIG = {"id": "h001", "audience": "off", "starts_at": None, "speed": 1}
MAX_SPEED = 120  # owner's test runs: 1 real minute = 2 hunt hours at most

_FA = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")
_DAYS = ("دوشنبه", "سه‌شنبه", "چهارشنبه", "پنجشنبه", "جمعه", "شنبه", "یکشنبه")


def fa(x: Any) -> str:
    return str(x).translate(_FA)


@lru_cache(maxsize=8)
def load(hunt_id: str) -> dict | None:
    if not HUNT_ID.match(hunt_id or ""):
        return None
    path = HUNTS_DIR / hunt_id / "hunt.json"
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def config(cfg: dict) -> dict:
    """The `hunt` remote-config value, cleaned: unknown audience = off, speed kept in [1, MAX_SPEED]."""
    raw = cfg.get("hunt") if isinstance(cfg.get("hunt"), dict) else {}
    out = dict(DEFAULT_CONFIG) | {k: raw[k] for k in DEFAULT_CONFIG if k in raw}
    if out["audience"] not in AUDIENCES:
        out["audience"] = "off"
    try:
        out["speed"] = max(1, min(MAX_SPEED, int(out["speed"])))
    except (TypeError, ValueError):
        out["speed"] = 1
    st = out["starts_at"]
    out["starts_at"] = int(st) if isinstance(st, (int, float)) and st > 0 else None
    return out


def visible(cfg: dict, player) -> bool:
    if cfg["audience"] == "all":
        return True
    return cfg["audience"] == "testers" and bool(getattr(player, "tester", False))


def now_epoch() -> float:
    return gameclock.now().timestamp()


def minute_at(cfg: dict, epoch: float) -> int:
    """Hunt minutes since the start (negative before it)."""
    return math.floor((epoch - cfg["starts_at"]) * cfg["speed"] / 60)


def wall(cfg: dict, minute: int) -> int:
    """Unix seconds of a hunt minute."""
    return int(cfg["starts_at"] + minute * 60 / cfg["speed"])


def tehran_label(epoch: int) -> str:
    """«جمعه ساعت ۲۱:۰۰» in Tehran time."""
    dt = datetime.fromtimestamp(epoch, tz=timezone.utc).astimezone(gameclock.tz())
    return f"{_DAYS[dt.weekday()]} ساعت {fa(dt.strftime('%H:%M'))}"


def leave_minute(h: dict, s: dict, holds: dict) -> int | None:
    if s.get("leave") is None:
        return None
    return int(s["leave"]) + int(holds.get(s["id"], 0)) * int(h["hold_minutes"])


def is_gone(h: dict, s: dict, holds: dict, accused: str | None, minute: int) -> bool:
    lm = leave_minute(h, s, holds)
    return lm is not None and minute >= lm and accused != s["id"]


def opened_drops(h: dict, early: list, minute: int) -> list[dict]:
    return [d for d in h["drops"] if d["minute"] <= minute or d["id"] in early]


def next_closed_drop(h: dict, early: list, minute: int) -> dict | None:
    for d in h["drops"]:
        if not (d["minute"] <= minute or d["id"] in early):
            return d
    return None


def unlocked_items(h: dict, early: list, minute: int, solved_at: int | None = None) -> list[str]:
    """Evidence the player can see (and cite): opened drops and the killer's messages that carry evidence."""
    out = [i for d in opened_drops(h, early, minute) for i in d["items"]]
    for m in delivered(h, minute, solved_at):
        if m.get("evidence"):
            out.append(m["evidence"])
    return out


def delivered(h: dict, minute: int, solved_at: int | None = None) -> list[dict]:
    """The killer's messages that arrived. A detective who found the killer gets no more of them."""
    return [m for m in h["messages"] if m["minute"] <= minute and (solved_at is None or m["minute"] <= solved_at)]


def stars_for(h: dict, suspect: str, evidence: str, early: list, minute: int) -> int:
    a = h["answer"]
    if suspect != a["culprit"]:
        return 0
    if evidence in a["strong"]:
        before = next((d for d in h["drops"] if d["id"] == a.get("strong_before")), None)
        seen = before is not None and (before["minute"] <= minute or before["id"] in early)
        return 2 if seen else 3
    return 1


def fill(text: str, values: dict) -> str:
    for k, v in values.items():
        text = text.replace("{" + k + "}", v)
    return text


def has_image(hunt_id: str, name: str | None) -> bool:
    """A picture is offered only once its file is in the hunt folder (pictures arrive later than the text)."""
    return bool(name) and IMG_NAME.match(name) is not None and (HUNTS_DIR / hunt_id / "img" / f"{name}.webp").is_file()


def item_out(h: dict, item_id: str) -> dict:
    it = h["items"][item_id]
    img = it.get("img") if has_image(h["id"], it.get("img")) else None
    return {"id": item_id, "title": it["title"], "short": it["short"], "img": img, "blocks": it["blocks"]}


def state(h: dict, cfg: dict, row, coins: int, collective: dict, now: float | None = None) -> dict:
    """Everything the app shows. `row` is the player's HuntState (or None before the start)."""
    now = now_epoch() if now is None else now
    start, dur = cfg["starts_at"], int(h["duration_minutes"])
    deadline_at = wall(cfg, dur)
    values = {"deadline": tehran_label(deadline_at), "pct": fa(collective["pct"])}
    base = {"visible": True, "id": h["id"], "kicker": h["kicker"], "title": h["title"], "place": h["place"],
            "now": int(now), "starts_at": start, "deadline_at": deadline_at, "speed": cfg["speed"],
            "threshold": h["threshold"], "prices": h["prices"], "hold_hours": h["hold_minutes"] // 60,
            "rewards": h["rewards"], "rules": [[k, fill(t, values)] for k, t in h["rules"]],
            "victim": h["victim"], "img_base": f"/hunt-img/{h['id']}/", "coins": coins, "collective": collective}
    minute = minute_at(cfg, now)
    if minute < 0:
        return base | {"status": "scheduled"}
    minute = min(minute, dur)
    ended = minute >= dur
    holds = dict(row.holds or {}) if row else {}
    early = list(row.early or []) if row else []
    accused = row.accused if row else None
    solved_at = row.accused_minute if row and row.solved else None

    suspects = []
    for s in h["suspects"]:
        lm = leave_minute(h, s, holds)
        suspects.append({k: s[k] for k in ("id", "name", "age", "role", "portrait", "gender", "quote", "why")} | {
            "leave_at": None if lm is None else wall(cfg, lm), "gone": is_gone(h, s, holds, accused, minute),
            "held": int(holds.get(s["id"], 0))})
    drops = []
    for d in h["drops"]:
        is_open = d["minute"] <= minute or d["id"] in early
        drops.append({"id": d["id"], "title": d["title"], "at": wall(cfg, d["minute"]), "open": is_open,
                      "early": d["id"] in early and d["minute"] > minute,
                      "items": [item_out(h, i) for i in d["items"]] if is_open else []})
    msgs = []
    for m in delivered(h, minute, solved_at):
        parts = m["parts"]
        alt = m.get("if_stayed")
        if alt:
            s = next(x for x in h["suspects"] if x["id"] == alt["suspect"])
            if not is_gone(h, s, holds, accused, m["minute"]):
                parts = alt["parts"]
        out_parts = [p if isinstance(p, dict) else {"text": fill(p, values)} for p in parts
                     if not isinstance(p, dict) or has_image(h["id"], p.get("img"))]
        msgs.append({"id": m["id"], "at": wall(cfg, m["minute"]), "parts": out_parts})
    msg_items = [item_out(h, m["evidence"]) for m in delivered(h, minute, solved_at) if m.get("evidence")]
    a = h["answer"]
    mine = None
    if row and row.accused:
        mine = {"suspect": row.accused, "evidence": row.evidence, "solved": row.solved, "stars": row.stars,
                "at": wall(cfg, row.accused_minute or 0)}
        msgs.append({"id": "reply", "at": mine["at"], "parts": [{"text": a["reply_right"] if row.solved else a["reply_wrong"]}]})

    out = base | {"status": "ended" if ended else "live", "suspects": suspects, "drops": drops, "messages": msgs,
                  "message_items": msg_items, "mine": mine, "schedule": [] if ended else schedule(h, cfg, row, minute)}
    if ended:
        culprit = next(s for s in h["suspects"] if s["id"] == a["culprit"])
        caught_gone = is_gone(h, culprit, holds, accused, dur)
        out["ending"] = {"culprit": a["culprit"], "culprit_name": culprit["name"],
                         "reached": collective["pct"] >= h["threshold"],
                         "caught": a["caught_gone"] if caught_gone else a["caught_stayed"], "lines": a["ending"],
                         "truth": a["truth"], "key": a["key"], "fail_title": a["fail_title"], "fail_body": a["fail_body"]}
    return out


def schedule(h: dict, cfg: dict, row, minute: int) -> list[dict]:
    """Coming moments for phone notifications (generic texts: they never give content away)."""
    holds = dict(row.holds or {}) if row else {}
    early = list(row.early or []) if row else []
    solved_at = row.accused_minute if row and row.solved else None
    out = []
    for d in h["drops"]:
        if d["minute"] > minute and d["id"] not in early:
            out.append({"at": wall(cfg, d["minute"]), "head": "مدرک تازه رسید 🗂️", "body": f"«{d['title']}» در پرونده‌ی {h['title']}"})
    for m in h["messages"]:
        if m["minute"] > minute and solved_at is None:
            out.append({"at": wall(cfg, m["minute"]), "head": h["victim"]["name"], "body": "یک پیام تازه 📱"})
    accused = row.accused if row else None
    for s in h["suspects"]:
        lm = leave_minute(h, s, holds)
        if lm is not None and lm > minute and accused is None:
            warn = max(lm - 60, minute + 1)
            out.append({"at": wall(cfg, warn), "head": f"{s['name']} دارد می‌رود ✈️", "body": "یک ساعت دیگر از شهر می‌رود."})
    out.append({"at": wall(cfg, int(h["duration_minutes"])), "head": "نتیجه‌ی شکار اعلام شد", "body": f"ببین چند درصد کارآگاه‌ها قاتل {h['victim']['name']} را پیدا کردند."})
    return sorted(out, key=lambda e: e["at"])[:24]
