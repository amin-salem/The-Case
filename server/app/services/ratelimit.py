"""A small in-memory rate limit per IP (protects login/register from spam).

Good enough for one server process. If you run several processes or
servers, put the limit in nginx/Caddy or use Redis instead.
"""
import time
from collections import defaultdict, deque

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

# path prefix -> (max requests, per seconds)
LIMITS = {
    "/v1/auth/register": (10, 3600),
    "/v1/auth/login": (60, 600),
    "/v1/auth/transfer": (10, 600),
    "/v1/referrals": (10, 600),
    "/v1/auth/email": (20, 600),
    "/v1/": (600, 60),
}


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.hits: dict[tuple[str, str], deque] = defaultdict(deque)
        self.last_cleanup = time.monotonic()

    def _rule(self, path: str):
        for prefix, rule in LIMITS.items():
            if path.startswith(prefix):
                return prefix, rule
        return None, None

    async def dispatch(self, request: Request, call_next):
        from ..config import get_settings

        prefix, rule = self._rule(request.url.path)
        if rule is not None and get_settings().rate_limit:
            ip = request.headers.get("x-real-ip") or (request.client.host if request.client else "?")
            limit, window = rule
            now = time.monotonic()
            q = self.hits[(ip, prefix)]
            while q and q[0] < now - window:
                q.popleft()
            if len(q) >= limit:
                return JSONResponse({"detail": "too_many_requests"}, status_code=429,
                                    headers={"Retry-After": str(int(window - (now - q[0])) + 1)})
            q.append(now)
            if now - self.last_cleanup > 300:
                self.last_cleanup = now
                for k in [k for k, v in self.hits.items() if not v or v[-1] < now - 3600]:
                    del self.hits[k]
        return await call_next(request)
