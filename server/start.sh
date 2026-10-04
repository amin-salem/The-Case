#!/bin/sh
# Container start: update the database tables, then start the API.
set -e
alembic upgrade head
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}" \
  --workers "${WEB_CONCURRENCY:-2}" --proxy-headers --forwarded-allow-ips '*'
