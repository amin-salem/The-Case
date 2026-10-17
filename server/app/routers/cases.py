"""Cases: today's case (free), the archive (bought with coins), hints and accusations."""
import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import and_, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import anticheat as ac
from .. import content, gameclock, progress, ratings
from ..cache import TTLCache
from .. import economy as eco
from ..content import Case
from ..db import get_session
from ..models import CaseProgress, Player, utcnow
from ..schemas import (AccuseIn, AccuseOut, CaseOut, CaseRow, CasesOut, GainsOut, HintOut, ProgressOut, SeenIn, SeenOut,
                       ShowIn, ShowOut, StatsOut, SuspectStat, TickIn, TickOut)
from ..security import current_player
from ..util import add_coins
from .common import fast_json, vip_active
from .story import finish as story_finish, story_extra

router = APIRouter(prefix="/v1/cases", tags=["cases"])
log = logging.getLogger("cases")


MAX_WRONG_NOTES = 10


def _note_wrong(p: CaseProgress, body, kind: str) -> None:
    """Remember a wrong accusation (bounded) so the app can show it in red, now and after the case is solved."""
    tries = list(p.wrong_tries or [])
    if len(tries) < MAX_WRONG_NOTES:
        tries.append({"s": body.suspect, "e": body.evidence, "m": body.motive, "r": kind})
        p.wrong_tries = tries  # a new list, so the change is saved


NEUTRAL_REACTION = "اینو دیدم، ولی چیزی برای گفتن ندارم."


def _weekly_live(c: Case) -> bool:
    """A weekend case is "live" until it closes; after that it is an archive case (higher price, normal rewards)."""
    return content.is_weekly(c.id) and content.now_local() < content.weekly_closes_at(c)


def _unlock_cost(c: Case) -> int:
    return eco.WEEKEND_ARCHIVE_COST if content.is_weekly(c.id) else eco.UNLOCK_COST


def _shows_allowed(c: Case) -> int:
    """Evidence shows to suspects: a few for every chapter that is open (all of them once the case is in the archive)."""
    start, now = content.opens_at(c), content.now_local()
    from datetime import timedelta
    opened = sum(1 for ch in c.data["chapters"] if start + timedelta(hours=ch.get("at_hours", 0)) <= now)
    return eco.WEEKEND_SHOWS_PER_CHAPTER * max(1, opened)


def _reaction(c: Case, suspect: str, evidence: str) -> str:
    s = next((x for x in c.data["suspects"] if x["id"] == suspect), None) or {}
    return (s.get("reactions") or {}).get(evidence) or NEUTRAL_REACTION


def _progress_out(c: Case, p: CaseProgress | None) -> ProgressOut:
    hints = p.hints if p else 0
    attempts = p.attempts if p else 0
    return ProgressOut(hints=c.hints[:hints], attempts=attempts,
                       attempts_left=max(0, eco.MAX_ATTEMPTS - attempts),
                       solved=bool(p and p.solved), failed=bool(p and p.failed), stars=p.stars if p else 0,
                       hint_costs=eco.HINT_COSTS, answer_at=ac.answer_at_ts(p),
                       wrong_tries=list(p.wrong_tries or []) if p else [],
                       shows=[{"s": x["s"], "e": x["e"], "t": _reaction(c, x["s"], x["e"])} for x in (p.shows or [])]
                       if content.is_weekly(c.id) and p else [],
                       shows_left=max(0, _shows_allowed(c) - len(p.shows or [])) if content.is_weekly(c.id) and p else 0)


async def _progress(session: AsyncSession, player_id: str, case_id: str) -> CaseProgress | None:
    return await session.scalar(select(CaseProgress).where(
        CaseProgress.player_id == player_id, CaseProgress.case_id == case_id))


def _opened_case(case_id: str, player: Player) -> Case:
    if content.is_story(case_id):
        c = content.story_by_id(case_id)
        if c is None or not content.story_open_for(player):
            raise HTTPException(404, "no_case")
        return c
    if content.is_weekly(case_id):
        c = content.weekly_by_id(case_id)
        if c is None or content.opens_at(c) > content.now_local():
            raise HTTPException(404, "no_case")
        return c
    c = content.by_id(case_id)
    if c is None or content.opens_at(c) > content.now_local():  # same as "c not in content.opened()", without the list
        raise HTTPException(404, "no_case")
    return c


def _missed_between(last_solved: str, c: Case) -> int | None:
    """How many daily cases came between the last one solved (by publish date) and c.
    0 = c is the very next case; None = nothing solved before (or unknown)."""
    cases = content.all_cases()
    last = next((i for i, x in enumerate(cases) if x.publish.isoformat() == last_solved), None)
    if last is None:
        return None
    return cases.index(c) - last - 1


def add_active_time(p: CaseProgress, seconds: int, now) -> int:
    """Adds time the app says the case was open. Never more than really passed since the last
    report (plus a little slack), and at most TICK_MAX per report. Returns what was added."""
    since = p.last_tick_at or p.opened_at
    real = int((now - since).total_seconds()) + 5 if since else seconds
    add = max(0, min(seconds, eco.TICK_MAX, real))
    p.active_seconds = (p.active_seconds or 0) + add
    p.last_tick_at = now
    return add


def _is_today(c: Case, today: Case | None = ...) -> bool:
    """`today` may be passed by a caller that already knows today's case (the case list asks for 50 rows)."""
    t = content.todays_case() if today is ... else today
    return t is not None and t.id == c.id


def _can_open(c: Case, p: CaseProgress | None, player: Player, today: Case | None = ...) -> bool:
    if content.is_story(c.id):
        return p is not None  # a story chapter is opened on /v1/story, never bought here
    if content.is_weekly(c.id):
        if _weekly_live(c):
            return True  # the weekend case is free for everyone while it is open
        # once it closed it is an archive case (higher price), unless bought, played to the end, or VIP
        return vip_active(player) or bool(p and (p.unlocked or p.solved or p.failed))
    return _is_today(c, today) or vip_active(player) or bool(p and (p.unlocked or p.solved or p.failed))


_solvers = TTLCache("solver_counts", ttl=30, max_size=2)


async def _solver_counts(session: AsyncSession) -> dict[str, int]:
    """How many detectives solved each case: one aggregate over the whole progress table, the same for everybody
    and only decoration on the list, so it is shared for 30 s per worker instead of being run on every app start."""
    async def load():
        return {k: int(n) for k, n in (await session.execute(
            select(CaseProgress.case_id, func.count()).where(CaseProgress.solved.is_(True))
            .group_by(CaseProgress.case_id))).all()}
    return await _solvers.get_or_load("n", load)


@router.get("", response_model=CasesOut)  # the answer is already a validated model: sent as it is (fast_json)
async def list_cases(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    opened = content.opened()
    mine = {p.case_id: p for p in (await session.execute(
        select(CaseProgress).where(CaseProgress.player_id == player.id))).scalars().all()}
    counts = await _solver_counts(session)
    rated = await ratings.summary(session)
    my_stars = await ratings.mine(session, player.id)
    today = content.todays_case()

    def row(c: Case) -> CaseRow:
        p = mine.get(c.id)
        s = c.summary()
        return CaseRow(**s, today=today is not None and c.id == today.id,
                       weekend=content.is_weekly(c.id), locked=not _can_open(c, p, player, today), unlock_cost=_unlock_cost(c),
                       solved=bool(p and p.solved), failed=bool(p and p.failed),
                       stars=p.stars if p else 0, solvers=int(counts.get(c.id, 0)),
                       rating_avg=rated.get(c.id, (0.0, 0, 0))[0], rating_count=rated.get(c.id, (0.0, 0, 0))[1],
                       comment_count=rated.get(c.id, (0.0, 0, 0))[2], my_rating=my_stars.get(c.id, 0))

    archive = [row(c) for c in reversed(opened) if today is None or c.id != today.id]
    now = content.now_local()
    # expired weekend cases join the archive (newest first by publish date)
    archive += [row(c) for c in content.weekly_cases() if content.weekly_closes_at(c) <= now]
    archive.sort(key=lambda r: r.publish, reverse=True)
    weekly = content.current_weekly()
    return fast_json(CasesOut(today=row(today) if today else None,
                              next_case_at=int(content.next_case_at().timestamp()), archive=archive,
                              weekly=row(weekly) if weekly else None,
                              weekly_closes_at=int(content.weekly_closes_at(weekly).timestamp()) if weekly else None))


@router.get("/{case_id}", response_model=CaseOut)
async def get_case(case_id: str, player: Player = Depends(current_player),
                   session: AsyncSession = Depends(get_session)):
    c = _opened_case(case_id, player)
    p = await _progress(session, player.id, c.id)
    if not _can_open(c, p, player):
        if content.is_story(c.id):
            raise HTTPException(409, "chapter_locked")
        raise HTTPException(402, {"error": "locked", "cost": _unlock_cost(c)})
    if p is None:
        p = CaseProgress(player_id=player.id, case_id=c.id, opened_at=utcnow())
        session.add(p)
        try:
            await session.commit()
        except IntegrityError:  # opened twice at the same moment
            await session.rollback()
            p = await _progress(session, player.id, c.id)
    data = content.weekly_public(c) if content.is_weekly(c.id) else c.public()
    if content.is_story(c.id):
        for k in (*content.STORY_FIELDS, "partner_hints", "scenes", "ending", "board"):
            data.pop(k, None)
        data["story"] = story_extra(c, p)
    if ac.answer_visible(p):
        data["solution"] = c.data["solution"]  # solved, or lost and the answer is public now
    # every player sees suspects and evidence in their own order (ids unchanged)
    seed = f"{player.id}:{c.id}"
    for k in ("suspects", "evidence"):
        if isinstance(data.get(k), list):
            data[k] = ac.shuffled(data[k], f"{seed}:{k}")
    return fast_json(CaseOut(case=data, progress=_progress_out(c, p), today=_is_today(c)))


@router.post("/{case_id}/unlock", response_model=CaseOut)
async def unlock(case_id: str, player: Player = Depends(current_player),
                 session: AsyncSession = Depends(get_session)):
    c = _opened_case(case_id, player)
    p = await _progress(session, player.id, c.id)
    if content.is_story(c.id) and p is None:
        raise HTTPException(409, "chapter_locked")
    if not _can_open(c, p, player):
        cost = _unlock_cost(c)
        if player.coins < cost:
            raise HTTPException(402, {"error": "not_enough_coins", "need": cost})
        add_coins(session, player, -cost, f"unlock:{c.id}")
        await progress.record(session, player, case_unlock=1)
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
    c = _opened_case(case_id, player)
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
    gains = await progress.record(session, player, hint=1)
    await session.commit()
    return HintOut(hint=hint, coins=player.coins, progress=_progress_out(c, p), gains=GainsOut(**gains.out()))


async def _daily_rank(session: AsyncSession, case_id: str, stars: int, seconds: int) -> int:
    better = await session.scalar(select(func.count()).select_from(CaseProgress)
                                  .join(Player, Player.id == CaseProgress.player_id).where(
        CaseProgress.case_id == case_id, CaseProgress.solved.is_(True), CaseProgress.was_daily.is_(True),
        CaseProgress.ranked.is_(True), ac.visible_player(),
        or_(CaseProgress.stars > stars, and_(CaseProgress.stars == stars, CaseProgress.seconds < seconds))))
    return int(better or 0) + 1


@router.post("/{case_id}/accuse", response_model=AccuseOut)
async def accuse(case_id: str, body: AccuseIn, player: Player = Depends(current_player),
                 session: AsyncSession = Depends(get_session)):
    c = _opened_case(case_id, player)
    p = await _progress(session, player.id, c.id)
    if p is None or not _can_open(c, p, player):
        raise HTTPException(409, "open_case_first")
    if p.solved or p.failed:
        raise HTTPException(409, "case_finished")
    # weekend case: accusing is allowed from chapter 1 (a right early accusation pays a bonus, a wrong one costs a try)
    fmt2 = content.is_weekly(c.id) and c.data.get("format") == 2
    if fmt2 and not body.motive:
        raise HTTPException(422, "how_needed")

    explanation = c.data["solution"]["explanation"]
    add_active_time(p, body.extra_seconds, utcnow())  # once per accusation, before the judging below
    today_case = _is_today(c)
    today = gameclock.game_day(content.now_local()).isoformat()  # the GAME day it was finished (app/gameclock.py)
    if p.first_accused is None and body.suspect in {s["id"] for s in c.data["suspects"]}:
        p.first_accused = body.suspect  # the player's first instinct, for the "what others thought" stats

    weekly = content.is_weekly(c.id)
    live = _weekly_live(c)  # an expired weekend case in the archive pays like a normal archive case
    right_motive = not weekly or body.motive == c.data["solution"].get("motive")
    # two-part accusation (format 2): who + why/how. Culprit right = solved (3 stars if the second part is right too,
    # at most 2 if not); culprit wrong = a try is lost and the case stays open. Older cases: culprit + proof + motive.
    if fmt2 and body.suspect == c.culprit or (not fmt2 and body.suspect == c.culprit and body.evidence in c.proof and right_motive):
        now = utcnow()
        p.solved, p.finished_at, p.day, p.was_daily = True, now, today, today_case
        # apps that report their open time are timed by it; older apps by the clock since opening
        p.seconds = max(1, p.active_seconds) if p.active_seconds else max(1, int((now - p.opened_at).total_seconds()))
        natural = eco.stars_for(p.hints, p.attempts, p.proof_misses or 0)
        if fmt2 and not right_motive:
            natural = min(natural, 2)
        # proof of investigation: without enough time and interrogations it is still solved, but 1 star, no place
        proven = ac.proof_ok(p)
        p.stars, p.ranked = (natural if proven else 1), proven
        if not proven:
            log.info("anticheat unproven_solve case=%s active=%s seen=%d capped=%s", c.id, p.active_seconds,
                     len(p.seen or []), natural > 1)
        reward = (eco.WEEKLY_REWARD if live else eco.SOLVE_REWARD)[p.stars]
        early_bonus = 0
        if live and right_motive and content.now_local() < content.weekly_all_open_at(c):
            early_bonus = eco.WEEKLY_EARLY_BONUS  # solved before the last chapter opened
            reward += early_bonus
        freezes_used, badge, streak_up = 0, None, False
        if today_case:
            reward += eco.DAILY_BONUS
            # the streak counts daily cases in a row (by case, not by calendar day,
            # because a daily case stays "today's case" from 21:00 to 21:00)
            mine = c.publish.isoformat()
            if player.last_daily_solved != mine:
                missed = _missed_between(player.last_daily_solved, c)
                held = player.streak_freezes or 0
                if missed == 0:
                    player.streak += 1
                elif missed is not None and 0 < missed <= held and player.streak > 0:
                    # streak insurance covers the missed cases
                    player.streak_freezes = held - missed
                    freezes_used = missed
                    player.streak += 1
                else:
                    player.streak = 1
                player.best_streak = max(player.best_streak, player.streak)
                player.last_daily_solved = mine
                streak_up = True
                if player.streak % eco.STREAK_BONUS_EVERY == 0:
                    reward += eco.STREAK_BONUS
                if player.streak in eco.STREAK_BADGES:
                    badge = player.streak
        # story warrants are scarce (economy.warrants_for_solve): the first solve ever, a streak milestone, every
        # second live weekend case. Tonight's case and the daily missions no longer give one.
        warrants = eco.warrants_for_solve(first_ever=(player.cases_solved or 0) == 0, streak_up=streak_up,
                                          streak=player.streak, live=live,
                                          live_solved_before=int((player.stats or {}).get("weekly_solved", 0)))
        player.cases_solved += 1
        player.stars_total += p.stars
        add_coins(session, player, reward, f"solve:{c.id}")
        xp = eco.WEEKLY_XP[p.stars] if live else eco.XP_CASE[p.stars] + (eco.XP_DAILY_BONUS if today_case else 0)
        early = today_case and (content.now_local() - content.opens_at(c)).total_seconds() <= 30 * 60
        gains = await progress.record(
            session, player, xp=xp, case_solved=1, daily_solved=int(today_case),
            case_3stars=int(p.stars == 3), case_no_hint=int(p.hints == 0),
            first_try=int(p.attempts == 0 and not p.proof_misses), fast5=int(p.seconds <= 300),
            fast2=int(p.seconds <= 120 and not weekly), early_daily=int(early), weekly_solved=int(live), warrants=warrants)
        await story_finish(session, player.id, c.id, p)
        await session.commit()
        _solvers.clear()  # this worker shows the new solver count at once; the others within 30 s
        await ac.maybe_pay_referral(player.id)
        rank = (await _daily_rank(session, c.id, p.stars, p.seconds)
                if today_case and p.ranked and ac.is_visible(player) else None)
        return AccuseOut(result="solved", unranked=not p.ranked, stars_capped=natural > p.stars,
                         attempts_left=eco.MAX_ATTEMPTS - p.attempts, stars=p.stars,
                         reward=reward, coins=player.coins, streak=player.streak, explanation=explanation,
                         culprit=c.culprit, proof=sorted(c.proof), rank=rank, progress=_progress_out(c, p),
                         seconds=p.seconds, hints_used=p.hints, freezes_used=freezes_used, badge=badge,
                         gains=GainsOut(**gains.out()), story=story_extra(c, p) if content.is_story(c.id) else None,
                         early_bonus=early_bonus, how_right=right_motive if fmt2 else None)

    # right person but not the evidence that proves it (or, in the weekly case, the wrong motive):
    # the first few times it costs a star, not a try
    near = "wrong_motive" if body.evidence in c.proof else "wrong_proof"
    if body.suspect == c.culprit and not ac.proof_ok(p):
        # anti-cheat: "right person, wrong proof" tells a probing throwaway account who the culprit is. Only a player
        # who has really investigated (the same bar as 3 stars) gets this hint; a hasty accusation gets the plain
        # «wrong» answer and loses a try. Fair players investigate first, so for them nothing changes.
        near = "wrong_suspect"
        log.info("anticheat plain_wrong case=%s active=%s seen=%d", c.id, p.active_seconds, len(p.seen or []))
    elif body.suspect == c.culprit and (p.proof_misses or 0) < eco.FREE_PROOF_MISSES:
        p.proof_misses = (p.proof_misses or 0) + 1
        _note_wrong(p, body, near)
        await session.commit()
        return AccuseOut(result=near, attempts_left=eco.MAX_ATTEMPTS - p.attempts, coins=player.coins,
                         streak=player.streak, progress=_progress_out(c, p))
    p.attempts += 1
    result = near if body.suspect == c.culprit else "wrong_suspect"
    # a hasty accusation of the real culprit is answered with the plain «wrong»: the note says so, so a later review is honest
    _note_wrong(p, body, "hasty" if (body.suspect == c.culprit and result == "wrong_suspect") else result)
    if p.attempts >= eco.MAX_ATTEMPTS:
        p.failed, p.finished_at, p.day = True, utcnow(), today
        p.reveal_at = ac.reveal_time(c, ac.now_utc())  # the answer stays secret until then
        gains = await progress.record(session, player, xp=eco.XP_CASE_FAILED, case_failed=1)
        await story_finish(session, player.id, c.id, p)
        await session.commit()
        shown = ac.answer_visible(p)
        return AccuseOut(result="failed", attempts_left=0, coins=player.coins, streak=player.streak,
                         explanation=explanation if shown else None, culprit=c.culprit if shown else None,
                         proof=sorted(c.proof) if shown else [], answer_at=ac.answer_at_ts(p),
                         progress=_progress_out(c, p), hints_used=p.hints, gains=GainsOut(**gains.out()),
                         story=story_extra(c, p) if content.is_story(c.id) else None)
    await session.commit()
    return AccuseOut(result=result, attempts_left=eco.MAX_ATTEMPTS - p.attempts, coins=player.coins,
                     streak=player.streak, progress=_progress_out(c, p))


@router.post("/{case_id}/show", response_model=ShowOut)
async def show_evidence(case_id: str, body: ShowIn, player: Player = Depends(current_player),
                        session: AsyncSession = Depends(get_session)):
    """Weekend case: show one evidence card to one suspect and get what the suspect says. A few shows per opened
    chapter; showing the same card to the same suspect again is free (it only repeats the answer)."""
    c = _opened_case(case_id, player)
    if not content.is_weekly(c.id):
        raise HTTPException(404, "no_case")
    # the progress row is locked, so two requests at once cannot spend the same show twice
    p = await session.scalar(select(CaseProgress).where(
        CaseProgress.player_id == player.id, CaseProgress.case_id == c.id).with_for_update())
    if p is None or not _can_open(c, p, player):
        raise HTTPException(409, "open_case_first")
    if p.solved or p.failed:
        raise HTTPException(409, "case_finished")
    if body.suspect not in {s["id"] for s in c.data["suspects"]}:
        raise HTTPException(404, "no_suspect")
    if body.evidence not in {e["id"] for e in content.weekly_public(c)["evidence"]}:
        raise HTTPException(404, "no_evidence")  # unknown, or its chapter is not open yet
    shows = list(p.shows or [])
    if not any(x["s"] == body.suspect and x["e"] == body.evidence for x in shows):
        if len(shows) >= _shows_allowed(c):
            raise HTTPException(409, "no_shows_left")
        shows.append({"s": body.suspect, "e": body.evidence})
        p.shows = shows  # a new list, so the change is saved
        await session.commit()
        log.info("weekend show case=%s used=%d", c.id, len(shows))
    out = _progress_out(c, p)
    return ShowOut(suspect=body.suspect, evidence=body.evidence, text=_reaction(c, body.suspect, body.evidence),
                   shows_left=out.shows_left, progress=out)


@router.get("/{case_id}/stats", response_model=StatsOut)
async def stats(case_id: str, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """What everyone else thought: shown only after the player has finished the case (no spoilers)."""
    c = _opened_case(case_id, player)
    p = await _progress(session, player.id, c.id)
    if p is None or not (p.solved or p.failed):
        raise HTTPException(409, "finish_first")
    firsts = dict((await session.execute(
        select(CaseProgress.first_accused, func.count()).where(
            CaseProgress.case_id == c.id, CaseProgress.first_accused.is_not(None))
        .group_by(CaseProgress.first_accused))).all())
    guessed = sum(firsts.values())
    finished_q = select(func.count()).select_from(CaseProgress).where(
        CaseProgress.case_id == c.id, or_(CaseProgress.solved.is_(True), CaseProgress.failed.is_(True)))
    finished = int(await session.scalar(finished_q) or 0)
    solved = int(await session.scalar(select(func.count()).select_from(CaseProgress).where(
        CaseProgress.case_id == c.id, CaseProgress.solved.is_(True))) or 0)
    first_try = int(await session.scalar(select(func.count()).select_from(CaseProgress).where(
        CaseProgress.case_id == c.id, CaseProgress.solved.is_(True), CaseProgress.attempts == 0)) or 0)

    def pct(n: int, of: int) -> int:
        return round(100 * n / of) if of else 0

    return StatsOut(players=finished, solved_pct=pct(solved, finished), first_try_pct=pct(first_try, finished),
                    culprit="" if ac.answer_pending(p) else c.culprit,
                    suspects=[SuspectStat(id=s["id"], pct=pct(int(firsts.get(s["id"], 0)), guessed))
                              for s in c.data["suspects"]])


@router.post("/{case_id}/seen", response_model=SeenOut)
async def seen(case_id: str, body: SeenIn, player: Player = Depends(current_player),
               session: AsyncSession = Depends(get_session)):
    """The app says a suspect's interrogation was opened (for the "interrogate everyone" mission)."""
    c = _opened_case(case_id, player)
    p = await _progress(session, player.id, c.id)
    if p is None or not _can_open(c, p, player):
        raise HTTPException(409, "open_case_first")
    ids = [s["id"] for s in c.data["suspects"]]
    if body.suspect not in ids:
        raise HTTPException(404, "no_suspect")
    before = set(p.seen or [])
    after = before | {body.suspect}
    # The weekend mission counts the suspects a player talks to *today*, even ones already met on an
    # earlier day (a player who solved the case still has to be able to finish it).
    daily_new = 0
    if content.is_weekly(c.id):
        day = content.mission_day_str()
        stats = dict(player.stats or {})
        wk = stats.get("wk_seen") or {}
        today_ids = set(wk.get("ids", [])) if wk.get("day") == day else set()
        key = f"{c.id}:{body.suspect}"
        if key not in today_ids:
            daily_new = 1
            stats["wk_seen"] = {"day": day, "ids": sorted(today_ids | {key})}
            player.stats = stats
    gains = None
    if after != before or daily_new:
        new = len(after - before)
        if new:
            p.seen = sorted(after)
        gains = await progress.record(session, player, suspect_seen=new, weekly_seen=daily_new,
                                      interrogate_all=int(bool(new) and after >= set(ids)))
        await session.commit()
    return SeenOut(seen=len(after), total=len(ids), gains=GainsOut(**gains.out()) if gains else GainsOut())


@router.post("/{case_id}/tick", response_model=TickOut)
async def tick(case_id: str, body: TickIn, player: Player = Depends(current_player),
               session: AsyncSession = Depends(get_session)):
    """The app reports, every half minute and when leaving, how long the case screen was open."""
    c = _opened_case(case_id, player)
    p = await _progress(session, player.id, c.id)
    if p is None:
        raise HTTPException(409, "open_case_first")
    if not (p.solved or p.failed):
        add_active_time(p, body.seconds, utcnow())
        await session.commit()
    return TickOut(active_seconds=p.active_seconds or 0)
