"""Leaderboards: today's case (most plaques, then fastest), this week (plaques of the week's own cases, per league), all time,
a streak board and the player sheet.

Every list is bounded (limit <= 100, offset <= 1000), ordered by a total order (so pages never overlap) and answers
`next_offset` while more rows exist. My own place and the gap to the place above are computed with COUNT queries, never by
loading the whole board. Nothing here writes."""
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import anticheat as ac
from .. import achievements, avatars, content, economy, gameclock, streakrepair, weekboard
from ..cache import TTLCache
from ..db import get_session
from ..models import CaseProgress, Player, PlayerAchievement, WeekLeague
from ..schemas import (CardAchievement, DailyStats, LeagueInfo, LeagueWeek, LeaderboardOut, LeaderRow, PlayerCardOut, RankGap,
                       StreakBoardOut)
from ..security import current_player
from ..util import ts
from .common import rank_title

router = APIRouter(prefix="/v1", tags=["leaderboard"])

MAX_OFFSET = 1000
WEEKLY_WINDOW = 200            # the weekly board is cached per worker as the first N rows
STREAK_CANDIDATES = 300        # the streak board looks at the N longest STORED streaks, then drops the dead ones
CARD_WEEKS = 6                 # league history on the player sheet
_streaks = TTLCache("streak_board", ttl=60, max_size=2)


def _tonight():
    """Tonight's case (one place, so a test can name its own)."""
    return content.todays_case()


def _row(pl: Player, live: streakrepair.LiveStreak, rank: int, value: int, *, me_id: str, stars: int = 0, league: str = "") -> LeaderRow:
    return LeaderRow(rank=rank, nickname=pl.nickname, avatar=pl.avatar, avatar_id=avatars.avatar_key(pl),
                     avatar_frame=avatars.frame_key(pl), streak=live.of(pl), value=value, stars=stars, me=pl.id == me_id,
                     rank_title=rank_title(pl), league_name=league, pid=pl.id)


def _gap(rank: int, mine: int, above: int | None, unit: str, *, lower_is_better: bool = False) -> RankGap | None:
    """The distance to the place above, as the amount needed to PASS it (so never 0)."""
    if rank <= 1 or above is None:
        return None
    diff = (mine - above + 1) if lower_is_better else (above - mine + 1)
    return RankGap(next_rank=rank - 1, diff=max(1, diff), unit=unit)


@router.get("/leaderboard", response_model=LeaderboardOut)
async def leaderboard(period: str = Query("daily", pattern="^(daily|weekly|all)$"),
                      limit: int = Query(50, ge=1, le=100),
                      offset: int = Query(0, ge=0, le=MAX_OFFSET),
                      league: int | None = Query(None, ge=0, le=7),
                      player: Player = Depends(current_player),
                      session: AsyncSession = Depends(get_session)):
    live = streakrepair.LiveStreak()  # the flame: one lookup per row, no extra query
    if period == "daily":
        return await _daily(player, limit, offset, session, live)
    if period == "weekly":
        return await _weekly(player, league, limit, offset, session, live)
    return await _all_time(player, limit, offset, session, live)


# ------------------------------------------------------------------ daily
def _daily_conds(case_id: str):
    return [CaseProgress.case_id == case_id, CaseProgress.solved.is_(True), CaseProgress.was_daily.is_(True),
            CaseProgress.ranked.is_(True), ac.visible_player()]


_DAILY_ORDER = (CaseProgress.stars.desc(), CaseProgress.seconds.asc(), CaseProgress.id.asc())


async def _daily(player, limit, offset, session, live) -> LeaderboardOut:
    c = _tonight()
    if c is None:
        raise HTTPException(404, "no_case")
    conds = _daily_conds(c.id)
    q = (select(Player, CaseProgress.stars, CaseProgress.seconds)
         .join(CaseProgress, CaseProgress.player_id == Player.id).where(*conds)
         .order_by(*_DAILY_ORDER).offset(offset).limit(limit + 1))
    rows = (await session.execute(q)).all()
    more = len(rows) > limit
    out = [_row(pl, live, offset + i + 1, secs, me_id=player.id, stars=st) for i, (pl, st, secs) in enumerate(rows[:limit])]
    me = next((r for r in out if r.me), None)
    gap = None
    mine = (await session.execute(
        select(CaseProgress.id, CaseProgress.stars, CaseProgress.seconds).join(Player, CaseProgress.player_id == Player.id)
        .where(*conds, CaseProgress.player_id == player.id))).first()
    if mine is not None:
        pid, st, secs = mine
        ahead = await session.scalar(
            select(func.count()).select_from(CaseProgress).join(Player, CaseProgress.player_id == Player.id).where(
                *conds, or_(CaseProgress.stars > st,
                            and_(CaseProgress.stars == st, CaseProgress.seconds < secs),
                            and_(CaseProgress.stars == st, CaseProgress.seconds == secs, CaseProgress.id < pid))))
        rank = int(ahead or 0) + 1
        if me is None:
            me = _row(player, live, rank, secs, me_id=player.id, stars=st)
        if rank > 1:
            above = (await session.execute(
                select(CaseProgress.stars, CaseProgress.seconds).join(Player, CaseProgress.player_id == Player.id)
                .where(*conds).order_by(*_DAILY_ORDER).offset(rank - 2).limit(1))).first()
            if above is not None:
                a_st, a_secs = above
                # more plaques up there: the gap is in plaques; the same plaques: in seconds (to be faster)
                gap = (_gap(rank, st, a_st, "plaque") if a_st > st
                       else _gap(rank, secs, a_secs, "seconds", lower_is_better=True))
    stats = await _daily_summary(session, c.id)
    return LeaderboardOut(period="daily", title=f"پرونده‌ی امروز: {c.data['title']}", top=out, me=me, gap=gap, daily=stats,
                          next_offset=offset + limit if more else None)


async def _daily_summary(session: AsyncSession, case_id: str) -> DailyStats:
    """Fresh totals and ranked times from one database snapshot, shared by all workers through SQL.

    ONE definition of "the rows of tonight's table": `_daily_conds` (solved tonight, ranked, visible player). The header
    count, the fastest time, the mean and the median all come from exactly those rows, so the header never disagrees with
    the table. Times use only valid durations (seconds > 0)."""
    eligible = (select(CaseProgress.seconds.label("seconds"))
                .join(Player, CaseProgress.player_id == Player.id)
                .where(*_daily_conds(case_id)).cte("daily_eligible"))
    timed = (select(eligible.c.seconds,
                    func.row_number().over(order_by=eligible.c.seconds).label("rn"),
                    func.count().over().label("n"))
             .where(eligible.c.seconds > 0).cte("daily_timed"))
    middle = func.abs(2 * timed.c.rn - timed.c.n - 1) <= 1
    q = select(
        select(func.count()).select_from(eligible).scalar_subquery().label("solved"),
        select(func.min(timed.c.seconds)).scalar_subquery().label("fastest"),
        select(func.avg(timed.c.seconds)).where(middle).scalar_subquery().label("median"),
        select(func.avg(timed.c.seconds)).scalar_subquery().label("mean"),
    )
    row = (await session.execute(q)).one()

    def whole(v):
        return None if v is None else int(float(v) + 0.5)

    return DailyStats(solved=int(row.solved), fastest=None if row.fastest is None else int(row.fastest),
                      median=None if row.median is None else int(row.median), mean=whole(row.mean))


# ------------------------------------------------------------------ all time
async def _all_time(player, limit, offset, session, live) -> LeaderboardOut:
    visible = ac.visible_player()
    order = (Player.stars_total.desc(), Player.cases_solved.desc(), Player.id.asc())
    rows = (await session.execute(select(Player).where(visible, Player.stars_total > 0)
                                  .order_by(*order).offset(offset).limit(limit + 1))).scalars().all()
    more = len(rows) > limit
    out = [_row(pl, live, offset + i + 1, pl.stars_total, me_id=player.id, stars=pl.stars_total) for i, pl in enumerate(rows[:limit])]
    me = next((r for r in out if r.me), None)
    gap = None
    if player.stars_total > 0 and ac.is_visible(player):
        ahead = await session.scalar(select(func.count()).select_from(Player).where(
            visible, or_(Player.stars_total > player.stars_total,
                         and_(Player.stars_total == player.stars_total, Player.cases_solved > player.cases_solved),
                         and_(Player.stars_total == player.stars_total, Player.cases_solved == player.cases_solved,
                              Player.id < player.id))))
        rank = int(ahead or 0) + 1
        if me is None:
            me = _row(player, live, rank, player.stars_total, me_id=player.id, stars=player.stars_total)
        if rank > 1:
            above = await session.scalar(select(Player.stars_total).where(visible, Player.stars_total > 0)
                                         .order_by(*order).offset(rank - 2).limit(1))
            gap = _gap(rank, player.stars_total, above, "plaque")
    return LeaderboardOut(period="all", title="همه‌ی زمان‌ها", top=out, me=me, gap=gap,
                          next_offset=offset + limit if more else None)


# ------------------------------------------------------------------ weekly
async def _weekly(player: Player, league: int | None, limit: int, offset: int, session: AsyncSession,
                  live: streakrepair.LiveStreak) -> LeaderboardOut:
    """The week's own cases only (weekboard.py has the rule); one league at a time, the player's own by default."""
    ws = gameclock.week_of(content.now_local())
    on = weekboard.leagues_on()
    mine = await weekboard.league_of(session, ws, player.id) if on else None
    shown = (league if league is not None else mine) if on else None
    window = min(offset + limit + 1, WEEKLY_WINDOW)
    rows = await weekboard.cached_rows(session, ws, shown, window)
    page = rows[offset:offset + limit] if offset < WEEKLY_WINDOW else []
    more = len(rows) > offset + limit and offset + limit < WEEKLY_WINDOW
    lname = weekboard.LEAGUES[shown] if shown is not None else ""
    out = [LeaderRow(rank=offset + i + 1, nickname=r["nickname"], avatar=r["avatar"], avatar_id=r["avatar_id"],
                     avatar_frame=r["avatar_frame"], streak=r.get("streak", 0), value=r["points"], stars=r["points"],
                     me=r["id"] == player.id, rank_title=r["rank_title"], league_name=lname, pid=r["id"])
           for i, r in enumerate(page)]
    me = next((r for r in out if r.me), None)
    gap = None
    if (shown is None or shown == mine) and ac.is_visible(player):
        idx = next((i for i, r in enumerate(rows) if r["id"] == player.id), None)
        if idx is not None:
            rank, pts = idx + 1, rows[idx]["points"]
            above = rows[idx - 1]["points"] if idx > 0 else None
            if me is None:
                me = LeaderRow(rank=rank, nickname=player.nickname, avatar=player.avatar, avatar_id=avatars.avatar_key(player),
                               avatar_frame=avatars.frame_key(player), streak=live.of(player), value=pts, stars=pts, me=True,
                               rank_title=rank_title(player), league_name=lname, pid=player.id)
        else:
            st = await weekboard.my_standing(session, ws, player, shown)
            rank, pts, above = (st[0], st[1], None) if st is not None else (0, 0, None)
            if st is not None:
                me = LeaderRow(rank=rank, nickname=player.nickname, avatar=player.avatar, avatar_id=avatars.avatar_key(player),
                               avatar_frame=avatars.frame_key(player), streak=live.of(player), value=pts, stars=pts, me=True,
                               rank_title=rank_title(player), league_name=lname, pid=player.id)
                if rank > 1:
                    prev = await weekboard.standings(session, ws, league=shown, limit=1, offset=rank - 2)
                    above = prev[0].points if prev else None
        if rank:
            gap = _gap(rank, pts, above, "plaque")
    title = "این هفته" + (f" · لیگ {weekboard.LEAGUES[shown]}" if shown is not None else "")
    return LeaderboardOut(period="weekly", title=title, top=out, me=me, week_ends_at=int(gameclock.week_end(ws).timestamp()),
                          league=shown, my_league=mine, gap=gap, next_offset=offset + limit if more else None,
                          leagues=[LeagueInfo(**weekboard.league_info(i)) for i in range(len(weekboard.LEAGUES))] if on else [])


# ------------------------------------------------------------------ streaks
async def _streak_ranking(session: AsyncSession, live: streakrepair.LiveStreak) -> list[LeaderRow]:
    """Visible players by LIVE streak, longest first. Reads the STREAK_CANDIDATES longest stored streaks (indexed), then drops
    the ones that are already dead (LiveStreak). Same for everybody, cached per worker for 60 s as plain rows (never ORM objects)."""
    async def load():
        q = (select(Player).where(ac.visible_player(), Player.streak > 0)
             .order_by(Player.streak.desc(), Player.id.asc()).limit(STREAK_CANDIDATES))
        found = [(live.of(pl), pl) for pl in (await session.execute(q)).scalars().all()]
        found = sorted([f for f in found if f[0] > 0], key=lambda f: (-f[0], f[1].id))
        return [_row(pl, live, 0, n, me_id="") for n, pl in found]
    return await _streaks.get_or_load("all", load)


@router.get("/leaderboard/streaks", response_model=StreakBoardOut)
async def streak_board(limit: int = Query(30, ge=1, le=100), offset: int = Query(0, ge=0, le=MAX_OFFSET),
                       player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    live = streakrepair.LiveStreak()
    ranking = await _streak_ranking(session, live)
    top = [r.model_copy(update={"rank": offset + i + 1, "me": r.pid == player.id})
           for i, r in enumerate(ranking[offset:offset + limit])]
    mine_live = live.of(player)
    me, gap = None, None
    if ac.is_visible(player) and mine_live > 0:
        idx = next((i for i, r in enumerate(ranking) if r.pid == player.id), None)
        if idx is not None:
            me = ranking[idx].model_copy(update={"rank": idx + 1, "me": True})
            gap = _gap(idx + 1, mine_live, ranking[idx - 1].value if idx > 0 else None, "nights")
        else:
            me = _row(player, live, 0, mine_live, me_id=player.id)   # rank 0 = below the candidates: no place is shown
    return StreakBoardOut(top=top, me=me, my_best=max(int(player.best_streak or 0), mine_live), gap=gap,
                          next_offset=offset + limit if offset + limit < len(ranking) else None)


# ------------------------------------------------------------------ player sheet
MIN_FASTEST = 10               # seconds: a faster "solve" is not shown as a record


def league_of(xp: int) -> int:
    """The league a player's profile rank belongs to (weekboard.LEAGUE_FROM_RANK is the one place that decides)."""
    r = economy.rank_of(int(xp or 0))
    return max(i for i, first in enumerate(weekboard.LEAGUE_FROM_RANK) if r >= first)


def _metal(a: achievements.Achievement) -> int:
    """Bronze / silver / gold by how far along its chain a tier is."""
    n = len(achievements.CHAIN_BY_ID[a.chain].tiers) if a.chain in achievements.CHAIN_BY_ID else 0
    if n <= 0 or a.tier <= 0:
        return 0
    f = a.tier / n
    return 0 if f <= 0.34 else 1 if f <= 0.67 else 2


async def member_no(session: AsyncSession, pl: Player) -> int:
    """Signup order: how many players registered before him (and he himself). Uses ix_players_created_at."""
    return int(await session.scalar(select(func.count()).select_from(Player).where(or_(
        Player.created_at < pl.created_at, and_(Player.created_at == pl.created_at, Player.id <= pl.id)))) or 0)


async def fastest_solve(session: AsyncSession, pid: str) -> int:
    """The fastest solve of a MAIN case. Only cases that exist in today's content count: the old quick puzzles (solved in
    10-20 seconds) are gone from the game, and their rows must not become anybody's record (Amin, 12 Nov 2026). Only RANKED
    solves count too: a case solved without enough investigation (ranked=false) is not on any board, so it is no record either."""
    secs = case((CaseProgress.active_seconds > 0, CaseProgress.active_seconds), else_=CaseProgress.seconds)
    main_ids = [c.id for c in content.all_cases()] + [c.id for c in content.weekly_cases()]
    best = await session.scalar(select(func.min(secs)).where(
        CaseProgress.player_id == pid, CaseProgress.solved.is_(True), CaseProgress.ranked.is_(True),
        CaseProgress.case_id.in_(main_ids), secs >= MIN_FASTEST))
    return int(best or 0)

@router.get("/players/{pid}/card", response_model=PlayerCardOut)
async def player_card(pid: str, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Public numbers of one detective for the sheet that opens from a board row. Hidden players (banned, testers, new
    unsecured accounts) answer 404 like a missing one, so the endpoint cannot be used to find them."""
    if len(pid) > 32:
        raise HTTPException(404, "no_player")
    pl = player if pid == player.id else await session.get(Player, pid)
    if pl is None or (pl.id != player.id and not ac.is_visible(pl)):
        raise HTTPException(404, "no_player")
    ws = gameclock.week_of(content.now_local())
    weeks = [(ws - timedelta(days=7 * k)).isoformat() for k in range(CARD_WEEKS)]
    got = {w: lg for w, lg in (await session.execute(
        select(WeekLeague.week, WeekLeague.league).where(WeekLeague.week.in_(weeks), WeekLeague.player_id == pl.id))).all()}
    hist = [LeagueWeek(week=w, league=weekboard.LEAGUES[min(int(got[w]), len(weekboard.LEAGUES) - 1)]) for w in weeks if w in got]
    live = streakrepair.LiveStreak().of(pl)
    got_ach = (await session.execute(select(PlayerAchievement.achievement_id, PlayerAchievement.at).where(
        PlayerAchievement.player_id == pl.id).order_by(PlayerAchievement.at.desc(), PlayerAchievement.id.desc()).limit(3))).all()
    recent = [CardAchievement(title=a.title, group=a.group, metal=_metal(a), at=ts(at) or 0)
              for aid, at in got_ach if (a := achievements.BY_ID.get(aid)) is not None]
    lg = league_of(pl.xp)
    return PlayerCardOut(pid=pl.id, nickname=pl.nickname, avatar=pl.avatar, avatar_id=avatars.avatar_key(pl),
                         avatar_frame=avatars.frame_key(pl), rank_title=rank_title(pl), cases_solved=int(pl.cases_solved or 0),
                         stars_total=int(pl.stars_total or 0), streak=live, best_streak=max(int(pl.best_streak or 0), live),
                         league_history=hist, league=lg, league_name=weekboard.LEAGUES[lg],
                         member_no=await member_no(session, pl), since=ts(pl.created_at) or 0,
                         fastest=await fastest_solve(session, pl.id), recent=recent)
