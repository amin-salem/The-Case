"""Database tables. All times are stored as UTC (without timezone info)."""
import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint, false, true
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
    avatar: Mapped[int] = mapped_column(Integer, default=0)  # detective portrait index (old apps; see avatar_id)
    avatar_id: Mapped[str] = mapped_column(String(24), default="", server_default="")  # det_01, ex_cat ... ("" = from avatar)
    avatar_frame: Mapped[str] = mapped_column(String(24), default="frame_brass", server_default="frame_brass")
    invite_code: Mapped[str] = mapped_column(String(12), unique=True, index=True)
    referred_by: Mapped[str | None] = mapped_column(String(32), nullable=True)
    invites_rewarded: Mapped[int] = mapped_column(Integer, default=0)
    # set once the inviter has been paid (or refused) for this player's invitation (see anticheat.maybe_pay_referral)
    referral_paid: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())

    # permanent account (optional)
    email: Mapped[str | None] = mapped_column(String(120), unique=True, nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(200), nullable=True)
    secure_rewarded: Mapped[bool] = mapped_column(Boolean, default=False)
    # phone-secured account: only a keyed hash of the number is stored, plus the last 4 digits to show the player
    phone_hash: Mapped[str | None] = mapped_column(String(64), unique=True, nullable=True)
    phone_last4: Mapped[str | None] = mapped_column(String(4), nullable=True)
    phone_verified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    feed_seen_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)  # messages hub: everything older is read

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

    xp: Mapped[int] = mapped_column(Integer, default=0, server_default="0")  # detective rank comes from this
    stats: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # lifetime counters (achievements)

    # daily missions
    last_chest_day: Mapped[str] = mapped_column(String(10), default="", server_default="")
    chest_streak: Mapped[int] = mapped_column(Integer, default=0, server_default="0")  # days in a row, all done
    chests: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    warrants: Mapped[int] = mapped_column(Integer, default=0, server_default="0")  # story mode «حکم بازرسی»

    # what the app reports about itself (POST /v1/me/client); validated and bounded by ClientInfoIn
    client_version: Mapped[str] = mapped_column(String(24), default="", server_default="")
    client_build: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    platform: Mapped[str] = mapped_column(String(16), default="", server_default="")
    os_version: Mapped[str] = mapped_column(String(32), default="", server_default="")
    device_model: Mapped[str] = mapped_column(String(48), default="", server_default="")
    client_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

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
    proof_misses: Mapped[int] = mapped_column(Integer, default=0, server_default="0")  # right suspect, wrong proof
    first_accused: Mapped[str | None] = mapped_column(String(16), nullable=True)  # for "what others thought"
    seen: Mapped[list | None] = mapped_column(JSON, nullable=True)  # suspects interrogated (ids)
    # solving time = only the time the case screen was really open (the app reports it in ticks)
    active_seconds: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    last_tick_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # anti-cheat: False = solved without enough investigation (1 star, no leaderboard place)
    ranked: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())
    # a lost case shows its answer only from this time (UTC); None = at once
    reveal_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # the player's wrong accusations in order: [{"s": suspect, "e": evidence, "m": motive|None, "r": kind}] (at most 10)
    wrong_tries: Mapped[list | None] = mapped_column(JSON, nullable=True)
    # weekend case: [{s, e, c}] evidence cards shown to suspects (c = chapter index when shown)
    shows: Mapped[list | None] = mapped_column(JSON, nullable=True)


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


class RiddleAnswer(Base):
    """One player and one quick riddle of one day: opened with coins (if not free) and answered once."""

    __tablename__ = "riddle_answers"
    __table_args__ = (UniqueConstraint("player_id", "day", "riddle_id", name="uq_riddle_answer"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    day: Mapped[str] = mapped_column(String(10))           # Tehran day of the set
    riddle_id: Mapped[str] = mapped_column(String(16))
    unlocked: Mapped[bool] = mapped_column(Boolean, default=False)  # bought with coins
    choice: Mapped[int | None] = mapped_column(Integer, nullable=True)  # None = not answered yet, -1 = time ran out
    correct: Mapped[bool] = mapped_column(Boolean, default=False)
    seconds: Mapped[int] = mapped_column(Integer, default=0)
    at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class MissionDay(Base):
    """A player's counters for one Tehran day (what daily missions watch) and whether the chest was opened."""

    __tablename__ = "mission_days"
    __table_args__ = (UniqueConstraint("player_id", "day", name="uq_mission_day"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    day: Mapped[str] = mapped_column(String(10))
    counts: Mapped[dict] = mapped_column(JSON, default=dict)
    claimed: Mapped[bool] = mapped_column(Boolean, default=False)


class PlayerAchievement(Base):
    __tablename__ = "player_achievements"
    __table_args__ = (UniqueConstraint("player_id", "achievement_id", name="uq_player_achievement"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    achievement_id: Mapped[str] = mapped_column(String(32))
    at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class PlayerAvatar(Base):
    """An avatar or a frame a player owns beyond the free ones (kind: avatar | frame; how: goal | shop | admin)."""

    __tablename__ = "player_avatars"
    __table_args__ = (UniqueConstraint("player_id", "kind", "avatar_id", name="uq_player_avatar"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(8), default="avatar", server_default="avatar")
    avatar_id: Mapped[str] = mapped_column(String(24))
    how: Mapped[str] = mapped_column(String(8), default="goal")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class StoryProgress(Base):
    """One player and one story chapter: opened (free, by warrant, by waiting or for coins) and finished."""

    __tablename__ = "story_progress"
    __table_args__ = (UniqueConstraint("player_id", "season", "chapter", name="uq_story_progress"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    season: Mapped[int] = mapped_column(Integer)
    chapter: Mapped[int] = mapped_column(Integer)
    opened_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    solved: Mapped[bool] = mapped_column(Boolean, default=False)
    stars: Mapped[int] = mapped_column(Integer, default=0)


class StoryState(Base):
    """Where a player is inside a story chapter's scenes (choices format): current scene, the choices made,
    the clues held and the relationship states. One row per player and chapter; sizes are bounded by the chapter."""

    __tablename__ = "story_state"
    __table_args__ = (UniqueConstraint("player_id", "chapter_id", name="uq_story_state"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    chapter_id: Mapped[str] = mapped_column(String(8))
    scene: Mapped[str] = mapped_column(String(24), default="")
    chosen: Mapped[list] = mapped_column(JSON, default=list)
    clues: Mapped[list] = mapped_column(JSON, default=list)
    relations: Mapped[dict] = mapped_column(JSON, default=dict)
    done: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class AdminLog(Base):
    """What the admin did from the panel (gifts, bans), for the record."""

    __tablename__ = "admin_log"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    action: Mapped[str] = mapped_column(String(32))
    target: Mapped[str] = mapped_column(String(48), default="")
    detail: Mapped[dict] = mapped_column(JSON, default=dict)


class RateHit(Base):
    """Rate limiter counters shared by all workers (strict limits). One row per bucket key and window start; lock rows
    ("lock:...") use window_start as the unlock time. Old rows are deleted hourly (services/ratelimit.py)."""

    __tablename__ = "rate_hits"
    __table_args__ = (Index("ix_rate_hits_window_start", "window_start"),)

    key: Mapped[str] = mapped_column(String(160), primary_key=True)
    window_start: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=False)
    count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")


class CaseComment(Base):
    """A detective's comment (with 1-5 stars) on a case, or a reply to one. Nothing is public until the admin approves it.
    status: pending -> approved | rejected; an approved one can later be hidden. `slot` is "root" for the one comment a
    player may write per case (the unique constraint makes that atomic) and a fresh id for each reply."""

    __tablename__ = "case_comments"
    __table_args__ = (
        UniqueConstraint("case_id", "player_id", "slot", name="uq_comment_slot"),
        Index("ix_comments_case_status", "case_id", "status", "id"),
        Index("ix_comments_status", "status", "id"),
        Index("ix_comments_parent", "parent_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    case_id: Mapped[str] = mapped_column(String(16))
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    parent_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    slot: Mapped[str] = mapped_column(String(32), default="root")
    rating: Mapped[int] = mapped_column(Integer, default=0)  # 1..5 for a comment, 0 for a reply
    body: Mapped[str] = mapped_column(String(400), default="")
    status: Mapped[str] = mapped_column(String(10), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class ReferralPayout(Base):
    """One paid invitation. The unique constraints make the limits atomic: an invited player is paid for once,
    one device pays out once, and an inviter has at most INVITE_PAID_PER_WEEK slots per week."""

    __tablename__ = "referral_payouts"
    __table_args__ = (UniqueConstraint("inviter_id", "week", "slot", name="uq_referral_slot"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    inviter_id: Mapped[str] = mapped_column(String(32), index=True)
    invitee_id: Mapped[str] = mapped_column(String(32), unique=True)
    device_id: Mapped[str] = mapped_column(String(128), unique=True)
    week: Mapped[str] = mapped_column(String(10))
    slot: Mapped[int] = mapped_column(Integer)
    paid_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class PhoneCode(Base):
    """One SMS code sent to a phone (stored as a keyed hash). Short-lived; a few wrong tries burn it."""

    __tablename__ = "phone_codes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    phone_hash: Mapped[str] = mapped_column(String(64), index=True)
    purpose: Mapped[str] = mapped_column(String(8))  # "secure" (add to this account) | "login" (new device)
    player_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    used: Mapped[bool] = mapped_column(Boolean, default=False)
