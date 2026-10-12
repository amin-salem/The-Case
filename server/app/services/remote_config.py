"""Settings the app downloads at start (change them without a new app version)."""
from __future__ import annotations

import copy
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import ConfigValue

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


async def load_config(session: AsyncSession) -> dict[str, Any]:
    cfg = copy.deepcopy(DEFAULTS)
    for row in (await session.execute(select(ConfigValue))).scalars().all():
        cfg[row.key] = row.value
    return cfg
