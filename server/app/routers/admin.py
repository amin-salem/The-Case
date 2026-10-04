"""Admin tools. Every call needs the header  X-Admin-Key: <ADMIN_API_KEY>."""
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import case, delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from .. import economy as eco
from ..db import get_session
from ..models import Broadcast, CaseProgress, CoinLog, ConfigValue, InboxItem, Player, Purchase, utcnow
from ..schemas import ConfigIn, GiftIn
from ..security import require_admin
from ..services.remote_config import DEFAULTS, load_config
from ..util import ts

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])


@router.get("/stats")
async def stats(session: AsyncSession = Depends(get_session)):
    now = utcnow()
    day, month = now - timedelta(days=1), now - timedelta(days=30)

    async def count(stmt) -> int:
        return int(await session.scalar(stmt) or 0)

    today = content.todays_case()
    by_product = (await session.execute(select(Purchase.product_id, func.count()).where(
        Purchase.status == "granted", Purchase.created_at >= month).group_by(Purchase.product_id))).all()
    return {
        "players": await count(select(func.count()).select_from(Player)),
        "new_24h": await count(select(func.count()).select_from(Player).where(Player.created_at >= day)),
        "active_24h": await count(select(func.count()).select_from(Player).where(Player.last_seen >= day)),
        "today_case": today.id if today else None,
        "today_opened": await count(select(func.count()).select_from(CaseProgress).where(
            CaseProgress.case_id == (today.id if today else ""))),
        "today_solved": await count(select(func.count()).select_from(CaseProgress).where(
            CaseProgress.case_id == (today.id if today else ""), CaseProgress.solved.is_(True))),
        "cases_written": len(content.all_cases()),
        "cases_left_in_schedule": len([c for c in content.all_cases() if c not in content.opened()]),
        "purchases_30d": {p: n for p, n in by_product},
    }


@router.get("/cases")
async def cases_report(session: AsyncSession = Depends(get_session)):
    """Every case: when it opens, how many opened/solved it, average stars (to tune difficulty)."""
    rows = dict(((cid, (n, s, a)) for cid, n, s, a in (await session.execute(
        select(CaseProgress.case_id, func.count(),
               func.sum(case((CaseProgress.solved.is_(True), 1), else_=0)),
               func.avg(case((CaseProgress.solved.is_(True), CaseProgress.stars), else_=None)))
        .group_by(CaseProgress.case_id))).all()))
    out = []
    for c in content.all_cases():
        n, s, a = rows.get(c.id, (0, 0, None))
        out.append({**c.summary(), "opens_at": content.opens_at(c).isoformat(), "opened_by": int(n or 0),
                    "solved_by": int(s or 0), "avg_stars": round(float(a), 2) if a is not None else None})
    return out


@router.get("/players")
async def find_players(q: str = Query("", max_length=40), limit: int = Query(30, le=200),
                       session: AsyncSession = Depends(get_session)):
    stmt = select(Player).order_by(Player.last_seen.desc()).limit(limit)
    if q:
        stmt = stmt.where(or_(Player.nickname.contains(q), Player.invite_code == q.upper(),
                              Player.id.startswith(q), Player.email == q.lower()))
    return [{"id": p.id, "nickname": p.nickname, "coins": p.coins, "solved": p.cases_solved,
             "banned": p.banned, "last_seen": ts(p.last_seen)} for p in (await session.execute(stmt)).scalars().all()]


@router.get("/players/{player_id}")
async def player_detail(player_id: str, session: AsyncSession = Depends(get_session)):
    p = await session.get(Player, player_id)
    if p is None:
        raise HTTPException(404, "no_player")
    coins = (await session.execute(select(CoinLog).where(CoinLog.player_id == p.id)
                                   .order_by(CoinLog.id.desc()).limit(50))).scalars().all()
    prog = (await session.execute(select(CaseProgress).where(CaseProgress.player_id == p.id))).scalars().all()
    return {
        "player": {"id": p.id, "nickname": p.nickname, "email": p.email, "coins": p.coins, "streak": p.streak,
                   "solved": p.cases_solved, "stars": p.stars_total, "no_ads": p.no_ads,
                   "vip_until": ts(p.vip_until), "banned": p.banned, "created_at": ts(p.created_at)},
        "coin_log": [{"amount": c.amount, "reason": c.reason, "balance": c.balance, "at": ts(c.at)} for c in coins],
        "cases": [{"case": x.case_id, "solved": x.solved, "failed": x.failed, "stars": x.stars,
                   "hints": x.hints, "attempts": x.attempts, "seconds": x.seconds} for x in prog],
    }


class BanIn(BaseModel):
    banned: bool = True


@router.post("/players/{player_id}/ban")
async def ban(player_id: str, body: BanIn, session: AsyncSession = Depends(get_session)):
    p = await session.get(Player, player_id)
    if p is None:
        raise HTTPException(404, "no_player")
    p.banned = body.banned
    await session.commit()
    return {"id": p.id, "banned": p.banned}


@router.get("/config")
async def get_config(session: AsyncSession = Depends(get_session)):
    return await load_config(session)


@router.put("/config")
async def set_config(body: ConfigIn, session: AsyncSession = Depends(get_session)):
    unknown = [k for k in body.values if k not in DEFAULTS]
    if unknown:
        raise HTTPException(422, f"unknown keys: {unknown}")
    for key, value in body.values.items():
        row = await session.get(ConfigValue, key)
        if row is None:
            session.add(ConfigValue(key=key, value=value))
        else:
            row.value, row.updated_at = value, utcnow()
    await session.commit()
    return await load_config(session)


@router.delete("/config/{key}")
async def reset_config(key: str, session: AsyncSession = Depends(get_session)):
    await session.execute(delete(ConfigValue).where(ConfigValue.key == key))
    await session.commit()
    return await load_config(session)


@router.post("/gifts")
async def send_gift(body: GiftIn, session: AsyncSession = Depends(get_session)):
    try:
        grants = eco.check_grants(body.grants)
    except (ValueError, KeyError, TypeError) as e:
        raise HTTPException(422, str(e))
    exp = utcnow() + timedelta(days=body.expires_in_days) if body.expires_in_days else None
    if body.player_id:
        if await session.get(Player, body.player_id) is None:
            raise HTTPException(404, "no_player")
        item = InboxItem(player_id=body.player_id, title=body.title, message=body.message, grants=grants,
                         expires_at=exp)
        session.add(item)
        await session.commit()
        return {"sent_to": body.player_id, "id": f"p{item.id}"}
    b = Broadcast(title=body.title, message=body.message, grants=grants, expires_at=exp)
    session.add(b)
    await session.commit()
    return {"sent_to": "everyone", "id": f"b{b.id}"}
