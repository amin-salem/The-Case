"""Story choices: scenes with options, locked options, the board, old-format chapters."""
import json

import pytest

from app import content, storyflow

from .conftest import new_player


def chapter(**over):
    base = json.loads(json.dumps(content.by_id("c001").data))
    base.pop("publish")
    ev = base["evidence"][0]["id"]
    d = {**base, "id": "s01ch01", "number": 1, "season": 1, "chapter": 1, "title": "فصل ۱", "partner_intro": "بیا.",
         "partner_outro_win": "آفرین.", "partner_outro_lose": "نه.", "thread": "کبریت.",
         "scenes": [
             {"id": "a", "text": "شروع", "speaker": "partner", "options": [
                 {"id": "a1", "title": "اول بازار", "sub": "می‌پرسی", "goes_to": "b", "gives_clue": ["k1"],
                  "relations": {"p1": "friendly"}},
                 {"id": "a2", "title": "اول انبار", "sub": "می‌بینی", "goes_to": "c", "gives_clue": [ev],
                  "relations": {"p1": "suspicious"}}]},
             {"id": "b", "text": "بازار", "options": [
                 {"id": "b1", "title": "ادامه", "goes_to": "d"}, {"id": "b2", "title": "برگرد", "goes_to": "d"}]},
             {"id": "c", "text": "انبار", "options": [
                 {"id": "c1", "title": "ادامه", "goes_to": "d"}, {"id": "c2", "title": "برگرد", "goes_to": "d"}]},
             {"id": "d", "text": "دفتر", "options": [
                 {"id": "d1", "title": "پرونده‌ی قدیمی", "goes_to": "end", "needs_clue": "k1"},
                 {"id": "d2", "title": "برو سراغ مظنون", "goes_to": "end"}]}],
         "ending": {"id": "end", "text": "حالا متهم."},
         "board": {"people": [{"id": "p1", "name": "عباس"}, {"id": "p2", "name": "قاسم"}],
                   "clues": [{"id": "k1", "title": "دفتر قدیمی", "text": "یک دفتر."}]}}
    d.update(over)
    return d


def write(tmp_path, monkeypatch, d):
    (tmp_path / "s01").mkdir(exist_ok=True)
    (tmp_path / "s01" / "ch01.json").write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
    monkeypatch.setattr(content, "STORY_DIR", tmp_path)
    monkeypatch.setitem(content.STORY_SEASON, "opens_at", "2026-01-01T00:00:00")
    content._story_load.cache_clear()


@pytest.fixture
def story(tmp_path, monkeypatch):
    write(tmp_path, monkeypatch, chapter())
    yield
    content._story_load.cache_clear()


def bad(d):
    with pytest.raises(content.CaseError):
        content.validate_story(json.loads(json.dumps(d)), 1, 1)


def test_valid_chapter_passes():
    content.validate_story(chapter(), 1, 1)


def test_validator_rejects_broken_graphs():
    d = chapter()
    d["scenes"][0]["options"][0]["goes_to"] = "nowhere"
    bad(d)
    d = chapter()
    d["scenes"][1]["options"] = []  # dead end
    bad(d)
    d = chapter()
    d["scenes"][3]["options"][0]["goes_to"] = "a"  # loop
    bad(d)
    d = chapter()
    d["scenes"][0]["options"][1]["goes_to"] = "b"  # scene c is never reached
    bad(d)
    d = chapter()
    d["scenes"][3]["options"][1]["needs_clue"] = "k1"  # every option locked
    bad(d)
    d = chapter()
    d["scenes"][0]["options"][0]["gives_clue"] = []  # k1 can never be held
    bad(d)
    d = chapter()
    d["scenes"][0]["options"][0]["gives_clue"] = ["nope"]
    bad(d)
    d = chapter()
    d["scenes"][0]["options"][0]["relations"] = {"zz": "friendly"}
    bad(d)
    d = chapter()
    d["scenes"][0]["text"] = "ک" * 3000
    bad(d)
    d = chapter()
    d["scenes"][0]["options"] += [{"id": f"x{i}", "title": "t", "goes_to": "b"} for i in range(3)]
    bad(d)


def test_locked_clue_must_come_from_an_earlier_scene():
    d = chapter()
    d["scenes"][0]["options"][0]["needs_clue"] = "k1"  # needs a clue given by its own options
    d["scenes"][0]["options"][1]["needs_clue"] = None
    bad(d)


def test_old_format_is_one_scene_with_a_start_option():
    d = chapter()
    for k in ("scenes", "ending", "board"):
        d.pop(k)
    content.validate_story(d, 1, 1)
    flow = content.story_scenes(d)
    assert len(flow["scenes"]) == 1 and flow["scenes"][0]["options"][0]["title"] == "شروع"
    c = content.Case(id="s01ch01", number=1, publish=content.date(2026, 1, 1), data=d)
    st = storyflow.new_state()
    st["scene"] = "start"
    new, err = storyflow.apply_choice(c, st, "start", "go")
    assert err is None and new["done"] is True


async def start(client, name="sc-1"):
    p = await new_player(client, name)
    h = p["headers"]
    assert (await client.post("/v1/story/1/open", headers=h)).status_code == 200
    return h


async def test_valid_path_and_board(client, story):
    h = await start(client)
    s = (await client.get("/v1/story/chapter/s01ch01/state", headers=h)).json()
    assert s["scene"]["id"] == "a" and [o["id"] for o in s["scene"]["options"]] == ["a1", "a2"]
    assert "goes_to" not in json.dumps(s)  # destinations stay on the server
    assert [p["state"] for p in s["board"]["people"]] == ["unmet", "unmet"]
    r = await client.post("/v1/story/chapter/s01ch01/choose", headers=h, json={"scene": "a", "option": "a1"})
    s = r.json()
    assert r.status_code == 200 and s["scene"]["id"] == "b" and "k1" in s["clues"]
    assert s["board"]["people"][0]["state"] == "friendly"
    held = {c["id"]: c["status"] for c in s["board"]["clues"]}
    assert held["k1"] == "held"
    r = await client.post("/v1/story/chapter/s01ch01/choose", headers=h, json={"scene": "b", "option": "b1"})
    r = await client.post("/v1/story/chapter/s01ch01/choose", headers=h, json={"scene": "d", "option": "d1"})
    s = r.json()
    assert s["done"] is True and s["scene"]["ending"] is True
    b = (await client.get("/v1/story/board", headers=h)).json()
    assert b["held"] == 1 and b["continue_chapter"] is None
    assert b["people"][0]["text"] == "با تو راحت است"


async def test_locked_option_refused_and_clue_marked_missed(client, story):
    h = await start(client)
    await client.post("/v1/story/chapter/s01ch01/choose", headers=h, json={"scene": "a", "option": "a2"})
    s = (await client.post("/v1/story/chapter/s01ch01/choose", headers=h, json={"scene": "c", "option": "c1"})).json()
    opts = {o["id"]: o for o in s["scene"]["options"]}
    assert opts["d1"]["locked"] is True and "فصل ۱" in opts["d1"]["reason"] and opts["d2"]["locked"] is False
    r = await client.post("/v1/story/chapter/s01ch01/choose", headers=h, json={"scene": "d", "option": "d1"})
    assert r.status_code == 409 and r.json()["detail"] == "locked"
    status = {c["id"]: c["status"] for c in s["board"]["clues"]}
    assert status["k1"] == "missed"  # no path left gives it
    r = await client.post("/v1/story/chapter/s01ch01/choose", headers=h, json={"scene": "d", "option": "d2"})
    assert r.json()["done"] is True  # a closed path never blocks the chapter


async def test_double_submit_is_idempotent_and_wrong_scene_refused(client, story):
    h = await start(client)
    url = "/v1/story/chapter/s01ch01/choose"
    first = (await client.post(url, headers=h, json={"scene": "a", "option": "a1"})).json()
    again = await client.post(url, headers=h, json={"scene": "a", "option": "a1"})
    assert again.status_code == 200 and again.json() == first and len(again.json()["clues"]) == 1
    other = await client.post(url, headers=h, json={"scene": "a", "option": "a2"})
    assert other.status_code == 409 and other.json()["detail"] == "wrong_scene"  # can't take back
    assert (await client.post(url, headers=h, json={"scene": "b", "option": "zz"})).status_code == 404
    assert (await client.post(url, headers=h, json={"scene": "", "option": "a1"})).status_code == 422


async def test_state_is_private_and_needs_an_opened_chapter(client, story):
    h = await start(client, "sc-a")
    await client.post("/v1/story/chapter/s01ch01/choose", headers=h, json={"scene": "a", "option": "a1"})
    other = (await new_player(client, "sc-b"))["headers"]
    assert (await client.get("/v1/story/chapter/s01ch01/state", headers=other)).status_code == 409  # not opened
    await client.post("/v1/story/1/open", headers=other)
    s = (await client.get("/v1/story/chapter/s01ch01/state", headers=other)).json()
    assert s["scene"]["id"] == "a" and s["clues"] == []  # starts fresh, sees nothing of the other player
    assert (await client.get("/v1/story/chapter/s01ch99/state", headers=other)).status_code == 404
    b = (await client.get("/v1/story/board", headers=other)).json()
    assert b["held"] == 0 and b["continue_chapter"] == 1


async def test_choice_cap(client, story, monkeypatch):
    h = await start(client)
    monkeypatch.setattr(content, "MAX_CHOICES", 1)
    url = "/v1/story/chapter/s01ch01/choose"
    await client.post(url, headers=h, json={"scene": "a", "option": "a1"})
    r = await client.post(url, headers=h, json={"scene": "b", "option": "b1"})
    assert r.status_code == 409 and r.json()["detail"] == "too_many_choices"


async def test_old_format_chapter_still_plays(client, tmp_path, monkeypatch):
    d = chapter()
    for k in ("scenes", "ending", "board"):
        d.pop(k)
    write(tmp_path, monkeypatch, d)
    h = await start(client, "sc-old")
    s = (await client.get("/v1/story/chapter/s01ch01/state", headers=h)).json()
    assert s["scene"]["options"][0]["title"] == "شروع"
    s = (await client.post("/v1/story/chapter/s01ch01/choose", headers=h, json={"scene": "start", "option": "go"})).json()
    assert s["done"] is True
    case = (await client.get("/v1/cases/s01ch01", headers=h)).json()["case"]
    assert "scenes" not in case and "board" not in case and "ending" not in case


async def test_real_chapter_one_loads_and_plays(client, monkeypatch):
    content._story_load.cache_clear()
    monkeypatch.setitem(content.STORY_SEASON, "opens_at", "2026-01-01T00:00:00")
    c = content.story_by_id("s01ch01")
    assert c is not None and len(c.data["scenes"]) >= 1
    h = await start(client, "sc-real")
    s = (await client.get("/v1/story/chapter/s01ch01/state", headers=h)).json()
    while not s["done"]:
        o = next(x for x in s["scene"]["options"] if not x["locked"])
        s = (await client.post("/v1/story/chapter/s01ch01/choose", headers=h,
                               json={"scene": s["scene"]["id"], "option": o["id"]})).json()
    assert s["scene"]["ending"] is True
