"""Anti-cheat: delayed answers, proof of investigation, throwaway accounts, per-player shuffle, cheat report."""
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import httpx
import pytest
from sqlalchemy import func, select, update

from app import anticheat as ac
from app import content, db, gameclock
from app import economy as eco
from app.config import get_settings
from app.main import app
from app.models import AdminLog, CaseProgress, InboxItem, Player, ReferralPayout, utcnow
from app.models import RateHit
from app.services.ratelimit import MemoryStore, body_for, limiter
from app.services import ratelimit as rl

from .conftest import ADMIN, new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


@pytest.fixture
def strict_rules(monkeypatch):
    """The real proof-of-investigation numbers (the other tests switch them off)."""
    monkeypatch.setattr(eco, "MIN_ACTIVE_SECONDS", 90)
    monkeypatch.setattr(eco, "MIN_SUSPECTS_SEEN", 2)


def night(case_id: str, hours: int = 1) -> datetime:
    return content.opens_at(content.by_id(case_id)) + timedelta(hours=hours)


async def accuse(client, h, c, suspect, evidence=None, **extra):
    r = await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                          json={"suspect": suspect, "evidence": evidence or sorted(c.proof)[0], **extra})
    assert r.status_code == 200, r.text
    return r.json()


def innocent_of(c):
    return next(s["id"] for s in c.data["suspects"] if s["id"] != c.culprit)


async def fail_case(client, h, c, **extra):
    r = None
    for _ in range(eco.MAX_ATTEMPTS):
        r = await accuse(client, h, c, innocent_of(c), **extra)
    assert r["result"] == "failed"
    return r


async def set_progress(pid, case_id, **vals):
    async with db.SessionLocal() as s:
        await s.execute(update(CaseProgress).where(CaseProgress.player_id == pid, CaseProgress.case_id == case_id)
                        .values(**vals))
        await s.commit()


# ---------------------------------------------------------------- 1. delayed answer
async def test_lost_nightly_case_hides_the_answer_until_the_next_case(client, clock):
    c = content.by_id("c045")
    clock(night("c045"))
    opens_next = int(content.next_case_at().timestamp())
    p = await new_player(client, "delay-1")
    h = p["headers"]
    await client.get(f"/v1/cases/{c.id}", headers=h)
    r = await fail_case(client, h, c)
    assert r["culprit"] is None and r["explanation"] is None and r["proof"] == [] and r["answer_at"] == opens_next
    got = (await client.get(f"/v1/cases/{c.id}", headers=h)).json()
    assert "solution" not in got["case"] and got["progress"]["failed"] and got["progress"]["answer_at"] == opens_next
    st = (await client.get(f"/v1/cases/{c.id}/stats", headers=h)).json()
    assert st["culprit"] == ""  # the stats screen must not give it away either
    blob = (await client.get(f"/v1/cases/{c.id}", headers=h)).text + (await client.get("/v1/cases", headers=h)).text
    assert c.data["solution"]["explanation"] not in blob
    # the next case opens: the answer is public
    clock(datetime.fromtimestamp(opens_next + 60, TEHRAN))
    got = (await client.get(f"/v1/cases/{c.id}", headers=h)).json()
    assert got["case"]["solution"]["culprit"] == c.culprit and got["progress"]["answer_at"] is None
    st = (await client.get(f"/v1/cases/{c.id}/stats", headers=h)).json()
    assert st["culprit"] == c.culprit


async def test_solvers_see_the_explanation_at_once(client, clock):
    c = content.by_id("c046")
    clock(night("c046"))
    p = await new_player(client, "delay-solver")
    await client.get(f"/v1/cases/{c.id}", headers=p["headers"])
    r = await accuse(client, p["headers"], c, c.culprit)
    assert r["result"] == "solved" and r["explanation"] and r["culprit"] == c.culprit and r["answer_at"] is None


async def test_archive_case_shows_the_answer_at_once(client, clock):
    old, newer = content.by_id("c046"), content.by_id("c047")
    clock(night("c047"))
    p = await new_player(client, "delay-archive")
    h = p["headers"]
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == p["player_id"]).values(coins=500))
        await s.commit()
    assert (await client.post(f"/v1/cases/{old.id}/unlock", headers=h)).status_code == 200
    r = await fail_case(client, h, old)
    assert r["culprit"] == old.culprit and r["explanation"] and r["answer_at"] is None
    assert newer.id != old.id


async def test_lost_weekend_case_waits_for_its_closing(client, clock):
    w = content.weekly_cases()[0]
    clock(content.weekly_all_open_at(w) + timedelta(hours=1))
    p = await new_player(client, "delay-weekend")
    h = p["headers"]
    await client.get(f"/v1/cases/{w.id}", headers=h)
    wrong_motive = w.data["solution"].get("motive")
    r = None
    for _ in range(eco.MAX_ATTEMPTS):
        r = await accuse(client, h, w, innocent_of(w), motive=wrong_motive)
    closes = int(content.weekly_closes_at(w).timestamp())
    assert r["result"] == "failed" and r["culprit"] is None and r["answer_at"] == closes
    assert "solution" not in (await client.get(f"/v1/cases/{w.id}", headers=h)).json()["case"]
    clock(datetime.fromtimestamp(closes + 60, TEHRAN))
    assert (await client.get(f"/v1/cases/{w.id}", headers=h)).json()["case"]["solution"]["culprit"] == w.culprit


def test_story_answer_comes_24_hours_after_the_failure():
    ch = content.Case(id="s01ch02", number=2, publish=date(2026, 10, 1), data={})
    at = datetime(2026, 10, 13, 12, 0)
    assert ac.reveal_time(ch, at) == at + timedelta(hours=24)
    pending = CaseProgress(failed=True, solved=False, reveal_at=utcnow() + timedelta(hours=5))
    assert ac.answer_pending(pending) and not ac.answer_visible(pending) and ac.answer_at_ts(pending)
    # the partner's closing lines and the season thread wait with the answer
    from app.routers.story import story_extra
    c = content.Case(id="s01ch02", number=2, publish=date(2026, 10, 1), data={
        "season": 1, "chapter": 2, "partner_intro": "hi", "partner_outro_win": "win",
        "partner_outro_lose": "he did it", "thread": "a burnt match"})
    assert "outro" not in story_extra(c, pending) and "thread" not in story_extra(c, pending)
    shown = CaseProgress(failed=True, solved=False, reveal_at=utcnow() - timedelta(minutes=1))
    assert story_extra(c, shown)["outro"] == "he did it"
    assert story_extra(c, CaseProgress(solved=True))["outro"] == "win"


# ---------------------------------------------------------------- 2. proof of investigation
async def test_solve_without_investigation_is_one_star_and_unranked(client, clock, strict_rules):
    c = content.by_id("c047")
    clock(night("c047"))
    lazy = await new_player(client, "proof-lazy")
    diligent = await new_player(client, "proof-diligent")
    for pl in (lazy, diligent):
        await client.get(f"/v1/cases/{c.id}", headers=pl["headers"])
    r = await accuse(client, lazy["headers"], c, c.culprit)
    assert r["result"] == "solved" and r["stars"] == 1 and r["unranked"] and r["stars_capped"] and r["rank"] is None
    assert r["reward"] == eco.solve_reward(c.data.get("difficulty"), 1) + eco.DAILY_BONUS
    ids = [s["id"] for s in c.data["suspects"]][:2]
    await set_progress(diligent["player_id"], c.id, active_seconds=eco.min_active_seconds(c.data["difficulty"]), seen=ids)
    r = await accuse(client, diligent["headers"], c, c.culprit)
    assert r["stars"] == 3 and not r["unranked"] and r["rank"] is not None
    assert r["reward"] == eco.solve_reward(c.data.get("difficulty"), 3) + eco.DAILY_BONUS
    lb = (await client.get("/v1/leaderboard?period=daily", headers=lazy["headers"])).json()
    assert lb["me"] is None
    lb = (await client.get("/v1/leaderboard?period=daily", headers=diligent["headers"])).json()
    assert lb["me"] is not None and lb["me"]["stars"] == 3
    wk = (await client.get("/v1/leaderboard?period=weekly", headers=lazy["headers"])).json()
    assert wk["me"] is None  # the weekly sum counts only ranked solves


async def test_time_alone_or_suspects_alone_is_not_enough(client, clock, strict_rules):
    c = content.by_id("c048")
    clock(night("c048"))
    ids = [s["id"] for s in c.data["suspects"]]
    cases = [({"active_seconds": 500, "seen": ids[:1]}, "proof-one-suspect"),
             ({"active_seconds": 30, "seen": ids[:3]}, "proof-short-time")]
    for vals, device in cases:
        p = await new_player(client, device)
        await client.get(f"/v1/cases/{c.id}", headers=p["headers"])
        await set_progress(p["player_id"], c.id, **vals)
        r = await accuse(client, p["headers"], c, c.culprit)
        assert r["result"] == "solved" and r["stars"] == 1 and r["unranked"], device


# ---------------------------------------------------------------- 3. throwaway accounts
async def test_new_unsecured_accounts_are_hidden_from_leaderboards(client, clock):
    c = content.by_id("c049")
    clock(night("c049"))
    fresh = await new_player(client, "young-1", aged=False)
    await client.get(f"/v1/cases/{c.id}", headers=fresh["headers"])
    r = await accuse(client, fresh["headers"], c, c.culprit)
    assert r["result"] == "solved" and r["rank"] is None  # still plays and is paid
    for period in ("daily", "weekly", "all"):
        lb = (await client.get(f"/v1/leaderboard?period={period}", headers=fresh["headers"])).json()
        assert lb["me"] is None, period
    # securing the account with an email shows it
    r = await client.post("/v1/auth/email", headers=fresh["headers"],
                          json={"email": "young1@example.com", "password": "secret-pass-1"})
    assert r.status_code == 200, r.text
    lb = (await client.get("/v1/leaderboard?period=daily", headers=fresh["headers"])).json()
    assert lb["me"] is not None
    # ... and so does time
    other = await new_player(client, "young-2", aged=False)
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == other["player_id"]).values(
            created_at=utcnow() - timedelta(hours=eco.HIDE_NEW_ACCOUNT_HOURS + 1)))
        await s.commit()
        pl = await s.get(Player, other["player_id"])
        assert ac.is_visible(pl)


async def test_weekly_prizes_skip_hidden_accounts(client, monkeypatch):
    from types import SimpleNamespace

    from app import gameclock, rewards, weekboard
    ws = date(2027, 6, 18)   # a Friday; fake cases, so no other test's solves are on this board
    monkeypatch.setattr(content, "week_cases", lambda w: [SimpleNamespace(id=f"za{w.isoformat()}-{i}") for i in range(7)])
    monkeypatch.setattr(weekboard, "leagues_on", lambda: False)
    monkeypatch.setattr(content, "now_local", lambda: datetime(2027, 6, 25, 22, 0, tzinfo=TEHRAN))
    young = await new_player(client, "prize-young", aged=False)
    old = await new_player(client, "prize-old")
    async with db.SessionLocal() as s:
        for pl in (young, old):
            for i in range(2):
                s.add(CaseProgress(player_id=pl["player_id"], case_id=f"za{ws.isoformat()}-{i}", solved=True, stars=3, ranked=True,
                                   seconds=60, finished_at=gameclock.to_utc_naive(datetime(2027, 6, 19 + i, 10, tzinfo=TEHRAN))))
        await s.commit()
    async with db.SessionLocal() as s:
        await rewards.settle_week(s, ws)
        got = {i.player_id for i in (await s.execute(select(InboxItem).where(
            InboxItem.source == rewards.source_for(ws)))).scalars()}
    assert old["player_id"] in got and young["player_id"] not in got


async def fake_solve_days(pid, n):
    async with db.SessionLocal() as s:
        for i in range(n):
            s.add(CaseProgress(player_id=pid, case_id=f"zr{i}-{pid[:8]}", solved=True, stars=1, day=f"2026-09-0{i + 1}"))
        await s.commit()


async def referral_items(pid):
    async with db.SessionLocal() as s:
        return int(await s.scalar(select(func.count()).select_from(InboxItem).where(
            InboxItem.player_id == pid, InboxItem.source == "referral")) or 0)


async def test_inviter_is_paid_only_after_three_solve_days(client):
    inviter = await new_player(client, "inv-main")
    me = (await client.get("/v1/me", headers=inviter["headers"])).json()
    invitee = await new_player(client, "inv-friend")
    r = await client.post("/v1/referrals/redeem", headers=invitee["headers"], json={"code": me["invite_code"]})
    assert r.status_code == 200, r.text
    assert await referral_items(inviter["player_id"]) == 0  # nothing at redeem time
    await fake_solve_days(invitee["player_id"], 2)
    assert await ac.maybe_pay_referral(invitee["player_id"]) is False
    assert await referral_items(inviter["player_id"]) == 0
    await fake_solve_days_extra(invitee["player_id"])
    assert await ac.maybe_pay_referral(invitee["player_id"]) is True
    assert await referral_items(inviter["player_id"]) == 1
    assert await ac.maybe_pay_referral(invitee["player_id"]) is False  # never twice
    assert await referral_items(inviter["player_id"]) == 1


async def fake_solve_days_extra(pid):
    async with db.SessionLocal() as s:
        s.add(CaseProgress(player_id=pid, case_id=f"zx-{pid[:8]}", solved=True, stars=1, day="2026-09-09"))
        await s.commit()


async def test_one_paid_invite_per_device_and_five_per_week(client):
    inviter = await new_player(client, "cap-main")
    code = (await client.get("/v1/me", headers=inviter["headers"])).json()["invite_code"]
    a = await new_player(client, "cap-shared-device")
    b = await new_player(client, "cap-shared-device")  # a second account on the same phone
    for pl in (a, b):
        assert (await client.post("/v1/referrals/redeem", headers=pl["headers"], json={"code": code})).status_code == 200
        await fake_solve_days(pl["player_id"], 3)
    assert await ac.maybe_pay_referral(a["player_id"]) is True
    assert await ac.maybe_pay_referral(b["player_id"]) is False  # same device
    assert await referral_items(inviter["player_id"]) == 1
    # a full week: the 6th paid invite of the same week is refused
    week = gameclock.week_of(content.now_local()).isoformat()
    async with db.SessionLocal() as s:
        for i in range(2, eco.INVITE_PAID_PER_WEEK + 1):
            s.add(ReferralPayout(inviter_id=inviter["player_id"], invitee_id=f"x{i}", device_id=f"dev-x{i}", week=week, slot=i))
        await s.commit()
    late = await new_player(client, "cap-late")
    assert (await client.post("/v1/referrals/redeem", headers=late["headers"], json={"code": code})).status_code == 200
    await fake_solve_days(late["player_id"], 3)
    assert await ac.maybe_pay_referral(late["player_id"]) is False
    assert await referral_items(inviter["player_id"]) == 1
    async with db.SessionLocal() as s:  # the refusal is final: not retried on every solve
        assert (await s.get(Player, late["player_id"])).referral_paid is True


def mk(ip):
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app, client=(ip, 5000)), base_url="http://test")


@pytest.fixture
async def rate_clock(monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit", True)

    class Clock:
        t = 1_699_999_200.0

        def __call__(self):
            return self.t
    c = Clock()
    monkeypatch.setattr(limiter, "clock", c)
    async with db.SessionLocal() as s:
        await s.execute(RateHit.__table__.delete())
        await s.commit()
    limiter.mem = MemoryStore()
    limiter.strict_override = None
    limiter.reload({})
    yield c
    limiter.strict_override = None
    limiter.reload({})


async def test_registration_limits_per_ip_and_per_device_over_a_day(rate_clock):
    async with mk("198.51.100.77") as c:
        codes = []
        for i in range(11):
            if i:
                rate_clock.t += 61  # stay under the per-minute limit
            r = await c.post("/v1/auth/register", json={"device_id": f"ip-day-{i}"})
            codes.append(r.status_code)
        assert codes[:10] == [200] * 10 and codes[10] == 429
        body = r.json()
        assert body["error"] == "rate_limited" and body["message"] == rl.REGISTER_MESSAGE and "Retry-After" in r.headers
    # one phone: 3 accounts a day, even an hour later and from other networks
    for i in range(3):
        async with mk(f"198.51.100.{i + 1}") as c:
            assert (await c.post("/v1/auth/register", json={"device_id": "one-phone-1"})).status_code == 200
    rate_clock.t += 3600
    async with mk("198.51.100.99") as c:
        r = await c.post("/v1/auth/register", json={"device_id": "one-phone-1"})
        assert r.status_code == 429 and r.json()["message"] == rl.REGISTER_MESSAGE
    assert body_for(429, 5)["message"] == rl.MESSAGE


# ---------------------------------------------------------------- 4. shuffle
async def test_suspects_and_evidence_are_shuffled_per_player(client, clock):
    c = content.by_id("c045")
    clock(night("c045"))
    orders, ev_orders = set(), set()
    for i in range(6):
        p = await new_player(client, f"shuffle-{i}")
        case = (await client.get(f"/v1/cases/{c.id}", headers=p["headers"])).json()["case"]
        again = (await client.get(f"/v1/cases/{c.id}", headers=p["headers"])).json()["case"]
        assert [s["id"] for s in case["suspects"]] == [s["id"] for s in again["suspects"]]  # stable per player
        assert {s["id"] for s in case["suspects"]} == {s["id"] for s in c.data["suspects"]}
        assert {e["id"] for e in case["evidence"]} == {e["id"] for e in c.data["evidence"]}
        assert case["suspects"][0].keys() == c.data["suspects"][0].keys()
        orders.add(tuple(s["id"] for s in case["suspects"]))
        ev_orders.add(tuple(e["id"] for e in case["evidence"]))
    assert len(orders) >= 2 and len(ev_orders) >= 2


def test_shuffle_is_independent_of_the_other_items():
    full = [{"id": f"e{i}"} for i in range(12)]
    order = [x["id"] for x in ac.shuffled(full, "player:case")]
    subset = [x for x in full if x["id"] not in {"e3", "e7", "e9"}]
    assert [x["id"] for x in ac.shuffled(subset, "player:case")] == [i for i in order if i in {x["id"] for x in subset}]
    assert order != [x["id"] for x in full] or order != [x["id"] for x in ac.shuffled(full, "other:case")]


# ---------------------------------------------------------------- 5/6. scripts and the cheat report
async def test_cheat_report_lists_devices_fast_solves_and_bursts(client, clock):
    c = content.by_id("c050")
    clock(night("c050"))
    for i in range(3):
        await new_player(client, "report-farm-device")
    suspect = innocent_of(c)
    ids = []
    for i in range(4):
        p = await new_player(client, f"report-burst-{i}", aged=False)
        ids.append(p["player_id"])
        await client.get(f"/v1/cases/{c.id}", headers=p["headers"])
        await accuse(client, p["headers"], c, suspect)
    lazy = await new_player(client, "report-fast")
    await client.get(f"/v1/cases/{c.id}", headers=lazy["headers"])
    await accuse(client, lazy["headers"], c, c.culprit)
    assert (await client.get("/admin/cheat-report")).status_code == 403
    rep = (await client.get("/admin/cheat-report", headers=ADMIN)).json()
    assert any(d["device"] == "report-far" and d["accounts"] >= 3 for d in rep["devices"])
    assert any(f["player_id"] == lazy["player_id"] and f["active_seconds"] < 60 for f in rep["fast_solves"])
    burst = next(b for b in rep["same_answer_bursts"] if b["case"] == c.id and b["suspect"] == suspect)
    assert burst["accounts"] >= 4 and set(ids) <= set(burst["player_ids"])
    assert "summary" in rep
    # the admin can ban from the same panel
    r = await client.post(f"/admin/players/{ids[0]}/ban", headers=ADMIN, json={"banned": True})
    assert r.status_code == 200 and r.json()["banned"] is True
    # the weekly summary is written once
    assert (await client.post("/admin/cheat-report/weekly", headers=ADMIN)).json() == {"stored": True}
    assert (await client.post("/admin/cheat-report/weekly", headers=ADMIN)).json() == {"stored": False}
    async with db.SessionLocal() as s:
        assert await s.scalar(select(func.count()).select_from(AdminLog).where(AdminLog.action == "cheat_report")) == 1


def test_start_coins_are_modest():
    assert eco.START_COINS <= 100


async def test_hasty_accusation_does_not_reveal_the_culprit(client, clock, strict_rules):
    c = content.by_id("c049")
    clock(night("c049"))
    bad_ev = next(e["id"] for e in c.data["evidence"] if e["id"] not in c.proof)
    ids = [s["id"] for s in c.data["suspects"]][:2]
    hasty = await new_player(client, "nudge-hasty")
    careful = await new_player(client, "nudge-careful")
    for pl in (hasty, careful):
        await client.get(f"/v1/cases/{c.id}", headers=pl["headers"])
    await set_progress(careful["player_id"], c.id, active_seconds=eco.min_active_seconds(c.data["difficulty"]), seen=ids)
    # right person, wrong proof: the hasty one gets the same answer as for an innocent person and loses a try
    r = await accuse(client, hasty["headers"], c, c.culprit, bad_ev)
    assert r["result"] == "inconclusive" and r["attempts_left"] == eco.MAX_ATTEMPTS - 1
    assert r["progress"]["wrong_tries"][-1]["r"] == "inconclusive"
    # a player who investigated gets the usual nudge, free of tries
    r = await accuse(client, careful["headers"], c, c.culprit, bad_ev)
    assert r["result"] == "wrong_proof" and r["attempts_left"] == eco.MAX_ATTEMPTS


def test_needed_active_time_follows_the_difficulty(strict_rules):
    """90 s for a medium case; easier cases ask for less, harder ones for more (60/75/90/110/130)."""
    assert [eco.min_active_seconds(d) for d in (1, 2, 3, 4, 5)] == [60, 75, 90, 110, 130]
    assert eco.min_active_seconds(None) == 90 and eco.min_active_seconds(9) == 90


async def test_a_fast_reader_of_an_easy_case_gets_the_stars_but_a_hard_one_needs_more(client, clock, strict_rules, monkeypatch):
    c = content.by_id("c047")
    ids = [s["id"] for s in c.data["suspects"]][:2]
    clock(night("c047"))
    results = {}
    for diff, active in ((2, 80), (5, 80)):  # 80 s: enough for difficulty 2 (75 s), not for 5 (130 s)
        monkeypatch.setitem(c.data, "difficulty", diff)
        pl = await new_player(client, f"proof-diff-{diff}")
        await client.get(f"/v1/cases/{c.id}", headers=pl["headers"])
        await set_progress(pl["player_id"], c.id, active_seconds=active, seen=ids)
        results[diff] = await accuse(client, pl["headers"], c, c.culprit)
    assert results[2]["stars"] == 3 and not results[2]["unranked"]
    assert results[5]["stars"] == 1 and results[5]["unranked"]



async def test_early_refusals_have_no_culprit_oracle_and_can_be_corrected(client, clock, strict_rules):
    c = content.by_id("c049")
    clock(night(c.id))
    bad = next(e["id"] for e in c.data["evidence"] if e["id"] not in c.proof)
    histories = []
    for i, suspect in enumerate((c.culprit, innocent_of(c))):
        pl = await new_player(client, f"inconclusive-{i}")
        await client.get(f"/v1/cases/{c.id}", headers=pl["headers"])
        result = await accuse(client, pl["headers"], c, suspect, bad)
        assert result["result"] == "inconclusive"
        assert result["culprit"] is None and result["proof"] == [] and result["explanation"] is None
        assert result["attempts_left"] == eco.MAX_ATTEMPTS - 1
        note = result["progress"]["wrong_tries"][-1]
        assert note == {"s": suspect, "e": bad, "m": None, "r": "inconclusive"}
        reopened = (await client.get(f"/v1/cases/{c.id}", headers=pl["headers"])).json()
        assert reopened["progress"]["wrong_tries"] == [note] and "solution" not in reopened["case"]
        histories.append({**note, "s": "submitted-suspect"})
        if suspect == c.culprit:
            await set_progress(pl["player_id"], c.id, active_seconds=eco.min_active_seconds(c.data["difficulty"]),
                               seen=[s["id"] for s in c.data["suspects"]][:2])
            solved = await accuse(client, pl["headers"], c, c.culprit)
            assert solved["result"] == "solved" and solved["stars"] == 2
    assert histories[0] == histories[1]


async def test_legacy_hasty_and_wrong_suspect_histories_do_not_reveal_culprit(client, clock, strict_rules):
    c = content.by_id("c049")
    clock(night(c.id))
    pl = await new_player(client, "legacy-refusals")
    await client.get(f"/v1/cases/{c.id}", headers=pl["headers"])
    await set_progress(pl["player_id"], c.id, wrong_tries=[
        {"s": c.culprit, "e": "e1", "m": None, "r": "hasty"},
        {"s": innocent_of(c), "e": "e1", "m": None, "r": "wrong_suspect"},
    ])
    p = (await client.get(f"/v1/cases/{c.id}", headers=pl["headers"])).json()["progress"]
    assert [t["r"] for t in p["wrong_tries"]] == ["inconclusive", "inconclusive"]
    assert all(set(t) == {"s", "e", "m", "r"} for t in p["wrong_tries"])


async def test_inconclusive_refusals_keep_the_same_attempt_limit(client, clock, strict_rules):
    c = content.by_id("c049")
    clock(night(c.id))
    pl = await new_player(client, "inconclusive-limit")
    await client.get(f"/v1/cases/{c.id}", headers=pl["headers"])
    result = await fail_case(client, pl["headers"], c)
    assert result["attempts_left"] == 0 and result["progress"]["failed"]
    assert {t["r"] for t in result["progress"]["wrong_tries"]} == {"inconclusive"}
    assert result["culprit"] is None
