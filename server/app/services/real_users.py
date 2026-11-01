"""Real users vs. throw-away rows (READ ONLY). The «players» table counts every installation, so it overstates people:
testers, banned rows, load-test rows, installs that never opened a case, and people who came back on a new
installation (clearing the app's data makes a new random device id, so the old row is never linked to the new one).

Segments (each non-excluded row is in exactly one):
  excluded   tester, banned, or a load-test row (device id «smoke-load-…»)
  duplicate  probably the same person as a newer row (see `duplicate_ids`)
  real       solved at least one case, or has a granted purchase
  tried      opened a case but never solved one and never paid
  empty      never opened a case
Nothing here changes data. Queries use plain columns/EXISTS only (PostgreSQL-safe) and are bounded."""
from __future__ import annotations

import re
from datetime import timedelta

from sqlalchemy import and_, exists, func, not_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import CaseProgress, Player, Purchase, utcnow

SEGMENTS = ("real", "tried", "empty", "duplicate", "excluded")
MAX_ROWS = 20000          # at most this many newest rows are examined for duplicates
QUIET_GRACE = timedelta(days=1)   # the older row must have gone quiet by (new row's creation + this)
MIN_KEY = 5               # shortest e-mail name (letters only) that may link two rows


def _excluded():
    return or_(Player.tester.is_(True), Player.banned.is_(True), Player.device_id.startswith("smoke-load-"))


def _has_purchase():
    return exists().where(and_(Purchase.player_id == Player.id, Purchase.status == "granted"))


def _has_progress():
    return exists().where(CaseProgress.player_id == Player.id)


def _real():
    return or_(Player.cases_solved > 0, _has_purchase())


def _letters(email: str | None) -> str:
    return re.sub(r"[^a-z]", "", (email or "").split("@", 1)[0].lower())


def _linked(a: str, b: str) -> bool:
    """Two e-mail names (letters only) that start the same way: maryam / maryamfarzaneh."""
    short, long_ = (a, b) if len(a) <= len(b) else (b, a)
    return len(short) >= MIN_KEY and long_.startswith(short)


async def duplicate_ids(session: AsyncSession) -> dict[str, str]:
    """{older row id: reason} for rows that are probably the same person as a NEWER row.
    «device»: a guest with no solved case sharing the device id of an account that has an e-mail or phone (the app made
    a guest first, then the player signed in to the old account). «email»: two rows whose e-mail names start the same,
    where the older one went quiet by the time the newer one was created. Excluded rows are never touched."""
    rows = (await session.execute(
        select(Player.id, Player.device_id, Player.email, Player.phone_hash, Player.cases_solved, Player.created_at,
               Player.last_seen).where(not_(_excluded())).order_by(Player.created_at.desc(), Player.id).limit(MAX_ROWS))).all()
    out: dict[str, str] = {}
    by_dev: dict[str, list] = {}
    by_key: dict[str, list] = {}
    for r in rows:
        by_dev.setdefault(r.device_id, []).append(r)
        k = _letters(r.email)
        if len(k) >= MIN_KEY:
            by_key.setdefault(k[:MIN_KEY], []).append(r)
    for grp in by_dev.values():
        if len(grp) > 1 and any(r.email or r.phone_hash for r in grp):
            for r in grp:
                if not (r.email or r.phone_hash) and not r.cases_solved:
                    out[r.id] = "device"
    for grp in by_key.values():
        grp = sorted(grp, key=lambda r: (r.created_at, r.id))
        for i, old in enumerate(grp):
            for new in grp[i + 1:]:
                if (new.id != old.id and _linked(_letters(old.email), _letters(new.email))
                        and (old.last_seen or old.created_at) <= new.created_at + QUIET_GRACE):
                    out.setdefault(old.id, "email")
                    break
    return out


async def summary(session: AsyncSession) -> dict:
    now = utcnow()
    base = not_(_excluded())
    count = lambda *w: session.scalar(select(func.count()).select_from(Player).where(*w))
    total = int(await count() or 0)
    dup = await duplicate_ids(session)
    ids = list(dup)

    async def in_dup(*w) -> int:
        return int(await count(Player.id.in_(ids), *w) or 0) if ids else 0

    excluded = int(await count(_excluded()) or 0)
    real = int(await count(base, _real()) or 0) - await in_dup(_real())
    tried = int(await count(base, not_(_real()), _has_progress()) or 0) - await in_dup(not_(_real()), _has_progress())
    empty = int(await count(base, not_(_real()), not_(_has_progress())) or 0) - await in_dup(not_(_real()), not_(_has_progress()))
    real_ids = [i for i in ids] if ids else []
    ok_real = and_(base, _real(), not_(Player.id.in_(real_ids))) if real_ids else and_(base, _real())
    return {"players": total, "real": real, "tried": tried, "empty": empty, "duplicate": len(dup), "excluded": excluded,
            "real_active_7d": int(await count(ok_real, Player.last_seen >= now - timedelta(days=7)) or 0),
            "real_active_30d": int(await count(ok_real, Player.last_seen >= now - timedelta(days=30)) or 0),
            "duplicate_device": sum(1 for v in dup.values() if v == "device"),
            "duplicate_email": sum(1 for v in dup.values() if v == "email")}


def where_segment(segment: str, dup_ids: list[str]):
    """SQL condition for a players-list filter."""
    base = not_(_excluded())
    not_dup = not_(Player.id.in_(dup_ids)) if dup_ids else True
    if segment == "excluded":
        return _excluded()
    if segment == "duplicate":
        return and_(base, Player.id.in_(dup_ids)) if dup_ids else Player.id == "-"
    if segment == "real":
        return and_(base, not_dup, _real())
    if segment == "tried":
        return and_(base, not_dup, not_(_real()), _has_progress())
    if segment == "empty":
        return and_(base, not_dup, not_(_real()), not_(_has_progress()))
    return True


async def label_rows(session: AsyncSession, rows: list[Player], dup: dict[str, str]) -> dict[str, dict]:
    """{player id: {"segment", "reason"}} for one page of rows."""
    ids = [p.id for p in rows]
    bought = set((await session.scalars(select(Purchase.player_id).where(
        Purchase.player_id.in_(ids), Purchase.status == "granted"))).all()) if ids else set()
    opened = set((await session.scalars(select(CaseProgress.player_id).where(
        CaseProgress.player_id.in_(ids)).distinct())).all()) if ids else set()
    out = {}
    for p in rows:
        if p.tester or p.banned or (p.device_id or "").startswith("smoke-load-"):
            seg = "excluded"
        elif p.id in dup:
            seg = "duplicate"
        elif (p.cases_solved or 0) > 0 or p.id in bought:
            seg = "real"
        elif p.id in opened:
            seg = "tried"
        else:
            seg = "empty"
        out[p.id] = {"segment": seg, "reason": dup.get(p.id, "")}
    return out
