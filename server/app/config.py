"""All server settings, read from environment variables (or a .env file)."""
from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_DEV_JWT = "change-me-dev-only"
_DEV_ADMIN = "change-me-admin-dev-only"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    env: str = "dev"  # "dev" or "prod"
    database_url: str = "sqlite+aiosqlite:///./the_case.db"
    auto_create_tables: bool = True
    content_dir: str = ""  # CONTENT_DIR: complete external content root; empty keeps bundled defaults

    jwt_secret: str = _DEV_JWT
    jwt_days: int = 30
    admin_api_key: str = _DEV_ADMIN
    # Independent report-only credential. Empty hash or expired/missing deadline disables access.
    analytics_api_key_sha256: str = ""
    analytics_api_key_expires_at: int = 0  # Unix seconds, UTC

    # Cafe Bazaar
    bazaar_mode: str = "fake"  # fake | api_secret | oauth
    bazaar_package_name: str = "ir.gammly.parvandeh"
    bazaar_base_url: str = "https://pardakht.cafebazaar.ir/devapi/v2"
    bazaar_api_secret: str = ""
    bazaar_client_id: str = ""
    bazaar_client_secret: str = ""
    bazaar_refresh_token: str = ""

    # Myket (the store we publish on first). The access token is in the Myket developer panel, under the
    # app's in-app products. Empty in production = Myket purchases are refused.
    myket_access_token: str = ""
    myket_package_name: str = "ir.gammly.parvandeh"
    myket_base_url: str = "https://developer.myket.ir/api/partners/applications"

    # Phone-secured accounts (SMS code). SMS costs money: kill switch + strict limits. The key lives ONLY in the environment.
    sms_enabled: bool = True  # SMS_ENABLED=false refuses every SMS (kill switch)
    sms_mode: str = "fake"  # fake (tests, never sends) | ghasedak
    sms_api_key: str = ""
    sms_template: str = ""  # the approved OTP template name in the Ghasedak panel; it has one parameter: the code
    sms_url: str = "https://gateway.ghasedak.me/rest/api/v1/WebService/SendOtpWithParams"
    phone_pepper: str = ""  # secret for hashing phone numbers; empty = derived from JWT_SECRET

    email_signup_enabled: bool = False  # EMAIL_SIGNUP_ENABLED=true re-opens securing a NEW account with email (never verified)
    require_phone_for_email: bool = True  # REQUIRE_PHONE_FOR_EMAIL=false: email accounts are not asked to link a phone

    comments_enabled: bool = True  # COMMENTS_ENABLED=false hides and refuses case comments (kill switch)

    streak_repair_enabled: bool = True  # STREAK_REPAIR_ENABLED=false hides and refuses the paid streak repair (kill switch)

    detective_tools_enabled: bool = True  # DETECTIVE_TOOLS_ENABLED=false hides and refuses the detective tools (kill switch)

    # Investigation depth (docs/operations.md «Leaked answers»): a solve is ranked only with enough real investigation.
    depth_gate_enabled: bool = True   # DEPTH_GATE_ENABLED=false turns the whole gate off (kill switch)
    depth_min_cards: int = 0          # distinct evidence cards TAPPED (capped by the cards the case has). 0 = only recorded: the app counts taps/pins, and a card can be read without a tap, so raise this only after looking at the real numbers
    depth_min_questions: int = 2      # distinct interrogation questions asked
    depth_need_proof: bool = False    # DEPTH_NEED_PROOF=true: at least one card of solution.proof must have been opened
    depth_require_report: bool = False  # true: an app that never reports depth (an old app) is gated too

    # Fair daily reward (docs/operations.md «Leaked answers»): a small draw among ranked 3-plaque solvers, and a weekly
    # board that rewards consistency (nights solved, then nights solved on time, then plaques, speed only breaks ties).
    daily_draw_enabled: bool = False  # OFF since 24 Oct 2026 (Amin): no draws, no winner messages. DAILY_DRAW_ENABLED=true turns it back on
    week_rank_mode: str = "consistency"  # WEEK_RANK_MODE=points restores the old order (plaques first)

    # Rewarded ads pay coins only when a real ad network is in the app.
    ads_enabled: bool = False

    # The game clock (app/gameclock.py): a game day starts when the night's case opens (21:00 Tehran); a week starts on
    # WEEK_START_WEEKDAY (Monday=0 ... Friday=4) at that hour and lasts 7 game days.
    timezone: str = "Asia/Tehran"
    new_case_hour: int = 21
    week_start_weekday: int = 4
    # Weekly board: leagues by experience (False = one board for everybody)
    leagues_enabled: bool = True

    cors_origins: str = "*"
    rate_limit: bool = True  # RATE_LIMIT=false is the kill switch (policies: RL_<NAME>, see docs/operations.md)
    redis_url: str = ""  # optional: shared counters for the strict limits (else the database is used)
    rate_trusted_hops: int = 1  # proxies in front of the server; the client IP is the Nth X-Forwarded-For entry from the right
    rate_trusted_proxies: str = ""  # optional CIDR list of proxies allowed to set X-Forwarded-For (default: private addresses)
    rate_admin_allow_ips: str = ""  # comma list of IPs that are never locked out of /admin

    @field_validator("database_url")
    @classmethod
    def _async_driver(cls, v: str) -> str:
        """Liara (and most hosts) give "postgresql://..." or "postgres://...";
        SQLAlchemy async needs "postgresql+asyncpg://..."."""
        for prefix in ("postgres://", "postgresql://"):
            if v.startswith(prefix):
                return "postgresql+asyncpg://" + v[len(prefix):]
        return v

    def check_production(self) -> None:
        if self.env == "prod":
            problems = []
            if self.jwt_secret == _DEV_JWT or len(self.jwt_secret) < 32:
                problems.append("JWT_SECRET")
            if self.admin_api_key == _DEV_ADMIN or len(self.admin_api_key) < 24:
                problems.append("ADMIN_API_KEY")
            if self.bazaar_mode == "fake" and not self.myket_access_token:
                problems.append("MYKET_ACCESS_TOKEN (or a real BAZAAR_MODE): no store can verify purchases")
            if self.sms_enabled and self.sms_mode == "ghasedak" and not (self.sms_api_key and self.sms_template):
                problems.append("SMS_API_KEY and SMS_TEMPLATE (or SMS_ENABLED=false)")
            if problems:
                raise RuntimeError("Set safe values for: " + ", ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()

