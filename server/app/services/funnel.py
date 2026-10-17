"""Funnel and retention for the admin panel screen «قیف و ماندگاری» (GET /admin/api/funnel?days=30).

Everything is derived from tables that already exist (players, case_progress, purchases): no per-event tracking.
**Retention is derived from case activity**: a player "returned on day N" when a case_progress row of his was opened or
finished on the Tehran calendar day N days after his signup day. Opening the app without touching a case does not count
(only `players.last_seen` is used for the DAU/WAU numbers).

Rules (docs/operations.md «Funnel and retention»):
- Plain SQL aggregates (GROUP BY, window functions for medians); no rows are loaded into Python, no N+1. Every section
  is a handful of queries whose cost grows with the number of players in the window (at most 90 days).
- Cohort days are Tehran calendar days. The day boundaries are computed here (UTC, naive, like every stored time) and
  the cohort number of a row is a CASE over them, so the same SQL runs on SQLite (CI) and Postgres (Liara).
- Smoke-test players (device id «smoke-…») and banned players are left out of every number.
- The answer holds counts and case ids only: no player id, nickname, email or device id.
- Each section is computed on its own: a failing one returns {"error": "section_failed"} and the others still work.
"""
from __future__ import annotations

import logging
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Awaitable, Callable

from sqlalchemy import Integer, and_, case, cast, extract, func, literal_column, not_, or_, select, union_all
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content, economy
from ..models import CaseProgress as CP
from ..models import Player, Purchase
from ..purge import SMOKE_PREFIX

log = logging.getLogger("funnel")

MAX_DAYS = 90
STOP_AFTER_H = 48        # a player whose last_seen is older than this has "stopped"
QUALITY_DAYS = 14        # the per-case table looks at cases opened in the last 14 days
CASE_ROWS = 40           # at most this many cases in the per-case table
ABANDON_ROWS = 10
RETENTION_DAYS = (1, 3, 7)
INVITE_DAYS = economy.INVITE_MIN_DAYS  # "solved on this many different days" (the invite-paid rule)
ERR = {"error": "section_failed"}


# ------------------------------------------------------------------ day buckets and small SQL helpers

class Frame:
    """The window: `days` Tehran calendar days ending today. Day i (0 = oldest, days-1 = today) starts at bounds[i] (UTC)."""

    def __init__(self, now: datetime, days: int):
        tz = content.now_local().tzinfo
        self.now = now
        self.days = max(1, min(MAX_DAYS, int(days)))
        local_today = now.replace(tzinfo=timezone.utc).astimezone(tz).date()
        self.dates: list[date] = [local_today - timedelta(days=self.days - 1 - i) for i in range(self.days)]
        self.bounds: list[datetime] = [
            datetime.combine(d, time.min, tzinfo=tz).astimezone(timezone.utc).replace(tzinfo=None) for d in self.dates]
        self.start = self.bounds[0]
        self.today = self.days - 1

    def idx(self, col):
        """SQL expression: the day number (0..days-1) of a datetime column, NULL before the window."""
        return case(*[(col >= b, i) for i, b in reversed(list(enumerate(self.bounds)))])

    def eligible(self, d: int) -> int:
        """Cohorts 0..eligible(d) have fully lived through day +d (that day is over); younger ones are skipped."""
        return self.today - d - 1


def _valid_player():
    return and_(not_(Player.device_id.startswith(SMOKE_PREFIX)), Player.banned.is_(False))


def _players(f: Frame):
    """Players who signed up inside the window, with their cohort number."""
    return select(Player.id.label("pid"), Player.created_at.label("created"), Player.last_seen.label("seen"),
                  f.idx(Player.created_at).label("c")).where(Player.created_at >= f.start, _valid_player()).subquery()


def _activity(f: Frame):
    """Every (player, day number) at which a case was opened or finished inside the window."""
    opened = select(CP.player_id.label("pid"), f.idx(CP.opened_at).label("a")).where(CP.opened_at >= f.start)
    done = select(CP.player_id.label("pid"), f.idx(CP.finished_at).label("a")).where(CP.finished_at >= f.start)
    return union_all(opened, done).subquery()


def _epoch(session: AsyncSession, col):
    if session.bind.dialect.name == "sqlite":
        return cast(func.strftime("%s", col), Integer)
    return extract("epoch", col)


async def _percentiles(session: AsyncSession, values, qs=(50,), group=None) -> dict[Any, list[float | None]]:
    """Nearest-rank percentiles of `values` (a select with a column «v» and, if grouped, a column «g»), computed in SQL
    with window functions. Returns {group: [value per q]} ({0: ...} when not grouped)."""
    base = values.subquery()
    g = base.c.g if group else literal_column("0")
    ranked = select(base.c.v.label("v"), g.label("g"),
                    func.row_number().over(partition_by=g, order_by=base.c.v).label("rn"),
                    func.count().over(partition_by=g).label("n")).subquery()
    cols = [func.max(case((ranked.c.rn == (ranked.c.n * q + 99) // 100, ranked.c.v), else_=None)) for q in qs]
    rows = (await session.execute(select(ranked.c.g, *cols).group_by(ranked.c.g))).all()
    return {r[0]: [None if x is None else float(x) for x in r[1:]] for r in rows}


def _pct(a: int, b: int) -> float | None:
    return round(100.0 * a / b, 1) if b else None


def _i(x) -> int:
    return int(x or 0)


# ------------------------------------------------------------------ sections

async def _signups(s: AsyncSession, f: Frame) -> dict:
    pl = _players(f)
    rows = dict((await s.execute(select(pl.c.c, func.count()).group_by(pl.c.c))).all())
    days = [{"day": d.isoformat(), "new": _i(rows.get(i))} for i, d in enumerate(f.dates)]
    return {"days": days, "total": sum(x["new"] for x in days)}


async def _funnel(s: AsyncSession, f: Frame) -> dict:
    pl = _players(f)
    done = or_(CP.solved.is_(True), CP.failed.is_(True))
    pp = (select(CP.player_id.label("pid"), func.count().label("opened"),
                 func.sum(case((done, 1), else_=0)).label("fin"),
                 func.count(func.distinct(case((and_(CP.solved.is_(True), CP.day != ""), CP.day), else_=None))).label("sdays"))
          .where(CP.player_id.in_(select(pl.c.pid))).group_by(CP.player_id).subquery())
    first = (select(CP.player_id.label("pid"), CP.solved.label("solved"), CP.failed.label("failed"),
                    func.row_number().over(partition_by=CP.player_id, order_by=[CP.opened_at, CP.id]).label("rn"))
             .where(CP.player_id.in_(select(pl.c.pid))).subquery())
    fc = select(first.c.pid, first.c.solved, first.c.failed).where(first.c.rn == 1).subquery()
    q = (select(pl.c.c, func.count(),
                func.sum(case((func.coalesce(pp.c.opened, 0) > 0, 1), else_=0)),
                func.sum(case((or_(fc.c.solved.is_(True), fc.c.failed.is_(True)), 1), else_=0)),
                func.sum(case((fc.c.solved.is_(True), 1), else_=0)),
                func.sum(case((func.coalesce(pp.c.sdays, 0) >= INVITE_DAYS, 1), else_=0)))
         .select_from(pl.outerjoin(pp, pp.c.pid == pl.c.pid).outerjoin(fc, fc.c.pid == pl.c.pid)).group_by(pl.c.c))
    got = {r[0]: [_i(x) for x in r[1:]] for r in (await s.execute(q)).all()}
    keys = ("registered", "opened", "finished_first", "solved_first", "solved_3_days")
    days, tot = [], [0] * 5
    for i, d in enumerate(f.dates):
        v = got.get(i, [0] * 5)
        tot = [a + b for a, b in zip(tot, v)]
        days.append({"day": d.isoformat(), **dict(zip(keys, v))})
    total = dict(zip(keys, tot))
    return {"days": days, "total": total,
            "pct": {k: _pct(total[k], total["registered"]) for k in keys}}


async def _retention(s: AsyncSession, f: Frame) -> dict:
    pl, act = _players(f), _activity(f)
    d = act.c.a - pl.c.c
    q = (select(pl.c.c, d.label("d"), func.count(func.distinct(pl.c.pid)))
         .select_from(pl.join(act, act.c.pid == pl.c.pid)).where(d.in_(RETENTION_DAYS)).group_by(pl.c.c, d))
    back = {(r[0], r[1]): _i(r[2]) for r in (await s.execute(q)).all()}
    size = dict((await s.execute(select(pl.c.c, func.count()).group_by(pl.c.c))).all())
    out, days = {}, []
    for i, dt in enumerate(f.dates):
        row: dict[str, Any] = {"day": dt.isoformat(), "new": _i(size.get(i))}
        for n in RETENTION_DAYS:
            row[f"d{n}"] = back.get((i, n), 0) if i <= f.eligible(n) else None  # None = cohort too young
        days.append(row)
    for n in RETENTION_DAYS:
        cohorts = [r for r in days if r[f"d{n}"] is not None]
        base, ret = sum(r["new"] for r in cohorts), sum(r[f"d{n}"] for r in cohorts)
        out[f"d{n}"] = {"returned": ret, "of": base, "pct": _pct(ret, base), "cohorts": len(cohorts)}
    day, week = f.now - timedelta(days=1), f.now - timedelta(days=7)
    allp = select(func.count(), func.sum(case((Player.last_seen >= day, 1), else_=0)),
                  func.sum(case((Player.last_seen >= week, 1), else_=0))).where(_valid_player())
    total, dau, wau = [_i(x) for x in (await s.execute(allp)).one()]
    return {"days": days, "total": out,
            "active": {"players": total, "dau": dau, "wau": wau, "dau_pct": _pct(dau, total),
                       "wau_pct": _pct(wau, total), "dau_wau_pct": _pct(dau, wau)}}


STAGES = [("never_opened", "هیچ پرونده‌ای باز نکرد"), ("opened_not_finished", "پرونده باز کرد ولی تمام نکرد"),
          ("finished_1", "۱ پرونده تمام کرد و رفت"), ("finished_2", "۲ پرونده تمام کرد و رفت"),
          ("finished_3_4", "۳ تا ۴ پرونده تمام کرد و رفت"), ("finished_5_plus", "۵ پرونده یا بیشتر تمام کرد و رفت")]


async def _drop_off(s: AsyncSession, f: Frame) -> dict:
    pl = _players(f)
    done = or_(CP.solved.is_(True), CP.failed.is_(True))
    pp = (select(CP.player_id.label("pid"), func.count().label("opened"), func.sum(case((done, 1), else_=0)).label("fin"))
          .where(CP.player_id.in_(select(pl.c.pid))).group_by(CP.player_id).subquery())
    opened, fin = func.coalesce(pp.c.opened, 0), func.coalesce(pp.c.fin, 0)
    stage = case((opened == 0, "never_opened"), (fin == 0, "opened_not_finished"), (fin == 1, "finished_1"),
                 (fin == 2, "finished_2"), (fin <= 4, "finished_3_4"), else_="finished_5_plus")
    st = select(pl.c.pid.label("pid"), stage.label("stage")).select_from(pl.outerjoin(pp, pp.c.pid == pl.c.pid)) \
        .where(pl.c.seen < f.now - timedelta(hours=STOP_AFTER_H)).subquery()
    got = dict((await s.execute(select(st.c.stage, func.count()).group_by(st.c.stage))).all())
    stopped = sum(_i(v) for v in got.values())
    stages = [{"key": k, "label": label, "players": _i(got.get(k)), "pct": _pct(_i(got.get(k)), stopped)} for k, label in STAGES]
    q = (select(CP.case_id, func.count()).where(CP.opened_at >= f.start, CP.opened_at < f.now - timedelta(hours=24),
                                                CP.solved.is_(False), CP.failed.is_(False),
                                                CP.player_id.in_(select(pl.c.pid)))
         .group_by(CP.case_id).order_by(func.count().desc(), CP.case_id).limit(ABANDON_ROWS))
    cases = [{"case": c, "title": _title(c), "abandoned": _i(n)} for c, n in (await s.execute(q)).all()]
    return {"stopped_after_hours": STOP_AFTER_H, "stopped": stopped, "stages": stages, "abandoned_cases": cases}


def _title(case_id: str) -> str:
    c = content.by_id(case_id) or content.weekly_by_id(case_id)
    t = (c.data.get("title") if c is not None and isinstance(c.data, dict) else None) or ""
    return t


async def _money(s: AsyncSession, f: Frame) -> dict:
    pl, act = _players(f), _activity(f)
    granted = Purchase.status == "granted"
    pay = dict((await s.execute(select(pl.c.c, func.count()).where(pl.c.pid.in_(select(Purchase.player_id).where(granted)))
                                .group_by(pl.c.c))).all())
    registered = _i(await s.scalar(select(func.count()).select_from(pl)))
    payers = sum(_i(v) for v in pay.values())
    # D7-retained players (cohorts old enough) and how many of them paid
    ok = pl.c.c <= f.eligible(7)
    d7 = act.c.a - pl.c.c == 7
    ret = select(pl.c.pid).select_from(pl.join(act, act.c.pid == pl.c.pid)).where(d7, ok).distinct().subquery()
    d7_n = _i(await s.scalar(select(func.count()).select_from(ret)))
    d7_payers = _i(await s.scalar(select(func.count()).select_from(ret).where(
        ret.c.pid.in_(select(Purchase.player_id).where(granted)))))
    # time from signup to the first verified purchase (hours)
    first = (select(Purchase.player_id.label("pid"), func.min(Purchase.created_at).label("t")).where(granted)
             .group_by(Purchase.player_id).subquery())
    secs = select((_epoch(s, first.c.t) - _epoch(s, pl.c.created)).label("v")).select_from(
        pl.join(first, first.c.pid == pl.c.pid))
    med = (await _percentiles(s, secs)).get(0, [None])[0]
    # revenue by pack: purchases made in the window by valid players (coins/units, never prices)
    rows = (await s.execute(select(Purchase.product_id, Purchase.status, func.count())
                            .select_from(Purchase).join(Player, Player.id == Purchase.player_id)
                            .where(Purchase.created_at >= f.start, _valid_player())
                            .group_by(Purchase.product_id, Purchase.status))).all()
    packs: dict[str, dict] = {}
    for pid, status, n in rows:
        p = packs.setdefault(pid, {"product": pid, "granted": 0, "refunded": 0, "rejected": 0, "coins": 0})
        if status in ("granted", "refunded", "rejected"):
            p[status] += _i(n)
    for p in packs.values():
        prod = economy.PRODUCTS.get(p["product"])
        p["coins"] = p["granted"] * prod.coins if prod else None
        p["vip_days"] = p["granted"] * prod.vip_days if prod and prod.vip_days else None
        p["no_ads"] = bool(prod and prod.no_ads)
    # coin balances of players seen in the last 7 days (are coins scarce?)
    active = Player.last_seen >= f.now - timedelta(days=7)
    q = _percentiles(s, select(Player.coins.label("v")).where(active, _valid_player()), qs=(25, 50, 75))
    qs = (await q).get(0, [None] * 3)
    n_active = _i(await s.scalar(select(func.count()).select_from(Player).where(active, _valid_player())))
    zero = _i(await s.scalar(select(func.count()).select_from(Player).where(active, _valid_player(), Player.coins <= 0)))
    return {"registered": registered, "payers": payers, "conversion_pct": _pct(payers, registered),
            "d7_retained": d7_n, "d7_retained_payers": d7_payers, "d7_conversion_pct": _pct(d7_payers, d7_n),
            "first_purchase_median_hours": None if med is None else round(med / 3600.0, 1),
            "packs": sorted(packs.values(), key=lambda p: (-p["granted"], p["product"])),
            "coins": {"active_players": n_active, "p25": qs[0], "median": qs[1], "p75": qs[2],
                      "zero_pct": _pct(zero, n_active)}}


async def _quality(s: AsyncSession, f: Frame) -> dict:
    done = or_(CP.solved.is_(True), CP.failed.is_(True))
    base = [CP.opened_at >= f.start, _valid_player()]
    row = (await s.execute(select(
        func.count(), func.sum(case((done, 1), else_=0)), func.sum(case((CP.solved.is_(True), 1), else_=0)),
        func.sum(case((CP.failed.is_(True), 1), else_=0)),
        func.sum(case((and_(CP.solved.is_(True), CP.stars >= 3), 1), else_=0)),
        func.sum(case((and_(CP.solved.is_(True), CP.stars == 2), 1), else_=0)),
        func.sum(case((and_(CP.solved.is_(True), CP.stars <= 1), 1), else_=0)),
        func.avg(case((done, CP.hints), else_=None)))
        .select_from(CP).join(Player, Player.id == CP.player_id).where(*base))).one()
    opened, fin, solved, failed, p3, p2, p1 = (_i(x) for x in row[:7])
    hints = None if row[7] is None else round(float(row[7]), 2)
    med = (await _percentiles(s, select(CP.active_seconds.label("v")).select_from(CP).join(Player, Player.id == CP.player_id)
                              .where(*base, CP.solved.is_(True), CP.active_seconds > 0))).get(0, [None])[0]
    since = f.now - timedelta(days=QUALITY_DAYS)
    per = (await s.execute(select(
        CP.case_id, func.count(), func.sum(case((CP.solved.is_(True), 1), else_=0)),
        func.sum(case((CP.failed.is_(True), 1), else_=0)))
        .select_from(CP).join(Player, Player.id == CP.player_id).where(CP.opened_at >= since, _valid_player())
        .group_by(CP.case_id).order_by(func.count().desc(), CP.case_id).limit(CASE_ROWS))).all()
    meds = await _percentiles(s, select(CP.active_seconds.label("v"), CP.case_id.label("g")).select_from(CP).join(Player, Player.id == CP.player_id)
                              .where(CP.opened_at >= since, _valid_player(), CP.solved.is_(True), CP.active_seconds > 0),
                              group=True)
    cases = []
    for cid, n, sol, fai in per:
        m = meds.get(cid, [None])[0]
        cases.append({"case": cid, "title": _title(cid), "opened": _i(n), "solved": _i(sol), "failed": _i(fai),
                      "solved_pct": _pct(_i(sol), _i(n)), "failed_pct": _pct(_i(fai), _i(n)),
                      "median_active_seconds": None if m is None else round(m)})
    return {"opened": opened, "finished": fin, "solved": solved, "failed": failed,
            "failed_pct": _pct(failed, fin), "plaques": {"3": p3, "2": p2, "1": p1,
                                                         "3_pct": _pct(p3, solved), "2_pct": _pct(p2, solved), "1_pct": _pct(p1, solved)},
            "median_active_seconds": None if med is None else round(med), "avg_hints": hints,
            "cases_days": QUALITY_DAYS, "cases": cases}


SECTIONS: dict[str, Callable[[AsyncSession, Frame], Awaitable[dict]]] = {
    "signups": _signups, "funnel": _funnel, "retention": _retention, "drop_off": _drop_off,
    "money": _money, "quality": _quality}


async def build(session: AsyncSession, days: int = 30, now: datetime | None = None) -> dict:
    """The whole screen. A failing section becomes {"error": "section_failed"} (logged without data); the rest is intact."""
    now = now or datetime.now(timezone.utc).replace(tzinfo=None)
    f = Frame(now, days)
    out: dict[str, Any] = {"days": f.days, "generated_at": int(now.replace(tzinfo=timezone.utc).timestamp()),
                           "timezone": str(content.now_local().tzinfo), "first_day": f.dates[0].isoformat(),
                           "last_day": f.dates[-1].isoformat()}
    for name, fn in SECTIONS.items():
        try:
            out[name] = await fn(session, f)
        except Exception as e:  # noqa: BLE001 - one broken query must not blank the page
            log.warning("funnel section failed name=%s error=%s", name, type(e).__name__)
            try:
                await session.rollback()  # Postgres: a failed statement poisons the transaction
            except Exception:  # noqa: BLE001
                pass
            out[name] = dict(ERR)
    out["text"] = summary_text(out)
    return out


# ------------------------------------------------------------------ the text for «کپی به‌صورت متن»

def _p(v) -> str:
    return "—" if v is None else f"{v}%"


def summary_text(d: dict) -> str:
    L = [f"قیف و ماندگاری ({d['first_day']} تا {d['last_day']}، {d['days']} روز، منطقه‌ی زمانی {d['timezone']})",
         "ماندگاری از فعالیت در پرونده‌ها حساب شده؛ بازیکن‌های تست و مسدود حساب نمی‌شوند."]

    def bad(name):
        return isinstance(d.get(name), dict) and d[name].get("error")

    f = d.get("funnel", {})
    L.append("\n[قیف]" + (" خطا" if bad("funnel") else ""))
    if not bad("funnel"):
        t, pc = f["total"], f["pct"]
        L += [f"ثبت‌نام: {t['registered']}", f"پرونده باز کرد: {t['opened']} ({_p(pc['opened'])})",
              f"اولین پرونده را تمام کرد: {t['finished_first']} ({_p(pc['finished_first'])})",
              f"اولین پرونده را حل کرد: {t['solved_first']} ({_p(pc['solved_first'])})",
              f"در ۳ روز مختلف حل کرد: {t['solved_3_days']} ({_p(pc['solved_3_days'])})"]
    L.append("\n[ماندگاری]" + (" خطا" if bad("retention") else ""))
    if not bad("retention"):
        r = d["retention"]
        for n in RETENTION_DAYS:
            x = r["total"][f"d{n}"]
            L.append(f"D{n}: {_p(x['pct'])} ({x['returned']} از {x['of']}، {x['cohorts']} روز ثبت‌نام قدیمی‌ِ کافی)")
        a = r["active"]
        L.append(f"فعال ۲۴ ساعت: {a['dau']} از {a['players']} ({_p(a['dau_pct'])})؛ فعال ۷ روز: {a['wau']} ({_p(a['wau_pct'])})؛ DAU/WAU: {_p(a['dau_wau_pct'])}")
    L.append("\n[کجا ول می‌کنن]" + (" خطا" if bad("drop_off") else ""))
    if not bad("drop_off"):
        o = d["drop_off"]
        L.append(f"بازیکن‌های رفته (بیش از {o['stopped_after_hours']} ساعت بدون ورود): {o['stopped']}")
        L += [f"{x['label']}: {x['players']} ({_p(x['pct'])})" for x in o["stages"]]
        L += [f"رها شده در {c['case']} {c['title']}: {c['abandoned']}" for c in o["abandoned_cases"]]
    L.append("\n[پول]" + (" خطا" if bad("money") else ""))
    if not bad("money"):
        m = d["money"]
        h = m["first_purchase_median_hours"]
        L += [f"خریدار: {m['payers']} از {m['registered']} ({_p(m['conversion_pct'])})؛ از ماندگارهای D7: {m['d7_retained_payers']} از {m['d7_retained']} ({_p(m['d7_conversion_pct'])})",
              "میانه‌ی زمان تا اولین خرید: " + ("—" if h is None else f"{h} ساعت")]
        L += [f"بسته {p['product']}: {p['granted']} خرید موفق" + (f"، {p['coins']} سکه" if p.get("coins") else "")
              + (f"، {p['refunded']} برگشتی" if p["refunded"] else "") for p in m["packs"]]
        c = m["coins"]
        L.append(f"سکه‌ی بازیکن‌های فعال ۷ روز ({c['active_players']} کارآگاه): چارک اول {c['p25']}، میانه {c['median']}، چارک سوم {c['p75']}، بدون سکه {_p(c['zero_pct'])}")
    L.append("\n[کیفیت بازی]" + (" خطا" if bad("quality") else ""))
    if not bad("quality"):
        q = d["quality"]
        pq = q["plaques"]
        L += [f"حل‌شده: {q['solved']}، شکست: {q['failed']} ({_p(q['failed_pct'])} از تمام‌شده‌ها)",
              f"پلاک ۳/۲/۱: {_p(pq['3_pct'])} / {_p(pq['2_pct'])} / {_p(pq['1_pct'])}",
              f"میانه‌ی زمان فعال تا حل: {q['median_active_seconds']} ثانیه؛ میانگین سرنخ: {q['avg_hints']}"]
        L += [f"{c['case']} {c['title']}: باز {c['opened']}، حل {_p(c['solved_pct'])}، شکست {_p(c['failed_pct'])}، میانه {c['median_active_seconds']}ث"
              for c in q["cases"]]
    return "\n".join(L)
