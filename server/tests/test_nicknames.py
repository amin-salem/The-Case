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


# ---- 10 Nov 2026: «taken» and «not acceptable» are different errors; no emoji or stickers in a name ----

async def rename_v2(client, p, name):
    return await client.patch("/v1/me", headers=p["headers"], json={"nickname": name, "name_errors": True})


def test_problem_codes_and_the_character_whitelist():
    from app.util import clean_nickname, nickname_problem as prob
    assert prob("شرلوک") is None and prob("می‌لاد") is None and prob("Ali 99") is None and prob("علی_رضا") is None
    assert prob("کارآگاه۱۲۳۴") is None and prob("Ali.K") is None
    for emoji in ("علی😀", "😀😀", "🕵️ شرلوک", "ali❤", "علی★", "تست\u200d", "ab\u202e", "علی\n\tرضا\x00", "a\ufe0fb"):
        assert prob(emoji) == "nickname_chars", repr(emoji)
    assert prob("x") == "nickname_length" and prob("") == "nickname_length" and prob("a" * 17) == "nickname_length"
    assert prob("123456") == "nickname_chars" and prob("...") == "nickname_chars"     # needs a letter
    assert prob("site.ir") == "bad_nickname" and prob("admin") == "bad_nickname" and prob("a1234567z") == "bad_nickname"
    assert clean_nickname("  علی   رضا ") == "علی رضا" and clean_nickname("علی😀") is None


async def test_new_app_gets_separate_codes_and_old_app_keeps_the_old_one(client):
    a, b = await new_player(client, "nv-a"), await new_player(client, "nv-b")
    assert (await rename(client, a, "کنجکاوان")).status_code == 200
    taken = await rename_v2(client, b, "کنجکاوان")
    assert taken.status_code == 422 and taken.json()["detail"] == "nickname_taken"
    assert (await rename_v2(client, b, "علی😀")).json()["detail"] == "nickname_chars"
    assert (await rename_v2(client, b, "x")).json()["detail"] == "nickname_length"
    assert (await rename_v2(client, b, "admin")).json()["detail"] == "bad_nickname"
    # the old app (no name_errors) still gets the one code its text maps
    for name in ("کنجکاوان", "علی😀", "x", "admin"):
        r = await rename(client, b, name)
        assert r.status_code == 422 and r.json()["detail"] == "bad_nickname", name
    assert (await rename_v2(client, b, "شبگرد")).status_code == 200


async def test_a_refused_name_changes_nothing(client):
    a = await new_player(client, "nz-a")
    before = (await client.get("/v1/me", headers=a["headers"])).json()["nickname"]
    for name in ("علی😀", "x", "a" * 40):
        assert (await rename_v2(client, a, name)).status_code == 422
    assert (await client.get("/v1/me", headers=a["headers"])).json()["nickname"] == before
