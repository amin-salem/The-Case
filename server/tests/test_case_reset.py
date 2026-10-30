"""Admin «ریست پرونده»: one case back to «not played» for one player; no refund, no second reward."""
from sqlalchemy import select

from app import content, db
from app.models import AdminLog, CaseComment, CaseGuess, CaseProgress, CaseToolUse, CoinLog, Player
from .conftest import ADMIN, new_player
from .test_anticheat import accuse, fail_case
from .test_difficulty_economy import balance, changed, fund
from datetime import timedelta


async def setup(client, monkeypatch, name):
    c = changed(content.by_id("c020"), 2)
    tomorrow = content.by_id("c021")
    monkeypatch.setattr(content, "all_cases", lambda: (c, tomorrow))
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(tomorrow) + timedelta(hours=1))
    p = await new_player(client, name, aged=True)
    await fund(p["player_id"])
    cost = (await client.get("/v1/cases", headers=p["headers"])).json()["archive"]
    row = next(r for r in cost if r["id"] == c.id)
    assert (await client.post(f"/v1/cases/{c.id}/unlock", headers=p["headers"],
                              json={"expected_cost": row["unlock_cost"]})).status_code == 200
    return c, p


async def reset(client, pid, case_id, **kw):
    return await client.post(f"/admin/api/players/{pid}/case-reset", headers=ADMIN, json={"case_id": case_id, **kw})


async def test_reset_needs_admin_key_and_confirm(client, monkeypatch):
    c, p = await setup(client, monkeypatch, "reset-auth")
    pid = p["player_id"]
    assert (await client.post(f"/admin/api/players/{pid}/case-reset", json={"case_id": c.id, "confirm": True})).status_code == 403
    assert (await reset(client, pid, c.id)).status_code == 422  # no confirm
    assert (await reset(client, pid, "c999", confirm=True)).status_code == 404
    assert (await reset(client, "nope", c.id, confirm=True)).status_code == 404
    assert (await reset(client, pid, c.id, confirm=True)).json()["detail"] == "nothing_to_reset"  # opened, never played


async def test_reset_a_solved_case_then_solve_again_pays_nothing(client, monkeypatch):
    c, p = await setup(client, monkeypatch, "reset-solve")
    h, pid = p["headers"], p["player_id"]
    async with db.SessionLocal() as s:
        s.add_all([CaseToolUse(player_id=pid, case_id=c.id, kind="lens", source="free", result={}),
                   CaseGuess(player_id=pid, case_id=c.id, suspect=c.culprit),
                   CaseComment(player_id=pid, case_id=c.id, rating=5, body="خوب بود", status="approved")])
        await s.commit()
    won = await accuse(client, h, c, c.culprit)
    assert won["result"] == "solved"
    paid = await balance(pid)
    async with db.SessionLocal() as s:
        before = await s.get(Player, pid)
        solved_n, stars_n = before.cases_solved, before.stars_total
    pv = (await client.get(f"/admin/api/players/{pid}/case-reset?case_id={c.id}", headers=ADMIN)).json()
    assert pv["solved"] and pv["tools"] == 1 and pv["guesses"] == 1 and pv["comments"] == 1
    r = await reset(client, pid, c.id, confirm=True)
    assert r.status_code == 200 and r.json()["was_solved"] is True
    assert await balance(pid) == paid  # no refund
    async with db.SessionLocal() as s:
        pr = await s.scalar(select(CaseProgress).where(CaseProgress.player_id == pid, CaseProgress.case_id == c.id))
        assert not pr.solved and not pr.failed and pr.stars == 0 and pr.attempts == 0 and pr.unlocked
        pl = await s.get(Player, pid)
        assert pl.cases_solved == solved_n - 1 and pl.stars_total == stars_n - won["stars"]
        for m in (CaseToolUse, CaseGuess, CaseComment):
            assert (await s.scalars(select(m).where(m.player_id == pid, m.case_id == c.id))).all() == []
        log = await s.scalar(select(AdminLog).where(AdminLog.action == "case_reset"))
        assert log.target == pid and log.detail["case"] == c.id
    # open again without paying, solve again: solved, but nothing is paid or counted twice
    assert (await client.get(f"/v1/cases/{c.id}", headers=h)).status_code == 200
    again = await accuse(client, h, c, c.culprit)
    assert again["result"] == "solved" and again["reward"] == 0
    assert await balance(pid) == paid
    async with db.SessionLocal() as s:
        pl = await s.get(Player, pid)
        assert pl.cases_solved == solved_n and pl.stars_total == stars_n - won["stars"] + again["stars"]
        solves = (await s.scalars(select(CoinLog).where(CoinLog.player_id == pid, CoinLog.reason == f"solve:{c.id}"))).all()
        assert len(solves) == 1


async def test_reset_a_lost_case_reopens_it_for_free(client, monkeypatch):
    c, p = await setup(client, monkeypatch, "reset-lost")
    h, pid = p["headers"], p["player_id"]
    await fail_case(client, h, c)
    assert (await client.get(f"/v1/cases/{c.id}", headers=h)).status_code == 402  # closed, paid reopen
    money = await balance(pid)
    assert (await reset(client, pid, c.id, confirm=True)).json()["was_solved"] is False
    assert (await client.get(f"/v1/cases/{c.id}", headers=h)).status_code == 200
    assert await balance(pid) == money


async def test_reset_touches_only_that_case_and_player(client, monkeypatch):
    c, p = await setup(client, monkeypatch, "reset-scope")
    other = await new_player(client, "reset-other", aged=True)
    await fund(other["player_id"])
    row = next(r for r in (await client.get("/v1/cases", headers=other["headers"])).json()["archive"] if r["id"] == c.id)
    await client.post(f"/v1/cases/{c.id}/unlock", headers=other["headers"], json={"expected_cost": row["unlock_cost"]})
    await accuse(client, p["headers"], c, c.culprit)
    await accuse(client, other["headers"], c, c.culprit)
    await reset(client, p["player_id"], c.id, confirm=True)
    async with db.SessionLocal() as s:
        mine = await s.scalar(select(CaseProgress).where(CaseProgress.player_id == other["player_id"], CaseProgress.case_id == c.id))
        assert mine.solved  # the other player is untouched
