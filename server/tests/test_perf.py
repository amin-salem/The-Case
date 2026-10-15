"""CPU work per request (docs/operations.md «Capacity»): the faster code must give the same answers as the old code."""
from datetime import datetime, time, timedelta, timezone

import httpx
from fastapi import FastAPI
from zoneinfo import ZoneInfo

from app import cache, content, db, feed
from app.config import get_settings
from app.models import Player
from app.routers import cases as cases_router
from app.routers.common import fast_json
from app.schemas import CaseOut, CasesOut, FeedOut
from app.services import ratelimit

from .conftest import new_player


# --------------------------------------------------------------------------- opening moments
def test_opens_at_equals_the_plain_computation_and_follows_the_settings(monkeypatch):
    s = get_settings()
    for c in (*content.all_cases(), *content.weekly_cases()):
        hour = c.data.get("open_hour")
        hour = hour if isinstance(hour, int) and 0 <= hour <= 23 else s.new_case_hour
        assert content.opens_at(c) == datetime.combine(c.publish, time(hour), tzinfo=ZoneInfo(s.timezone))
    c = content.all_cases()[0]
    before = content.opens_at(c)
    monkeypatch.setattr(s, "new_case_hour", (s.new_case_hour + 1) % 24)  # a changed setting is not served from the memo
    assert content.opens_at(c).hour == s.new_case_hour and content.opens_at(c) != before


def test_opened_and_todays_case_by_the_clock():
    cases = content.all_cases()
    c = cases[5]
    t = content.opens_at(c)
    assert content.todays_case(t - timedelta(seconds=1)) == cases[4]
    assert content.todays_case(t) == c and cases[5] in content.opened(t) and cases[6] not in content.opened(t)


# --------------------------------------------------------------------------- identical JSON
async def _old_style_body(model):
    """What FastAPI sends for a route with response_model that returns the model (the code before this change)."""
    app = FastAPI()
    cls = type(model)

    @app.get("/x", response_model=cls)
    async def x():
        return model

    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
        return (await c.get("/x")).content


async def test_fast_json_is_byte_identical_to_the_response_model_path(client):
    p = await new_player(client, "perf-json")
    h = p["headers"]
    lst = (await client.get("/v1/cases", headers=h))
    assert lst.status_code == 200
    m = CasesOut.model_validate(lst.json())
    assert fast_json(m).body == await _old_style_body(m) == lst.content
    today = content.todays_case()
    one = await client.get(f"/v1/cases/{today.id}", headers=h)
    assert one.status_code == 200
    m = CaseOut.model_validate(one.json())
    assert fast_json(m).body == await _old_style_body(m) == one.content
    f = await client.get("/v1/feed", headers=h)
    m = FeedOut.model_validate(f.json())
    assert fast_json(m).body == await _old_style_body(m) == f.content
    assert "solution" not in one.json()["case"] and "hints" not in one.json()["case"]


async def test_case_list_flags_are_per_player_and_unchanged(client):
    a = await new_player(client, "perf-list-a")
    b = await new_player(client, "perf-list-b")
    today = content.todays_case()
    ra = (await client.get("/v1/cases", headers=a["headers"])).json()
    assert ra["today"]["id"] == today.id and ra["today"]["locked"] is False and ra["today"]["today"] is True
    assert ra["archive"] and all(r["locked"] and not r["today"] for r in ra["archive"] if not r["weekend"])
    assert (await client.get(f"/v1/cases/{today.id}", headers=a["headers"])).status_code == 200
    rb = (await client.get("/v1/cases", headers=b["headers"])).json()
    assert rb["today"]["stars"] == 0 and rb["today"]["solved"] is False
    # an archive case bought by A is open for A only
    old = ra["archive"][0]
    async with db.SessionLocal() as s:
        from sqlalchemy import update
        await s.execute(update(Player).where(Player.id == a["player_id"]).values(coins=1000))
        await s.commit()
    if not old["weekend"]:
        assert (await client.post(f"/v1/cases/{old['id']}/unlock", headers=a["headers"])).status_code == 200
        ra2 = (await client.get("/v1/cases", headers=a["headers"])).json()
        rb2 = (await client.get("/v1/cases", headers=b["headers"])).json()
        assert next(r for r in ra2["archive"] if r["id"] == old["id"])["locked"] is False
        assert next(r for r in rb2["archive"] if r["id"] == old["id"])["locked"] is True


def test_is_today_with_and_without_the_given_case():
    today = content.todays_case()
    for c in content.all_cases():
        assert cases_router._is_today(c) == cases_router._is_today(c, today) == (c.id == today.id)
    assert cases_router._is_today(today, None) is False


async def test_unopened_case_is_still_404(client):
    p = await new_player(client, "perf-404")
    future = content.all_cases()[-1]
    if content.opens_at(future) > content.now_local():
        assert (await client.get(f"/v1/cases/{future.id}", headers=p["headers"])).status_code == 404
    assert (await client.get("/v1/cases/nope", headers=p["headers"])).status_code == 404


# --------------------------------------------------------------------------- the feed's shared part
async def _old_openings(player, now):
    """The case / weekend part of the feed the way it was built before the shared list."""
    since = now - timedelta(days=feed.WINDOW_DAYS)
    born = player.created_at or since
    local_now = now.replace(tzinfo=timezone.utc).astimezone(content._tz())
    out = {}

    def add(id_, at):
        if not (at > now or at < since):
            out[id_] = int(at.replace(tzinfo=timezone.utc).timestamp())

    for c in content.opened(local_now):
        at = feed._utc(content.opens_at(c))
        if at >= born:
            add(f"c{c.id}", at)
    for c in content.weekly_cases():
        start = content.opens_at(c)
        for n, ch in enumerate(c.data.get("chapters") or [], start=1):
            at = feed._utc(start + timedelta(hours=ch.get("at_hours", 0)))
            if at >= born:
                add(f"w{c.id}{n}", at)
    return out


async def test_feed_openings_equal_the_old_ones_for_every_clock_and_player():
    cases = content.all_cases()
    now0 = feed._utc(content.opens_at(cases[10])) + timedelta(minutes=1)
    cache.clear_all()
    async with db.SessionLocal() as s:
        p = Player(device_id="perf-feed-old", secret_hash="x", nickname="t", invite_code="PERFF1")
        s.add(p)
        await s.commit()
        for born_days in (200, 3, 0):
            p.created_at = now0 - timedelta(days=born_days)
            for step in (timedelta(0), timedelta(hours=-5), timedelta(days=3), timedelta(days=-30), timedelta(hours=40)):
                now = now0 + step  # same worker cache serves all of them
                rows = await feed.build_feed(s, p, now)
                got = {r["id"]: r["at"] for r in rows if r["kind"] in ("case", "weekend")}
                want = await _old_openings(p, now)
                if len(want) <= feed.MAX_ITEMS:
                    assert got == want
                else:
                    assert set(got) <= set(want)
        await s.delete(p)
        await s.commit()


async def test_feed_is_ordered_and_two_players_do_not_share_their_news(client):
    a = await new_player(client, "perf-feed-a")
    b = await new_player(client, "perf-feed-b", aged=False)
    fa = (await client.get("/v1/feed", headers=a["headers"])).json()["items"]
    fb = (await client.get("/v1/feed", headers=b["headers"])).json()["items"]
    keys = [(i["at"], i["id"]) for i in fa]
    assert keys == sorted(keys, reverse=True)
    assert len(fa) >= len(fb)  # a brand new account is not told about cases that opened before it joined


# --------------------------------------------------------------------------- rate limiter
def test_trusted_proxy_networks_are_parsed_once_and_give_the_same_answer():
    ratelimit._proxy_networks.cache_clear()
    text = "10.0.0.0/8, 192.168.1.0/24"
    a = ratelimit._proxy_networks(text)
    assert ratelimit._proxy_networks(text) is a and ratelimit._proxy_networks.cache_info().hits == 1
    assert ratelimit.client_ip({"x-forwarded-for": "1.2.3.4, 9.9.9.9"}, "10.1.2.3", 1, a) == "9.9.9.9"
    assert ratelimit.client_ip({"x-forwarded-for": "1.2.3.4"}, "8.8.8.8", 1, a) == "8.8.8.8"  # peer not trusted
    assert ratelimit._proxy_networks("") == [] and ratelimit._proxy_networks(" , ") == []
