"""Admin tools. Every call needs the header  X-Admin-Key: <ADMIN_API_KEY>."""
import logging
import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import case, delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import cheatreport, content, purge
from .. import economy as eco
from ..db import get_session
from ..models import AdminLog, Broadcast, CaseProgress, CoinLog, ConfigValue, InboxItem, Player, Purchase, utcnow
from ..schemas import ConfigIn, GiftIn
from ..security import hash_secret, make_token, new_secret, require_admin
from ..services import sms
from ..services.remote_config import DEFAULTS, invalidate as invalidate_config, load_config
from ..util import add_coins, default_nickname, ts, unique_invite_code

log = logging.getLogger("admin")
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
             "banned": p.banned, "tester": p.tester, "last_seen": ts(p.last_seen)} for p in (await session.execute(stmt)).scalars().all()]


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
    session.add(AdminLog(action="ban" if body.banned else "unban", target=p.id, detail={"nickname": p.nickname}))
    await session.commit()
    return {"id": p.id, "banned": p.banned}


class SmokeBulkIn(BaseModel):
    n: int = Field(default=100, ge=1, le=500)


@router.post("/players/smoke-bulk")
async def smoke_bulk(body: SmokeBulkIn, session: AsyncSession = Depends(get_session)):
    """For tools/load_test.py: makes up to 500 throw-away players (device id «smoke-load-…») and returns their tokens, so a
    load test does not hit the per-IP registration limit. Remove them with purge-smoke (the test deletes them itself)."""
    run = uuid.uuid4().hex[:6]
    made = []
    for i in range(body.n):
        player = Player(secret_hash=hash_secret(new_secret()), device_id=f"smoke-load-{run}-{i}", app_version=1,
                        nickname=default_nickname(), invite_code=await unique_invite_code(session), token_gen=0, coins=0)
        session.add(player)
        await session.flush()
        add_coins(session, player, eco.START_COINS, "welcome")
        made.append(player)
    session.add(AdminLog(action="smoke_bulk", target=f"smoke-load-{run}", detail={"n": body.n}))
    await session.commit()
    return {"players": [{"player_id": p.id, "token": make_token(p.id, 0)[0]} for p in made]}


@router.post("/players/purge-smoke")
async def purge_smoke_players(session: AsyncSession = Depends(get_session)):
    """Deletes every test player whose device id starts with «smoke-» (made by tools/smoke_test.py), completely.
    Up to 1000 per call; call again if "more" is true."""
    ids = await purge.smoke_player_ids(session, 1000)
    n = await purge.purge_players(session, ids)
    session.add(AdminLog(action="purge_smoke", target="smoke-*", detail={"deleted": n}))
    await session.commit()
    return {"deleted": n, "more": len(ids) >= 1000}


@router.get("/cheat-report")
async def cheat_report(days: int = Query(7, ge=1, le=60), session: AsyncSession = Depends(get_session)):
    """Devices with many accounts, solves under 60 s of active time, new accounts giving the same answer within
    minutes. Ban a player with POST /admin/players/{id}/ban."""
    return await cheatreport.build(session, days)


@router.post("/cheat-report/weekly")
async def cheat_report_weekly(session: AsyncSession = Depends(get_session)):
    """Writes this week's summary into the admin log now (it also happens by itself once a week)."""
    return {"stored": await cheatreport.store_weekly(session)}


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
    invalidate_config()
    return await load_config(session)


@router.delete("/config/{key}")
async def reset_config(key: str, session: AsyncSession = Depends(get_session)):
    await session.execute(delete(ConfigValue).where(ConfigValue.key == key))
    await session.commit()
    invalidate_config()
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
        session.add(AdminLog(action="gift", target=body.player_id, detail={"title": body.title, "grants": grants}))
        await session.commit()
        return {"sent_to": body.player_id, "id": f"p{item.id}"}
    b = Broadcast(title=body.title, message=body.message, grants=grants, expires_at=exp)
    session.add(b)
    session.add(AdminLog(action="broadcast", target="everyone", detail={"title": body.title, "grants": grants}))
    await session.commit()
    return {"sent_to": "everyone", "id": f"b{b.id}"}


class TesterIn(BaseModel):
    phone: str = Field(min_length=10, max_length=20)  # the phone number linked to the player's account
    tester: bool = True


@router.post("/players/tester")
async def set_tester(body: TesterIn, session: AsyncSession = Depends(get_session)):
    """Makes the player who secured the account with this phone number a tester (or removes it): the story is open for
    him while it is closed to everybody, and he never appears on a leaderboard. The number is only compared as a hash."""
    phone = sms.normalize_phone(body.phone)
    if phone is None:
        raise HTTPException(400, "bad_phone")
    p = await session.scalar(select(Player).where(Player.phone_hash == sms.phone_hash(phone)))
    if p is None:
        raise HTTPException(404, "no_player")
    p.tester = body.tester
    session.add(AdminLog(action="tester" if body.tester else "untester", target=p.id, detail={"nickname": p.nickname}))
    await session.commit()
    log.info("admin tester player=%s tester=%s", p.id[:6], body.tester)
    return {"id": p.id, "nickname": p.nickname, "tester": p.tester}
