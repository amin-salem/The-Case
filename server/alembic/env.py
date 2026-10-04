"""Alembic migrations (database schema changes) for production.

    alembic upgrade head                      # apply all changes
    alembic revision --autogenerate -m "..."  # after you change app/models.py
"""
import asyncio

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from app import models  # noqa: F401  (registers the tables)
from app.config import get_settings
from app.db import Base

target_metadata = Base.metadata
URL = get_settings().database_url


def run_offline() -> None:
    context.configure(url=URL, target_metadata=target_metadata, literal_binds=True,
                      render_as_batch=URL.startswith("sqlite"))
    with context.begin_transaction():
        context.run_migrations()


def _run(connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata,
                      render_as_batch=URL.startswith("sqlite"))
    with context.begin_transaction():
        context.run_migrations()


async def run_online() -> None:
    engine = create_async_engine(URL)
    async with engine.connect() as conn:
        await conn.run_sync(_run)
    await engine.dispose()


if context.is_offline_mode():
    run_offline()
else:
    asyncio.run(run_online())
