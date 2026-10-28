"""Runs in the wallet-postgres CI job too: the first-days offers query must work on PostgreSQL (asyncpg), where a
GROUP BY on a bound expression fails. A brand-new account must get its case list (28 Oct 2026: it was a 500)."""
from app import db, welcome
from app.models import CoinLog
from .conftest import new_player


async def test_new_account_gets_cases_and_offers(client):
    p = await new_player(client, "wo-pg", aged=False)
    r = await client.get("/v1/cases", headers=p["headers"])
    assert r.status_code == 200
    async with db.SessionLocal() as s:
        from app.models import Player
        pl = await s.get(Player, p["player_id"])
        assert await welcome.offers_for(s, pl) == welcome.Offers(reopen=True, archive=True)
        s.add_all([CoinLog(player_id=pl.id, amount=-100, reason="reopen:c001", balance=0),
                   CoinLog(player_id=pl.id, amount=-50, reason="unlock:c002", balance=0)])
        await s.commit()
        assert await welcome.offers_for(s, pl) == welcome.Offers(reopen=False, archive=False)
