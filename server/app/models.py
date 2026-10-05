"""Database tables. All times are stored as UTC (without timezone info)."""
import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def new_id() -> str:
    return uuid.uuid4().hex


class Player(Base):
    __tablename__ = "players"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    secret_hash: Mapped[str] = mapped_column(String(64))
    token_gen: Mapped[int] = mapped_column(Integer, default=0)  # +1 logs out old phones
    device_id: Mapped[str] = mapped_column(String(128), index=True)
    app_version: Mapped[int] = mapped_column(Integer, default=0)

    nickname: Mapped[str] = mapped_column(String(24), default="")
    avatar: Mapped[int] = mapped_column(Integer, default=0)  # detective portrait index
    invite_code: Mapped[str] = mapped_column(String(12), unique=True, index=True)
    referred_by: Mapped[str | None] = mapped_column(String(32), nullable=True)
    invites_rewarded: Mapped[int] = mapped_column(Integer, default=0)

    # permanent account (optional)
    email: Mapped[str | None] = mapped_column(String(120), unique=True, nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(200), nullable=True)
    secure_rewarded: Mapped[bool] = mapped_column(Boolean, default=False)

    # wallet & perks (the server is the boss of coins: nothing to cheat on the phone)
    coins: Mapped[int] = mapped_column(Integer, default=0)
    no_ads: Mapped[bool] = mapped_column(Boolean, default=False)
    vip_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    # daily habit
    streak: Mapped[int] = mapped_column(Integer, default=0)
    best_streak: Mapped[int] = mapped_column(Integer, default=0)
    last_daily_solved: Mapped[str] = mapped_column(String(10), default="")  # YYYY-MM-DD (Tehran)
    last_login_reward: Mapped[str] = mapped_column(String(10), default="")
    login_day: Mapped[int] = mapped_column(Integer, default=0, server_default="0")  # 1..7 in the calendar
    streak_freezes: Mapped[int] = mapped_column(Integer, default=0, server_default="0")  # streak insurance held
    ad_day: Mapped[str] = mapped_column(String(10), default="")
    ad_count: Mapped[int] = mapped_column(Integer, default=0)
    cases_solved: Mapped[int] = mapped_column(Integer, default=0)
    stars_total: Mapped[int] = mapped_column(Integer, default=0)

    banned: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    last_seen: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class CaseProgress(Base):
    """One player working on one case."""

    __tablename__ = "case_progress"
    __table_args__ = (
        UniqueConstraint("player_id", "case_id", name="uq_progress"),
        Index("ix_progress_case_solved", "case_id", "solved"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    case_id: Mapped[str] = mapped_column(String(16))
    unlocked: Mapped[bool] = mapped_column(Boolean, default=False)  # archive cases are bought
    opened_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    hints: Mapped[int] = mapped_column(Integer, default=0)      # hints bought (0..3)
    attempts: Mapped[int] = mapped_column(Integer, default=0)   # wrong accusations
    solved: Mapped[bool] = mapped_column(Boolean, default=False)
    failed: Mapped[bool] = mapped_column(Boolean, default=False)
    stars: Mapped[int] = mapped_column(Integer, default=0)
    seconds: Mapped[int] = mapped_column(Integer, default=0)    # time to solve
    was_daily: Mapped[bool] = mapped_column(Boolean, default=False)  # finished as "today's case"
    day: Mapped[str] = mapped_column(String(10), default="")    # Tehran day it was finished
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    first_accused: Mapped[str | None] = mapped_column(String(16), nullable=True)  # for "what others thought"


class Purchase(Base):
    """A Cafe Bazaar purchase. purchase_token is unique so it can't be used twice."""

    __tablename__ = "purchases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[str] = mapped_column(String(64))
    purchase_token: Mapped[str] = mapped_column(String(255), unique=True)
    status: Mapped[str] = mapped_column(String(16))  # granted|rejected|refunded
    grants: Mapped[list] = mapped_column(JSON, default=list)
    raw: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class CoinLog(Base):
    """Every change of a player's coins (for support and fraud checks)."""

    __tablename__ = "coin_log"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(String(32), index=True)
    amount: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(48))
    balance: Mapped[int] = mapped_column(Integer)
    at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class InboxItem(Base):
    __tablename__ = "inbox"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(80))
    message: Mapped[str] = mapped_column(String(400), default="")
    grants: Mapped[list] = mapped_column(JSON, default=list)
    source: Mapped[str] = mapped_column(String(24), default="admin")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Broadcast(Base):
    __tablename__ = "broadcasts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(80))
    message: Mapped[str] = mapped_column(String(400), default="")
    grants: Mapped[list] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class BroadcastClaim(Base):
    __tablename__ = "broadcast_claims"
    __table_args__ = (UniqueConstraint("broadcast_id", "player_id", name="uq_bc_claim"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    broadcast_id: Mapped[int] = mapped_column(ForeignKey("broadcasts.id", ondelete="CASCADE"))
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    claimed_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class TransferCode(Base):
    __tablename__ = "transfer_codes"

    code: Mapped[str] = mapped_column(String(16), primary_key=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    used: Mapped[bool] = mapped_column(Boolean, default=False)


class ConfigValue(Base):
    __tablename__ = "config"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[Any] = mapped_column(JSON, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (Index("ix_events_name_ts", "name", "ts"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(String(32), index=True)
    name: Mapped[str] = mapped_column(String(48))
    props: Mapped[dict] = mapped_column(JSON, default=dict)
    ts: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
