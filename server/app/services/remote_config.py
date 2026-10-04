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
    "update_url": "https://cafebazaar.ir/app/ir.aminsalem.the_case",
    "maintenance": False,
    "maintenance_message": "در حال تعمیر سرور هستیم، چند دقیقه دیگه برگرد!",
    # Price labels shown in the shop (the real price is set in the Bazaar panel)
    "prices": {
        "coins_small": "[قیمت] تومان",
        "coins_medium": "[قیمت] تومان",
        "coins_large": "[قیمت] تومان",
        "starter_pack": "[قیمت] تومان",
        "remove_ads": "[قیمت] تومان",
        "vip_monthly": "[قیمت] / ماه",
    },
    "news": [],
}


async def load_config(session: AsyncSession) -> dict[str, Any]:
    cfg = copy.deepcopy(DEFAULTS)
    for row in (await session.execute(select(ConfigValue))).scalars().all():
        cfg[row.key] = row.value
    return cfg
