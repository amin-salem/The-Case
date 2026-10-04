"""Database connection (SQLAlchemy 2, async)."""
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from .config import get_settings


class Base(DeclarativeBase):
    pass


def _make_engine(url: str):
    kwargs = {"pool_pre_ping": True}
    if url.startswith("sqlite"):
        kwargs = {"connect_args": {"check_same_thread": False}}
    return create_async_engine(url, **kwargs)


engine = _make_engine(get_settings().database_url)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


def configure(url: str) -> None:
    """Point the app at another database (used by tests)."""
    global engine, SessionLocal
    engine = _make_engine(url)
    SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def create_tables() -> None:
    from . import models  # noqa: F401  (registers the tables)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
