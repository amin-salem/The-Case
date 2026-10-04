# Builds the game server (server/ folder) - used by Liara's GitHub deploy.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/srv PORT=3000
WORKDIR /srv

COPY server/requirements.txt .
RUN pip install --no-cache-dir --timeout 120 --retries 10 -r requirements.txt

COPY server/app ./app
COPY server/alembic ./alembic
COPY server/alembic.ini server/start.sh ./

RUN useradd --create-home appuser
USER appuser

EXPOSE 3000
# start.sh: "alembic upgrade head" (creates/updates tables), then the API on $PORT
CMD ["sh", "./start.sh"]
