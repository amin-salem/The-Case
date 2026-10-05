#!/usr/bin/env python3
"""Checks that a running server answers every call the app makes.

    python tools/smoke_test.py                                   # https://thecase.liara.run
    python tools/smoke_test.py http://127.0.0.1:8000 --solve     # a local server: also solves today's case
    ADMIN_API_KEY=... python tools/smoke_test.py URL             # also checks the admin calls

It registers one throw-away player ("smoke-xxxx"). Exit code 0 = everything works.
"""
import argparse
import json
import os
import sys
import time
import uuid
from pathlib import Path

import httpx

CASES = Path(__file__).resolve().parent.parent / "app" / "content" / "cases"
results: list[tuple[bool, str, str]] = []


def check(ok: bool, name: str, detail: str = ""):
    results.append((bool(ok), name, detail))
    print(f"  {'OK  ' if ok else 'FAIL'} {name}" + (f"   {detail}" if detail else ""))
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("base", nargs="?", default=os.environ.get("API_URL", "https://thecase.liara.run"))
    ap.add_argument("--solve", action="store_true", help="solve today's case using the local case files (local servers only)")
    ap.add_argument("--timeout", type=float, default=25)
    a = ap.parse_args()
    base = a.base.rstrip("/")
    print(f"Server: {base}")
    c = httpx.Client(base_url=base, timeout=a.timeout, follow_redirects=True)

    def call(method, path, **kw):
        t = time.time()
        try:
            r = c.request(method, path, **kw)
        except Exception as e:  # noqa: BLE001
            check(False, f"{method} {path}", f"no connection: {type(e).__name__}: {e}")
            return None
        ms = int((time.time() - t) * 1000)
        return r, ms

    def expect(method, path, status=200, name=None, **kw):
        out = call(method, path, **kw)
        if out is None:
            return None
        r, ms = out
        ok = r.status_code == status
        check(ok, name or f"{method} {path}", f"{r.status_code} in {ms} ms" + ("" if ok else f"  body: {r.text[:200]}"))
        try:
            return r.json() if ok else None
        except Exception:  # noqa: BLE001
            return None

    print("\nPublic")
    h = expect("GET", "/health")
    if h is None:
        print("\nThe server did not answer /health, so nothing else can work.")
        return 2
    check(h.get("ok") is True, "health says ok", f"cases loaded: {h.get('cases')}, version: {h.get('version')}")
    cfg = expect("GET", "/v1/config")
    check(cfg and "economy" in cfg and "next_case_at" in cfg, "config has economy and next case time")
    check(cfg and cfg.get("maintenance") in (None, False, 0, "false", ""), "not in maintenance mode", str(cfg.get("maintenance") if cfg else ""))

    print("\nAccount")
    reg = expect("POST", "/v1/auth/register", json={"device_id": f"smoke-{uuid.uuid4().hex[:12]}", "app_version": 1})
    if not reg:
        return 1
    hdr = {"Authorization": f"Bearer {reg['token']}"}
    me = expect("GET", "/v1/me", headers=hdr)
    check(me and me.get("coins", 0) > 0, "new player got welcome coins", f"coins={me and me.get('coins')}")
    check(me and me.get("login_day") == 1 and me.get("login_reward", 0) > 0, "login calendar: day 1 reward",
          f"day={me and me.get('login_day')} reward={me and me.get('login_reward')}")
    check(cfg and "login_calendar" in cfg.get("economy", {}) and cfg.get("share_url"), "config has login calendar and share link")
    expect("PATCH", "/v1/me", headers=hdr, json={"nickname": "smoke test"}, name="PATCH /v1/me (nickname)")
    expect("GET", "/v1/me", status=401, name="GET /v1/me without a token is refused")

    print("\nCases")
    lst = expect("GET", "/v1/cases", headers=hdr)
    if not lst or not lst.get("today"):
        check(False, "there is a case for today")
        return 1
    today = lst["today"]
    check(True, "there is a case for today", f"{today['id']} «{today['title']}» difficulty {today['difficulty']}, archive {len(lst['archive'])}")
    got = expect("GET", f"/v1/cases/{today['id']}", headers=hdr)
    check(got and "solution" not in got["case"] and "hints" not in got["case"], "today's case does not leak the solution")
    check(got and len(got["case"]["suspects"]) >= 3 and len(got["case"]["evidence"]) >= 5, "case has suspects and evidence")
    hint = expect("POST", f"/v1/cases/{today['id']}/hint", headers=hdr)
    check(hint and hint.get("hint"), "a hint can be bought")
    if lst["archive"]:
        old = lst["archive"][0]
        r = call("GET", f"/v1/cases/{old['id']}", headers=hdr)
        check(r and r[0].status_code in (200, 402), "archive case is gated by coins", f"{r[0].status_code}" if r else "")

    suspects = [s["id"] for s in got["case"]["suspects"]]
    evidence = [e["id"] for e in got["case"]["evidence"]]
    wrong = expect("POST", f"/v1/cases/{today['id']}/accuse", headers=hdr, json={"suspect": suspects[0], "evidence": evidence[0]}, name="POST accuse (one try)")
    check(wrong and wrong.get("result") in ("wrong_suspect", "wrong_proof", "solved"), "accusation is judged by the server", str(wrong and wrong.get("result")))
    if wrong and wrong.get("result") != "solved":
        expect("GET", f"/v1/cases/{today['id']}/stats", status=409, headers=hdr, name="others' guesses stay hidden until you finish")
    if a.solve:
        f = next((p for p in CASES.glob("*.json") if json.loads(p.read_text(encoding="utf-8"))["id"] == today["id"]), None)
        if f:
            sol = json.loads(f.read_text(encoding="utf-8"))["solution"]
            r = expect("POST", f"/v1/cases/{today['id']}/accuse", headers=hdr, json={"suspect": sol["culprit"], "evidence": sol["proof"][0]}, name="POST accuse (right answer)")
            check(r and r.get("result") == "solved" and r.get("reward", 0) > 0, "solving pays out coins and shows the explanation", str(r and {k: r.get(k) for k in ("result", "stars", "reward", "rank")}))
            st = expect("GET", f"/v1/cases/{today['id']}/stats", headers=hdr, name="GET what others thought")
            check(st and st.get("players", 0) >= 1 and len(st.get("suspects", [])) == len(suspects), "stats cover every suspect")

    print("\nQuick riddles")
    rd = expect("GET", "/v1/riddles", headers=hdr)
    items = (rd or {}).get("items", [])
    check(len(items) >= 3 and all(i.get("answer") is None for i in items), "today's riddles, answers hidden", f"{len(items)} riddles")
    free = next((i for i in items if not i.get("locked") and not i.get("answered")), None)
    if free:
        ans = expect("POST", f"/v1/riddles/{free['id']}/answer", headers=hdr, json={"choice": 0, "seconds": 20})
        check(ans and ans.get("explain") and ans.get("answer") in (0, 1, 2), "a riddle is judged by the server and explained")

    print("\nDaily missions")
    ms = expect("GET", "/v1/missions", headers=hdr)
    check(ms and len(ms.get("missions", [])) == 3, "three daily missions", ", ".join(m["title"] for m in (ms or {}).get("missions", [])))
    early = call("POST", "/v1/missions/claim", headers=hdr)
    check(early and early[0].status_code in (200, 409), "the chest opens only when all missions are done")

    print("\nEconomy, social")
    lb = expect("GET", "/v1/leaderboard?period=daily", headers=hdr)
    check(lb is not None and "me" in lb, "daily leaderboard")
    expect("GET", "/v1/leaderboard?period=weekly", headers=hdr, name="GET leaderboard weekly")
    expect("GET", "/v1/leaderboard?period=all", headers=hdr, name="GET leaderboard all-time")
    ad = call("POST", "/v1/wallet/ad-reward", headers=hdr)
    check(ad and ad[0].status_code in (200, 403), "rewarded ads: pay coins, or switched off until real ads exist",
          f"{ad[0].status_code}" if ad else "")
    fr = call("POST", "/v1/wallet/streak-freeze", headers=hdr)
    check(fr and (fr[0].status_code == 200 or (fr[0].status_code == 402 and "not_enough_coins" in fr[0].text)),
          "streak insurance: bought, or refused for lack of coins", f"{fr[0].status_code}" if fr else "")
    expect("GET", "/v1/inbox", headers=hdr)
    code = expect("POST", "/v1/auth/transfer-code", headers=hdr)
    check(code and code.get("code"), "transfer code for moving to a new phone")
    expect("POST", "/v1/events", headers=hdr, json={"events": [{"name": "smoke_test", "props": {"ok": 1}}]}, name="POST analytics events")

    adm = os.environ.get("ADMIN_API_KEY")
    if adm:
        print("\nAdmin")
        ah = {"X-Admin-Key": adm}
        st = expect("GET", "/admin/stats", headers=ah)
        check(st and st.get("cases_written", 0) >= 50, "admin sees the 50 cases", str(st and st.get("cases_written")))
        expect("GET", "/admin/cases", headers=ah)
    expect("GET", "/admin/stats", status=403, name="admin calls without the key are refused")

    bad = [r for r in results if not r[0]]
    print(f"\n{len(results) - len(bad)} of {len(results)} checks passed.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
