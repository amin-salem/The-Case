"""Shared bits for the routers."""
from __future__ import annotations

from fastapi.responses import JSONResponse

from .. import avatars, streakrepair
from .. import economy as eco
from ..config import get_settings
from ..accounts import mask_email, mask_phone
from ..models import Player, utcnow
from ..schemas import ProfileOut, StreakRepairOffer
from ..util import ts


def vip_active(p: Player) -> bool:
    return bool(p.vip_until and p.vip_until > utcnow())


def rank_title(p: Player) -> str:
    return eco.RANKS[eco.rank_of(p.xp or 0)][1]


def profile_out(p: Player, login_reward: int = 0) -> ProfileOut:
    xp = p.xp or 0
    r = eco.rank_of(xp)
    nxt = eco.RANKS[r + 1] if r + 1 < len(eco.RANKS) else None
    try:  # the repair offer must never break the profile
        offer = streakrepair.repair_offer(p)
    except Exception:
        offer = None
    return ProfileOut(
        streak_repair=StreakRepairOffer(key=offer["key"], streak=offer["streak"], price=offer["price"]) if offer else None,
        xp=xp, rank=r, rank_title=eco.RANKS[r][1], rank_xp=eco.RANKS[r][0],
        next_rank_xp=nxt[0] if nxt else None, next_rank_title=nxt[1] if nxt else None,
        achievements=int((p.stats or {}).get("achievements_earned", 0)),
        player_id=p.id, nickname=p.nickname, avatar=p.avatar, avatar_id=avatars.avatar_key(p), avatar_frame=avatars.frame_key(p), invite_code=p.invite_code,
        referred=p.referred_by is not None, email=mask_email(p.email), secured=bool(p.email or p.phone_hash), phone=mask_phone(p),
        needs_phone=bool(p.email and not p.phone_hash and get_settings().require_phone_for_email),
        coins=p.coins, no_ads=p.no_ads or vip_active(p), vip_until=ts(p.vip_until),
        streak=p.streak, best_streak=p.best_streak, cases_solved=p.cases_solved,
        stars_total=p.stars_total, login_reward=login_reward,
        login_day=p.login_day or 0, warrants=p.warrants or 0, streak_freezes=p.streak_freezes or 0,
    )


def fast_json(model) -> JSONResponse:
    """The JSON FastAPI would send for `response_model=<this model>`, without validating the model a second time and
    walking it a third time (on the case list that was about 50 rows x 3). Same bytes: by_alias, JSON mode, and
    Starlette's own JSONResponse. The route keeps its response_model, so the OpenAPI schema is unchanged."""
    return JSONResponse(model.model_dump(mode="json", by_alias=True))
