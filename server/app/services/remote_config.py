"""Settings the app downloads at start (change them without a new app version)."""
from __future__ import annotations

import copy
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..cache import TTLCache
from ..models import ConfigValue

# The same rows are read by every app start (/v1/config) and every /v1/me (the bell): keep them for a few seconds.
# An admin change clears the cache of the worker that handled it; the other workers catch up within the TTL.
_rows = TTLCache("config_rows", ttl=10, max_size=2)

DEFAULTS: dict[str, Any] = {
    "min_version": 1,
    "latest_version": 1,
    "update_url": "https://cafebazaar.ir/app/ir.gammly.parvandeh",
    "share_url": "https://cafebazaar.ir/app/ir.gammly.parvandeh",
    "privacy_url": "https://gaamly.ir/privacy",
    "terms_url": "https://gaamly.ir/terms",
    "support_email": "aminsaalem@gmail.com",
    "ads_enabled": False,
    "maintenance": False,
    "maintenance_message": "در حال تعمیر سرور هستیم، چند دقیقه دیگه برگرد!",
    # Price labels shown in the shop when the store can't tell the app its own price.
    # The real price is the one set for each product in the Bazaar panel; keep these the same.
    "prices": {
        "coins_small": "۳۹٬۰۰۰ تومان",
        "coins_medium": "۹۹٬۰۰۰ تومان",
        "coins_large": "۲۴۹٬۰۰۰ تومان",
        "starter_pack": "۴۹٬۰۰۰ تومان",
        "remove_ads": "۵۹٬۰۰۰ تومان",
        "vip_monthly": "۱۴۹٬۰۰۰ تومان / ۳۰ روز",
    },
    "news": [],
}


async def _load_rows(session: AsyncSession) -> list[tuple[str, Any, Any]]:
    async def loader():
        return [(r.key, r.value, r.updated_at) for r in (await session.execute(select(ConfigValue))).scalars().all()]
    return await _rows.get_or_load("rows", loader)


def invalidate() -> None:
    _rows.clear()


async def load_config(session: AsyncSession) -> dict[str, Any]:
    cfg = copy.deepcopy(DEFAULTS)
    for key, value, _ in await _load_rows(session):
        cfg[key] = copy.deepcopy(value)
    return cfg


async def stamp_of(session: AsyncSession, key: str):
    """When a config value was last saved (None if it was never set)."""
    return next((at for k, _, at in await _load_rows(session) if k == key), None)
