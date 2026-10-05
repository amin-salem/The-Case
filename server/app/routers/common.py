"""Shared bits for the routers."""
from __future__ import annotations

from .. import economy as eco
from ..accounts import mask_email
from ..models import Player, utcnow
from ..schemas import ProfileOut
from ..util import ts


def vip_active(p: Player) -> bool:
    return bool(p.vip_until and p.vip_until > utcnow())


def rank_title(p: Player) -> str:
    return eco.RANKS[eco.rank_of(p.xp or 0)][1]


def profile_out(p: Player, login_reward: int = 0) -> ProfileOut:
    xp = p.xp or 0
    r = eco.rank_of(xp)
    nxt = eco.RANKS[r + 1] if r + 1 < len(eco.RANKS) else None
    return ProfileOut(
        xp=xp, rank=r, rank_title=eco.RANKS[r][1], rank_xp=eco.RANKS[r][0],
        next_rank_xp=nxt[0] if nxt else None, next_rank_title=nxt[1] if nxt else None,
        achievements=int((p.stats or {}).get("achievements_earned", 0)),
        player_id=p.id, nickname=p.nickname, avatar=p.avatar, invite_code=p.invite_code,
        referred=p.referred_by is not None, email=mask_email(p.email), secured=bool(p.email),
        coins=p.coins, no_ads=p.no_ads or vip_active(p), vip_until=ts(p.vip_until),
        streak=p.streak, best_streak=p.best_streak, cases_solved=p.cases_solved,
        stars_total=p.stars_total, login_reward=login_reward,
        login_day=p.login_day or 0, streak_freezes=p.streak_freezes or 0,
    )
