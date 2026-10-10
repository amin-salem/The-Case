"""Weekly leaderboard prizes. When a week (Saturday to Friday) ends, the best players of that week
get coins in their inbox, with a message. Safe to call any number of times: a week is paid once."""
import asyncio
from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import content
from .models import CaseProgress, InboxItem, Player

PRIZES = {1: 300, 2: 200, 3: 150}   # ranks 4..10 get PRIZE_REST
PRIZE_REST = 75
TOP_N = 10
_lock = asyncio.Lock()


def prize_for(rank: int) -> int:
    return PRIZES.get(rank, PRIZE_REST if rank <= TOP_N else 0)


def source_for(week_start: date) -> str:
    return f"wk:{week_start.isoformat()}"  # 13 chars, fits the 24-char column


async def settle_last_week(session: AsyncSession) -> int:
    """Pays the week that just ended (once). Returns how many players got a prize."""
    this_week = content.week_start(date.fromisoformat(content.today_str()))
    prev = this_week - timedelta(days=7)
    src = source_for(prev)
    async with _lock:
        done = await session.scalar(select(InboxItem.id).where(InboxItem.source == src).limit(1))
        if done is not None:
            return 0
        total = func.sum(CaseProgress.stars).label("total")
        q = (select(Player, total).join(CaseProgress, CaseProgress.player_id == Player.id)
             .where(CaseProgress.solved.is_(True), CaseProgress.day >= prev.isoformat(),
                    CaseProgress.day < this_week.isoformat(), Player.banned.is_(False))
             .group_by(Player.id).order_by(total.desc(), Player.created_at.asc()).limit(TOP_N))
        rows = (await session.execute(q)).all()
        for i, (pl, stars) in enumerate(rows, start=1):
            coins = prize_for(i)
            medal = {1: "🥇", 2: "🥈", 3: "🥉"}.get(i, "🏅")
            session.add(InboxItem(
                player_id=pl.id, source=src,
                title=f"جایزه‌ی هفته: رتبه‌ی {i} {medal}",
                message=f"تو هفته‌ی گذشته با {int(stars)} ستاره رتبه‌ی {i} جدول برترها شدی. این جایزه‌ی توئه!",
                grants=[{"type": "coins", "amount": coins}]))
        await session.commit()
        return len(rows)
