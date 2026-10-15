"""A small meter of what ONE worker process is doing, so a load test shows where the time goes (docs/operations.md «Capacity»).

Every second a sampler records: how late the event loop woke up (lag), how much CPU this process used, how many database
connections are checked out, and how many requests are in flight. A tiny ASGI middleware counts requests and 5xx answers.
When the worker is busy, one WARNING line is logged at most every 10 s (no personal data); the last minute is also readable
at GET /admin/api/runtime. Nothing here touches the database, and a failure in the meter never breaks a request.
"""
import asyncio
import logging
import os
import time
from collections import deque

log = logging.getLogger("runtime")

WINDOW = 60              # samples kept (one per second)
LOG_EVERY = 10           # seconds between "busy" log lines
BUSY_CPU = 0.70          # a worker using 70 % of a core is busy
BUSY_LAG_MS = 200        # the event loop woke up 200 ms late
BUSY_INFLIGHT = 50       # requests in flight at once


class RuntimeStats:
    def __init__(self, clock=time.monotonic, cpu=time.process_time):
        self.clock = clock
        self.cpu = cpu
        self.inflight = 0
        self.requests = 0
        self.errors_5xx = 0
        self.samples: deque[dict] = deque(maxlen=WINDOW)
        self._last_wall = clock()
        self._last_cpu = cpu()
        self._last_log = -1e9

    # -- requests
    def request_started(self) -> None:
        self.inflight += 1
        self.requests += 1

    def request_finished(self, status: int) -> None:
        self.inflight = max(0, self.inflight - 1)
        if status >= 500:
            self.errors_5xx += 1

    # -- the sampler
    def sample(self, lag_s: float, pool: dict | None = None) -> dict:
        wall, cpu = self.clock(), self.cpu()
        dt = wall - self._last_wall
        cpu_frac = ((cpu - self._last_cpu) / dt) if dt > 0 else 0.0
        self._last_wall, self._last_cpu = wall, cpu
        pool = pool or {}
        s = {"t": wall, "lag_ms": max(0.0, lag_s) * 1000.0, "cpu": max(0.0, cpu_frac), "inflight": self.inflight,
             "pool_out": int(pool.get("out", 0)), "pool_max": int(pool.get("max", 0)),
             "requests": self.requests, "errors_5xx": self.errors_5xx}
        self.samples.append(s)
        return s

    @staticmethod
    def is_busy(s: dict) -> bool:
        pool_full = s["pool_max"] > 0 and s["pool_out"] >= s["pool_max"]
        return bool(s["cpu"] >= BUSY_CPU or s["lag_ms"] >= BUSY_LAG_MS or s["inflight"] >= BUSY_INFLIGHT or pool_full)

    def should_log(self, s: dict) -> bool:
        if not self.is_busy(s) or s["t"] - self._last_log < LOG_EVERY:
            return False
        self._last_log = s["t"]
        return True

    def log_line(self, s: dict) -> str:
        return ("runtime busy pid=%d cpu=%.0f%% lag_ms=%d pool=%d/%d inflight=%d requests=%d errors_5xx=%d"
                % (os.getpid(), s["cpu"] * 100, s["lag_ms"], s["pool_out"], s["pool_max"], s["inflight"], s["requests"],
                   s["errors_5xx"]))

    # -- what the admin call shows
    def snapshot(self) -> dict:
        rows = list(self.samples)
        out = {"pid": os.getpid(), "seconds": 0, "requests_total": self.requests, "errors_5xx_total": self.errors_5xx,
               "inflight_now": self.inflight}
        if not rows:
            return out
        span = rows[-1]["t"] - rows[0]["t"]
        out.update({
            "seconds": len(rows),
            "cpu_avg_percent": round(100 * sum(r["cpu"] for r in rows) / len(rows), 1),
            "cpu_max_percent": round(100 * max(r["cpu"] for r in rows), 1),
            "lag_max_ms": round(max(r["lag_ms"] for r in rows)),
            "lag_avg_ms": round(sum(r["lag_ms"] for r in rows) / len(rows)),
            "inflight_max": max(r["inflight"] for r in rows),
            "pool_out_max": max(r["pool_out"] for r in rows),
            "pool_limit": rows[-1]["pool_max"],
            "requests_per_second": round((rows[-1]["requests"] - rows[0]["requests"]) / span, 1) if span > 0 else 0.0,
            "errors_5xx_window": rows[-1]["errors_5xx"] - rows[0]["errors_5xx"]})
        return out


STATS = RuntimeStats()


def pool_state() -> dict:
    """Checked-out connections and the pool limit (size + overflow); empty if this pool cannot say."""
    try:
        from .. import db
        p = db.engine.pool
        return {"out": p.checkedout(), "max": p.size() + max(0, getattr(p, "_max_overflow", 0))}
    except Exception:
        return {}


async def sampler(stats: RuntimeStats = STATS, interval: float = 1.0) -> None:
    """Runs for the life of the worker (started in the lifespan). Never raises."""
    while True:
        try:
            t0 = time.monotonic()
            await asyncio.sleep(interval)
            s = stats.sample(time.monotonic() - t0 - interval, pool_state())
            if stats.should_log(s):
                log.warning(stats.log_line(s))
        except asyncio.CancelledError:
            raise
        except Exception as e:  # the meter must never take the worker down
            log.warning("runtime sampler error: %s", type(e).__name__)
            await asyncio.sleep(interval)


class StatsMiddleware:
    """Pure ASGI: counts requests in flight and 5xx answers (an unhandled error counts as 500)."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        STATS.request_started()
        status = [500]

        async def send_status(message):
            if message["type"] == "http.response.start":
                status[0] = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, send_status)
        finally:
            STATS.request_finished(status[0])
