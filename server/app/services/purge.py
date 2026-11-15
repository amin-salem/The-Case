"""Support tool: delete accounts that are CERTAINLY worth nothing (admin only, previewed, confirmed, logged).

A row is a candidate only when it is a guest (no e-mail, no phone), is not a tester or banned, and holds nothing of
value: no solved case, no case opened at all, no purchase, no comment, no XP/stars/streak/warrants/VIP, no coins above
the starting gift, nobody was invited by it and it was not invited by anyone. On top of that ONE of:
  abandoned  created and last seen more than ABANDONED_DAYS ago (it never did anything and went away)
  orphan     shares its device id with an account that has an e-mail or phone, and is at least a day old
             (the app made a guest first, then the player signed in to the old account)
  smoke      a load-test row (device id «smoke-load-…»), at least a day old
If a deleted device comes back, the app's saved login is refused («wrong_login») and the app registers a new guest by
itself, so nothing breaks for the player. Every id is re-checked inside the transaction (under the player lock): an id
sent by the panel that no longer qualifies is skipped. At most MAX_BATCH rows per call."""
from __future__ import annotations

import logging
from datetime import timedelta

from sqlalchemy import and_, delete, exists, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from .. import economy as eco
from ..db import Base, lock_players
from ..models import AdminLog, CaseComment, CaseProgress, Player, Purchase, utcnow
from ..util import ts

log = logging.getLogger("purge")
ABANDONED_DAYS = 14
MIN_AGE = timedelta(days=1)
MAX_BATCH = 200
REASONS = ("abandoned", "orphan", "smoke")


def _worthless():
    P = Player
    twin = aliased(Player)
    return and_(
        P.email.is_(None), P.phone_hash.is_(None), P.tester.is_(False), P.banned.is_(False),
        P.cases_solved == 0, P.stars_total == 0, P.xp == 0, P.streak == 0, P.best_streak == 0, P.warrants == 0,
        P.no_ads.is_(False), P.vip_until.is_(None), P.coins <= eco.START_COINS, P.referred_by.is_(None),
        ~exists().where(CaseProgress.player_id == P.id), ~exists().where(Purchase.player_id == P.id),
        ~exists().where(CaseComment.player_id == P.id), ~exists().where(twin.referred_by == P.id))


def condition(reason: str, now=None):
    now = now or utcnow()
    P = Player
    if reason == "smoke":  # load-test rows are throw-away whatever they hold (never a tester)
        return and_(P.device_id.startswith("smoke-load-"), P.tester.is_(False), P.created_at < now - MIN_AGE)
    if reason == "abandoned":
        return and_(_worthless(), P.created_at < now - timedelta(days=ABANDONED_DAYS),
                    P.last_seen < now - timedelta(days=ABANDONED_DAYS))
    if reason == "orphan":
        other = aliased(Player)
        return and_(_worthless(), P.created_at < now - MIN_AGE,
                    exists().where(and_(other.device_id == P.device_id, other.id != P.id,
                                        or_(other.email.is_not(None), other.phone_hash.is_not(None)))))
    raise ValueError(reason)


def any_condition(now=None):
    return or_(*(condition(r, now) for r in REASONS))


async def preview(session: AsyncSession, limit: int = MAX_BATCH) -> dict:
    now = utcnow()
    counts = {r: int(await session.scalar(select(func.count()).select_from(Player).where(condition(r, now))) or 0)
              for r in REASONS}
    total = int(await session.scalar(select(func.count()).select_from(Player).where(any_condition(now))) or 0)
    rows = (await session.execute(select(Player).where(any_condition(now)).order_by(Player.created_at, Player.id)
                                  .limit(max(1, min(limit, MAX_BATCH))))).scalars().all()
    ids = [p.id for p in rows]
    why: dict[str, str] = {}
    for r in reversed(REASONS):  # the first reason in REASONS wins
        for pid in (await session.scalars(select(Player.id).where(Player.id.in_(ids), condition(r, now)))).all():
            why[pid] = r
    items = [{"id": p.id, "short_id": p.id[:6], "nickname": p.nickname, "reason": why.get(p.id, ""), "coins": p.coins,
              "created": ts(p.created_at), "last_seen": ts(p.last_seen)} for p in rows]
    return {"counts": counts, "total": total, "items": items, "max_batch": MAX_BATCH,
            "abandoned_days": ABANDONED_DAYS}


async def delete_rows(session: AsyncSession, ids: list[str]) -> None:
    """Delete these player rows and everything that hangs on them (no commit; the caller holds the player locks)."""
    for table in reversed(Base.metadata.sorted_tables):
        if table.name != "players" and "player_id" in table.c:
            await session.execute(delete(table).where(table.c.player_id.in_(ids)))
    await session.execute(delete(Player).where(Player.id.in_(ids)))


async def apply(session: AsyncSession, ids: list[str] | None) -> dict:
    """Delete the given ids (or, when None, the first MAX_BATCH candidates). Each is re-validated under its lock."""
    now = utcnow()
    if ids is None:
        ids = list((await session.scalars(select(Player.id).where(any_condition(now)).order_by(Player.created_at, Player.id)
                                          .limit(MAX_BATCH))).all())
    ids = sorted(set(ids))[:MAX_BATCH]
    if not ids:
        return {"ok": True, "deleted": 0, "skipped": 0}
    await lock_players(session, ids)
    ok = list((await session.scalars(select(Player.id).where(Player.id.in_(ids), any_condition(now)))).all())
    if ok:
        await delete_rows(session, ok)
        session.add(AdminLog(action="purge_players", target=f"{len(ok)} rows", detail={
            "n": len(ok), "skipped": len(ids) - len(ok), "ids": [i[:8] for i in ok[:50]]}))
    await session.commit()
    log.info("admin purge deleted=%d skipped=%d", len(ok), len(ids) - len(ok))
    return {"ok": True, "deleted": len(ok), "skipped": len(ids) - len(ok)}
