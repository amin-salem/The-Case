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

    jwt_secret: str = _DEV_JWT
    jwt_days: int = 30
    admin_api_key: str = _DEV_ADMIN

    # Cafe Bazaar
    bazaar_mode: str = "fake"  # fake | api_secret | oauth
    bazaar_package_name: str = "ir.aminsalem.the_case"
    bazaar_base_url: str = "https://pardakht.cafebazaar.ir/devapi/v2"
    bazaar_api_secret: str = ""
    bazaar_client_id: str = ""
    bazaar_client_secret: str = ""
    bazaar_refresh_token: str = ""

    # Myket (the store we publish on first). The access token is in the Myket developer panel, under the
    # app's in-app products. Empty in production = Myket purchases are refused.
    myket_access_token: str = ""
    myket_package_name: str = "ir.aminsalem.the_case"
    myket_base_url: str = "https://developer.myket.ir/api/partners/applications"

    # Rewarded ads pay coins only when a real ad network is in the app.
    ads_enabled: bool = False

    # Daily case: the day changes at midnight in Iran, the new case opens at 21:00
    timezone: str = "Asia/Tehran"
    new_case_hour: int = 21

    cors_origins: str = "*"
    rate_limit: bool = True

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
            if problems:
                raise RuntimeError("Set safe values for: " + ", ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()
