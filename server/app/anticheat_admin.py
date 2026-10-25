"""Admin side of the anti-cheat relaxation (25 Oct 2026, Amin): the WATCHER and the one-time STAR RESTORE.

- watch(): read-only, bounded. For solved daily/archive cases of the last N days it measures what the OLD strict rules
  (anticheat.strict_verdict, frozen constants) would have done, and what the live relaxed rules do. No player ids.
- restore(): gives back the stars that the strict proof of investigation took from honest players. Dry run by default.
  Bounded batches, one transaction each, idempotent (case_progress.stars_restored, set in the same UPDATE ... WHERE
  stars_restored = false) and race-safe on two workers; star totals move with an atomic increment.
Coins, XP and achievements are NOT touched (giving the coin difference is the owner's decision).
"""
from __future__ import annotations

import logging
import statistics
from collections import defaultdict
from datetime import timedelta

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from . import anticheat as ac
from . import content, db
from . import economy as eco
from .config import get_settings
from .models import AdminLog, CaseProgress, Player, utcnow

log = logging.getLogger("anticheat")

WATCH_MAX_ROWS = 20000     # a flood of solves can never make the watcher read an unbounded table
WATCH_TREND_DAYS = 7
RESTORE_BATCH = 300
RESTORE_BATCH_MAX = 500
LEVEL_GREEN_BELOW = 5.0    # percent of solves the strict rules would have hurt: <5 green, 5-15 amber, >15 red
LEVEL_RED_ABOVE = 15.0


def _difficulty(c: content.Case) -> int:
    try:
        return min(5, max(1, int(c.data.get("difficulty") or 3)))
    except (TypeError, ValueError):
        return 3


def _plain_case(case_id: str) -> content.Case | None:
    """The daily/archive case, or None for weekend, story and unknown ids (they have their own formats)."""
    if content.is_weekly(case_id) or content.is_story(case_id):
        return None
    return content.by_id(case_id)


def level_for(pct: float) -> str:
    return "green" if pct < LEVEL_GREEN_BELOW else "amber" if pct <= LEVEL_RED_ABOVE else "red"


def _live_settings() -> dict:
    st = get_settings()
    return {"active_time_scale": eco.active_time_scale(), "min_suspects_seen": eco.min_suspects_seen(),
            "depth_min_questions": st.depth_min_questions}


# ---------------------------------------------------------------- the watcher
async def watch(session: AsyncSession, days: int = 7) -> dict:
    days = min(30, max(1, int(days)))
    since = utcnow() - timedelta(days=days)
    q = (select(CaseProgress.case_id, CaseProgress.day, CaseProgress.finished_at, CaseProgress.active_seconds,
                CaseProgress.seen, CaseProgress.cards_opened, CaseProgress.questions_asked)
         .join(Player, Player.id == CaseProgress.player_id)
         .where(CaseProgress.solved.is_(True), CaseProgress.finished_at >= since,
                Player.banned.is_(False), Player.tester.is_(False))
         .order_by(CaseProgress.finished_at.desc()).limit(WATCH_MAX_ROWS))
    rows = (await session.execute(q)).all()

    total = affected = kept_full = kept_ranked = 0
    by_reason = {"time": 0, "suspects": 0, "depth": 0}
    by_diff = {str(d): {"solves": 0, "affected": 0, "time": 0, "suspects": 0, "depth": 0} for d in range(1, 6)}
    per_day: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    active: dict[int, list[int]] = defaultdict(list)
    for case_id, day, finished, active_s, seen, cards, asked in rows:
        c = _plain_case(case_id)
        if c is None:
            continue
        diff = _difficulty(c)
        n_seen = len(seen or [])
        n_q = None if (cards is None and asked is None) else len(set(asked or []))
        sv = ac.strict_verdict(active_s, n_seen, n_q, diff, True)
        # the live (relaxed) rules, on a transient row, so DEPTH_NEED_PROOF / DEPTH_MIN_CARDS are honoured too
        probe = CaseProgress(active_seconds=active_s or 0, seen=seen, cards_opened=cards, questions_asked=asked)
        live_proof = ac.proof_ok(probe, c)
        live_depth = ac.depth_ok(probe, c)[0]
        total += 1
        d = by_diff[str(diff)]
        d["solves"] += 1
        active[diff].append(int(active_s or 0))
        key = day or (finished.date().isoformat() if finished else "")
        per_day[key][0] += 1
        if sv["reason"]:
            affected += 1
            by_reason[sv["reason"]] += 1
            d["affected"] += 1
            d[sv["reason"]] += 1
            per_day[key][1] += 1
            kept_full += int(live_proof)
            kept_ranked += int(live_proof and live_depth)

    pct = round(100.0 * affected / total, 1) if total else 0.0
    trend = [{"day": k, "solves": v[0], "affected": v[1],
              "pct": round(100.0 * v[1] / v[0], 1) if v[0] else 0.0}
             for k, v in sorted(per_day.items())][-WATCH_TREND_DAYS:]
    return {
        "days": days, "rows_read": len(rows), "truncated": len(rows) >= WATCH_MAX_ROWS,
        "total_solves": total,
        "strict": {"affected": affected, "pct": pct, "one_star": by_reason["time"] + by_reason["suspects"],
                   "by_reason": by_reason, "by_difficulty": by_diff,
                   "kept_full_stars_by_relaxed": kept_full, "kept_ranked_by_relaxed": kept_ranked,
                   "still_hurt_by_relaxed": affected - kept_full},
        "level": level_for(pct),
        "per_day": trend,
        "median_active_seconds": {str(d): (int(statistics.median(v)) if v else None) for d, v in
                                  sorted((d, active.get(d, [])) for d in range(1, 6))},
        "live_rules": _live_settings(),
        "strict_rules": {"active_time_scale": 1.0, "min_suspects_seen": eco.STRICT_MIN_SUSPECTS,
                         "depth_min_questions": eco.STRICT_MIN_QUESTIONS},
        "hint": "برای سخت‌گیری دوباره در لیارا بگذار: ACTIVE_TIME_SCALE=1 ، MIN_SUSPECTS_SEEN=2 ، DEPTH_MIN_QUESTIONS=2",
    }


# ---------------------------------------------------------------- the star restore
def _paid_retry(p: CaseProgress) -> bool:
    """Today's case replayed after a loss (same test as accuse(): was_daily and unlocked). It never gets a board place."""
    return bool(p.was_daily and p.unlocked)


def judge(p: CaseProgress, c: content.Case) -> dict | None:
    """Is this stored solve an honest candidate for getting stars back? None = no. Otherwise
    {"new_stars", "delta", "rank", "difficulty"}. Honest = capped by the old rules (strict proof failed) but passing the
    live relaxed proof; real throwaway patterns (a few seconds of active time) fail the relaxed proof and are left alone."""
    natural = eco.stars_for(p.hints or 0, p.attempts or 0, p.proof_misses or 0)
    if natural <= (p.stars or 0):
        return None
    diff = _difficulty(c)
    n_q = None if (p.cards_opened is None and p.questions_asked is None) else len(set(p.questions_asked or []))
    if ac.strict_verdict(p.active_seconds, len(p.seen or []), n_q, diff, True)["proof_ok"]:
        return None   # the old rules would have passed it: the missing stars have another cause, do not guess
    if not ac.proof_ok(p, c):
        return None   # still too little work under the relaxed rules
    rank = (not p.ranked) and (not _paid_retry(p)) and ac.depth_ok(p, c)[0]
    return {"new_stars": natural, "delta": natural - (p.stars or 0), "rank": rank, "difficulty": diff}


async def restore(session: AsyncSession, dry_run: bool = True, after: int = 0, limit: int = RESTORE_BATCH) -> dict:
    """One bounded batch (ids above `after`, at most `limit` prefiltered rows). Returns counts only. Call again with
    `next_after` until done=True. dry_run=False applies the batch in ONE transaction."""
    limit = min(RESTORE_BATCH_MAX, max(1, int(limit)))
    if not dry_run:
        await db.begin_write(session)   # SQLite: one writer; PostgreSQL relies on the row locks of the UPDATEs
    rows = (await session.execute(
        select(CaseProgress).join(Player, Player.id == CaseProgress.player_id)
        .where(CaseProgress.solved.is_(True), CaseProgress.stars_restored.is_(False), CaseProgress.stars < 3,
               CaseProgress.id > int(after), Player.banned.is_(False), Player.tester.is_(False))
        .order_by(CaseProgress.id).limit(limit))).scalars().all()

    candidates = stars_to_give = ranked_back = restored = lost_race = 0
    by_diff: dict[str, dict] = {}
    player_delta: dict[str, int] = defaultdict(int)
    for p in rows:
        c = _plain_case(p.case_id)
        verdict = judge(p, c) if c is not None else None
        if verdict is None:
            continue
        candidates += 1
        stars_to_give += verdict["delta"]
        ranked_back += int(verdict["rank"])
        bucket = by_diff.setdefault(str(verdict["difficulty"]), {"solves": 0, "stars": 0})
        bucket["solves"] += 1
        bucket["stars"] += verdict["delta"]
        if dry_run:
            continue
        values = {"stars": verdict["new_stars"], "stars_restored": True}
        if verdict["rank"]:
            values["ranked"] = True
        # the guard in WHERE makes a second call or a second worker a no-op for this row
        res = await session.execute(
            update(CaseProgress).where(CaseProgress.id == p.id, CaseProgress.stars_restored.is_(False),
                                       CaseProgress.solved.is_(True), CaseProgress.stars == p.stars).values(**values))
        if res.rowcount == 1:
            restored += 1
            player_delta[p.player_id] += verdict["delta"]
        else:
            lost_race += 1
    given = 0
    if not dry_run:
        for pid, delta in player_delta.items():   # atomic increments, never read-modify-write
            await session.execute(update(Player).where(Player.id == pid).values(stars_total=Player.stars_total + delta))
            given += delta
        session.add(AdminLog(action="anticheat_restore", target="case_progress",
                             detail={"scanned": len(rows), "candidates": candidates, "restored": restored,
                                     "stars": given, "skipped_race": lost_race, "after": int(after)}))
        await session.commit()
        log.info("anticheat restore_batch scanned=%d candidates=%d restored=%d stars=%d skipped_race=%d",
                 len(rows), candidates, restored, given, lost_race)
        from . import weekboard
        weekboard.invalidate()            # boards recount stars from case_progress
        try:
            from .routers import cases as cases_router
            cases_router._solvers.clear()
        except Exception:                 # a cache that cannot be cleared only expires by its TTL
            pass
    out = {"dry_run": dry_run, "scanned": len(rows), "candidates": candidates, "stars_to_give": stars_to_give,
           "ranked_to_restore": ranked_back, "by_difficulty": by_diff,
           "next_after": rows[-1].id if rows else int(after), "done": len(rows) < limit}
    if not dry_run:
        out.update({"restored": restored, "stars_given": given, "skipped_race": lost_race})
    return out
