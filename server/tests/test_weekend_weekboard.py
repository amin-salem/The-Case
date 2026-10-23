"""Live weekend stars belong on the same board and prize settlement as nightly stars."""
import copy
import hashlib
from datetime import date, datetime, timedelta
from types import SimpleNamespace
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import select

from app import content, db, gameclock, rewards, weekboard
from app.config import get_settings
from app.models import CaseProgress, InboxItem, Player
from app.routers import cases as case_router

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def board_cases(monkeypatch, request):
    """Real case formats with isolated ids/dates; no production data or synthetic board filter."""
    suffix = hashlib.sha256(request.node.nodeid.encode()).hexdigest()[:8]
    ws = date(2030, 1, 4)  # Friday; its weekend opens Thursday 10 January at 09:00.

    def clone(base, cid, publish):
        data = copy.deepcopy(base.data)
        data.update(id=cid, publish=publish.isoformat())
        return content.Case(id=cid, number=base.number, publish=publish, data=data)

    nightly = clone(content.all_cases()[0], "cn" + suffix, ws + timedelta(days=5))
    base = next(c for c in content.weekly_cases() if c.data.get("format") == 2)
    weekend = clone(base, "wn" + suffix, ws + timedelta(days=6))
    weekend.data.update(open_hour=9, closes_hours=36)
    old = clone(base, "wo" + suffix, ws - timedelta(days=1))
    old.data.update(open_hour=9, closes_hours=36)
    monkeypatch.setattr(content, "all_cases", lambda: (nightly,))
    monkeypatch.setattr(content, "weekly_cases", lambda: (old, weekend))
    now = [datetime(2030, 1, 10, 20, tzinfo=TEHRAN)]
    monkeypatch.setattr(gameclock, "_clock", lambda: now[0])
    monkeypatch.setattr(case_router, "utcnow", lambda: gameclock.to_utc_naive(now[0]))
    # Keep a warmed board fresh for the whole test: a passing assertion cannot depend on its TTL expiring.
    monkeypatch.setattr(weekboard._boards, "clock", lambda: 100.0)
    return SimpleNamespace(ws=ws, nightly=nightly, weekend=weekend, old=old,
                           set_now=lambda value: now.__setitem__(0, value))


async def solve_case(client, player, case):
    opened = await client.get(f"/v1/cases/{case.id}", headers=player["headers"])
    assert opened.status_code == 200, opened.text
    body = {"suspect": case.culprit, "evidence": sorted(case.proof)[0]}
    if content.is_weekly(case.id):
        body["motive"] = case.data["solution"]["motive"]
    response = await client.post(f"/v1/cases/{case.id}/accuse", headers=player["headers"], json=body)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["result"] == "solved" and result["ranked"] and result["stars"] == 3
    return body


async def board(client, player):
    response = await client.get("/v1/leaderboard?period=weekly", headers=player["headers"])
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize("mode", ["points", "consistency"])
@pytest.mark.parametrize("leagues", [False, True])
async def test_weekend_solve_refreshes_warmed_board_without_double_counting(client, monkeypatch, board_cases, mode, leagues):
    monkeypatch.setattr(get_settings(), "week_rank_mode", mode)
    monkeypatch.setattr(weekboard, "leagues_on", lambda: leagues)
    p = await new_player(client, f"weekend-board-{mode}-{leagues}")
    await solve_case(client, p, board_cases.nightly)
    before = await board(client, p)  # cache contains this player with only the nightly case's 3 stars
    assert before["me"]["stars"] == 3

    body = await solve_case(client, p, board_cases.weekend)
    after = await board(client, p)
    assert after["me"]["stars"] == 6
    own = next(row for row in after["top"] if row["me"])
    assert own["stars"] == own["value"] == after["me"]["value"] == 6
    async with db.SessionLocal() as session:
        progress = await session.scalar(select(CaseProgress).where(
            CaseProgress.player_id == p["player_id"], CaseProgress.case_id == board_cases.weekend.id))
        assert progress.ranked and not progress.was_daily  # weekend inclusion must not depend on the nightly flag

    repeated = await client.post(f"/v1/cases/{board_cases.weekend.id}/accuse", headers=p["headers"], json=body)
    assert repeated.status_code == 409
    assert (await board(client, p))["me"]["stars"] == 6
    async with db.SessionLocal() as session:
        assert (await session.get(Player, p["player_id"])).stars_total == 6


async def test_weekend_counts_for_weekly_prize_minimum_and_message(client, monkeypatch, board_cases):
    monkeypatch.setattr(weekboard, "leagues_on", lambda: False)
    p = await new_player(client, "weekend-prize-combined")
    await solve_case(client, p, board_cases.nightly)
    await solve_case(client, p, board_cases.weekend)
    async with db.SessionLocal() as session:
        rows = await weekboard.standings(session, board_cases.ws)
        own = next(row for row in rows if row.player.id == p["player_id"])
        assert own.points == 6 and own.cases == 2
        assert await rewards.settle_week(session, board_cases.ws) == 1
        assert await rewards.settle_week(session, board_cases.ws) == 0
        prize = await session.scalar(select(InboxItem).where(
            InboxItem.player_id == p["player_id"], InboxItem.source == rewards.source_for(board_cases.ws)))
        assert "6 پلاک" in prize.message
        assert prize.grants == [{"type": "coins", "amount": weekboard.prize_for(1, False)}]


async def test_old_weekend_unranked_and_close_boundary_do_not_add_weekly_stars(client, monkeypatch, board_cases):
    monkeypatch.setattr(weekboard, "leagues_on", lambda: False)
    close = gameclock.to_utc_naive(gameclock.week_end(board_cases.ws))
    players = [await new_player(client, f"weekend-boundary-{i}") for i in range(4)]
    async with db.SessionLocal() as session:
        for player, case, ranked, finished in (
            (players[0], board_cases.weekend, True, close - timedelta(microseconds=1)),
            (players[1], board_cases.weekend, True, close),
            (players[2], board_cases.weekend, False, close - timedelta(minutes=1)),
            (players[3], board_cases.old, True, close - timedelta(minutes=1)),
        ):
            session.add(CaseProgress(player_id=player["player_id"], case_id=case.id, solved=True, ranked=ranked,
                                     stars=3, seconds=100, finished_at=finished, was_daily=False))
        await session.commit()
        rows = await weekboard.standings(session, board_cases.ws)
        assert [(row.player.id, row.points) for row in rows] == [(players[0]["player_id"], 3)]
    board_cases.set_now(gameclock.week_end(board_cases.ws))
    assert (await board(client, players[0]))["me"] is None  # the next week starts empty, no carry-over


def test_real_weekend_cases_are_in_their_publication_week():
    for weekend in content.weekly_cases():
        ws = content.case_week(weekend)
        assert weekend.id in {case.id for case in content.week_cases(ws)}
        assert weekend.id not in {case.id for case in content.week_cases(ws + timedelta(days=7))}
