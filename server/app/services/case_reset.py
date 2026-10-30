"""Support tool: put ONE case back to «not played» for ONE player so they can solve it again.

Clears only that case for that player: the progress row (solved/failed, stars, attempts, hints, time, notes), tools used,
the first guess, their comment/rating (and replies under it). The board is computed from progress rows, so the place
on the weekly board disappears with them. Kept on purpose: coins already paid (no refund), an archive unlock (they
paid for it), streak, XP, achievements. The case id goes into `player.stats["reset_cases"]`: solving it again pays
no coins, XP, warrants or counters (anti double-farming)."""
from __future__ import annotations

import logging

from sqlalchemy import delete, func, or_, select

from .. import content, weekboard
from ..db import lock_players
from ..models import AdminLog, CaseComment, CaseGuess, CaseProgress, CaseToolUse, Player, utcnow

log = logging.getLogger("case")
MARK_KEY = "reset_cases"
MARK_CAP = 100  # the newest 100 resets are remembered per player


class ResetError(Exception):
    def __init__(self, code: str, status: int = 409):
        self.code, self.status = code, status


def was_reset(player: Player, case_id: str) -> bool:
    return case_id in ((player.stats or {}).get(MARK_KEY) or [])


def _check_case(case_id: str) -> None:
    if not case_id or len(case_id) > 16:
        raise ResetError("bad_case", 422)
    if content.is_story(case_id):
        raise ResetError("story_case", 422)  # story chapters keep their own progress; not handled here


async def preview(session, player_id: str, case_id: str) -> dict:
    _check_case(case_id)
    p = await session.scalar(select(CaseProgress).where(CaseProgress.player_id == player_id, CaseProgress.case_id == case_id))
    if p is None:
        raise ResetError("no_progress", 404)
    count = lambda m: session.scalar(select(func.count()).select_from(m).where(m.player_id == player_id, m.case_id == case_id))
    return {"case": case_id, "solved": p.solved, "failed": p.failed, "stars": p.stars, "attempts": p.attempts, "hints": p.hints,
            "seconds": p.seconds, "tools": int(await count(CaseToolUse) or 0), "guesses": int(await count(CaseGuess) or 0),
            "comments": int(await count(CaseComment) or 0),
            "on_board": bool(p.solved and p.ranked)}


async def apply(session, player_id: str, case_id: str) -> dict:
    """One transaction; the player row is locked so two clicks (or a solve at the same moment) cannot interleave."""
    _check_case(case_id)
    player = (await lock_players(session, [player_id])).get(player_id)
    if player is None:
        raise ResetError("no_player", 404)
    p = await session.scalar(select(CaseProgress).where(CaseProgress.player_id == player_id, CaseProgress.case_id == case_id)
                             .with_for_update())
    if p is None:
        raise ResetError("no_progress", 404)
    if not (p.solved or p.failed or p.attempts or p.hints):
        raise ResetError("nothing_to_reset", 409)
    was_solved, stars = bool(p.solved), int(p.stars or 0)
    if was_solved:
        player.cases_solved = max(0, (player.cases_solved or 0) - 1)
        player.stars_total = max(0, (player.stars_total or 0) - stars)
    p.solved = p.failed = p.was_daily = False
    p.stars = p.seconds = p.attempts = p.hints = p.proof_misses = p.active_seconds = 0
    p.day, p.finished_at, p.last_tick_at, p.reveal_at, p.first_accused = "", None, None, None, None
    p.seen = p.cards_opened = p.questions_asked = p.wrong_tries = p.shows = p.night1 = None
    p.ranked = True
    p.opened_at = utcnow()  # `unlocked` stays: an archive case they paid for is not locked again
    n_tools = (await session.execute(delete(CaseToolUse).where(CaseToolUse.player_id == player_id, CaseToolUse.case_id == case_id))).rowcount
    n_guess = (await session.execute(delete(CaseGuess).where(CaseGuess.player_id == player_id, CaseGuess.case_id == case_id))).rowcount
    mine = select(CaseComment.id).where(CaseComment.player_id == player_id, CaseComment.case_id == case_id)
    ids = list((await session.scalars(mine)).all())
    n_comments = 0
    if ids:
        n_comments = (await session.execute(delete(CaseComment).where(
            CaseComment.case_id == case_id, or_(CaseComment.id.in_(ids), CaseComment.parent_id.in_(ids))))).rowcount
    stats = dict(player.stats or {})
    marks = [m for m in (stats.get(MARK_KEY) or []) if m != case_id] + [case_id]
    stats[MARK_KEY] = marks[-MARK_CAP:]
    player.stats = stats  # a new dict, so the change is saved
    session.add(AdminLog(action="case_reset", target=player_id, detail={
        "case": case_id, "was_solved": was_solved, "stars": stars, "tools": n_tools, "guesses": n_guess, "comments": n_comments}))
    await session.commit()
    weekboard.invalidate()
    log.info("admin case_reset case=%s was_solved=%s", case_id, was_solved)
    return {"ok": True, "case": case_id, "was_solved": was_solved, "tools": n_tools, "guesses": n_guess, "comments": n_comments}
