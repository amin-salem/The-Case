"""Cases: today's case (free), the archive (bought with coins), hints and accusations."""
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import and_, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from .. import economy as eco
from ..content import Case
from ..db import get_session
from ..models import CaseProgress, Player, utcnow
from ..schemas import AccuseIn, AccuseOut, CaseOut, CaseRow, CasesOut, HintOut, ProgressOut
from ..security import current_player
from ..util import add_coins
from .common import vip_active

router = APIRouter(prefix="/v1/cases", tags=["cases"])


def _progress_out(c: Case, p: CaseProgress | None) -> ProgressOut:
    hints = p.hints if p else 0
    attempts = p.attempts if p else 0
    return ProgressOut(hints=c.hints[:hints], attempts=attempts,
                       attempts_left=max(0, eco.MAX_ATTEMPTS - attempts),
                       solved=bool(p and p.solved), failed=bool(p and p.failed), stars=p.stars if p else 0,
                       hint_costs=eco.HINT_COSTS)


async def _progress(session: AsyncSession, player_id: str, case_id: str) -> CaseProgress | None:
    return await session.scalar(select(CaseProgress).where(
        CaseProgress.player_id == player_id, CaseProgress.case_id == case_id))


def _opened_case(case_id: str) -> Case:
    c = content.by_id(case_id)
    if c is None or c not in content.opened():
        raise HTTPException(404, "no_case")
    return c


def _is_today(c: Case) -> bool:
    t = content.todays_case()
    return t is not None and t.id == c.id


def _can_open(c: Case, p: CaseProgress | None, player: Player) -> bool:
    return _is_today(c) or vip_active(player) or bool(p and (p.unlocked or p.solved or p.failed))


@router.get("", response_model=CasesOut)
async def list_cases(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    opened = content.opened()
    mine = {p.case_id: p for p in (await session.execute(
        select(CaseProgress).where(CaseProgress.player_id == player.id))).scalars().all()}
    counts = dict((await session.execute(
        select(CaseProgress.case_id, func.count()).where(CaseProgress.solved.is_(True))
        .group_by(CaseProgress.case_id))).all())
    today = content.todays_case()

    def row(c: Case) -> CaseRow:
        p = mine.get(c.id)
        s = c.summary()
        return CaseRow(**s, today=today is not None and c.id == today.id,
                       locked=not _can_open(c, p, player), unlock_cost=eco.UNLOCK_COST,
                       solved=bool(p and p.solved), failed=bool(p and p.failed),
                       stars=p.stars if p else 0, solvers=int(counts.get(c.id, 0)))

    archive = [row(c) for c in reversed(opened) if today is None or c.id != today.id]
    return CasesOut(today=row(today) if today else None,
                    next_case_at=int(content.next_case_at().timestamp()), archive=archive)


@router.get("/{case_id}", response_model=CaseOut)
async def get_case(case_id: str, player: Player = Depends(current_player),
                   session: AsyncSession = Depends(get_session)):
    c = _opened_case(case_id)
    p = await _progress(session, player.id, c.id)
    if not _can_open(c, p, player):
        raise HTTPException(402, {"error": "locked", "cost": eco.UNLOCK_COST})
    if p is None:
        p = CaseProgress(player_id=player.id, case_id=c.id, opened_at=utcnow())
        session.add(p)
        try:
            await session.commit()
        except IntegrityError:  # opened twice at the same moment
            await session.rollback()
            p = await _progress(session, player.id, c.id)
    data = c.public()
    if p is not None and (p.solved or p.failed):
        data["solution"] = c.data["solution"]  # finished: show how it was solved
    return CaseOut(case=data, progress=_progress_out(c, p), today=_is_today(c))


@router.post("/{case_id}/unlock", response_model=CaseOut)
async def unlock(case_id: str, player: Player = Depends(current_player),
                 session: AsyncSession = Depends(get_session)):
    c = _opened_case(case_id)
    p = await _progress(session, player.id, c.id)
    if not _can_open(c, p, player):
        if player.coins < eco.UNLOCK_COST:
            raise HTTPException(402, {"error": "not_enough_coins", "need": eco.UNLOCK_COST})
        add_coins(session, player, -eco.UNLOCK_COST, f"unlock:{c.id}")
        if p is None:
            p = CaseProgress(player_id=player.id, case_id=c.id)
            session.add(p)
        p.unlocked = True
        p.opened_at = utcnow()
        await session.commit()
    return await get_case(case_id, player, session)


@router.post("/{case_id}/hint", response_model=HintOut)
async def buy_hint(case_id: str, player: Player = Depends(current_player),
                   session: AsyncSession = Depends(get_session)):
    c = _opened_case(case_id)
    p = await _progress(session, player.id, c.id)
    if p is None or not _can_open(c, p, player):
        raise HTTPException(409, "open_case_first")
    if p.solved or p.failed:
        raise HTTPException(409, "case_finished")
    if p.hints >= len(c.hints):
        raise HTTPException(409, "no_more_hints")
    cost = 0 if (p.hints == 0 and vip_active(player)) else eco.HINT_COSTS[p.hints]
    if player.coins < cost:
        raise HTTPException(402, {"error": "not_enough_coins", "need": cost})
    if cost:
        add_coins(session, player, -cost, f"hint{p.hints + 1}:{c.id}")
    hint = c.hints[p.hints]
    p.hints += 1
    await session.commit()
    return HintOut(hint=hint, coins=player.coins, progress=_progress_out(c, p))


async def _daily_rank(session: AsyncSession, case_id: str, stars: int, seconds: int) -> int:
    better = await session.scalar(select(func.count()).select_from(CaseProgress).where(
        CaseProgress.case_id == case_id, CaseProgress.solved.is_(True), CaseProgress.was_daily.is_(True),
        or_(CaseProgress.stars > stars, and_(CaseProgress.stars == stars, CaseProgress.seconds < seconds))))
    return int(better or 0) + 1


@router.post("/{case_id}/accuse", response_model=AccuseOut)
async def accuse(case_id: str, body: AccuseIn, player: Player = Depends(current_player),
                 session: AsyncSession = Depends(get_session)):
    c = _opened_case(case_id)
    p = await _progress(session, player.id, c.id)
    if p is None or not _can_open(c, p, player):
        raise HTTPException(409, "open_case_first")
    if p.solved or p.failed:
        raise HTTPException(409, "case_finished")

    explanation = c.data["solution"]["explanation"]
    today_case = _is_today(c)
    today = content.today_str()

    if body.suspect == c.culprit and body.evidence in c.proof:
        now = utcnow()
        p.solved, p.finished_at, p.day, p.was_daily = True, now, today, today_case
        p.seconds = max(1, int((now - p.opened_at).total_seconds()))
        p.stars = eco.stars_for(p.hints, p.attempts)
        reward = eco.SOLVE_REWARD[p.stars]
        if today_case:
            reward += eco.DAILY_BONUS
            if player.last_daily_solved != today:
                yesterday = (date.fromisoformat(today) - timedelta(days=1)).isoformat()
                player.streak = player.streak + 1 if player.last_daily_solved == yesterday else 1
                player.best_streak = max(player.best_streak, player.streak)
                player.last_daily_solved = today
                if player.streak % eco.STREAK_BONUS_EVERY == 0:
                    reward += eco.STREAK_BONUS
        player.cases_solved += 1
        player.stars_total += p.stars
        add_coins(session, player, reward, f"solve:{c.id}")
        await session.commit()
        rank = await _daily_rank(session, c.id, p.stars, p.seconds) if today_case else None
        return AccuseOut(result="solved", attempts_left=eco.MAX_ATTEMPTS - p.attempts, stars=p.stars,
                         reward=reward, coins=player.coins, streak=player.streak, explanation=explanation,
                         culprit=c.culprit, proof=sorted(c.proof), rank=rank, progress=_progress_out(c, p))

    p.attempts += 1
    # right person but not the evidence that proves it: tell them (it's still a wrong try)
    result = "wrong_proof" if body.suspect == c.culprit else "wrong_suspect"
    if p.attempts >= eco.MAX_ATTEMPTS:
        p.failed, p.finished_at, p.day = True, utcnow(), today
        await session.commit()
        return AccuseOut(result="failed", attempts_left=0, coins=player.coins, streak=player.streak,
                         explanation=explanation, culprit=c.culprit, proof=sorted(c.proof),
                         progress=_progress_out(c, p))
    await session.commit()
    return AccuseOut(result=result, attempts_left=eco.MAX_ATTEMPTS - p.attempts, coins=player.coins,
                     streak=player.streak, progress=_progress_out(c, p))
