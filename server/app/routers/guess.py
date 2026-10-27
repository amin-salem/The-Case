"""«به نظر تو کیه؟»: POST/GET /v1/cases/{id}/guess (app/guess.py)."""
import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from .. import anticheat as ac
from .. import content, guess
from ..db import get_session
from ..models import CaseGuess, CaseProgress, Player
from ..security import current_player
from .cases import _can_open, _opened_case, _progress

router = APIRouter(prefix="/v1/cases", tags=["guess"])
log = logging.getLogger("guess")


class GuessIn(BaseModel):
    suspect: str = Field(min_length=1, max_length=16)  # a suspect id, or "?" for «نمی‌دونم»


def _suspect_ids(c) -> list[str]:
    ids = [s["id"] for s in c.data["suspects"]]
    if content.is_weekly(c.id):
        vis = content.visible_suspect_ids(c)
        ids = [i for i in ids if i in vis]
    return ids


def _started(p: CaseProgress) -> bool:
    """The investigation has begun (evidence opened, someone questioned, a hint bought, an accusation made)."""
    return bool(p.solved or p.failed or p.attempts or p.hints or p.seen or p.cards_opened or p.questions_asked)


def _case(case_id: str, player: Player):
    if content.is_story(case_id):
        raise HTTPException(404, "no_case")  # story chapters have no guess
    return _opened_case(case_id, player)


@router.post("/{case_id}/guess")
async def give_guess(case_id: str, body: GuessIn, player: Player = Depends(current_player),
                     session: AsyncSession = Depends(get_session)):
    c = _case(case_id, player)
    p = await _progress(session, player.id, c.id)
    if p is None or not _can_open(c, p, player):
        raise HTTPException(409, "open_case_first")
    if body.suspect != guess.UNKNOWN and body.suspect not in _suspect_ids(c):
        raise HTTPException(422, "no_suspect")
    dialect = session.bind.dialect.name if session.bind is not None else "sqlite"
    insert = pg_insert if dialect == "postgresql" else sqlite_insert
    mine = await session.scalar(select(CaseGuess.suspect).where(CaseGuess.player_id == player.id, CaseGuess.case_id == c.id))
    if mine is None:
        if _started(p):
            raise HTTPException(409, "too_late")  # the guess is for BEFORE the evidence: later it is not a first guess
        res = await session.execute(insert(CaseGuess).values(player_id=player.id, case_id=c.id, suspect=body.suspect)
                                    .on_conflict_do_nothing(index_elements=["player_id", "case_id"]))
        await session.commit()
        if res.rowcount:
            log.info("guess case=%s unknown=%s", c.id, body.suspect == guess.UNKNOWN)
            return {"guess": body.suspect, "already": False}
        mine = await session.scalar(select(CaseGuess.suspect).where(
            CaseGuess.player_id == player.id, CaseGuess.case_id == c.id))
    return {"guess": mine, "already": True}  # a second guess changes nothing (also when two requests race)


@router.get("/{case_id}/guess")
async def get_guess(case_id: str, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """The player's own first guess; the crowd's percentages and the culprit only once the answer is theirs to see."""
    c = _case(case_id, player)
    p = await _progress(session, player.id, c.id)
    if p is None:
        raise HTTPException(409, "open_case_first")
    mine = await session.scalar(select(CaseGuess.suspect).where(CaseGuess.player_id == player.id, CaseGuess.case_id == c.id))
    out = {"guess": mine, "community": None, "culprit": None, "correct": None}
    if ac.answer_visible(p):
        out["community"] = guess.community(await guess.counts(session, c.id), _suspect_ids(c))
        out["culprit"] = c.culprit
        out["correct"] = None if mine is None else mine == c.culprit
    return out
