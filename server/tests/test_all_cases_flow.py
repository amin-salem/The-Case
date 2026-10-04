"""Plays every one of the 50 cases through the real API, as a player would."""
import pytest

from app import content, economy

from .conftest import new_player


@pytest.fixture
def all_open(monkeypatch):
    """Pretend it's the evening after the last case, so all 50 are open, and let the archive be free."""
    from datetime import datetime
    from zoneinfo import ZoneInfo

    last = content.all_cases()[-1]
    later = datetime(last.publish.year, last.publish.month, last.publish.day, 23, 0, tzinfo=ZoneInfo("Asia/Tehran"))
    monkeypatch.setattr(content, "now_local", lambda: later)
    monkeypatch.setattr(economy, "UNLOCK_COST", 0)
    return later


async def test_every_case_can_be_solved_and_only_by_the_right_proof(client, all_open):
    p = await new_player(client, "marathon-runner")
    h = p["headers"]
    lst = (await client.get("/v1/cases", headers=h)).json()
    assert 1 + len(lst["archive"]) == 50
    for c in content.all_cases():
        opened = (await client.post(f"/v1/cases/{c.id}/unlock", headers=h)) if c.id != lst["today"]["id"] else None
        if opened is not None:
            assert opened.status_code == 200, c.id
        got = await client.get(f"/v1/cases/{c.id}", headers=h)
        assert got.status_code == 200, c.id
        case = got.json()["case"]
        assert "solution" not in case and "hints" not in case
        assert {s["id"] for s in case["suspects"]} == {s["id"] for s in c.data["suspects"]}
        # an innocent person is always rejected
        innocent = next(s["id"] for s in c.data["suspects"] if s["id"] != c.culprit)
        r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": innocent, "evidence": sorted(c.proof)[0]})).json()
        assert r["result"] == "wrong_suspect", c.id
        # the right person with evidence that doesn't prove the lie is rejected too
        non_proof = [e["id"] for e in c.data["evidence"] if e["id"] not in c.proof]
        r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": c.culprit, "evidence": non_proof[0]})).json()
        assert r["result"] == "wrong_proof", c.id
        # every piece of proof solves it on a fresh account
        for k, ev in enumerate(sorted(c.proof)):
            q = await new_player(client, f"solver-{c.id}-{k}")
            await client.post(f"/v1/cases/{c.id}/unlock", headers=q["headers"])
            await client.get(f"/v1/cases/{c.id}", headers=q["headers"])
            r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=q["headers"], json={"suspect": c.culprit, "evidence": ev})).json()
            assert r["result"] == "solved" and r["culprit"] == c.culprit, f"{c.id} {ev}"
            assert r["explanation"]
