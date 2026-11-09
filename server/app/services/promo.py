"""Promo cases (Amin, 2 Nov 2026): a case from the archive that is FREE to open for 48 hours for a NEW detective.

Why: an ad video plays the start of a good old case; the viewer installs, wants to find the answer and must not meet a
coin wall on his first night. Nothing is given away that was being sold to that player: he did not have the game yet.
- Who: an account younger than `welcome.NEWBIE_DAYS` (the same "new detective" as the first-days offers). Older accounts pay
  the normal archive price, so players who already know the game are not handed what Amin sells.
- What: opening the case costs 0 coins while the window is open. Once opened it stays open for him (`unlocked`). The solve
  rewards are the normal archive rewards (nothing extra).
- Where the list lives: the config row `promo_cases` (a JSON list, see remote_config.DEFAULTS), so no new table and no
  migration. An admin starts or ends a window in the panel (routers/admin_ui.py `/promo`). A broken row is ignored, so a bad
  edit can never make a case free by accident (fail closed for the giveaway).
- Bounded: at most MAX_ACTIVE windows open at once, at most MAX_STORED rows kept (the oldest ended ones are dropped).
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from .. import welcome
from ..models import AdminLog, CaseProgress, CoinLog, ConfigValue, Player, Purchase, utcnow
from . import remote_config
from .funnel import _valid_player

log = logging.getLogger("promo")

KEY = "promo_cases"
DEFAULT_HOURS = 48
MIN_HOURS = 1
MAX_HOURS = 168
MAX_ACTIVE = 10
MAX_STORED = 40


def _row(raw: Any) -> tuple[str, datetime, datetime] | None:
    """One stored row as (case_id, starts, ends), or None when it is malformed."""
    try:
        cid, s, e = raw["case_id"], datetime.fromisoformat(raw["starts_at"]), datetime.fromisoformat(raw["ends_at"])
        if not isinstance(cid, str) or not 0 < len(cid) <= 16 or s.tzinfo is not None or e.tzinfo is not None or e < s:
            return None
        return cid, s, e
    except (KeyError, TypeError, ValueError):
        return None


def parse(rows: Any, now: datetime) -> dict[str, datetime]:
    """case id -> end of the window, for the windows that are open at `now`."""
    out: dict[str, datetime] = {}
    for raw in rows if isinstance(rows, list) else []:
        r = _row(raw)
        if r and r[1] <= now < r[2]:
            out[r[0]] = max(r[2], out.get(r[0], r[2]))
    return out


async def active(session: AsyncSession, now: datetime | None = None) -> dict[str, datetime]:
    return parse(await remote_config.load_value(session, KEY), now or utcnow())


async def listing(session: AsyncSession, now: datetime | None = None) -> list[dict]:
    """For the panel: every stored window, newest first, with its state."""
    now = now or utcnow()
    out = []
    for raw in await remote_config.load_value(session, KEY) or []:
        r = _row(raw)
        if r is None:
            continue
        c = content.by_id(r[0]) or content.weekly_by_id(r[0])
        out.append({"case_id": r[0], "title": (c.data.get("title") if c else "") or "",
                    "starts_at": r[1].isoformat(timespec="seconds"), "ends_at": r[2].isoformat(timespec="seconds"),
                    "state": "upcoming" if now < r[1] else "open" if now < r[2] else "ended"})
    return sorted(out, key=lambda x: x["starts_at"], reverse=True)


def _check_case(case_id: str, now_local: datetime | None = None) -> None:
    """Only a published archive case can be a promo: not a story chapter, not tonight's case (free for everybody), not a
    weekend case that is still live (its window and prices are its own)."""
    if content.is_story(case_id):
        raise HTTPException(422, "story_case")
    c = content.weekly_by_id(case_id) if content.is_weekly(case_id) else content.by_id(case_id)
    if c is None:
        raise HTTPException(404, "no_case")
    now = now_local or content.now_local()
    if content.opens_at(c) > now:
        raise HTTPException(422, "not_published")
    if content.is_weekly(case_id) and now < content.weekly_closes_at(c):
        raise HTTPException(422, "weekend_live")
    t = content.todays_case(now)
    if t is not None and t.id == c.id:
        raise HTTPException(422, "todays_case")


async def _save(session: AsyncSession, rows: list[dict]) -> None:
    row = await session.get(ConfigValue, KEY)
    if row is None:
        session.add(ConfigValue(key=KEY, value=rows))
    else:
        row.value, row.updated_at = rows, utcnow()
    await session.commit()
    remote_config.invalidate()


async def start(session: AsyncSession, case_id: str, hours: int = DEFAULT_HOURS, now: datetime | None = None) -> dict:
    """Open a window now for `hours`. Starting a case that is already open again restarts its window from now."""
    if not isinstance(hours, int) or not MIN_HOURS <= hours <= MAX_HOURS:
        raise HTTPException(422, "bad_hours")
    _check_case(case_id)
    now = now or utcnow()
    stored = [r for r in (await remote_config.load_value(session, KEY) or []) if _row(r)]
    stored = [r for r in stored if r["case_id"] != case_id]
    if len(parse(stored, now)) >= MAX_ACTIVE:
        raise HTTPException(409, "too_many_active")
    new = {"case_id": case_id, "starts_at": now.isoformat(timespec="seconds"),
           "ends_at": (now + timedelta(hours=hours)).isoformat(timespec="seconds")}
    stored.append(new)
    stored.sort(key=lambda r: r["starts_at"])
    session.add(AdminLog(action="promo_start", target=case_id, detail={"hours": hours}))
    await _save(session, stored[-MAX_STORED:])
    log.info("promo_started case=%s hours=%d", case_id, hours)
    return new


async def end(session: AsyncSession, case_id: str, now: datetime | None = None) -> bool:
    """Close the open window of a case now. Returns False when none was open."""
    now = now or utcnow()
    rows, changed = [], False
    for raw in await remote_config.load_value(session, KEY) or []:
        r = _row(raw)
        if r is None:
            continue
        if r[0] == case_id and r[1] <= now < r[2]:
            raw, changed = {**raw, "ends_at": now.isoformat(timespec="seconds")}, True
            if now <= r[1]:
                continue
        rows.append(raw)
    if changed:
        session.add(AdminLog(action="promo_end", target=case_id, detail={}))
        await _save(session, rows)
        log.info("promo_ended case=%s", case_id)
    return changed


IMPACT_ROWS = 10      # windows measured per call (the newest)
IMPACT_CAP = 5000     # players looked at per window
_CHUNK = 500


async def impact(session: AsyncSession, now: datetime | None = None) -> list[dict]:
    """What each promo window did (read only), newest window first.

    - `signups`: accounts created while the window was open (until now, or its end).
    - `signups_before`: accounts created in an equally long stretch just before it (the baseline to compare with; a
      comparison, not proof: the ad, the day of the week and the store ranking all move signups).
    - `opened`: detectives who opened the case for free (ledger line `promo:<case>`), `opened_new` of them signed up inside
      the window; `solved` of those solved it; `buyers`: accounts created in the window that bought coins (any time since).
    Indexed queries only: players by `created_at`, then the ledger / progress / purchases by `player_id`. Bounded by IMPACT_CAP.
    """
    now = now or utcnow()
    out: list[dict] = []
    for w in (await listing(session, now))[:IMPACT_ROWS]:
        if w["state"] == "upcoming":
            continue
        s, e = datetime.fromisoformat(w["starts_at"]), min(now, datetime.fromisoformat(w["ends_at"]))
        span = max(e - s, timedelta(minutes=1))
        valid = _valid_player()
        new_ids = [r[0] for r in (await session.execute(select(Player.id).where(
            Player.created_at >= s, Player.created_at <= e, valid).limit(IMPACT_CAP))).all()]
        before = int(await session.scalar(select(func.count()).select_from(Player).where(
            Player.created_at >= s - span, Player.created_at < s, valid)) or 0)
        cand = {r[0]: r[1] for r in (await session.execute(select(Player.id, Player.created_at).where(
            Player.created_at >= s - timedelta(days=welcome.NEWBIE_DAYS), Player.created_at <= e, valid)
            .limit(IMPACT_CAP))).all()}
        opened: set[str] = set()
        ids = list(cand)
        for i in range(0, len(ids), _CHUNK):
            opened.update(r[0] for r in (await session.execute(select(CoinLog.player_id).where(
                CoinLog.player_id.in_(ids[i:i + _CHUNK]), CoinLog.reason == f"promo:{w['case_id']}", CoinLog.at >= s))).all())
        solved = 0
        buyers = 0
        olist, nlist = list(opened), new_ids
        for i in range(0, len(olist), _CHUNK):
            solved += int(await session.scalar(select(func.count()).select_from(CaseProgress).where(
                CaseProgress.player_id.in_(olist[i:i + _CHUNK]), CaseProgress.case_id == w["case_id"],
                CaseProgress.solved.is_(True))) or 0)
        for i in range(0, len(nlist), _CHUNK):
            buyers += int(await session.scalar(select(func.count(func.distinct(Purchase.player_id))).where(
                Purchase.player_id.in_(nlist[i:i + _CHUNK]), Purchase.status == "granted")) or 0)
        out.append({"case_id": w["case_id"], "title": w["title"], "state": w["state"], "starts_at": w["starts_at"],
                    "ends_at": w["ends_at"], "hours": round(span.total_seconds() / 3600, 1), "signups": len(new_ids),
                    "signups_before": before, "opened": len(opened),
                    "opened_new": sum(1 for p in opened if cand.get(p) and cand[p] >= s), "solved": solved, "buyers": buyers})
    return out
