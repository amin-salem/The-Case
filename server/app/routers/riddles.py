"""Quick riddles («معمای سریع»): today's set, opening the paid ones, and answering (once each)."""
from datetime import datetime, time, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content, progress, riddles
from .. import economy as eco
from ..db import get_session
from ..models import Player, RiddleAnswer, utcnow
from ..riddles import Riddle
from ..schemas import GainsOut, RiddleAnswerIn, RiddleAnswerOut, RiddleItem, RiddlesOut, RiddleUnlockOut
from ..security import current_player
from ..util import add_coins

router = APIRouter(prefix="/v1/riddles", tags=["riddles"])


def _item(r: Riddle, slot: int, a: RiddleAnswer | None) -> RiddleItem:
    free = slot <= eco.RIDDLE_FREE
    locked = not free and not (a and a.unlocked)
    answered = bool(a and a.choice is not None)
    it = RiddleItem(id=r.id, slot=slot, title=r.title, scene=r.scene, free=free, locked=locked,
                    answered=answered, correct=bool(a and a.correct), choice=a.choice if a else None)
    if not locked:
        pub = r.public()
        it.text, it.clue, it.choices = pub["text"], pub["clue"], pub["choices"]
    if answered:
        it.answer, it.explain = r.answer, r.explain
    return it


async def _mine(session: AsyncSession, player_id: str, day: str) -> dict[str, RiddleAnswer]:
    rows = (await session.execute(select(RiddleAnswer).where(
        RiddleAnswer.player_id == player_id, RiddleAnswer.day == day))).scalars().all()
    return {a.riddle_id: a for a in rows}


def _todays(riddle_id: str, day: str) -> tuple[Riddle, int]:
    for slot, r in enumerate(riddles.for_day(day), start=1):
        if r.id == riddle_id:
            return r, slot
    raise HTTPException(404, "not_today")


def _next_at() -> int:
    now = content.now_local()
    return int(datetime.combine(now.date() + timedelta(days=1), time(0), tzinfo=now.tzinfo).timestamp())


@router.get("", response_model=RiddlesOut)
async def today(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    day = content.today_str()
    mine = await _mine(session, player.id, day)
    items = [_item(r, slot, mine.get(r.id)) for slot, r in enumerate(riddles.for_day(day), start=1)]
    return RiddlesOut(day=day, items=items, unlock_cost=eco.RIDDLE_UNLOCK_COST, reward=eco.RIDDLE_REWARD,
                      seconds=eco.RIDDLE_SECONDS, next_at=_next_at(), coins=player.coins)


async def _row(session: AsyncSession, player: Player, day: str, riddle_id: str) -> RiddleAnswer:
    a = (await _mine(session, player.id, day)).get(riddle_id)
    if a is None:
        a = RiddleAnswer(player_id=player.id, day=day, riddle_id=riddle_id)
        session.add(a)
    return a


@router.post("/{riddle_id}/unlock", response_model=RiddleUnlockOut)
async def unlock(riddle_id: str, player: Player = Depends(current_player),
                 session: AsyncSession = Depends(get_session)):
    day = content.today_str()
    r, slot = _todays(riddle_id, day)
    a = (await _mine(session, player.id, day)).get(r.id)
    if slot > eco.RIDDLE_FREE and not (a and a.unlocked):
        if player.coins < eco.RIDDLE_UNLOCK_COST:
            raise HTTPException(402, {"error": "not_enough_coins", "need": eco.RIDDLE_UNLOCK_COST})
        a = await _row(session, player, day, r.id)
        a.unlocked = True
        add_coins(session, player, -eco.RIDDLE_UNLOCK_COST, f"riddle_unlock:{r.id}")
        gains = await progress.record(session, player, riddle_unlock=1)
        try:
            await session.commit()
        except IntegrityError:  # two taps at once
            await session.rollback()
            raise HTTPException(409, "try_again") from None
        return RiddleUnlockOut(item=_item(r, slot, a), coins=player.coins, gains=GainsOut(**gains.out()))
    return RiddleUnlockOut(item=_item(r, slot, a), coins=player.coins)


@router.post("/{riddle_id}/answer", response_model=RiddleAnswerOut)
async def answer(riddle_id: str, body: RiddleAnswerIn, player: Player = Depends(current_player),
                 session: AsyncSession = Depends(get_session)):
    day = content.today_str()
    r, slot = _todays(riddle_id, day)
    a = (await _mine(session, player.id, day)).get(r.id)
    if slot > eco.RIDDLE_FREE and not (a and a.unlocked):
        raise HTTPException(402, {"error": "locked", "cost": eco.RIDDLE_UNLOCK_COST})
    if a is not None and a.choice is not None:
        raise HTTPException(409, "already_answered")
    a = await _row(session, player, day, r.id)
    ok = body.choice == r.answer
    a.choice, a.correct, a.seconds, a.at = body.choice, ok, body.seconds, utcnow()
    reward = eco.RIDDLE_REWARD if ok else 0
    if reward:
        add_coins(session, player, reward, f"riddle:{r.id}")
    events = {"riddle_answer": 1}
    if ok:
        events["riddle_correct"] = 1
        if 0 < body.seconds <= eco.RIDDLE_FAST_SECONDS:
            events["riddle_fast"] = 1
    # three of today's riddles answered, all of them right
    answered = [x for x in (await _mine(session, player.id, day)).values() if x.choice is not None]
    if ok and len(answered) == eco.RIDDLE_FREE and all(x.correct for x in answered):
        events["riddle_perfect_day"] = 1
    gains = await progress.record(session, player, xp=eco.XP_RIDDLE_RIGHT if ok else eco.XP_RIDDLE_WRONG, **events)
    try:
        await session.commit()
    except IntegrityError:  # answered twice at the same moment
        await session.rollback()
        raise HTTPException(409, "already_answered") from None
    return RiddleAnswerOut(correct=ok, answer=r.answer, explain=r.explain, reward=reward, coins=player.coins,
                           item=_item(r, slot, a), gains=GainsOut(**gains.out()))
