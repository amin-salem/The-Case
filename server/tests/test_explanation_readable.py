"""Players never see card ids («e5») in the explanation: they are replaced by the card titles (Amin, 23 Oct 2026)."""
import re

from app import content


def test_readable_replaces_every_id_with_the_card_title():
    for c in (*content.all_cases(), *content.weekly_cases()):
        texts = [c.data["solution"]["explanation"]]
        if isinstance(c.data.get("night1"), dict):
            texts.append(c.data["night1"]["explanation"])
        for t in texts:
            out = content.readable(t, c.data)
            assert not re.search(r"\be\d+\b", out), c.id
            assert re.search(r"\be\d+\b", t) is None or "«" in out, c.id


def test_readable_example():
    data = {"evidence": [{"id": "e1", "title": "فاکتور"}, {"id": "e2", "title": "گزارش"}]}
    assert content.readable("(e1, e2) و e9", data) == "(«فاکتور», «گزارش») و یکی از مدارک"


async def test_case_detail_solution_has_no_ids(client, monkeypatch):
    """Opening a solved case again (case-detail route) sends the explanation readable, not the raw author text."""
    from datetime import timedelta
    from .conftest import new_player
    cid = "c026"
    c = content.by_id(cid)
    assert re.search(r"\be\d+\b", c.data["solution"]["explanation"])  # the raw text does cite ids
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(c) + timedelta(hours=1))
    h = (await new_player(client, "readable-1"))["headers"]
    await client.get(f"/v1/cases/{cid}", headers=h)
    r = await client.post(f"/v1/cases/{cid}/accuse", headers=h, json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})
    assert r.json()["result"] == "solved", r.text
    again = (await client.get(f"/v1/cases/{cid}", headers=h)).json()
    text = again["case"]["solution"]["explanation"]
    assert text and not re.search(r"\be\d+\b", text)
