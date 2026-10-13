"""The cheat report (admin only): signs that accounts are throwaways or scripted. It only reports; the admin decides
and can ban a player with POST /admin/players/{id}/ban (the existing Player.banned flag)."""
from __future__ import annotations

from datetime import date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import content
from . import economy as eco
from .models import AdminLog, CaseProgress, Player, utcnow
from .util import ts

DEVICE_MIN_ACCOUNTS = 3          # a device with this many accounts is listed
FAST_SOLVE_SECONDS = 60          # a solve with less active time than this is listed
BURST_MIN_ACCOUNTS = 4           # this many new accounts with the same first answer ...
BURST_MINUTES = 10               # ... within this many minutes are listed
LIST_LIMIT = 50


async def build(session: AsyncSession, days: int = 7) -> dict:
    since = utcnow() - timedelta(days=days)

    # 1. devices with many accounts
    rows = (await session.execute(
        select(Player.device_id, func.count()).where(Player.created_at >= since)
        .group_by(Player.device_id).having(func.count() >= DEVICE_MIN_ACCOUNTS)
        .order_by(func.count().desc()).limit(LIST_LIMIT))).all()
    devices = []
    for dev, n in rows:
        ids = (await session.execute(select(Player.id).where(Player.device_id == dev, Player.created_at >= since)
                                     .limit(10))).scalars().all()
        devices.append({"device": dev[:10], "accounts": int(n), "player_ids": ids})

    # 2. solves with under a minute of active time
    fast = [{"player_id": pl.id, "nickname": pl.nickname, "case": cp.case_id, "active_seconds": cp.active_seconds or 0,
             "stars": cp.stars, "ranked": bool(cp.ranked), "at": ts(cp.finished_at)}
            for cp, pl in (await session.execute(
                select(CaseProgress, Player).join(Player, Player.id == CaseProgress.player_id)
                .where(CaseProgress.solved.is_(True), CaseProgress.finished_at >= since,
                       CaseProgress.active_seconds < FAST_SOLVE_SECONDS)
                .order_by(CaseProgress.active_seconds.asc(), CaseProgress.finished_at.desc()).limit(LIST_LIMIT))).all()]

    # 3. many new accounts giving the same first answer within minutes
    cutoff = timedelta(hours=eco.HIDE_NEW_ACCOUNT_HOURS)
    rows = (await session.execute(
        select(CaseProgress.case_id, CaseProgress.first_accused, CaseProgress.opened_at, Player.id, Player.created_at)
        .join(Player, Player.id == CaseProgress.player_id)
        .where(CaseProgress.opened_at >= since, CaseProgress.first_accused.is_not(None), Player.email.is_(None))
        .order_by(CaseProgress.opened_at.asc()).limit(5000))).all()
    groups: dict[tuple[str, str], list[tuple[datetime, str]]] = {}
    for case_id, suspect, opened, pid, created in rows:
        if opened - created <= cutoff:  # a new account when it played
            groups.setdefault((case_id, suspect), []).append((opened, pid))
    bursts = []
    for (case_id, suspect), items in groups.items():
        best: list[tuple[datetime, str]] = []
        lo = 0
        for hi in range(len(items)):
            while items[hi][0] - items[lo][0] > timedelta(minutes=BURST_MINUTES):
                lo += 1
            if hi - lo + 1 > len(best):
                best = items[lo:hi + 1]
        if len(best) >= BURST_MIN_ACCOUNTS:
            bursts.append({"case": case_id, "suspect": suspect, "accounts": len(best), "from": ts(best[0][0]),
                           "to": ts(best[-1][0]), "player_ids": [pid for _, pid in best[:10]]})
    bursts.sort(key=lambda b: -b["accounts"])

    summary = (f"Cheat report, last {days} days: {len(devices)} devices with {DEVICE_MIN_ACCOUNTS}+ accounts, "
               f"{len(fast)} solves under {FAST_SOLVE_SECONDS} s of active time, "
               f"{len(bursts)} bursts of new accounts with the same answer.")
    return {"days": days, "summary": summary, "devices": devices, "fast_solves": fast[:LIST_LIMIT],
            "same_answer_bursts": bursts[:LIST_LIMIT], "ban": "POST /admin/players/{id}/ban"}


async def store_weekly(session: AsyncSession) -> bool:
    """Once a week, writes the short summary into the admin log (action "cheat_report"). Safe to call any time."""
    week = content.week_start(date.fromisoformat(content.today_str())).isoformat()
    done = await session.scalar(select(AdminLog.id).where(AdminLog.action == "cheat_report", AdminLog.target == week).limit(1))
    if done is not None:
        return False
    rep = await build(session, 7)
    session.add(AdminLog(action="cheat_report", target=week, detail={
        "summary": rep["summary"], "devices": len(rep["devices"]), "fast_solves": len(rep["fast_solves"]),
        "bursts": len(rep["same_answer_bursts"])}))
    await session.commit()
    return True
