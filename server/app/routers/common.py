"""Shared bits for the routers."""
from __future__ import annotations

from ..accounts import mask_email
from ..models import Player, utcnow
from ..schemas import ProfileOut
from ..util import ts


def vip_active(p: Player) -> bool:
    return bool(p.vip_until and p.vip_until > utcnow())


def profile_out(p: Player, login_reward: int = 0) -> ProfileOut:
    return ProfileOut(
        player_id=p.id, nickname=p.nickname, avatar=p.avatar, invite_code=p.invite_code,
        referred=p.referred_by is not None, email=mask_email(p.email), secured=bool(p.email),
        coins=p.coins, no_ads=p.no_ads or vip_active(p), vip_until=ts(p.vip_until),
        streak=p.streak, best_streak=p.best_streak, cases_solved=p.cases_solved,
        stars_total=p.stars_total, login_reward=login_reward,
        login_day=p.login_day or 0, streak_freezes=p.streak_freezes or 0,
    )
