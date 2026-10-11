#!/bin/sh
# The client IP is worked out by app/services/ratelimit.py (uvicorn's own proxy-header
# handling with '*' trusts the client-written left end of X-Forwarded-For, so it is off).
# Container start: update the database tables, then start the API.
set -e
alembic upgrade head
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}" \
  --workers "${WEB_CONCURRENCY:-2}" --no-proxy-headers
