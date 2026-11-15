"""Duplicate accounts (READ ONLY): one device id shared by 2+ Player rows is probably one person counted twice.

How it happens: a secured player (email/phone on the SAME row) opens the app on a new phone or after clearing data;
the app registers a new guest row first, then the player signs in to the old account, which takes the new device id
(routers/auth.py _login_as). The new guest row stays behind as an orphan with the same device id.

Nothing here changes data. Queries use plain columns only (no GROUP BY on bound expressions: asyncpg refuses that),
use the index on players.device_id, and are bounded (MAX_GROUPS groups, MAX_ROWS rows)."""
import logging
from datetime import timedelta

from sqlalchemy import and_, distinct, exists, func, not_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from ..db import lock_players
from ..models import AdminLog, Player, Purchase, utcnow
from ..util import ts
from . import purge as purge_service

log = logging.getLogger("duplicates")
HIDE_DAYS = 30         # a hidden row is deleted for good this many days later, if nobody used it since
MAX_HIDE = 100         # rows per call

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
    return (select(Player.device_id, func.count(Player.id).label("n")).where(Player.hidden_at.is_(None))
            .group_by(Player.device_id).having(func.count(Player.id) > 1))


async def summary(session: AsyncSession) -> dict:
    total = int(await session.scalar(select(func.count()).select_from(Player).where(Player.hidden_at.is_(None))) or 0)
    devices = int(await session.scalar(select(func.count(distinct(Player.device_id))).where(Player.hidden_at.is_(None))) or 0)
    hidden = int(await session.scalar(select(func.count()).select_from(Player).where(Player.hidden_at.is_not(None))) or 0)
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
            "probable_orphans": orphans, "real_people_estimate": total - orphans, "hidden": hidden}


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
    rows = (await session.execute(select(Player).where(Player.device_id.in_(ids), Player.hidden_at.is_(None))
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
        # the row to KEEP first: the secured one, else the one that did the most; then the orphans, then the rest
        items.sort(key=lambda i: ({"secured": 0, "orphan": 2, "guest": 1}[i["role"]], -int(i["solved"] or 0), i["created"] or 0))
        for k, i in enumerate(items):
            i["keep"] = k == 0
            i["can_hide"] = k > 0 and i["role"] != "secured" and not i["purchases"]
        out["groups"].append({"device": _short(dev) + "…", "rows": n, "shown": len(items), "players": items})
    return out


# ------------------------------------------------------------------ hide / restore / delete for good (Amin, 15 Nov 2026)
async def hidden_list(session: AsyncSession, limit: int = 200) -> dict:
    """Rows the admin hid, with the day each one is deleted for good (only when nobody used it since)."""
    now = utcnow()
    rows = (await session.execute(select(Player).where(Player.hidden_at.is_not(None))
                                  .order_by(Player.hidden_at.desc(), Player.id).limit(max(1, min(limit, 200))))).scalars().all()
    items = []
    for p in rows:
        used = (p.last_seen or p.hidden_at) > p.hidden_at + timedelta(days=1)
        due = p.hidden_at + timedelta(days=HIDE_DAYS)
        items.append({"id": p.id, "short_id": _short(p.id), "nickname": p.nickname, "solved": p.cases_solved, "coins": p.coins,
                      "hidden_at": ts(p.hidden_at), "delete_at": ts(due), "used_since": used, "due": due <= now and not used})
    return {"items": items, "ready": sum(1 for i in items if i["due"]), "days": HIDE_DAYS}


async def hide(session: AsyncSession, ids: list[str]) -> dict:
    """Hide duplicate rows of a device. Each id is re-checked under the player lock: it must be a visible guest (no e-mail,
    no phone) without a purchase, and its device must keep at least one other visible row (the one that stays)."""
    ids = sorted(set(ids))[:MAX_HIDE]
    if not ids:
        return {"ok": True, "hidden": 0, "skipped": 0}
    await lock_players(session, ids)
    rows = (await session.execute(select(Player).where(Player.id.in_(ids)))).scalars().all()
    bought = set((await session.scalars(select(Purchase.player_id).where(Purchase.player_id.in_(ids)))).all())
    devs = {p.device_id for p in rows}
    alive: dict[str, int] = {}
    for d, n in (await session.execute(select(Player.device_id, func.count(Player.id)).where(
            Player.device_id.in_(devs), Player.hidden_at.is_(None)).group_by(Player.device_id))).all():
        alive[d] = int(n)
    now, done = utcnow(), []
    for p in sorted(rows, key=lambda r: (r.cases_solved or 0, r.created_at)):   # the least used go first
        if p.hidden_at is not None or p.email or p.phone_hash or p.id in bought or alive.get(p.device_id, 0) < 2:
            continue
        p.hidden_at = now
        alive[p.device_id] -= 1
        done.append(p.id)
    if done:
        session.add(AdminLog(action="hide_duplicates", target=f"{len(done)} rows", detail={"n": len(done), "ids": [i[:8] for i in done[:50]]}))
    await session.commit()
    log.info("duplicates hidden=%d skipped=%d", len(done), len(ids) - len(done))
    return {"ok": True, "hidden": len(done), "skipped": len(ids) - len(done)}


async def restore(session: AsyncSession, ids: list[str]) -> dict:
    ids = sorted(set(ids))[:MAX_HIDE]
    if not ids:
        return {"ok": True, "restored": 0}
    await lock_players(session, ids)
    rows = (await session.execute(select(Player).where(Player.id.in_(ids), Player.hidden_at.is_not(None)))).scalars().all()
    for p in rows:
        p.hidden_at = None
    if rows:
        session.add(AdminLog(action="restore_duplicates", target=f"{len(rows)} rows", detail={"n": len(rows), "ids": [p.id[:8] for p in rows[:50]]}))
    await session.commit()
    return {"ok": True, "restored": len(rows)}


async def purge_expired(session: AsyncSession) -> dict:
    """Delete for good the rows hidden at least HIDE_DAYS days ago that nobody used since (last seen within a day of the
    hiding). A row that came back to life stays hidden and is listed with used_since=true for the admin to decide."""
    now = utcnow()
    cand = (await session.execute(select(Player.id, Player.hidden_at, Player.last_seen).where(
        Player.hidden_at.is_not(None), Player.hidden_at < now - timedelta(days=HIDE_DAYS)).limit(MAX_HIDE))).all()
    ids = [i for i, h, seen in cand if (seen or h) <= h + timedelta(days=1)]
    if not ids:
        return {"ok": True, "deleted": 0, "kept": len(cand)}
    await lock_players(session, ids)
    ok = list((await session.scalars(select(Player.id).where(Player.id.in_(ids), Player.hidden_at.is_not(None),
                                                            ~exists().where(Purchase.player_id == Player.id)))).all())
    if ok:
        await purge_service.delete_rows(session, ok)
        session.add(AdminLog(action="purge_hidden", target=f"{len(ok)} rows", detail={"n": len(ok), "ids": [i[:8] for i in ok[:50]]}))
    await session.commit()
    log.info("duplicates purged=%d kept=%d", len(ok), len(cand) - len(ok))
    return {"ok": True, "deleted": len(ok), "kept": len(cand) - len(ok)}
