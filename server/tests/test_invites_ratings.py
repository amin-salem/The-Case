"""Invite codes (what a redeem and the late inviter payment really do) and the star ratings on the case list."""
from datetime import timedelta

from sqlalchemy import select, update

from app import anticheat as ac
from app import content, db
from app import economy as eco
from app.models import CaseProgress, CoinLog, Player, utcnow

from .conftest import ADMIN, new_player

RATED = content.all_cases()[3].id


async def me(client, p):
    return (await client.get("/v1/me", headers=p["headers"])).json()


async def solve_days(pid, n, tag="a"):
    async with db.SessionLocal() as s:
        for i in range(n):
            s.add(CaseProgress(player_id=pid, case_id=f"zi{tag}{i}-{pid[:6]}", solved=True, stars=1, day=f"2026-08-0{i + 1}"))
        await s.commit()


# ---------------------------------------------------------------- invite codes
async def test_redeem_pays_the_new_player_at_once_and_only_once(client):
    inviter = await new_player(client, "iv-inviter-1")
    friend = await new_player(client, "iv-friend-1")
    code = (await me(client, inviter))["invite_code"]
    before = (await me(client, friend))["coins"]
    r = await client.post("/v1/referrals/redeem", headers=friend["headers"], json={"code": code.lower()})  # any case
    assert r.status_code == 200, r.text
    assert r.json()["grants"] == [{"type": "coins", "amount": eco.INVITE_NEW_PLAYER}]
    assert r.json()["coins"] == before + eco.INVITE_NEW_PLAYER
    after = await me(client, friend)
    assert after["coins"] == before + eco.INVITE_NEW_PLAYER and after["referred"] is True
    async with db.SessionLocal() as s:
        log = (await s.execute(select(CoinLog).where(CoinLog.player_id == friend["player_id"], CoinLog.reason == "invited"))).scalars().all()
    assert [row.amount for row in log] == [eco.INVITE_NEW_PLAYER]
    # twice: refused, no second payment
    again = await client.post("/v1/referrals/redeem", headers=friend["headers"], json={"code": code})
    assert again.status_code == 409 and again.json()["detail"] == "already_redeemed"
    assert (await me(client, friend))["coins"] == before + eco.INVITE_NEW_PLAYER


async def test_redeem_refusals_pay_nothing(client):
    inviter = await new_player(client, "iv-inviter-2")
    code = (await me(client, inviter))["invite_code"]
    # own code, unknown code
    own = await client.post("/v1/referrals/redeem", headers=inviter["headers"], json={"code": code})
    assert own.status_code == 404 and own.json()["detail"] == "bad_code"
    unknown = await new_player(client, "iv-unknown-1")
    assert (await client.post("/v1/referrals/redeem", headers=unknown["headers"], json={"code": "ZZZZZZ9"})).status_code == 404
    # the same phone as the inviter
    twin = await new_player(client, "iv-inviter-2")
    coins = (await me(client, twin))["coins"]
    same = await client.post("/v1/referrals/redeem", headers=twin["headers"], json={"code": code})
    assert same.status_code == 409 and same.json()["detail"] == "same_device"
    assert (await me(client, twin))["coins"] == coins
    # an account older than 7 days (this is why an old tester got nothing)
    old = await new_player(client, "iv-old-1")
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == old["player_id"]).values(created_at=utcnow() - timedelta(days=9)))
        await s.commit()
    coins = (await me(client, old))["coins"]
    late = await client.post("/v1/referrals/redeem", headers=old["headers"], json={"code": code})
    assert late.status_code == 410 and late.json()["detail"] == "only_for_new_players"
    assert (await me(client, old))["coins"] == coins
    st = (await client.get("/v1/referrals/status", headers=old["headers"])).json()
    assert st["can_redeem"] is False and st["referred"] is False


async def test_inviter_gets_a_gift_that_adds_coins_when_claimed(client):
    inviter = await new_player(client, "iv-inviter-3")
    friend = await new_player(client, "iv-friend-3")
    code = (await me(client, inviter))["invite_code"]
    assert (await client.post("/v1/referrals/redeem", headers=friend["headers"], json={"code": code})).status_code == 200
    await me(client, inviter)  # the daily login reward (if any) is paid by this call, not by the invite
    await solve_days(friend["player_id"], eco.INVITE_MIN_DAYS)
    assert await ac.maybe_pay_referral(friend["player_id"]) is True
    after = await me(client, inviter)  # may add an achievement reward for the invite; the gift itself waits in the inbox
    start = after["coins"]
    inbox = (await client.get("/v1/inbox", headers=inviter["headers"])).json()
    gift = next(i for i in inbox if i["title"].startswith("یه کارآگاه تازه"))
    assert gift["grants"] == [{"type": "coins", "amount": eco.INVITE_INVITER}]
    claimed = await client.post(f"/v1/inbox/{gift['id']}/claim", headers=inviter["headers"])
    assert claimed.status_code == 200 and claimed.json()["coins"] == start + eco.INVITE_INVITER
    assert (await client.post(f"/v1/inbox/{gift['id']}/claim", headers=inviter["headers"])).status_code == 409
    assert (await me(client, inviter))["coins"] == start + eco.INVITE_INVITER  # paid exactly once


async def test_referral_status_shows_progress_for_both_sides(client):
    inviter = await new_player(client, "iv-inviter-4")
    friend = await new_player(client, "iv-friend-4")
    code = (await me(client, inviter))["invite_code"]
    st = (await client.get("/v1/referrals/status", headers=friend["headers"])).json()
    assert st["can_redeem"] is True and st["referred"] is False and st["need_days"] == eco.INVITE_MIN_DAYS
    assert st["new_player_reward"] == eco.INVITE_NEW_PLAYER and st["inviter_reward"] == eco.INVITE_INVITER
    await client.post("/v1/referrals/redeem", headers=friend["headers"], json={"code": code})
    await solve_days(friend["player_id"], 2)
    mine = (await client.get("/v1/referrals/status", headers=friend["headers"])).json()
    assert mine["referred"] is True and mine["can_redeem"] is False and mine["my_days"] == 2 and mine["my_inviter_paid"] is False
    theirs = (await client.get("/v1/referrals/status", headers=inviter["headers"])).json()
    assert theirs["invited"] == 1 and theirs["best_days"] == 2 and theirs["invited_paid"] == 0
    await solve_days(friend["player_id"], 3, tag="b")  # more days than needed: shown at most "3 of 3"
    assert await ac.maybe_pay_referral(friend["player_id"]) is True
    theirs = (await client.get("/v1/referrals/status", headers=inviter["headers"])).json()
    assert theirs["invited"] == 1 and theirs["invited_paid"] == 1 and theirs["best_days"] == 0
    assert (await client.get("/v1/referrals/status", headers=friend["headers"])).json()["my_days"] == eco.INVITE_MIN_DAYS


# ---------------------------------------------------------------- ratings on the case list
async def finish(pid, case_id=RATED):
    async with db.SessionLocal() as s:
        s.add(CaseProgress(player_id=pid, case_id=case_id, solved=True, finished_at=utcnow()))
        await s.commit()


async def row(client, p, case_id=RATED):
    d = (await client.get("/v1/cases", headers=p["headers"])).json()
    return next(r for r in d["archive"] + ([d["today"]] if d["today"] else []) if r["id"] == case_id)


async def rate(client, p, stars, body=""):
    return await client.post(f"/v1/cases/{RATED}/comments", headers=p["headers"],
                             json={"body": body, "rating": stars, "parent_id": None})


async def test_case_rows_carry_average_count_and_my_rating(client):
    a = await new_player(client, "rt-a-1234")
    b = await new_player(client, "rt-b-1234")
    await finish(a["player_id"])
    await finish(b["player_id"])
    base = await row(client, a)
    assert base["my_rating"] == 0
    n0, w0 = base["rating_count"], base["comment_count"]
    assert (await rate(client, a, 4)).json()["status"] == "approved"  # stars alone count at once
    r = await row(client, a)
    assert r["my_rating"] == 4 and r["rating_count"] == n0 + 1 and r["comment_count"] == w0
    assert (await row(client, b))["my_rating"] == 0  # my_rating is private to the player
    assert (await rate(client, a, 5)).status_code == 409  # stars cannot be changed without text
    # the same player may add words once; the words wait for the admin, a second try is refused
    added = await rate(client, a, 4, "یه پرونده‌ی خوب بود")
    assert added.status_code == 200 and added.json()["status"] == "pending"
    assert (await rate(client, a, 4, "یه بار دیگه")).status_code == 409
    mid = await row(client, a)
    assert mid["comment_count"] == w0 and mid["my_rating"] == 4
    ok = await client.post(f"/admin/api/comments/{added.json()['id']}", headers=ADMIN, json={"action": "approve"})
    assert ok.status_code == 200
    done = await row(client, b)
    assert done["comment_count"] == w0 + 1 and done["rating_count"] == n0 + 1 and done["rating_avg"] > 0
