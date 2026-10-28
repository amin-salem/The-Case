"""A refused purchase row must not lock a paid token to the account that tried first (28 Oct 2026, vip_monthly)."""
import asyncio

from sqlalchemy import select

from app import db
from app.models import Purchase
from .conftest import new_player


async def refused_row(pid, token, product="vip_monthly", status="rejected"):
    async with db.SessionLocal() as s:
        s.add(Purchase(player_id=pid, product_id=product, purchase_token=token, status=status, raw={"reason": "bazaar_error:401"}))
        await s.commit()


async def verify(client, p, token, product="vip_monthly"):
    return (await client.post("/v1/purchases/verify", headers=p["headers"],
                              json={"product_id": product, "purchase_token": token})).json()


async def test_token_refused_on_another_account_is_granted_to_the_paying_account(client):
    first, second = await new_player(client, "pr-a"), await new_player(client, "pr-b")
    await refused_row(first["player_id"], "test-vip-moved")
    r = await verify(client, second, "test-vip-moved")
    assert r["status"] == "granted" and r["vip_until"]
    async with db.SessionLocal() as s:
        row = await s.scalar(select(Purchase).where(Purchase.purchase_token == "test-vip-moved"))
        assert row.player_id == second["player_id"] and row.status == "granted"
    # the first account cannot take it back
    assert (await verify(client, first, "test-vip-moved"))["reason"] == "token_used"


async def test_granted_token_stays_with_its_owner(client):
    a, b = await new_player(client, "pg-a"), await new_player(client, "pg-b")
    assert (await verify(client, a, "test-vip-owned"))["status"] == "granted"
    r = await verify(client, b, "test-vip-owned")
    assert r["status"] == "rejected" and r["reason"] == "token_used"


async def test_two_accounts_cannot_both_take_a_refused_token(client):
    a, b, c = await new_player(client, "pc-a"), await new_player(client, "pc-b"), await new_player(client, "pc-c")
    await refused_row(a["player_id"], "test-coins-race", product="coins_small")
    r1, r2 = await asyncio.gather(verify(client, b, "test-coins-race", "coins_small"), verify(client, c, "test-coins-race", "coins_small"))
    assert sorted([r1["status"], r2["status"]]) == ["granted", "rejected"]


async def test_refused_row_under_another_product_name_is_checked_again(client):
    a = await new_player(client, "pw-a")
    await refused_row(a["player_id"], "test-wrong-name", product="coins_small")
    r = await verify(client, a, "test-wrong-name", "vip_monthly")
    assert r["status"] == "granted"
