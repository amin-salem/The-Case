#!/usr/bin/env python3
"""Load test: N virtual players open the app the way real players do at 21:00, when the nightly case opens.

    python tools/load_test.py http://127.0.0.1:8000 -n 50                  # a local server (rate limits off: RATE_LIMIT=false)
    python tools/load_test.py https://gaamly.ir -n 200 --admin-key KEY       # from Iran, see docs/operations.md «Capacity»
    python tools/load_test.py https://gaamly.ir -n 1000 --burst --admin-key KEY

What every player does (about 15 requests, the same order as the app): GET /v1/config, GET /v1/me, GET /v1/cases,
GET /v1/cases/<today>, GET /v1/missions, GET /v1/feed, POST /v1/me/client, a few POST .../seen and .../tick, and for some of
them one accusation with a wrong suspect (it costs one try, nothing else). Players start spread over --ramp seconds, or all
within 20 s with --burst.

Accounts: the test players have device ids «smoke-load-<run>-<n>». Without --admin-key each one registers itself (POST
/v1/auth/register); the server allows only a few registrations per IP and day, so against a real server pass --admin-key
(or set ADMIN_API_KEY): the accounts are then made with POST /admin/players/smoke-bulk. At the end every player deletes itself
(DELETE /v1/me/smoke); the admin call POST /admin/players/purge-smoke removes anything left over.

Output: requests, errors by status (429 and 5xx matter most), p50/p95/p99 latency (overall and per endpoint), requests per
second, and a verdict. Exit code 1 means 5xx answers or lost connections.
Do not run it against the live server from a machine outside Iran (the route is unreliable and a flood disturbs real players).
"""
from __future__ import annotations

import argparse
import asyncio
import math
import os
import random
import sys
import time
import uuid
from collections import Counter, defaultdict

import httpx

MAX_PLAYERS = 5000
P95_OK_MS = 1000


def percentile(sorted_ms: list[float], p: float) -> float:
    """Nearest-rank percentile of an already sorted list (0 for an empty list)."""
    if not sorted_ms:
        return 0.0
    k = max(0, min(len(sorted_ms) - 1, math.ceil(p * len(sorted_ms) / 100) - 1))
    return sorted_ms[k]


class Stats:
    def __init__(self):
        self.rows: list[tuple[str, str, float]] = []  # (endpoint, status, ms)

    def add(self, name: str, status: str, ms: float) -> None:
        self.rows.append((name, status, ms))

    def summary(self, seconds: float) -> dict:
        ms = sorted(r[2] for r in self.rows)
        by_status = Counter(r[1] for r in self.rows)
        per: dict[str, list[float]] = defaultdict(list)
        for name, _, t in self.rows:
            per[name].append(t)
        errors5xx = sum(n for s, n in by_status.items() if s.startswith("5"))
        lost = sum(n for s, n in by_status.items() if s.startswith("ERR"))
        return {"requests": len(self.rows), "seconds": seconds, "rps": len(self.rows) / seconds if seconds > 0 else 0.0,
                "by_status": dict(sorted(by_status.items())), "p50": percentile(ms, 50), "p95": percentile(ms, 95),
                "p99": percentile(ms, 99), "max": ms[-1] if ms else 0.0, "5xx": errors5xx, "lost": lost,
                "429": by_status.get("429", 0),
                "per_endpoint": {k: (len(v), percentile(sorted(v), 50), percentile(sorted(v), 95), percentile(sorted(v), 99))
                                 for k, v in sorted(per.items())}}


def report(s: dict, players: int, failed_players: int) -> str:
    out = [f"\nPlayers: {players} ({failed_players} could not start)   Requests: {s['requests']}   Time: {s['seconds']:.1f} s   "
           f"Requests/second: {s['rps']:.1f}",
           "Answers by status: " + ", ".join(f"{k}: {v}" for k, v in s["by_status"].items()),
           f"Latency ms (all): p50 {s['p50']:.0f}   p95 {s['p95']:.0f}   p99 {s['p99']:.0f}   max {s['max']:.0f}",
           "", f"{'endpoint':32s}{'count':>7s}{'p50':>8s}{'p95':>8s}{'p99':>8s}"]
    for name, (n, p50, p95, p99) in s["per_endpoint"].items():
        out.append(f"{name:32s}{n:7d}{p50:8.0f}{p95:8.0f}{p99:8.0f}")
    problems = []
    if s["5xx"]:
        problems.append(f"{s['5xx']} server errors (5xx)")
    if s["lost"]:
        problems.append(f"{s['lost']} lost connections or timeouts")
    if s["429"]:
        problems.append(f"{s['429']} rate-limited answers (429): a limit is too tight for this pattern, or the test comes from one IP")
    if s["p95"] > P95_OK_MS:
        problems.append(f"p95 is {s['p95']:.0f} ms (goal: under {P95_OK_MS} ms)")
    out.append("")
    out.append("VERDICT: OK (no 5xx, no lost connections, p95 under 1 s)" if not problems else "VERDICT: look at -> " + "; ".join(problems))
    return "\n".join(out)


class Player:
    def __init__(self, n: int, run: str, client: httpx.AsyncClient, stats: Stats, sem: asyncio.Semaphore, rnd: random.Random,
                 think: float, token: str | None = None):
        self.n, self.client, self.stats, self.sem, self.rnd, self.think = n, client, stats, sem, rnd, think
        self.device = f"smoke-load-{run}-{n}"
        self.token = token
        self.hdr: dict = {"Authorization": f"Bearer {token}"} if token else {}

    async def call(self, method: str, path: str, name: str | None = None, record: bool = True, **kw):
        label = name or f"{method} {path}"
        async with self.sem:
            t = time.perf_counter()
            try:
                r = await self.client.request(method, path, headers=self.hdr, **kw)
                status = str(r.status_code)
            except Exception as e:  # noqa: BLE001 - a lost connection or timeout is a result, not a crash
                r, status = None, "ERR:" + type(e).__name__
            ms = (time.perf_counter() - t) * 1000
        if record:
            self.stats.add(label, status, ms)
        return r

    async def pause(self):
        await asyncio.sleep(self.rnd.uniform(0.3, 1.0) * self.think)

    async def register(self) -> bool:
        r = await self.call("POST", "/v1/auth/register", json={"device_id": self.device, "app_version": 1})
        if r is None or r.status_code != 200:
            return False
        self.token = r.json()["token"]
        self.hdr = {"Authorization": f"Bearer {self.token}"}
        return True

    async def open_app(self) -> None:
        """What the app does when it starts, then a short play session."""
        await self.call("GET", "/v1/config")
        await self.pause()
        await self.call("GET", "/v1/me")
        r = await self.call("GET", "/v1/cases")
        today = None
        if r is not None and r.status_code == 200:
            today = (r.json().get("today") or {}).get("id")
        await self.call("GET", "/v1/missions")
        await self.call("GET", "/v1/feed")
        await self.call("POST", "/v1/me/client", json={"app_version": "1.0.0", "build": 1, "platform": "android",
                                                        "os_version": "13", "device_model": "load-test"})
        if not today:
            return
        await self.pause()
        r = await self.call("GET", f"/v1/cases/{today}", name="GET /v1/cases/<today>")
        if r is None or r.status_code != 200:
            return
        suspects = [s["id"] for s in (r.json().get("case") or {}).get("suspects", [])]
        for sid in suspects[: self.rnd.randint(1, 3)]:
            await self.pause()
            await self.call("POST", f"/v1/cases/{today}/seen", name="POST /v1/cases/<today>/seen", json={"suspect": sid})
        await self.call("POST", f"/v1/cases/{today}/tick", name="POST /v1/cases/<today>/tick", json={"seconds": 30})
        if self.rnd.random() < 0.4:
            await self.pause()
            # a suspect id that does not exist is a wrong accusation that can never solve the case
            await self.call("POST", f"/v1/cases/{today}/accuse", name="POST /v1/cases/<today>/accuse",
                            json={"suspect": "zzz", "evidence": "", "extra_seconds": 0})
        await self.call("GET", "/v1/me", name="GET /v1/me (again)")

    async def cleanup(self) -> bool:
        r = await self.call("DELETE", "/v1/me/smoke", name="cleanup", record=False)
        return r is not None and r.status_code == 200


async def make_tokens(client: httpx.AsyncClient, n: int, admin_key: str) -> list[str]:
    """Accounts made by the admin call, in chunks of 500 (they are «smoke-» players, purge-smoke removes them)."""
    out: list[str] = []
    while len(out) < n:
        r = await client.post("/admin/players/smoke-bulk", headers={"X-Admin-Key": admin_key}, json={"n": min(500, n - len(out))})
        if r.status_code != 200:
            raise SystemExit(f"Could not make the test accounts: HTTP {r.status_code} {r.text[:200]}")
        out += [p["token"] for p in r.json()["players"]]
    return out


async def run(base: str, players: int = 200, ramp: float = 60.0, burst: bool = False, admin_key: str = "", timeout: float = 30.0,
              concurrency: int = 150, think: float = 0.5, seed: int | None = None, keep: bool = False,
              transport: httpx.AsyncBaseTransport | None = None) -> tuple[dict, int]:
    """Runs the test; returns (summary, players that could not start). `transport` lets the tests run it in-process."""
    if burst:
        ramp = min(ramp, 20.0)
    rnd = random.Random(seed)
    run_id = uuid.uuid4().hex[:6]
    stats = Stats()
    sem = asyncio.Semaphore(concurrency)
    limits = httpx.Limits(max_connections=concurrency, max_keepalive_connections=concurrency)
    async with httpx.AsyncClient(base_url=base.rstrip("/"), timeout=timeout, limits=limits, transport=transport) as client:
        tokens: list[str | None] = [None] * players
        if admin_key:
            tokens = list(await make_tokens(client, players, admin_key))
        started = [0]
        failed = [0]
        deleted = [0]

        async def one(i: int):
            await asyncio.sleep(ramp * i / max(1, players) if players > 1 else 0)
            p = Player(i, run_id, client, stats, sem, random.Random(rnd.random()), think, tokens[i])
            if not p.token and not await p.register():
                failed[0] += 1
                return
            started[0] += 1
            try:
                await p.open_app()
            finally:
                if not keep and await p.cleanup():
                    deleted[0] += 1

        t0 = time.perf_counter()
        await asyncio.gather(*(one(i) for i in range(players)))
        seconds = time.perf_counter() - t0
        if admin_key and not keep:
            r = await client.post("/admin/players/purge-smoke", headers={"X-Admin-Key": admin_key})  # anything left over
            if r.status_code == 200 and r.json().get("more"):
                print("Note: more «smoke-» players are left; call POST /admin/players/purge-smoke again.")
    summary = stats.summary(seconds)
    summary["started"], summary["deleted"] = started[0], deleted[0]
    return summary, failed[0]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("base", nargs="?", default=os.environ.get("API_URL", "http://127.0.0.1:8000"))
    ap.add_argument("-n", "--players", type=int, default=200)
    ap.add_argument("--ramp", type=float, default=60.0, help="players start spread over this many seconds (default 60)")
    ap.add_argument("--burst", action="store_true", help="everyone starts within 20 seconds (the 21:00 rush)")
    ap.add_argument("--admin-key", default=os.environ.get("ADMIN_API_KEY", ""), help="make the accounts through the admin API")
    ap.add_argument("--timeout", type=float, default=30.0)
    ap.add_argument("--concurrency", type=int, default=150, help="most requests in flight at once from this computer")
    ap.add_argument("--think", type=float, default=0.5, help="average pause between a player's requests, seconds")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--keep", action="store_true", help="do not delete the test players at the end")
    a = ap.parse_args()
    if not 1 <= a.players <= MAX_PLAYERS:
        print(f"-n must be between 1 and {MAX_PLAYERS}")
        return 2
    mode = "burst (all within 20 s)" if a.burst else f"ramp over {a.ramp:.0f} s"
    print(f"Server: {a.base}   players: {a.players}   {mode}   accounts: {'admin bulk' if a.admin_key else 'register'}")
    summary, failed = asyncio.run(run(a.base, a.players, a.ramp, a.burst, a.admin_key, a.timeout, a.concurrency, a.think,
                                      a.seed, a.keep))
    print(report(summary, a.players, failed))
    print(f"Test players deleted at the end: {summary['deleted']} of {summary['started']}")
    return 1 if (summary["5xx"] or summary["lost"] or failed == a.players) else 0


if __name__ == "__main__":
    sys.exit(main())
