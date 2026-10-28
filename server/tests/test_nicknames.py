"""Unique detective names (app/nicknames.py, 28 Oct 2026)."""
import asyncio

from sqlalchemy import select

from app import db, nicknames
from app.models import NicknameClaim
from .conftest import new_player


async def rename(client, p, name):
    return await client.patch("/v1/me", headers=p["headers"], json={"nickname": name})


def test_key_ignores_case_spaces_letter_variants_and_digit_scripts():
    k = nicknames.nickname_key
    assert k("علی") == k("علي") and k("Ali") == k("ali ") and k("علی_رضا") == k("علی رضا")
    assert k("کارآگاه ۱۲") == k("کارآگاه 12") and k("می‌لاد") == k("میلاد")
    assert k("علی") != k("رضا")
    assert nicknames.is_default("کارآگاه1234") and not nicknames.is_default("کارآگاه12")


async def test_a_taken_name_is_refused_even_with_other_spelling(client):
    a, b = await new_player(client, "nk-a"), await new_player(client, "nk-b")
    assert (await rename(client, a, "شرلوک")).status_code == 200
    r = await rename(client, b, "شرلوک")
    assert r.status_code == 422 and r.json()["detail"] == "bad_nickname"
    assert (await rename(client, b, " شرلوک ")).status_code == 422
    assert (await rename(client, b, "شرلوک_")).status_code == 422
    assert (await rename(client, b, "SHERLOCK")).status_code == 200   # a different name is fine
    assert (await rename(client, a, "شرلوک")).status_code == 200      # the owner can send his own name again


async def test_changing_the_name_frees_the_old_one(client):
    a, b = await new_player(client, "nf-a"), await new_player(client, "nf-b")
    assert (await rename(client, a, "پوارو")).status_code == 200
    assert (await rename(client, a, "ماگره")).status_code == 200
    assert (await rename(client, b, "پوارو")).status_code == 200
    assert (await rename(client, a, "پوارو")).status_code == 422
    async with db.SessionLocal() as s:
        mine = (await s.scalars(select(NicknameClaim).where(NicknameClaim.player_id == a["player_id"]))).all()
        assert [c.key for c in mine] == ["ماگره"]   # one name per player


async def test_two_detectives_asking_at_once_only_one_wins(client):
    ps = [await new_player(client, f"nr-{i}") for i in range(3)]
    rs = await asyncio.gather(*[rename(client, p, "کنجکاو") for p in ps])
    assert sorted(r.status_code for r in rs) == [200, 422, 422]


async def test_default_names_are_never_claimed_and_bad_names_still_refused(client):
    a = await new_player(client, "nd-a")
    assert (await rename(client, a, "کارآگاه4321")).status_code == 200
    async with db.SessionLocal() as s:
        assert (await s.scalars(select(NicknameClaim).where(NicknameClaim.player_id == a["player_id"]))).all() == []
    assert (await rename(client, a, "x")).status_code == 422   # too short: the old rule is unchanged
    assert (await rename(client, a, "")).status_code in (200, 422)


async def test_deleting_the_account_frees_the_name(client):
    a, b = await new_player(client, "ndl-a"), await new_player(client, "ndl-b")
    assert (await rename(client, a, "ناپدید")).status_code == 200
    assert (await client.post("/v1/me/delete", headers=a["headers"])).status_code == 200
    assert (await rename(client, b, "ناپدید")).status_code == 200
