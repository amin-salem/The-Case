from .conftest import ADMIN, new_player


async def test_admin_page_and_api_need_the_key(client):
    page = await client.get("/admin/ui")
    assert page.status_code == 200 and "text/html" in page.headers["content-type"]
    assert "test-admin-key" not in page.text  # the page holds no secrets
    for path in ("overview", "feed", "players", "cases", "money", "health", "log"):
        assert (await client.get(f"/admin/api/{path}")).status_code == 403
        assert (await client.get(f"/admin/api/{path}", headers={"X-Admin-Key": "wrong"})).status_code == 403


async def test_admin_api_reads(client):
    p = await new_player(client, "admin-ui-dev-1")
    h = p["headers"]
    await client.get("/v1/cases/today", headers=h)
    ov = (await client.get("/admin/api/overview?days=7", headers=ADMIN)).json()
    assert len(ov["days"]) == 7 and ov["totals"]["players"] >= 1
    assert sum(d["new"] for d in ov["days"]) >= 1
    feed = (await client.get("/admin/api/feed", headers=ADMIN)).json()
    assert any(i["kind"] == "signup" for i in feed)
    pl = (await client.get("/admin/api/players?sort=created", headers=ADMIN)).json()
    assert pl["total"] >= 1 and pl["items"]
    pid = pl["items"][0]["id"]
    d = (await client.get(f"/admin/api/players/{pid}", headers=ADMIN)).json()
    assert d["player"]["id"] == pid and isinstance(d["timeline"], list)
    assert (await client.get("/admin/api/players/nope", headers=ADMIN)).status_code == 404
    assert isinstance((await client.get("/admin/api/cases", headers=ADMIN)).json(), list)
    assert "purchases_by_product" in (await client.get("/admin/api/money", headers=ADMIN)).json()
    assert (await client.get("/admin/api/health", headers=ADMIN)).json()["db_ok"] is True


async def test_admin_actions_are_logged(client):
    p = await new_player(client, "admin-ui-dev-2")
    pid = (await client.get("/admin/api/players?sort=created", headers=ADMIN)).json()["items"][0]["id"]
    r = await client.post("/admin/gifts", headers=ADMIN, json={"title": "سلام", "message": "x", "player_id": pid,
                                                            "grants": [{"type": "coins", "amount": 5}]})
    assert r.status_code == 200
    assert (await client.post(f"/admin/players/{pid}/ban", headers=ADMIN, json={"banned": True})).status_code == 200
    assert (await client.post(f"/admin/players/{pid}/ban", headers=ADMIN, json={"banned": False})).status_code == 200
    log = (await client.get("/admin/api/log", headers=ADMIN)).json()
    assert [x["action"] for x in log][:3] == ["unban", "ban", "gift"]


# ---------------------------------------------------------------- health screen (no real network, fake clock)

import httpx as _httpx  # noqa: E402
import pytest  # noqa: E402

from app.services import health as H  # noqa: E402


@pytest.fixture
def fake(monkeypatch):
    H.reset()
    state = {"t": 1_000_000.0, "tls": {"gaamly.ir": 90, "thecase.liara.run": 90}, "liara": (200, {"user": {"balance": 900000}}),
             "calls": 0, "tls_calls": 0}

    async def tls(host):
        state["tls_calls"] += 1
        v = state["tls"][host]
        if isinstance(v, Exception):
            raise v
        return v

    async def liara(token):
        state["calls"] += 1
        assert token == "secret-token"
        v = state["liara"]
        if isinstance(v, Exception):
            raise v
        return v

    monkeypatch.setattr(H.deps, "clock", lambda: state["t"], raising=False)
    monkeypatch.setattr(H.deps, "tls_days", tls, raising=False)
    monkeypatch.setattr(H.deps, "liara_fetch", liara, raising=False)
    monkeypatch.setenv("LIARA_API_TOKEN", "secret-token")
    monkeypatch.delenv("LIARA_MIN_BALANCE", raising=False)
    yield state
    H.reset()


async def test_health2_needs_the_key(client):
    for path in ("health2", "liara"):
        assert (await client.get(f"/admin/api/{path}")).status_code == 403


async def test_health2_shape_and_no_secrets(client, fake):
    await new_player(client, "health-dev-1")
    r = await client.get("/admin/api/health2", headers=ADMIN)
    assert r.status_code == 200
    d = r.json()
    assert d["server"]["db_ok"] is True and d["server"]["version"]
    assert d["players"]["total"] >= 1 and isinstance(d["players"]["app_versions"], list)
    assert {i["host"] for i in d["domains"]["items"]} == {"gaamly.ir", "thecase.liara.run"}
    assert d["content"]["validation"] == "ok" and d["content"]["story"]["next_missing"] >= 1
    assert d["overall"] in ("ok", "warn", "bad") and d["watch"]
    assert d["security"]["admin_key_real"] is False  # the test key is short
    assert "test-admin-key" not in r.text and "test-secret-that-is-long" not in r.text and "secret-token" not in r.text


async def test_tls_thresholds_cache_and_failure(client, fake):
    fake["tls"]["gaamly.ir"] = 20
    d = (await client.get("/admin/api/health2", headers=ADMIN)).json()
    main = next(i for i in d["domains"]["items"] if i["host"] == "gaamly.ir")
    assert main["status"] == "warn" and main["days"] == 20
    assert d["domains"]["status"] == "warn"
    # cached for 10 minutes, then looked at again
    fake["tls"]["gaamly.ir"] = 5
    await client.get("/admin/api/health2", headers=ADMIN)
    assert fake["tls_calls"] == 2
    fake["t"] += 601
    d = (await client.get("/admin/api/health2", headers=ADMIN)).json()
    assert next(i for i in d["domains"]["items"] if i["host"] == "gaamly.ir")["status"] == "bad"
    # a failing check never breaks the endpoint; the old address is only amber
    fake["t"] += 601
    fake["tls"]["gaamly.ir"] = TimeoutError()
    fake["tls"]["thecase.liara.run"] = OSError("down")
    r = await client.get("/admin/api/health2", headers=ADMIN)
    assert r.status_code == 200
    items = {i["host"]: i for i in r.json()["domains"]["items"]}
    assert items["gaamly.ir"]["status"] == "bad" and items["gaamly.ir"]["error"] == "timeout"
    assert items["thecase.liara.run"]["status"] == "warn"


async def test_content_days_ahead_thresholds(client, fake, monkeypatch):
    from datetime import datetime
    from zoneinfo import ZoneInfo

    assert H.level_low(7, 7, 3) == "ok" and H.level_low(6, 7, 3) == "warn" and H.level_low(2, 7, 3) == "bad"
    last = H.content.all_cases()[-1].publish
    far = datetime(last.year + 1, 1, 1, 12, tzinfo=ZoneInfo("Asia/Tehran"))
    monkeypatch.setattr(H.deps, "now_local", lambda: far, raising=False)
    c = (await client.get("/admin/api/health2", headers=ADMIN)).json()["content"]
    assert c["days_ahead"] == 0 and c["days_ahead_status"] == "bad" and c["status"] == "bad"


async def test_one_failing_section_does_not_blank_the_screen(client, fake, monkeypatch):
    async def boom(*a, **k):
        raise RuntimeError("x")

    monkeypatch.setattr(H, "_players", boom)
    d = (await client.get("/admin/api/health2", headers=ADMIN)).json()
    assert d["players"]["status"] == "bad" and d["server"]["db_ok"] is True and d["overall"] == "bad"


async def test_liara_no_token(client, fake, monkeypatch):
    monkeypatch.delenv("LIARA_API_TOKEN")
    d = (await client.get("/admin/api/liara", headers=ADMIN)).json()
    assert d["state"] == "no_token" and "LIARA_API_TOKEN" in d["message"] and fake["calls"] == 0


async def test_liara_balance_thresholds_and_secrecy(client, fake):
    r = await client.get("/admin/api/liara", headers=ADMIN)
    d = r.json()
    assert d["state"] == "ok" and d["balance"] == 900000 and d["status"] == "ok" and d["limit"] == 300000
    assert "secret-token" not in r.text
    assert H._balance_result({"user": {"balance": 400000}}, 300000)["status"] == "warn"
    assert H._balance_result({"user": {"balance": 300000}}, 300000)["status"] == "bad"
    assert H._balance_result({"deep": [{"credit": 50}]}, 300000)["status"] == "bad"  # recursive fallback
    assert H._balance_result({"x": 1}, 300000)["kind"] == "no_balance_field"


async def test_liara_cache_and_rate_limit(client, fake):
    get = lambda q="": client.get("/admin/api/liara" + q, headers=ADMIN)  # noqa: E731
    assert (await get()).json()["cached"] is False
    d = (await get()).json()
    assert d["cached"] is True and fake["calls"] == 1  # cached 5 minutes
    fake["t"] += 10
    d = (await get("?refresh=true")).json()
    assert d["throttled"] is True and fake["calls"] == 1  # button: at most 1 real call per 30 s
    fake["t"] += 31
    fake["liara"] = (200, {"user": {"balance": 100}})
    d = (await get("?refresh=true")).json()
    assert d["cached"] is False and d["status"] == "bad" and fake["calls"] == 2
    fake["t"] += 301
    assert (await get()).json()["cached"] is False  # cache expired


async def test_liara_errors_show_a_kind_not_a_trace(client, fake):
    fake["liara"] = (401, {"message": "bad token"})
    d = (await client.get("/admin/api/liara", headers=ADMIN)).json()
    assert d["state"] == "error" and d["kind"] == "http_401"
    fake["t"] += 31
    fake["liara"] = _httpx.ReadTimeout("slow")
    d = (await client.get("/admin/api/liara?refresh=true", headers=ADMIN)).json()
    assert d["kind"] == "timeout"
    fake["t"] += 31
    fake["liara"] = _httpx.ConnectError("no route")
    assert (await client.get("/admin/api/liara?refresh=true", headers=ADMIN)).json()["kind"] == "network"
    fake["t"] += 31
    fake["liara"] = RuntimeError("secret-token leaked?")
    r = await client.get("/admin/api/liara?refresh=true", headers=ADMIN)
    assert r.json()["kind"] == "RuntimeError" and "secret-token" not in r.text
    fake["t"] += 31
    fake["liara"] = (200, {"nothing": 1})
    assert (await client.get("/admin/api/liara?refresh=true", headers=ADMIN)).json()["kind"] == "no_balance_field"


async def test_admin_page_reads_the_key_fragment_once(client):
    page = (await client.get("/admin/ui")).text
    assert "#k=" in page or "/^#k=(.+)$/" in page and "history.replaceState" in page
    assert 'id="key"' in page  # the manual key form for browsers stays


async def test_admin_page_keeps_the_open_tab_and_charts_show_values(client):
    page = (await client.get("/admin/ui")).text
    assert "adminTab" in page  # the open tab survives a reload
    assert "class=\"plink\"" in page and 'tr class="click" data-p="${esc(i.pid)}"><td>${ago(i.t)}' not in page  # feed rows no longer jump to a player
    assert "ch-tip" in page and "compact(" in page  # charts print their values and show a tapped day


async def test_admin_page_asks_questions_in_the_page(client):
    # the admin app's web view shows no browser pop-ups: confirm() answers "no" and alert() shows nothing
    html = (await client.get("/admin/ui")).text
    assert "alert(" not in html and "!confirm(" not in html and "(confirm(" not in html
    assert "await ask(" in html and 'id="cdlg"' in html
