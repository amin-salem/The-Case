"""The cheat report (admin only): signs that accounts are throwaways or scripted. It only reports; the admin decides
and can ban a player with POST /admin/players/{id}/ban (the existing Player.banned flag)."""
from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import content, gameclock
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
    week = gameclock.week_of(content.now_local()).isoformat()
    done = await session.scalar(select(AdminLog.id).where(AdminLog.action == "cheat_report", AdminLog.target == week).limit(1))
    if done is not None:
        return False
    rep = await build(session, 7)
    session.add(AdminLog(action="cheat_report", target=week, detail={
        "summary": rep["summary"], "devices": len(rep["devices"]), "fast_solves": len(rep["fast_solves"]),
        "bursts": len(rep["same_answer_bursts"])}))
    await session.commit()
    return True


# ---------------------------------------------------------------- suspicious solves of the last 24 hours
# Flag only, never auto-ban: the admin decides (POST /admin/players/{id}/ban). Bounded: at most MAX_ROWS solves are read
# and every list is cut to LIST_LIMIT. No personal data in the log (one structured line per cluster: case, size, span).
import logging  # noqa: E402
import statistics  # noqa: E402

from . import anticheat as ac  # noqa: E402
from .config import get_settings  # noqa: E402

slog = logging.getLogger("cheatreport")
MAX_ROWS = 5000
MEDIAN_MIN_SOLVES = 8        # a case needs this many solves in the window before "far faster than the median" means anything
FAST_RATIO = 0.25            # active time at most this share of the case's median
CLUSTER_MIN = 4              # this many accounts ...
CLUSTER_GAP = 60             # ... each solving within this many seconds of the previous one ...
CLUSTER_SPAN = 300           # ... all inside this many seconds ...
QUIET_BEFORE = 600           # ... right after at least this many seconds without any solve of that case


def find_clusters(times: list[tuple[datetime, str]]) -> list[list[tuple[datetime, str]]]:
    """Pure function. `times` = (finished_at, player_id) of ONE case, any order. Returns the groups that look like a
    shared answer: CLUSTER_MIN+ solves, consecutive gaps <= CLUSTER_GAP, span <= CLUSTER_SPAN, and a quiet period of
    QUIET_BEFORE seconds (or the window's start) before the first one."""
    items = sorted(times)
    out, i = [], 0
    while i < len(items):
        j = i
        while j + 1 < len(items) and (items[j + 1][0] - items[j][0]).total_seconds() <= CLUSTER_GAP \
                and (items[j + 1][0] - items[i][0]).total_seconds() <= CLUSTER_SPAN:
            j += 1
        group = items[i:j + 1]
        quiet = i == 0 or (items[i][0] - items[i - 1][0]).total_seconds() >= QUIET_BEFORE
        if len(group) >= CLUSTER_MIN and quiet:
            out.append(group)
        i = j + 1
    return out


async def suspicious_solves(session: AsyncSession, now: datetime | None = None) -> dict:
    now = now or utcnow()
    since = now - timedelta(hours=24)
    st = get_settings()
    rows = (await session.execute(
        select(CaseProgress, Player.nickname).join(Player, Player.id == CaseProgress.player_id)
        .where(CaseProgress.solved.is_(True), CaseProgress.finished_at >= since, CaseProgress.finished_at <= now)
        .order_by(CaseProgress.finished_at.asc()).limit(MAX_ROWS))).all()
    cases = {c.id: c for c in content.all_cases()}

    # 1. very low depth (the app reported it, and it is under the thresholds, or there was almost no active time)
    low = []
    for cp, nick in rows:
        c = cases.get(cp.case_id)
        if c is None:
            continue
        reported = cp.cards_opened is not None or cp.questions_asked is not None
        d = ac.depth_summary(cp, c)
        why = None
        if reported and (d["evidence"] < min(st.depth_min_cards, 2) or d["questions"] < 1):
            why = "depth"
        elif (cp.active_seconds or 0) < FAST_SOLVE_SECONDS:
            why = "active_time"
        if why:
            low.append({"player_id": cp.player_id, "case": cp.case_id, "why": why, "evidence": d["evidence"],
                        "questions": d["questions"], "active_seconds": d["active"], "ranked": bool(cp.ranked)})

    # 2. far faster than the median of the same case
    by_case: dict[str, list[CaseProgress]] = {}
    for cp, _ in rows:
        by_case.setdefault(cp.case_id, []).append(cp)
    fast = []
    for cid, items in by_case.items():
        act = [cp.active_seconds or 0 for cp in items if (cp.active_seconds or 0) > 0]
        if len(act) < MEDIAN_MIN_SOLVES:
            continue
        med = statistics.median(act)
        for cp in items:
            a = cp.active_seconds or 0
            if 0 < a <= med * FAST_RATIO:
                fast.append({"player_id": cp.player_id, "case": cid, "active_seconds": a, "median": int(med)})

    # 3. clusters of accounts solving within seconds after a quiet period
    clusters = []
    for cid, items in by_case.items():
        for g in find_clusters([(cp.finished_at, cp.player_id) for cp in items]):
            span = int((g[-1][0] - g[0][0]).total_seconds())
            clusters.append({"case": cid, "accounts": len(g), "span_seconds": span, "from": ts(g[0][0]),
                             "player_ids": [pid for _, pid in g[:10]]})
            slog.info("suspicious_cluster case=%s accounts=%d span=%ds", cid, len(g), span)
    clusters.sort(key=lambda x: -x["accounts"])

    return {"window_hours": 24, "solves_read": len(rows), "low_depth": low[:LIST_LIMIT], "far_faster": fast[:LIST_LIMIT],
            "clusters": clusters[:LIST_LIMIT], "note": "flags only; ban with POST /admin/players/{id}/ban"}
