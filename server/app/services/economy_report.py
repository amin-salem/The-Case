"""Economy health for the admin screen «اقتصاد سکه» (GET /admin/api/economy?days=14).

Question it answers: is the coin economy fair enough that players stay AND pay? Everything comes from tables that exist
(coin_log, players, case_progress, case_tool_uses); no new tracking. Same rules as the funnel report: aggregates in SQL,
smoke-test and banned players left out, no player id / nickname in the answer, each section computed alone (a failing one
returns {"error": "section_failed"}), identical SQL on SQLite (CI) and Postgres (Liara).

The two kinds of spending (docs/operations.md «Economy health»):
- **desire** (the player wants it): avatars and frames, archive cases, streak insurance, story skips, riddle unlocks;
- **escape** (the player is stuck or frustrated): hints, detective tools, reopening a lost case, mending a streak.
A healthy game earns from both, but a game whose spending is mostly escape feels like a trap and loses players.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any, Awaitable, Callable

from sqlalchemy import and_, case, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from .. import economy as eco
from ..models import CaseProgress as CP
from ..models import CaseToolUse, CoinLog, Player
from ..util import ts
from .funnel import _valid_player

log = logging.getLogger("economy_report")

MAX_DAYS = 60
ACTIVE_DAYS = 7
COHORT_CAP = 5000                  # players looked at for the first-day-spend comparison
ERR = {"error": "section_failed"}

DESIRE = ("avatar", "unlock", "story_skip", "streak_freeze", "riddle_unlock")
ESCAPE = ("hint", "tool", "reopen", "streak_repair")
BUCKETS = [(0, 0, "۰"), (1, 49, "۱ تا ۴۹"), (50, 99, "۵۰ تا ۹۹"), (100, 299, "۱۰۰ تا ۲۹۹"),
           (300, 699, "۳۰۰ تا ۶۹۹"), (700, None, "۷۰۰ و بیشتر")]


def kind_of(reason: str) -> str:
    """The coin-log reason without its case/day/item suffix, with hint1..3 and tool_x folded into one name."""
    head = (reason or "").split(":")[0]
    if head.startswith("hint"):
        return "hint"
    if head.startswith("tool_"):
        return "tool"
    return head or "other"


def group_of(kind: str) -> str:
    return "desire" if kind in DESIRE else "escape" if kind in ESCAPE else "other"


def _pct(n: int, total: int) -> float | None:
    return round(100 * n / total, 1) if total else None


async def _flows(s: AsyncSession, since: datetime) -> dict:
    rows = (await s.execute(
        select(CoinLog.reason, func.sum(CoinLog.amount), func.count())
        .join(Player, Player.id == CoinLog.player_id).where(CoinLog.at >= since, _valid_player())
        .group_by(CoinLog.reason))).all()
    earned: dict[str, int] = {}
    spent: dict[str, int] = {}
    uses: dict[str, int] = {}
    for reason, total, n in rows:
        total = int(total or 0)
        k = kind_of(reason)
        if total >= 0:
            earned[k] = earned.get(k, 0) + total
        else:
            spent[k] = spent.get(k, 0) + -total
            uses[k] = uses.get(k, 0) + int(n)
    e_total, s_total = sum(earned.values()), sum(spent.values())
    split = {"desire": 0, "escape": 0, "other": 0}
    for k, v in spent.items():
        split[group_of(k)] += v
    def table(d, total, with_uses=False):
        out = []
        for k, v in sorted(d.items(), key=lambda kv: -kv[1]):
            row = {"kind": k, "coins": v, "pct": _pct(v, total)}
            if with_uses:
                row["group"] = group_of(k)
                row["times"] = uses.get(k, 0)
            out.append(row)
        return out
    return {"earned_total": e_total, "spent_total": s_total, "earned": table(earned, e_total),
            "spent": table(spent, s_total, True), "spent_split_pct": {k: _pct(v, s_total) for k, v in split.items()},
            "spent_to_earned_pct": _pct(s_total, e_total)}


async def _balances(s: AsyncSession, now: datetime) -> dict:
    cols = [func.sum(case((Player.coins >= lo if hi is None else and_(Player.coins >= lo, Player.coins <= hi), 1), else_=0))
            for lo, hi, _ in BUCKETS]
    row = (await s.execute(select(func.count(), *cols, func.sum(case((Player.coins >= eco.HINT_COSTS[0], 1), else_=0)))
                           .where(Player.last_seen >= now - timedelta(days=ACTIVE_DAYS), _valid_player()))).one()
    total = int(row[0] or 0)
    counts = [int(x or 0) for x in row[1:1 + len(BUCKETS)]]
    afford = int(row[-1] or 0)
    return {"active_players": total, "active_days": ACTIVE_DAYS,
            "buckets": [{"label": lab, "players": c, "pct": _pct(c, total)} for (_, _, lab), c in zip(BUCKETS, counts)],
            "can_afford_first_hint_pct": _pct(afford, total), "first_hint_price": eco.HINT_COSTS[0],
            "prices": {"hints": list(eco.HINT_COSTS), "tools": dict(eco.TOOL_PRICES)}}


async def _cases(s: AsyncSession, since: datetime) -> dict:
    done = and_(CP.finished_at.isnot(None), CP.finished_at >= since)
    row = (await s.execute(
        select(func.count(), func.sum(case((CP.solved.is_(True), 1), else_=0)), func.sum(case((CP.failed.is_(True), 1), else_=0)),
               func.sum(case((CP.hints >= 1, 1), else_=0)), func.sum(case((CP.hints >= 2, 1), else_=0)),
               func.sum(case((CP.hints >= 3, 1), else_=0)), func.avg(CP.hints))
        .join(Player, Player.id == CP.player_id).where(done, _valid_player()))).one()
    n, solved, failed, h1, h2, h3, avg = (int(row[0] or 0), int(row[1] or 0), int(row[2] or 0), int(row[3] or 0),
                                          int(row[4] or 0), int(row[5] or 0), row[6])
    tools = (await s.execute(
        select(CaseToolUse.kind, CaseToolUse.source, func.count())
        .join(Player, Player.id == CaseToolUse.player_id).where(CaseToolUse.created_at >= since, _valid_player())
        .group_by(CaseToolUse.kind, CaseToolUse.source))).all()
    t: dict[str, dict] = {}
    for kind, source, c in tools:
        t.setdefault(kind, {"free": 0, "stock": 0, "coins": 0})[source if source in ("free", "stock", "coins") else "stock"] += int(c)
    return {"finished": n, "solved": solved, "failed": failed, "failed_pct": _pct(failed, n),
            "with_hint_pct": _pct(h1, n), "with_2_hints_pct": _pct(h2, n), "with_3_hints_pct": _pct(h3, n),
            "avg_hints": round(float(avg), 2) if avg is not None else None,
            "tools": [{"kind": k, **v} for k, v in sorted(t.items())]}


async def _after_loss(s: AsyncSession, since: datetime) -> dict:
    """Of the cases lost in the window: how many players opened any case afterwards (they came back), and how many paid
    for the second chance. Compares columns only (no date arithmetic), so it is the same SQL everywhere."""
    later = aliased(CP)
    lost = and_(CP.failed.is_(True), CP.solved.is_(False), CP.finished_at.isnot(None), CP.finished_at >= since)
    came_back = select(later.id).where(later.player_id == CP.player_id, later.opened_at > CP.finished_at,
                                       later.case_id != CP.case_id).exists()
    row = (await s.execute(select(func.count(), func.sum(case((came_back, 1), else_=0)))
                           .join(Player, Player.id == CP.player_id).where(lost, _valid_player()))).one()
    n, back = int(row[0] or 0), int(row[1] or 0)
    reopened = int((await s.scalar(select(func.count()).select_from(CoinLog).join(Player, Player.id == CoinLog.player_id)
                                   .where(CoinLog.at >= since, CoinLog.reason.like("reopen:%"), _valid_player()))) or 0)
    return {"lost_cases": n, "came_back_pct": _pct(back, n), "paid_second_chance": reopened,
            "paid_second_chance_pct": _pct(reopened, n)}


async def _first_day(s: AsyncSession, since: datetime, now: datetime) -> dict:
    """New players (signed up in the window, at least 2 days ago): did the ones who spent coins on an escape item in their
    first 24 hours come back later more or less than the others? 'Came back' = seen again 24 h or more after signup.
    A sample of at most COHORT_CAP players (the newest)."""
    rows = (await s.execute(select(Player.id, Player.created_at, Player.last_seen)
                            .where(Player.created_at >= since, Player.created_at <= now - timedelta(days=2), _valid_player())
                            .order_by(Player.created_at.desc()).limit(COHORT_CAP))).all()
    if not rows:
        return {"players": 0}
    created = {pid: c for pid, c, _ in rows}
    spenders: set[str] = set()
    ids = list(created)
    for i in range(0, len(ids), 500):
        chunk = ids[i:i + 500]
        for pid, at in (await s.execute(select(CoinLog.player_id, CoinLog.at).where(
                CoinLog.player_id.in_(chunk), CoinLog.amount < 0,
                (CoinLog.reason.like("hint%")) | (CoinLog.reason.like("tool_%")) | (CoinLog.reason.like("reopen:%"))))).all():
            if at <= created[pid] + timedelta(hours=24):
                spenders.add(pid)
    def back(group):
        return sum(1 for pid, c, seen in rows if pid in group and seen >= c + timedelta(hours=24))
    sp, rest = spenders, set(created) - spenders
    return {"players": len(created), "spent_first_day": len(sp), "others": len(rest),
            "spenders_came_back_pct": _pct(back(sp), len(sp)), "others_came_back_pct": _pct(back(rest), len(rest))}


def notes(d: dict) -> list[str]:
    """Plain-language readings of the numbers above (a guide, not a verdict; they need a few days of data)."""
    out: list[str] = []
    fl, bal, cs, loss, fd = (d.get(k) or {} for k in ("flows", "balances", "cases", "after_loss", "first_day"))
    if isinstance(fl, dict) and fl.get("spent_total"):
        esc = (fl.get("spent_split_pct") or {}).get("escape")
        if esc is not None and esc >= 60:
            out.append(f"{esc}٪ خرج سکه «فرار از گیر» است (سرنخ، ابزار، فرصت دوباره). این یعنی بازی بیشتر از گیرکردن پول می‌گیرد تا از میل بازیکن؛ قیمت سرنخ را پایین‌تر یا خرج‌های میل‌محور (آواتار، قاب، محافظ زنجیره) را جذاب‌تر کن.")
        elif esc is not None and esc <= 20:
            out.append(f"فقط {esc}٪ خرج سکه «فرار از گیر» است؛ شاید سرنخ و ابزار ارزان‌اند یا کسی به آن‌ها نیاز پیدا نمی‌کند.")
    if isinstance(bal, dict) and bal.get("active_players"):
        z = bal["buckets"][0]["pct"] or 0
        rich = bal["buckets"][-1]["pct"] or 0
        aff = bal.get("can_afford_first_hint_pct")
        if aff is not None and aff < 40:
            out.append(f"فقط {aff}٪ از فعال‌های هفته به قیمت اولین سرنخ ({bal['first_hint_price']}) می‌رسند؛ فشار زیاد است.")
        if rich >= 30:
            out.append(f"{rich}٪ فعال‌ها بالای ۷۰۰ سکه دارند و خرج نمی‌کنند؛ یا قیمت‌ها پایین‌اند یا خرجِ جذاب کم است.")
        if z >= 40:
            out.append(f"{z}٪ فعال‌ها سکه‌ی صفر دارند؛ درآمد رایگان کم است یا خرج زیاد.")
    if isinstance(loss, dict) and loss.get("lost_cases", 0) >= 20 and loss.get("came_back_pct") is not None and loss["came_back_pct"] < 60:
        out.append(f"فقط {loss['came_back_pct']}٪ بعد از باخت پرونده‌ی دیگری باز می‌کنند؛ باخت‌ها دارند بازیکن را می‌پرانند.")
    if isinstance(cs, dict) and cs.get("failed_pct") is not None and cs["failed_pct"] >= 40 and cs.get("finished", 0) >= 20:
        out.append(f"{cs['failed_pct']}٪ پرونده‌های تمام‌شده با شکست تمام شده‌اند؛ سختی را کنار قیمت سرنخ ببین.")
    if isinstance(fd, dict) and fd.get("spent_first_day", 0) >= 10 and fd.get("others", 0) >= 10:
        a, b = fd.get("spenders_came_back_pct"), fd.get("others_came_back_pct")
        if a is not None and b is not None and a + 10 < b:
            out.append(f"بازیکنی که روز اول برای سرنخ/ابزار سکه خرج کرد کمتر برگشته ({a}٪ در برابر {b}٪)؛ خرج روز اول ممکن است بیزارشان کند.")
    if not out:
        out.append("چیز نگران‌کننده‌ای در این عددها نیست (یا هنوز داده‌ی کافی نیست؛ چند روز صبر کن).")
    return out


SECTIONS: list[tuple[str, Callable[..., Awaitable[Any]], str]] = [
    ("flows", _flows, "since"), ("balances", _balances, "now"), ("cases", _cases, "since"),
    ("after_loss", _after_loss, "since"), ("first_day", _first_day, "both"),
]


async def build(s: AsyncSession, days: int, now: datetime | None = None) -> dict:
    from ..models import utcnow
    now = now or utcnow()
    days = max(1, min(MAX_DAYS, int(days)))
    since = now - timedelta(days=days)
    out: dict[str, Any] = {"days": days, "generated_at": ts(now)}
    for name, fn, arg in SECTIONS:
        try:
            out[name] = await (fn(s, since) if arg == "since" else fn(s, now) if arg == "now" else fn(s, since, now))
        except Exception:
            log.exception("economy section %s failed", name)
            await s.rollback()
            out[name] = dict(ERR)
    out["notes"] = notes(out)
    return out
