"""Phone-secured accounts: an SMS code proves the phone number.

secure: send -> verify (logged-in player adds a phone to the account; one phone per account).
new device: login/send -> login (code for a phone already on an account; logs the old device out).
Only a keyed hash of the number is stored. Every step is rate limited and fails closed.
"""
import hmac
import logging
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import economy as eco
from ..db import get_session, lock_players
from ..models import PhoneCode, Player, utcnow
from ..schemas import PhoneLoginIn, PhoneSendIn, PhoneSentOut, PhoneVerifyIn, RegisterOut, SecureOut
from ..security import current_player
from ..services import sms
from ..services.ratelimit import enforce
from ..util import add_coins
from .auth import _login_as
from .common import profile_out

log = logging.getLogger("phone")
router = APIRouter(prefix="/v1/auth/phone", tags=["phone"])


def _phone(raw: str) -> str:
    p = sms.normalize_phone(raw)
    if p is None:
        raise HTTPException(422, "bad_phone")
    return p


async def _issue(session: AsyncSession, phash: str, phone: str, purpose: str, player_id: str | None) -> PhoneSentOut:
    if not sms.available():
        raise HTTPException(503, "sms_unavailable")
    await enforce("sms_daily", "all")
    await session.execute(update(PhoneCode).where(PhoneCode.phone_hash == phash, PhoneCode.used.is_(False))
                          .values(used=True))
    code = sms.new_code()
    row = PhoneCode(phone_hash=phash, purpose=purpose, player_id=player_id, code_hash=sms.code_hash(phash, code),
                    expires_at=utcnow() + timedelta(seconds=sms.CODE_TTL))
    session.add(row)
    await session.commit()
    try:
        await sms.send_code(phone, code)
    except sms.SmsError as e:
        row.used = True
        await session.commit()
        log.warning("sms code not sent: %s purpose=%s", e.code, purpose)
        raise HTTPException(503, e.code)
    log.info("sms code sent purpose=%s", purpose)
    return PhoneSentOut(resend_after=60, expires_in=sms.CODE_TTL)


async def _check(session: AsyncSession, phash: str, code: str, purpose: str, player_id: str | None = None) -> PhoneCode:
    """Returns the code row if `code` is right (and burns it). Wrong tries are counted per code."""
    await enforce("sms_verify", phash)
    row = await session.scalar(select(PhoneCode).where(
        PhoneCode.phone_hash == phash, PhoneCode.purpose == purpose, PhoneCode.used.is_(False))
        .order_by(PhoneCode.id.desc()).limit(1))
    if row is None or row.expires_at < utcnow():
        raise HTTPException(400, "code_expired")
    if player_id is not None and row.player_id != player_id:  # somebody else's code: don't burn it
        raise HTTPException(400, "code_expired")
    row.attempts += 1
    if row.attempts > sms.MAX_TRIES:
        row.used = True
        await session.commit()
        raise HTTPException(400, "code_expired")
    if not hmac.compare_digest(row.code_hash, sms.code_hash(phash, code.strip().translate(sms._DIGITS))):
        await session.commit()
        raise HTTPException(400, "bad_code")
    won = await session.execute(update(PhoneCode).where(PhoneCode.id == row.id, PhoneCode.used.is_(False))
                                .values(used=True))
    await session.commit()
    if won.rowcount != 1:  # two requests with the same right code: only one wins
        raise HTTPException(400, "code_expired")
    return row


@router.post("/send", response_model=PhoneSentOut)
async def send(body: PhoneSendIn, player: Player = Depends(current_player),
               session: AsyncSession = Depends(get_session)):
    """Logged-in player asks for a code to add this phone number to the account."""
    phone = _phone(body.phone)
    if player.phone_hash:
        raise HTTPException(409, "phone_already_set")
    phash = sms.phone_hash(phone)
    taken = await session.scalar(select(Player.id).where(Player.phone_hash == phash))
    if taken is not None:
        raise HTTPException(409, "phone_taken")  # no SMS is paid for this
    await enforce("sms_device", player.device_id)
    await enforce("sms_phone", phash)
    return await _issue(session, phash, phone, "secure", player.id)


@router.post("/verify", response_model=SecureOut)
async def verify(body: PhoneVerifyIn, player: Player = Depends(current_player),
                 session: AsyncSession = Depends(get_session)):
    phone = _phone(body.phone)
    phash = sms.phone_hash(phone)
    await _check(session, phash, body.code, "secure", player.id)
    # OTP verification commits deliberately (burns the code). Reload eligibility under a new lock.
    player = (await lock_players(session, [player.id]))[player.id]
    player.phone_hash = phash
    player.phone_last4 = phone[-4:]
    player.phone_verified_at = utcnow()
    reward = 0
    if not player.secure_rewarded:
        player.secure_rewarded = True
        reward = eco.SECURE_REWARD
        await add_coins(session, player, reward, "secure_account")
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "phone_taken")
    log.info("phone secured reward=%s", reward)
    return SecureOut(profile=profile_out(player), reward=reward)


@router.post("/login/send", response_model=PhoneSentOut)
async def login_send(body: PhoneSendIn, session: AsyncSession = Depends(get_session)):
    """New device: ask for a code. The answer is the same whether or not the number has an account,
    and an SMS is only paid for when it does."""
    phone = _phone(body.phone)
    if len(body.device_id) < 4:
        raise HTTPException(422, "bad_device")
    phash = sms.phone_hash(phone)
    await enforce("sms_device", body.device_id)
    await enforce("sms_phone", phash)
    owner = await session.scalar(select(Player.id).where(Player.phone_hash == phash))
    if owner is None:
        return PhoneSentOut(resend_after=60, expires_in=sms.CODE_TTL)
    return await _issue(session, phash, phone, "login", owner)


@router.post("/login", response_model=RegisterOut)
async def login(body: PhoneLoginIn, session: AsyncSession = Depends(get_session)):
    phone = _phone(body.phone)
    phash = sms.phone_hash(phone)
    row = await _check(session, phash, body.code, "login")
    player = await session.get(Player, row.player_id) if row.player_id else None
    if player is None or player.phone_hash != phash:
        raise HTTPException(400, "code_expired")
    return await _login_as(session, player, body.device_id)

