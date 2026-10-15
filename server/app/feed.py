"""The messages hub: one merged, bounded feed (gifts, badges, case/weekend openings, announcements).

Nothing is stored for the feed itself except Player.feed_seen_at: an item is unread when it is newer than that.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import achievements, content
from .cache import TTLCache
from .config import get_settings
from .models import Broadcast, BroadcastClaim, InboxItem, Player, PlayerAchievement, utcnow
from .services.remote_config import load_value, stamp_of
from .util import ts

MAX_ITEMS = 40
WINDOW_DAYS = 14
_KINDS = ("gift", "case", "story", "weekend", "badge", "streak", "system")


def _coins(grants: list | None) -> int:
    return sum(int(g.get("amount", 0)) for g in (grants or []) if isinstance(g, dict) and g.get("type") == "coins")


def _utc(dt: datetime) -> datetime:
    """Aware local time -> naive UTC (the database way)."""
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


# The "a case / a weekend chapter opened" news does not depend on the player or on the clock (the clock only decides
# whether an item is already in the past, which build_feed checks per item), so it is built once per worker.
_openings = TTLCache("feed_openings", ttl=60, max_size=4)


def _static_openings() -> list[tuple]:
    """(id, kind, title, body, opening moment as naive UTC) for every nightly case and weekend chapter."""
    st = get_settings()
    key = (st.new_case_hour, st.timezone)
    hit = _openings.get_sync(key)
    if hit is not None:
        return hit
    out: list[tuple] = []
    for c in content.all_cases():
        out.append((f"c{c.id}", "case", f"پرونده‌ی «{c.data.get('title', '')}» باز شد", c.data.get("location") or "",
                    _utc(content.opens_at(c))))
    for c in content.weekly_cases():
        start = content.opens_at(c)
        chapters = c.data.get("chapters") or []
        title = c.data.get("title", "")
        for n, ch in enumerate(chapters, start=1):
            at = _utc(start + timedelta(hours=ch.get("at_hours", 0)))
            if n == 1:
                out.append((f"w{c.id}1", "weekend", f"پرونده‌ی آخر هفته باز شد: «{title}»", c.data.get("location") or "", at))
            else:
                out.append((f"w{c.id}{n}", "weekend", f"فصل {n} از {len(chapters)} باز شد: «{title}»", "مدارک تازه رسید.", at))
    _openings.put_sync(key, out)
    return out


async def build_feed(session: AsyncSession, player: Player, now: datetime | None = None) -> list[dict]:
    """Newest first, at most MAX_ITEMS, from the last WINDOW_DAYS days. `now` is naive UTC."""
    now = now or utcnow()
    since = now - timedelta(days=WINDOW_DAYS)
    seen = player.feed_seen_at
    rows: list[dict] = []

    def add(id_: str, kind: str, title: str, body: str, at: datetime, gift_id: str | None = None, reward: int = 0):
        if at > now or at < since:
            return
        rows.append({"id": id_, "kind": kind, "title": str(title)[:80], "body": str(body)[:400], "at": ts(at),
                     "unread": seen is None or at > seen, "gift_id": gift_id, "reward": reward})

    # gifts (personal ones may be claimed; the app claims them with the existing /v1/inbox/{id}/claim)
    for g in (await session.execute(select(InboxItem).where(
            InboxItem.player_id == player.id, InboxItem.created_at >= since)
            .order_by(InboxItem.id.desc()).limit(MAX_ITEMS))).scalars():
        live = g.claimed_at is None and (g.expires_at is None or g.expires_at > now)
        add(f"p{g.id}", "gift", g.title, g.message, g.created_at, f"p{g.id}" if live else None, _coins(g.grants))
    claimed = select(BroadcastClaim.broadcast_id).where(BroadcastClaim.player_id == player.id)
    for b in (await session.execute(select(Broadcast).where(
            Broadcast.created_at >= since, Broadcast.id.not_in(claimed),
            or_(Broadcast.expires_at.is_(None), Broadcast.expires_at > now))
            .order_by(Broadcast.id.desc()).limit(20))).scalars():
        add(f"b{b.id}", "gift", b.title, b.message, b.created_at, f"b{b.id}", _coins(b.grants))

    # badges earned recently
    by_id = {a.id: a for a in achievements.ALL}
    for aid, at in (await session.execute(select(PlayerAchievement.achievement_id, PlayerAchievement.at).where(
            PlayerAchievement.player_id == player.id, PlayerAchievement.at >= since)
            .order_by(PlayerAchievement.at.desc()).limit(MAX_ITEMS))).all():
        a = by_id.get(aid)
        if a:
            add(f"a{aid}", "badge", f"نشان «{a.title}»", a.desc, at, reward=a.coins)

    # openings that already happened (only those after the player joined: older ones are not news to them)
    born = player.created_at or since
    local_now = now.replace(tzinfo=timezone.utc).astimezone(content._tz())
    for id_, kind, title, body, at in _static_openings():
        if at >= born:  # items in the future (not opened yet) are dropped by add()
            add(id_, kind, title, body, at)
    try:  # story mode is paused while its opening time is in the future
        if content.story_opens_at() <= local_now and content.story_chapters():
            at = _utc(content.story_opens_at())
            if at >= born:
                add("s1", "story", f"داستان «{content.STORY_SEASON['title']}» شروع شد", content.STORY_SEASON["tagline"], at)
    except Exception:
        pass

    # announcements from the remote config (`news`: a list of {title, body, at?})
    try:
        news = await load_value(session, "news") or []
        stamp = await stamp_of(session, "news")
        for i, n in enumerate(news[:5] if isinstance(news, list) else []):
            if isinstance(n, str):
                n = {"title": n}
            if not isinstance(n, dict) or not n.get("title"):
                continue
            at = utcnow()
            if isinstance(n.get("at"), int):
                at = datetime.fromtimestamp(n["at"], timezone.utc).replace(tzinfo=None)
            elif stamp:
                at = stamp
            add(f"n{i}", "system", n["title"], n.get("body", ""), min(at, now))
    except Exception:
        pass

    rows.sort(key=lambda r: (r["at"], r["id"]), reverse=True)
    return rows[:MAX_ITEMS]


async def unread_count(session: AsyncSession, player: Player) -> int:
    return sum(1 for r in await build_feed(session, player) if r["unread"])
