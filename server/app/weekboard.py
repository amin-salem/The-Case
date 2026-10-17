"""The weekly board, in one place: «this week's points», the leagues, and the prizes.

ONE definition of «this week's points» (used by the board in routers/leaderboard.py and by the prize settlement in
rewards.py, so they can never disagree):

- Only the week's OWN cases count: the nightly cases and the weekend case whose release moment lies inside the week
  (app/gameclock.py: Friday 21:00 to the next Friday 21:00). A case belongs to the week it was published in, no matter
  when it is solved. Archive purchases of older cases never count here (they still give coins, plaques, album).
- A solve counts only while the week is open: finished before the next week's first case is released. After that the
  case is archive for the board.
- Only solved, ranked (investigated) solves of visible players count. Points = stars.
- Order: points, then more cases solved (consistency), then less total time, then older account.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import date

from sqlalchemy import case as sql_case
from sqlalchemy import func, literal, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import anticheat as ac
from . import content, gameclock
from . import economy as eco
from .cache import TTLCache
from .config import get_settings
from .models import CaseProgress, Player, WeekLeague

log = logging.getLogger("weekboard")

LEAGUES = ("تازه‌کار", "کارآگاه", "بازرس", "سرپرست")
# a league starts at the XP of these ranks of economy.RANKS: تازه‌کار (دستیار) | کارآگاه (ارشد) | بازرس (سربازرس) | نخبه and up
LEAGUE_FROM_RANK = (0, 2, 4, 6)
MARKER = "*"          # WeekLeague row: «the snapshot of this week exists»
MIN_CASES_FOR_PRIZE = 2   # a prize needs at least this many of the week's cases solved (an empty league is no free coins)
BOARD_TTL = 45        # seconds a board is kept per worker
_boards = TTLCache("weekly_board", ttl=BOARD_TTL, max_size=64)


@dataclass(frozen=True)
class Standing:
    player: Player
    points: int
    cases: int
    seconds: int


def league_min_xp() -> tuple[int, ...]:
    return tuple(eco.RANKS[i][0] for i in LEAGUE_FROM_RANK)


def league_for_xp(xp: int) -> int:
    mins = league_min_xp()
    return max(i for i, need in enumerate(mins) if (xp or 0) >= need)


def leagues_on() -> bool:
    return bool(get_settings().leagues_enabled)


def week_filters(ws: date):
    """SQL conditions of "a CaseProgress row counts for week ws" (the shared definition)."""
    ids = [c.id for c in content.week_cases(ws)] or ["-"]
    close = gameclock.to_utc_naive(gameclock.week_end(ws))
    return [CaseProgress.case_id.in_(ids), CaseProgress.solved.is_(True), CaseProgress.ranked.is_(True),
            CaseProgress.finished_at.is_not(None), CaseProgress.finished_at < close]


def counts_for_week(c: content.Case, finished_at_utc) -> date | None:
    """Pure helper (tests, docs): the week a solve of case c counts for, or None when it is archive."""
    ws = content.case_week(c)
    return ws if gameclock.to_utc_naive(gameclock.week_end(ws)) > finished_at_utc else None


# ------------------------------------------------------------------ leagues
async def ensure_snapshot(session: AsyncSession, ws: date) -> None:
    """Takes the league snapshot of week ws once (atomic: the marker row is part of it). Players who solved nothing
    yet are not stored; they play in league 0."""
    key = ws.isoformat()
    if await session.scalar(select(WeekLeague.week).where(WeekLeague.week == key, WeekLeague.player_id == MARKER)):
        return
    mins = league_min_xp()
    expr = sql_case((Player.xp >= mins[3], 3), (Player.xp >= mins[2], 2), (Player.xp >= mins[1], 1), else_=0)
    dialect = session.bind.dialect.name if session.bind is not None else "sqlite"
    if dialect == "postgresql":
        from sqlalchemy.dialects.postgresql import insert
    else:
        from sqlalchemy.dialects.sqlite import insert
    cols = ["week", "player_id", "league"]
    body = select(literal(key), Player.id, expr).where(Player.cases_solved > 0)
    await session.execute(insert(WeekLeague).from_select(cols, body).on_conflict_do_nothing())
    await session.execute(insert(WeekLeague).values(week=key, player_id=MARKER, league=0).on_conflict_do_nothing())
    await session.commit()
    log.info("league snapshot week=%s", key)


async def league_of(session: AsyncSession, ws: date, player_id: str) -> int:
    await ensure_snapshot(session, ws)
    v = await session.scalar(select(WeekLeague.league).where(WeekLeague.week == ws.isoformat(), WeekLeague.player_id == player_id))
    return int(v or 0)


# ------------------------------------------------------------------ standings
def _base(ws: date, league: int | None):
    pts = func.sum(CaseProgress.stars).label("pts")
    n = func.count(CaseProgress.id).label("n")
    secs = func.sum(CaseProgress.seconds).label("secs")
    q = select(Player, pts, n, secs).join(CaseProgress, CaseProgress.player_id == Player.id)
    if league is not None:
        q = q.outerjoin(WeekLeague, (WeekLeague.week == ws.isoformat()) & (WeekLeague.player_id == Player.id))
        q = q.where(func.coalesce(WeekLeague.league, 0) == league)
    q = q.where(*week_filters(ws), ac.visible_player())
    return q.group_by(Player.id)


async def standings(session: AsyncSession, ws: date, *, league: int | None = None, limit: int = 100) -> list[Standing]:
    """The top `limit` players of the week (of one league, or of everybody when league is None)."""
    q = _base(ws, league).order_by(func.sum(CaseProgress.stars).desc(), func.count(CaseProgress.id).desc(),
                                   func.sum(CaseProgress.seconds).asc(), Player.created_at.asc(), Player.id.asc()).limit(limit)
    return [Standing(pl, int(p), int(n), int(s or 0)) for pl, p, n, s in (await session.execute(q)).all()]


async def my_standing(session: AsyncSession, ws: date, player: Player, league: int | None) -> tuple[int, int] | None:
    """(rank, points) of one player, however far down: counts the players ahead of him (ties by points, cases, time)."""
    q = select(func.sum(CaseProgress.stars), func.count(CaseProgress.id), func.sum(CaseProgress.seconds)).where(
        *week_filters(ws), CaseProgress.player_id == player.id)
    pts, n, secs = (await session.execute(q)).one()
    if not n:
        return None
    pts, n, secs = int(pts), int(n), int(secs or 0)
    sub = _base(ws, league).with_only_columns(Player.id, func.sum(CaseProgress.stars).label("pts"),
                                              func.count(CaseProgress.id).label("n"),
                                              func.sum(CaseProgress.seconds).label("secs")).subquery()
    ahead = await session.scalar(select(func.count()).select_from(sub).where(
        (sub.c.pts > pts) | ((sub.c.pts == pts) & (sub.c.n > n)) | ((sub.c.pts == pts) & (sub.c.n == n) & (sub.c.secs < secs))))
    return int(ahead or 0) + 1, pts


async def cached_rows(session: AsyncSession, ws: date, league: int | None, limit: int) -> list[dict]:
    """The top rows as plain dicts, cached per worker for BOARD_TTL seconds (the data is the same for everybody)."""
    from . import avatars
    from .routers.common import rank_title

    async def load():
        rows = await standings(session, ws, league=league, limit=limit)
        return [{"id": s.player.id, "nickname": s.player.nickname, "avatar": s.player.avatar,
                 "avatar_id": avatars.avatar_key(s.player), "avatar_frame": avatars.frame_key(s.player),
                 "points": s.points, "rank_title": rank_title(s.player)} for s in rows]
    return await _boards.get_or_load((ws.isoformat(), league, limit), load, now_wall=content.now_local(),
                                     valid_until_of=lambda _v: gameclock.week_end(ws))


# ------------------------------------------------------------------ prizes
LEAGUE_PRIZES = {1: 120, 2: 80, 3: 50}      # per league: 4 x 250 = 1000 coins a week, less than the old single board (1175)
SINGLE_PRIZES = {1: 300, 2: 200, 3: 150}    # the single board (leagues off): ranks 4..10 get SINGLE_REST
SINGLE_REST = 75
SINGLE_TOP_N = 10


def prizes(league_mode: bool) -> tuple[dict[int, int], int, int]:
    """(prize by rank, prize for the other ranks up to top_n, top_n)."""
    return (LEAGUE_PRIZES, 0, 3) if league_mode else (SINGLE_PRIZES, SINGLE_REST, SINGLE_TOP_N)


def prize_for(rank: int, league_mode: bool = False) -> int:
    by_rank, rest, top_n = prizes(league_mode)
    return by_rank.get(rank, rest if rank <= top_n else 0)
