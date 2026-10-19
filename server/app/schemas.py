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


class PhoneSendIn(BaseModel):
    phone: str = Field(min_length=10, max_length=20)
    device_id: str = Field(default="", max_length=128)  # needed for the new-device login


class PhoneVerifyIn(BaseModel):
    phone: str = Field(min_length=10, max_length=20)
    code: str = Field(min_length=4, max_length=8)


class PhoneLoginIn(PhoneVerifyIn):
    device_id: str = Field(min_length=4, max_length=128)


class PhoneSentOut(BaseModel):
    ok: bool = True
    resend_after: int = 60   # seconds before another code can be asked
    expires_in: int = 300


# ---- profile & wallet
class ProfileOut(BaseModel):
    player_id: str
    nickname: str
    avatar: int
    avatar_id: str = ""      # det_01, ex_cat ...
    avatar_frame: str = "frame_brass"
    invite_code: str
    referred: bool
    email: str | None  # masked
    secured: bool
    needs_phone: bool = False  # email-secured account without a phone yet: the app asks to link one
    phone: str | None = None  # masked, only the last 4 digits are known
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
    warrants: int = 0                 # story warrants held
    unread: int = 0                   # unread items in the messages hub (the bell)
    gains: "GainsOut | None" = None   # earned right now (on /me: login-calendar week, late achievements)


class ProfileIn(BaseModel):
    nickname: str | None = Field(default=None, min_length=2, max_length=16)
    avatar: int | None = Field(default=None, ge=0, le=11)   # old apps
    avatar_id: str | None = Field(default=None, max_length=24)
    avatar_frame: str | None = Field(default=None, max_length=24)


_SAFE = r"^[A-Za-z0-9 ._+,()/-]*$"


class ClientInfoIn(BaseModel):
    """What the app says about itself. Every string is bounded and limited to plain characters."""

    app_version: str = Field(max_length=24, pattern=r"^[0-9][0-9A-Za-z.+-]*$")
    build: int = Field(ge=0, le=10_000_000)
    platform: str = Field(default="android", max_length=16, pattern=r"^[a-z]+$")
    os_version: str = Field(default="", max_length=32, pattern=_SAFE)
    device_model: str = Field(default="", max_length=48, pattern=_SAFE)


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
    category: str = ""  # topic key (content.CATEGORIES); empty for a case without one
    difficulty: int
    publish: str
    today: bool
    weekend: bool = False  # an expired weekend case in the archive (higher price)
    locked: bool        # archive case not bought yet
    unlock_cost: int
    solved: bool
    failed: bool
    stars: int
    solvers: int        # how many players solved it
    rating_avg: float = 0     # average stars of the approved ratings (0 = none yet)
    rating_count: int = 0     # how many detectives gave stars
    comment_count: int = 0    # approved written comments
    my_rating: int = 0        # the stars this player gave (0 = not rated)


class CasesOut(BaseModel):
    today: CaseRow | None
    next_case_at: int   # unix seconds
    archive: list[CaseRow]
    weekly: CaseRow | None = None         # this weekend's big case, while it is open
    weekly_closes_at: int | None = None
    weekly_next_chapter_at: int | None = None  # when chapter 2 opens (None once it has, or no chapters)
    weekly_format: int = 0                    # 3 = two-night format (night-1 question, newcomer in chapter 2)


class ProgressOut(BaseModel):
    hints: list[str]    # hints bought so far (text)
    attempts: int
    attempts_left: int
    solved: bool
    failed: bool
    stars: int
    hint_costs: list[int]
    answer_at: int | None = None  # a lost case: unix time when the answer becomes public (None = public / not lost)
    shows: list[dict[str, Any]] = []        # weekend case: evidence cards shown to suspects {s, e, t = what the suspect said}
    shows_left: int = 0
    wrong_tries: list[dict[str, Any]] = []  # this player's wrong accusations: {s, e, m, r} (r = wrong_suspect | wrong_proof | wrong_motive | hasty)
    night1: dict[str, Any] | None = None    # format 3: the player's night-1 answer {pick, ok, reward, card, explanation}; None = not answered


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
    evidence: str = Field(default="", max_length=16)          # not asked in the two-part weekend accusation
    motive: str | None = Field(default=None, max_length=16)   # the weekly case also asks "why"
    extra_seconds: int = Field(default=0, ge=0, le=3600)      # active time since the last tick


class LiarIn(BaseModel):
    suspect: str = Field(max_length=16)


class LiarOut(BaseModel):
    ok: bool
    reward: int = 0
    coins: int = 0
    progress: ProgressOut


class TickIn(BaseModel):
    seconds: int = Field(ge=0, le=3600)


class TickOut(BaseModel):
    active_seconds: int


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
    answer_at: int | None = None   # lost case: the answer (culprit, proof, explanation) is public from this time
    unranked: bool = False         # solved without enough investigation: 1 star, no leaderboard place
    stars_capped: bool = False     # ... and it would have had more stars
    story: dict[str, Any] | None = None  # story chapter finished: {season, chapter, outro, thread}
    early_bonus: int = 0           # weekend case solved before its last chapter: extra coins (already in reward)
    how_right: bool | None = None  # two-part weekend accusation: was the "why/how" part right (None = not asked)


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
    avatar_id: str = ""
    avatar_frame: str = "frame_brass"
    value: int        # stars (weekly/all) or seconds (daily)
    stars: int = 0
    me: bool = False
    rank_title: str = ""      # the player's detective rank


class LeagueInfo(BaseModel):
    id: int
    name: str


class LeaderboardOut(BaseModel):
    period: str
    title: str
    top: list[LeaderRow]
    me: LeaderRow | None
    week_ends_at: int | None = None            # weekly: when the board closes (= the next week's first case opens)
    league: int | None = None                  # weekly: the league shown (None = the single board)
    my_league: int | None = None
    leagues: list[LeagueInfo] = []             # weekly: the choices of the league switch (empty = leagues are off)


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


class ReferralStatusOut(BaseModel):
    """What the invite card shows. All numbers are server-side; the app only displays them."""
    referred: bool                # this player already entered a friend's code
    can_redeem: bool              # not referred yet and the account is at most 7 days old
    new_player_reward: int        # coins the new player gets at once
    inviter_reward: int           # coins the inviter gets later
    need_days: int                # solve days the invited player needs before the inviter is paid
    my_days: int = 0              # (referred players) days on which I solved cases, counted up to need_days
    my_inviter_paid: bool = False  # (referred players) my inviter has been settled
    invited: int = 0              # players who entered MY code
    invited_paid: int = 0         # ... of which already paid to me
    best_days: int = 0            # solve days of my closest unpaid invited friend (0 = nobody yet)
    max_paid: int = 0             # lifetime cap of paid invites


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
    warrants: int = 0                   # story warrants «حکم بازرسی» earned right now
    missions_done: list[str] = []       # titles of daily missions finished right now
    achievements: list[dict] = []       # {id, title, coins} earned right now
    avatars: list[dict] = []            # {id, kind, title}: avatars/frames unlocked by a goal right now


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


# --- story mode ---------------------------------------------------------------------------
class StoryOpenIn(BaseModel):
    warrant: bool = False   # spend a warrant to open a chapter that is still waiting


class StoryChapterOut(BaseModel):
    chapter: int
    id: str
    title: str | None = None       # hidden while the chapter is locked
    location: str | None = None
    scene: str | None = None
    state: str                     # done | open | ready | waiting | locked
    solved: bool = False
    stars: int = 0
    unlock_at: int | None = None   # waiting: when it opens by itself
    skip_cost: int | None = None   # waiting: coins to open it now
    can_warrant: bool = False      # waiting and the player holds a warrant


class StoryOut(BaseModel):
    open: bool
    opens_at: int
    season: int
    title: str
    tagline: str
    partner: str
    warrants: int
    coins: int
    free_chapters: int
    wait_hours: int
    next_open_at: int | None = None
    chapters: list[StoryChapterOut]
    case_id: str | None = None     # set by open/skip: the chapter's case id


class FeedItem(BaseModel):
    id: str
    kind: str  # gift | case | story | weekend | badge | streak | system
    title: str
    body: str = ""
    at: int
    unread: bool
    gift_id: str | None = None  # claimable gift: POST /v1/inbox/{gift_id}/claim
    reward: int = 0


class FeedOut(BaseModel):
    items: list[FeedItem]
    unread: int
    seen_at: int | None = None


class ShowIn(BaseModel):
    suspect: str = Field(max_length=16)
    evidence: str = Field(max_length=16)


class ShowOut(BaseModel):
    suspect: str
    evidence: str
    text: str            # what the suspect says when shown the card
    shows_left: int
    progress: ProgressOut
