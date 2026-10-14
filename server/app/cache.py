"""Small per-worker caches for data that is the SAME for every player and read on every app start.

Rules (docs/operations.md «Capacity»):
- Only shared, non-secret data goes in here. Never per-player data, never a case solution.
- Every cache is bounded (max_size) and every entry expires (ttl seconds, monotonic clock).
- An entry may also carry a `valid_until` wall-clock moment (a case opens, a chapter opens, midnight): after it the
  entry is dropped even if its TTL has not run out. An entry computed "in the future" (a test or a clock change moving
  time backwards) is dropped too.
- One loader runs at a time per key (a lock), so 200 requests arriving at 21:00:00 cause ONE query, not 200.
- With W workers the data can be up to ttl seconds old in each worker; keep ttl short (10-30 s).
"""
from __future__ import annotations

import asyncio
import time
from collections import OrderedDict
from typing import Any, Awaitable, Callable

ENABLED = True  # tests flip this to compare cached and uncached behaviour
_all: list["TTLCache"] = []


class TTLCache:
    def __init__(self, name: str, ttl: float, max_size: int = 64):
        self.name, self.ttl, self.max_size = name, ttl, max_size
        self.clock: Callable[[], float] = time.monotonic
        self._d: OrderedDict[Any, tuple[float, Any, Any, Any]] = OrderedDict()  # key -> (expires, value, valid_from, valid_until)
        self._locks: dict[Any, asyncio.Lock] = {}
        self.hits = self.misses = 0
        _all.append(self)

    def clear(self) -> None:
        self._d.clear()

    def _get(self, key, now_wall):
        e = self._d.get(key)
        if e is None:
            return None
        expires, value, vfrom, vuntil = e
        if self.clock() >= expires or (vfrom is not None and now_wall is not None and now_wall < vfrom) \
                or (vuntil is not None and now_wall is not None and now_wall >= vuntil):
            self._d.pop(key, None)
            return None
        self._d.move_to_end(key)
        return e

    def _put(self, key, value, now_wall, valid_until) -> None:
        self._d[key] = (self.clock() + self.ttl, value, now_wall if valid_until is not None else None, valid_until)
        self._d.move_to_end(key)
        while len(self._d) > self.max_size:
            self._d.popitem(last=False)

    def get_sync(self, key, now_wall=None):
        e = self._get(key, now_wall) if ENABLED else None
        return e[1] if e else None

    def put_sync(self, key, value, now_wall=None, valid_until=None) -> None:
        if ENABLED:
            self._put(key, value, now_wall, valid_until)

    async def get_or_load(self, key, loader: Callable[[], Awaitable[Any]], now_wall=None, valid_until_of=None):
        """Cached value, or loader() once (concurrent callers wait for it). valid_until_of(value) -> wall-clock moment."""
        if not ENABLED:
            return await loader()
        e = self._get(key, now_wall)
        if e is not None:
            self.hits += 1
            return e[1]
        lock = self._locks.setdefault(key, asyncio.Lock())
        async with lock:
            e = self._get(key, now_wall)
            if e is not None:
                self.hits += 1
                return e[1]
            self.misses += 1
            value = await loader()
            self._put(key, value, now_wall, valid_until_of(value) if valid_until_of else None)
        if len(self._locks) > self.max_size * 2:
            self._locks = {k: l for k, l in self._locks.items() if l.locked()}
        return value


def clear_all() -> None:
    for c in _all:
        c.clear()


def stats() -> list[dict]:
    return [{"name": c.name, "size": len(c._d), "hits": c.hits, "misses": c.misses} for c in _all]
