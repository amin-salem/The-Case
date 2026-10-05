"""Shapes of the JSON the app sends and receives."""
from typing import Any

from pydantic import BaseModel, Field


# ---- auth
class RegisterIn(BaseModel):
    device_id: str = Field(min_length=4, max_length=128)
    app_version: int = 0


class RegisterOut(BaseModel):
    player_id: str
    secret: str  # the app must keep this; it is shown only once
    token: str
    expires_at: int


class LoginIn(BaseModel):
    player_id: str = Field(max_length=32)
    secret: str = Field(max_length=128)
    app_version: int = 0


class TokenOut(BaseModel):
    token: str
    expires_at: int


class TransferIn(BaseModel):
    code: str = Field(min_length=4, max_length=16)
    device_id: str = Field(min_length=4, max_length=128)


class TransferCodeOut(BaseModel):
    code: str
    expires_at: int


class EmailIn(BaseModel):
    email: str = Field(min_length=5, max_length=120)
    password: str = Field(min_length=6, max_length=64)


class EmailLoginIn(EmailIn):
    device_id: str = Field(min_length=4, max_length=128)


# ---- profile & wallet
class ProfileOut(BaseModel):
    player_id: str
    nickname: str
    avatar: int
    invite_code: str
    referred: bool
    email: str | None  # masked
    secured: bool
    coins: int
    no_ads: bool
    vip_until: int | None
    streak: int
    best_streak: int
    cases_solved: int
    stars_total: int
    login_reward: int = 0  # coins given right now for today's first visit
    login_day: int = 0     # 1..7: today's place in the login calendar
    streak_freezes: int = 0
    xp: int = 0
    rank: int = 0             # index in the ranks list
    rank_title: str = ""
    rank_xp: int = 0          # XP where this rank starts
    next_rank_xp: int | None = None   # None at the top rank
    next_rank_title: str | None = None
    achievements: int = 0             # earned so far
    gains: "GainsOut | None" = None   # earned right now (on /me: login-calendar week, late achievements)


class ProfileIn(BaseModel):
    nickname: str | None = Field(default=None, min_length=2, max_length=16)
    avatar: int | None = Field(default=None, ge=0, le=11)


class CoinsOut(BaseModel):
    coins: int
    added: int = 0


class SecureOut(BaseModel):
    profile: ProfileOut
    reward: int = 0


# ---- cases
class CaseRow(BaseModel):
    id: str
    number: int
    title: str
    location: str
    scene: str
    difficulty: int
    publish: str
    today: bool
    locked: bool        # archive case not bought yet
    unlock_cost: int
    solved: bool
    failed: bool
    stars: int
    solvers: int        # how many players solved it


class CasesOut(BaseModel):
    today: CaseRow | None
    next_case_at: int   # unix seconds
    archive: list[CaseRow]


class ProgressOut(BaseModel):
    hints: list[str]    # hints bought so far (text)
    attempts: int
    attempts_left: int
    solved: bool
    failed: bool
    stars: int
    hint_costs: list[int]


class CaseOut(BaseModel):
    case: dict[str, Any]
    progress: ProgressOut
    today: bool


class HintOut(BaseModel):
    hint: str
    coins: int
    progress: ProgressOut
    gains: "GainsOut | None" = None


class AccuseIn(BaseModel):
    suspect: str = Field(max_length=16)
    evidence: str = Field(max_length=16)


class AccuseOut(BaseModel):
    result: str  # solved | wrong_suspect | wrong_proof | failed
    attempts_left: int
    stars: int = 0
    reward: int = 0
    coins: int = 0
    streak: int = 0
    explanation: str | None = None
    culprit: str | None = None
    proof: list[str] = []
    rank: int | None = None  # place on today's leaderboard
    progress: ProgressOut | None = None
    seconds: int = 0         # time to solve
    hints_used: int = 0
    freezes_used: int = 0    # streak insurance spent to keep the streak
    badge: int | None = None  # a streak badge (7, 30, 100) reached right now
    gains: "GainsOut | None" = None


class SuspectStat(BaseModel):
    id: str
    pct: int            # % of players who accused this suspect first


class StatsOut(BaseModel):
    players: int        # players who finished the case
    solved_pct: int
    first_try_pct: int  # solved with no wrong accusation
    culprit: str
    suspects: list[SuspectStat]


# ---- leaderboard
class LeaderRow(BaseModel):
    rank: int
    nickname: str
    avatar: int
    value: int        # stars (weekly/all) or seconds (daily)
    stars: int = 0
    me: bool = False
    rank_title: str = ""      # the player's detective rank


class LeaderboardOut(BaseModel):
    period: str
    title: str
    top: list[LeaderRow]
    me: LeaderRow | None


# ---- purchases, inbox, referral, analytics
class VerifyIn(BaseModel):
    product_id: str = Field(max_length=64)
    purchase_token: str = Field(min_length=4, max_length=255)
    store: str = Field(default="bazaar", pattern="^(bazaar|myket)$")


class VerifyOut(BaseModel):
    status: str  # granted | already_granted | rejected
    reason: str = ""
    coins: int = 0
    added: int = 0
    no_ads: bool = False
    vip_until: int | None = None
    consume: bool = False


class InboxRow(BaseModel):
    id: str
    title: str
    message: str
    grants: list[dict]
    expires_at: int | None


class ClaimOut(BaseModel):
    grants: list[dict]
    coins: int


class RedeemIn(BaseModel):
    code: str = Field(min_length=4, max_length=12)


class EventIn(BaseModel):
    name: str = Field(min_length=1, max_length=48)
    props: dict[str, Any] = {}
    ts: int | None = None


class EventsIn(BaseModel):
    events: list[EventIn] = Field(max_length=100)


# ---- admin
class GiftIn(BaseModel):
    title: str = Field(max_length=80)
    message: str = Field(default="", max_length=400)
    grants: list[dict]
    player_id: str | None = None
    expires_in_days: int | None = 14


class ConfigIn(BaseModel):
    values: dict[str, Any]


# --- progress (what an action earned besides coins) -------------------------------------
class GainsOut(BaseModel):
    xp: int = 0
    rank_up: str | None = None          # the new rank's title, when the player just went up
    missions_done: list[str] = []       # titles of daily missions finished right now
    achievements: list[dict] = []       # {id, title, coins} earned right now


# --- quick riddles ------------------------------------------------------------------------
class RiddleItem(BaseModel):
    id: str
    slot: int                 # 1..RIDDLES_PER_DAY
    title: str
    scene: str
    free: bool
    locked: bool              # not free and not bought yet: no text until it is opened
    answered: bool
    correct: bool = False
    choice: int | None = None
    text: str | None = None
    clue: str | None = None
    choices: list[str] = []
    answer: int | None = None   # only after answering
    explain: str | None = None  # only after answering


class RiddlesOut(BaseModel):
    day: str
    items: list[RiddleItem]
    unlock_cost: int
    reward: int
    seconds: int
    next_at: int              # unix seconds: when tomorrow's set opens
    coins: int


class RiddleAnswerIn(BaseModel):
    choice: int = Field(ge=-1, le=2)   # -1 = the timer ran out
    seconds: int = Field(default=0, ge=0, le=3600)


class RiddleAnswerOut(BaseModel):
    correct: bool
    answer: int
    explain: str
    reward: int
    coins: int
    item: RiddleItem
    gains: GainsOut = GainsOut()


class RiddleUnlockOut(BaseModel):
    item: RiddleItem
    coins: int
    gains: GainsOut = GainsOut()


# --- daily missions -----------------------------------------------------------------------
class MissionRow(BaseModel):
    id: str
    title: str
    target: int
    progress: int
    done: bool


class MissionsOut(BaseModel):
    day: str
    missions: list[MissionRow]
    all_done: bool
    claimed: bool
    chest_coins: int          # what the chest gives today (with the every-7-days bonus)
    chest_streak: int         # days in a row the chest was opened
    next_at: int              # unix seconds: when tomorrow's missions start
    coins: int


class ChestOut(BaseModel):
    missions: MissionsOut
    reward: int
    gains: GainsOut = GainsOut()


class SeenIn(BaseModel):
    suspect: str = Field(max_length=16)


class SeenOut(BaseModel):
    seen: int
    total: int
    gains: GainsOut = GainsOut()


ProfileOut.model_rebuild()
AccuseOut.model_rebuild()
HintOut.model_rebuild()


# --- achievements ------------------------------------------------------------------------
class AchievementRow(BaseModel):
    id: str
    title: str
    desc: str
    group: str
    target: int
    progress: int
    earned: bool
    earned_at: int | None = None
    coins: int
    xp: int


class AchievementsOut(BaseModel):
    earned: int
    total: int
    items: list[AchievementRow]
