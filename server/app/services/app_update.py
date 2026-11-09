"""App update notice, edited from the admin panel (Amin, 9 Nov 2026).

The app reads `latest_version` / `min_version` / `update_url` from the remote config (see app/lib/services/app_update.dart,
docs/operations.md «Update banner»). This service shows the three values with a count of who would see what, and saves them
safely:
- `latest_version` (1..99999): builds below it see the dismissible banner.
- `min_version` (1..latest): builds below it are BLOCKED with a full-screen page. Raising it above 1 needs `confirm_block`
  when at least one active player would be blocked, so a typo can never lock the players out.
- Counts use `players.client_build` (the app reports it; 0 = an old app that never reported and cannot show the banner),
  limited to players seen in the last 30 days, with one grouped query on indexed `last_seen`.
- Fails safe: a refused value changes nothing. Every change writes an `admin_log` row (`app_update`) and one structured log line.
"""
from __future__ import annotations

import logging
from datetime import timedelta
from typing import Any
from urllib.parse import urlparse

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import AdminLog, ConfigValue, Player, utcnow
from . import remote_config

log = logging.getLogger("app_update")

MAX_BUILD = 99999
ACTIVE_DAYS = 30


async def _counts(session: AsyncSession) -> dict[int, int]:
    since = utcnow() - timedelta(days=ACTIVE_DAYS)
    rows = (await session.execute(
        select(Player.client_build, func.count()).where(Player.last_seen >= since).group_by(Player.client_build)
    )).all()
    return {int(b or 0): int(n) for b, n in rows}


def _below(counts: dict[int, int], n: int) -> int:
    """Active players who report a build (> 0) lower than n."""
    return sum(c for b, c in counts.items() if 0 < b < n)


async def view(session: AsyncSession) -> dict[str, Any]:
    cfg = await remote_config.load_config(session)
    counts = await _counts(session)
    latest, mn = int(cfg.get("latest_version") or 1), int(cfg.get("min_version") or 1)
    builds = sorted(counts.items(), reverse=True)[:12]
    return {
        "latest_version": latest, "min_version": mn, "update_url": cfg.get("update_url") or "",
        "active_days": ACTIVE_DAYS,
        "banner_now": _below(counts, latest) if latest > 1 else 0,
        "blocked_now": _below(counts, mn) if mn > 1 else 0,
        "unknown_build": counts.get(0, 0),
        "builds": [{"build": b, "players": n} for b, n in builds],
    }


def preview(counts: dict[int, int], latest: int, mn: int) -> dict[str, int]:
    return {"banner": _below(counts, latest) if latest > 1 else 0, "blocked": _below(counts, mn) if mn > 1 else 0}


async def save(session: AsyncSession, latest: int, mn: int, confirm_block: bool = False,
               update_url: str | None = None) -> dict[str, Any]:
    if not (1 <= latest <= MAX_BUILD) or not (1 <= mn <= MAX_BUILD):
        raise HTTPException(422, "bad_version")
    if mn > latest:
        raise HTTPException(422, "min_above_latest")
    values: dict[str, Any] = {"latest_version": latest, "min_version": mn}
    if update_url is not None and update_url.strip():
        u = urlparse(update_url.strip())
        if u.scheme not in ("https", "http") or not u.netloc or len(update_url) > 300:
            raise HTTPException(422, "bad_url")
        values["update_url"] = update_url.strip()
    counts = await _counts(session)
    cur = await remote_config.load_config(session)
    blocked = preview(counts, latest, mn)["blocked"]
    raising = mn > int(cur.get("min_version") or 1)
    if raising and blocked > 0 and not confirm_block:
        raise HTTPException(409, "confirm_block")
    for key, value in values.items():
        row = await session.get(ConfigValue, key)
        if row is None:
            session.add(ConfigValue(key=key, value=value))
        else:
            row.value, row.updated_at = value, utcnow()
    session.add(AdminLog(action="app_update", target="config", detail={"latest": latest, "min": mn, "blocked": blocked}))
    await session.commit()
    remote_config.invalidate()
    log.info("app_update latest=%d min=%d blocked=%d", latest, mn, blocked)
    return await view(session)
