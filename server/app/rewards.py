"""Weekly leaderboard prizes. A week (app/gameclock.py: Friday 21:00 to the next Friday 21:00) is paid once, a few
minutes after it closed, from the SAME standings the board shows (weekboard.py): the best players of each league (or of
the single board when leagues are off) get coins in their inbox, with a message.
Safe to call any number of times and from any worker: the primary key of WeekSettlement lets exactly one caller pay."""
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from . import content, gameclock, weekboard
from .models import InboxItem, Player, WeekSettlement, utcnow
from .db import lock_players

# Weeks before this one were paid by the old rule (Saturday-to-Friday, archive solves counted) and are never touched.
FIRST_FAIR_WEEK = date(2026, 10, 16)

# kept for old imports/tests: the single-board prizes
PRIZES = weekboard.SINGLE_PRIZES
PRIZE_REST = weekboard.SINGLE_REST
TOP_N = weekboard.SINGLE_TOP_N


def prize_for(rank: int, league_mode: bool = False) -> int:
    return weekboard.prize_for(rank, league_mode)


def source_for(week_start: date, league: int | None = None) -> str:
    base = f"wk:{week_start.isoformat()}"  # 13 chars
    return base if league is None else f"{base}:{league}"  # fits the 24-char column


def settleable_weeks(now) -> list[date]:
    """The weeks that are closed (plus the safety margin) and not older than FIRST_FAIR_WEEK: the last two."""
    cur = gameclock.week_of(now)
    out = []
    for back in (1, 2):
        ws = cur - timedelta(days=7 * back)
        if ws >= FIRST_FAIR_WEEK and gameclock.settle_at(ws) <= now:
            out.append(ws)
    return sorted(out)


async def settle_last_week(session: AsyncSession) -> int:
    """Pays the closed weeks that are not paid yet. Returns how many players got a prize."""
    total = 0
    for ws in settleable_weeks(content.now_local()):
        total += await settle_week(session, ws)
    return total


async def settle_week(session: AsyncSession, ws: date) -> int:
    key = ws.isoformat()
    if await session.get(WeekSettlement, key) is not None:
        return 0
    league_mode = weekboard.leagues_on()
    n_rows = 0
    try:
        session.add(WeekSettlement(week=key, at=utcnow(), paid=0))
        await session.flush()  # the claim: a second caller fails here (primary key) and pays nothing
        winners = []  # (league or None, rank, Standing)
        if league_mode:
            await weekboard.ensure_snapshot(session, ws)
            for lg in range(len(weekboard.LEAGUES)):
                rows = await weekboard.standings(session, ws, league=lg, limit=weekboard.prizes(True)[2])
                winners += [(lg, i, s) for i, s in enumerate(rows, start=1) if s.cases >= weekboard.MIN_CASES_FOR_PRIZE]
        else:
            rows = await weekboard.standings(session, ws, limit=weekboard.prizes(False)[2])
            winners += [(None, i, s) for i, s in enumerate(rows, start=1) if s.cases >= weekboard.MIN_CASES_FOR_PRIZE]
        # the champion avatar and the loupe frame (granted on the player's next visit) stay scarce: only the top 3 of
        # the board, or of the highest league that has winners
        locked = await lock_players(session, [s.player.id for _, _, s in winners])
        top_league = max((lg for lg, _, _ in winners if lg is not None), default=None)
        for lg, rank, s in winners:
            pl: Player = locked[s.player.id]
            coins = weekboard.prize_for(rank, league_mode)
            if coins <= 0:
                continue
            if rank <= 3 and lg == top_league:
                pl.stats = {**(pl.stats or {}), "weekly_top3": int((pl.stats or {}).get("weekly_top3", 0)) + 1}
            medal = {1: "🥇", 2: "🥈", 3: "🥉"}.get(rank, "🏅")
            where = f" لیگ «{weekboard.LEAGUES[lg]}»" if lg is not None else ""
            session.add(InboxItem(
                player_id=pl.id, source=source_for(ws, lg),
                title=f"جایزه‌ی هفته: رتبه‌ی {rank}{where} {medal}",
                message=f"تو هفته‌ی گذشته با {s.points} پلاک رتبه‌ی {rank}{where} جدول برترها شدی. این جایزه‌ی توئه!",
                grants=[{"type": "coins", "amount": coins}]))
            n_rows += 1
        marker = await session.get(WeekSettlement, key)
        marker.paid = n_rows
        await session.commit()
    except IntegrityError:
        await session.rollback()
        return 0
    return n_rows

