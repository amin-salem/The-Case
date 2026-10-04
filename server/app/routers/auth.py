"""Accounts: guest first (no sign-up), then optional email + password.

First start: /register (the phone keeps player_id + secret). Later: /login.
New phone: email + password, or a one-time transfer code from the old phone.
Logging in on a new phone logs the old phone out.
"""
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import accounts as acc
from .. import economy as eco
from ..db import get_session
from ..models import Player, TransferCode, utcnow
from ..schemas import (EmailIn, EmailLoginIn, LoginIn, RegisterIn, RegisterOut, SecureOut, TokenOut,
                       TransferCodeOut, TransferIn)
from ..security import current_player, hash_secret, make_token, new_secret, random_code, secret_matches
from ..util import add_coins, default_nickname, ts, unique_invite_code
from .common import profile_out

router = APIRouter(prefix="/v1/auth", tags=["auth"])


async def _login_as(session: AsyncSession, player: Player, device_id: str) -> RegisterOut:
    if player.banned:
        raise HTTPException(403, "banned")
    secret = new_secret()
    player.secret_hash = hash_secret(secret)
    player.device_id = device_id
    player.token_gen += 1
    player.last_seen = utcnow()
    await session.commit()
    token, exp = make_token(player.id, player.token_gen)
    return RegisterOut(player_id=player.id, secret=secret, token=token, expires_at=exp)


@router.post("/register", response_model=RegisterOut)
async def register(body: RegisterIn, session: AsyncSession = Depends(get_session)):
    secret = new_secret()
    player = Player(secret_hash=hash_secret(secret), device_id=body.device_id, app_version=body.app_version,
                    nickname=default_nickname(), invite_code=await unique_invite_code(session),
                    token_gen=0, coins=0)
    session.add(player)
    await session.flush()
    add_coins(session, player, eco.START_COINS, "welcome")
    await session.commit()
    token, exp = make_token(player.id, 0)
    return RegisterOut(player_id=player.id, secret=secret, token=token, expires_at=exp)


@router.post("/login", response_model=TokenOut)
async def login(body: LoginIn, session: AsyncSession = Depends(get_session)):
    player = await session.get(Player, body.player_id)
    if player is None or not secret_matches(body.secret, player.secret_hash):
        raise HTTPException(401, "wrong_login")
    if player.banned:
        raise HTTPException(403, "banned")
    player.last_seen = utcnow()
    if body.app_version:
        player.app_version = body.app_version
    await session.commit()
    token, exp = make_token(player.id, player.token_gen)
    return TokenOut(token=token, expires_at=exp)


@router.post("/email", response_model=SecureOut)
async def set_email(body: EmailIn, player: Player = Depends(current_player),
                    session: AsyncSession = Depends(get_session)):
    """Add email + password to this account (or change the password)."""
    email = acc.normalize_email(body.email)
    if email is None:
        raise HTTPException(422, "bad_email")
    if not acc.password_ok(body.password):
        raise HTTPException(422, "bad_password")
    if player.email and player.email != email:
        raise HTTPException(409, "email_cant_change")
    taken = await session.scalar(select(Player.id).where(Player.email == email))
    if taken is not None and taken != player.id:
        raise HTTPException(409, "email_taken")
    player.email = email
    player.password_hash = acc.hash_password(body.password)
    reward = 0
    if not player.secure_rewarded:
        player.secure_rewarded = True
        reward = eco.SECURE_REWARD
        add_coins(session, player, reward, "secure_account")
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "email_taken")
    return SecureOut(profile=profile_out(player), reward=reward)


@router.post("/login/email", response_model=RegisterOut)
async def login_email(body: EmailLoginIn, session: AsyncSession = Depends(get_session)):
    email = acc.normalize_email(body.email)
    player = await session.scalar(select(Player).where(Player.email == email)) if email else None
    if player is None or not acc.check_password(body.password, player.password_hash):
        raise HTTPException(401, "wrong_login")
    return await _login_as(session, player, body.device_id)


@router.post("/transfer-code", response_model=TransferCodeOut)
async def make_transfer_code(player: Player = Depends(current_player),
                             session: AsyncSession = Depends(get_session)):
    code = random_code(8)
    exp = utcnow() + timedelta(hours=24)
    session.add(TransferCode(code=code, player_id=player.id, expires_at=exp))
    await session.commit()
    return TransferCodeOut(code=code, expires_at=ts(exp))


@router.post("/transfer", response_model=RegisterOut)
async def use_transfer_code(body: TransferIn, session: AsyncSession = Depends(get_session)):
    row = await session.scalar(select(TransferCode).where(TransferCode.code == body.code.strip().upper()))
    if row is None or row.used or row.expires_at < utcnow():
        raise HTTPException(404, "bad_code")
    player = await session.get(Player, row.player_id)
    if player is None:
        raise HTTPException(404, "bad_code")
    row.used = True
    return await _login_as(session, player, body.device_id)
