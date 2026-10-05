"""Health check, remote config and analytics."""
from datetime import timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from .. import economy as eco
from ..db import get_session
from ..models import Event, Player, utcnow
from ..schemas import EventsIn
from ..security import current_player
from ..services.remote_config import load_config
from ..util import from_ts

from ..version import VERSION

router = APIRouter(tags=["meta"])


@router.get("/health")
async def health(session: AsyncSession = Depends(get_session)):
    await session.execute(text("SELECT 1"))
    return {"ok": True, "cases": len(content.all_cases()), "version": VERSION}


@router.get("/v1/config")
async def config(session: AsyncSession = Depends(get_session)):
    """No login needed: forced update, maintenance, prices, game numbers."""
    cfg = await load_config(session)
    now = content.now_local()
    cfg.update({
        "server_time": int(now.timestamp()),
        "today": now.date().isoformat(),
        "next_case_at": int(content.next_case_at(now).timestamp()),
        "economy": {"hint_costs": eco.HINT_COSTS, "unlock_cost": eco.UNLOCK_COST,
                    "max_attempts": eco.MAX_ATTEMPTS, "ad_reward": eco.AD_REWARD, "ads_per_day": eco.AD_PER_DAY,
                    "secure_reward": eco.SECURE_REWARD, "invite_reward": eco.INVITE_INVITER,
                    "invite_new_player": eco.INVITE_NEW_PLAYER,
                    "login_calendar": eco.LOGIN_CALENDAR, "login_envelope": [min(eco.LOGIN_ENVELOPE), max(eco.LOGIN_ENVELOPE)],
                    "freeze_cost": eco.FREEZE_COST, "max_freezes": eco.MAX_FREEZES,
                    "streak_badges": list(eco.STREAK_BADGES),
                    "riddles_per_day": eco.RIDDLES_PER_DAY, "riddle_free": eco.RIDDLE_FREE,
                    "riddle_unlock_cost": eco.RIDDLE_UNLOCK_COST, "riddle_reward": eco.RIDDLE_REWARD,
                    "riddle_seconds": eco.RIDDLE_SECONDS, "products": {
                        k: {"coins": p.coins, "no_ads": p.no_ads, "kind": p.kind} for k, p in eco.PRODUCTS.items()}},
    })
    return cfg


@router.post("/v1/events")
async def events(body: EventsIn, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    now = utcnow()
    for e in body.events:
        when = now
        if e.ts and 0 < e.ts < 4_000_000_000:
            t = from_ts(e.ts)
            if now - timedelta(days=7) < t <= now + timedelta(minutes=5):
                when = t
        session.add(Event(player_id=player.id, name=e.name, props=dict(list(e.props.items())[:20]), ts=when))
    await session.commit()
    return {"stored": len(body.events)}
