"""Duplicate accounts (READ ONLY): one device id shared by 2+ Player rows is probably one person counted twice.

How it happens: a secured player (email/phone on the SAME row) opens the app on a new phone or after clearing data;
the app registers a new guest row first, then the player signs in to the old account, which takes the new device id
(routers/auth.py _login_as). The new guest row stays behind as an orphan with the same device id.

Nothing here changes data. Queries use plain columns only (no GROUP BY on bound expressions: asyncpg refuses that),
use the index on players.device_id, and are bounded (MAX_GROUPS groups, MAX_ROWS rows)."""
from sqlalchemy import and_, distinct, exists, func, not_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from ..models import Player, Purchase
from ..util import ts

MAX_GROUPS = 200       # at most this many device groups are ever listed
MAX_ROWS = 2000        # and at most this many player rows in total (a device with thousands of rows is cut)


def _secured(p):
    return or_(p.email.is_not(None), p.phone_hash.is_not(None))


def _guest(p):
    return and_(p.email.is_(None), p.phone_hash.is_(None))


def _short(value: str, n: int = 6) -> str:
    return (value or "")[:n]


def _groups_stmt():
    """Device ids shared by more than one row, the biggest groups first."""
    return (select(Player.device_id, func.count(Player.id).label("n")).group_by(Player.device_id)
            .having(func.count(Player.id) > 1))


async def summary(session: AsyncSession) -> dict:
    total = int(await session.scalar(select(func.count()).select_from(Player)) or 0)
    devices = int(await session.scalar(select(func.count(distinct(Player.device_id)))) or 0)
    grouped = _groups_stmt().subquery()
    groups = int(await session.scalar(select(func.count()).select_from(grouped)) or 0)
    rows_in_groups = int(await session.scalar(select(func.coalesce(func.sum(grouped.c.n), 0))) or 0)
    other = aliased(Player)
    has_secured_twin = exists().where(and_(other.device_id == Player.device_id, other.id != Player.id, _secured(other)))
    has_purchase = exists().where(Purchase.player_id == Player.id)
    orphans = int(await session.scalar(select(func.count()).select_from(Player).where(
        _guest(Player), Player.cases_solved == 0, Player.banned.is_(False), Player.tester.is_(False),
        has_secured_twin, not_(has_purchase))) or 0)
    return {"players": total, "devices": devices, "groups": groups, "rows_in_groups": rows_in_groups,
            "probable_orphans": orphans, "real_people_estimate": total - orphans}


async def groups(session: AsyncSession, limit: int = 50, offset: int = 0) -> dict:
    """The summary plus one page of groups (never beyond MAX_GROUPS). A group lists its rows: the secured one(s),
    the probable orphan guest(s) and anything else. Only a nickname, a short id and a phone's last 4 digits."""
    limit = max(1, min(int(limit), MAX_GROUPS))
    offset = max(0, int(offset))
    out = {"summary": await summary(session), "groups": [], "max_groups": MAX_GROUPS}
    take = min(limit, MAX_GROUPS - offset)
    if take <= 0:
        return out
    g = _groups_stmt().order_by(func.count(Player.id).desc(), Player.device_id).limit(take).offset(offset)
    devs = [(d, n) for d, n in (await session.execute(g)).all()]
    if not devs:
        return out
    ids = [d for d, _ in devs]
    rows = (await session.execute(select(Player).where(Player.device_id.in_(ids))
                                  .order_by(Player.device_id, Player.created_at, Player.id).limit(MAX_ROWS))).scalars().all()
    pids = [p.id for p in rows]
    bought = {}
    if pids:
        bought = {pid: int(c) for pid, c in (await session.execute(
            select(Purchase.player_id, func.count(Purchase.id)).where(Purchase.player_id.in_(pids))
            .group_by(Purchase.player_id))).all()}
    by_dev: dict[str, list] = {}
    for p in rows:
        by_dev.setdefault(p.device_id, []).append(p)
    for dev, n in devs:
        members = by_dev.get(dev, [])
        has_sec = any(p.email or p.phone_hash for p in members)
        items = []
        for p in members:
            sec = bool(p.email or p.phone_hash)
            orphan = (has_sec and not sec and p.cases_solved == 0 and not p.banned and not p.tester
                      and not bought.get(p.id))
            items.append({
                "id": p.id, "short_id": _short(p.id), "nickname": p.nickname,
                "role": "secured" if sec else ("orphan" if orphan else "guest"),
                "email": bool(p.email), "phone_last4": p.phone_last4 if p.phone_hash else None,
                "solved": p.cases_solved, "coins": p.coins, "purchases": bought.get(p.id, 0),
                "banned": bool(p.banned), "tester": bool(p.tester),
                "created": ts(p.created_at), "last_seen": ts(p.last_seen)})
        # the secured row first, then the orphans, then the rest
        items.sort(key=lambda i: {"secured": 0, "orphan": 1, "guest": 2}[i["role"]])
        out["groups"].append({"device": _short(dev) + "…", "rows": n, "shown": len(items), "players": items})
    return out
