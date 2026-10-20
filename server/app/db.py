"""Database connection (SQLAlchemy 2, async)."""
import os
import asyncio
from weakref import WeakKeyDictionary
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy import event
from sqlalchemy.orm import DeclarativeBase, Session

from .config import get_settings


class Base(DeclarativeBase):
    pass


def _env_int(name: str, default: int, lo: int, hi: int) -> int:
    """An integer setting from the environment, kept inside [lo, hi]; a bad value falls back to the default."""
    try:
        return max(lo, min(hi, int(os.environ.get(name, default))))
    except ValueError:
        return default


def pool_settings() -> dict:
    """Connection pool PER WORKER PROCESS (Postgres only). The total is workers x (DB_POOL_SIZE + DB_MAX_OVERFLOW) and must
    stay well under the database's connection limit (a 0.5 GB Postgres allows roughly 100, of which a few are reserved).
    Defaults: 5 + 5 = 10 per worker, 20 for two workers. A request that cannot get a connection waits DB_POOL_TIMEOUT
    seconds and then fails with a clean 5xx instead of piling up. Idle connections are recycled after DB_POOL_RECYCLE s."""
    return {"pool_size": _env_int("DB_POOL_SIZE", 5, 1, 50), "max_overflow": _env_int("DB_MAX_OVERFLOW", 5, 0, 50),
            "pool_timeout": _env_int("DB_POOL_TIMEOUT", 10, 1, 120), "pool_recycle": _env_int("DB_POOL_RECYCLE", 1800, 60, 86400),
            "pool_pre_ping": True}


def _make_engine(url: str):
    if url.startswith("sqlite"):
        return create_async_engine(url, connect_args={"check_same_thread": False})
    return create_async_engine(url, **pool_settings())


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



# SQLite is a single-process development/test backend. Do not reserve its SQL writer
# before rate-limit checks: DBStore uses a separate transaction in the same database.
# PostgreSQL correctness never depends on this process-local fallback.
_sqlite_writers = WeakKeyDictionary()


@event.listens_for(Session, "after_transaction_end")
def _release_sqlite_writer(session, transaction) -> None:
    if transaction.parent is None:
        lock = session.info.pop("wallet_sqlite_writer", None)
        if lock is not None:
            lock.release()


async def begin_write(session: AsyncSession) -> None:
    """Serialize SQLite game transactions without blocking independent rate-limit writes.

    Released by commit/rollback/close, including error paths. PostgreSQL uses row locks.
    """
    bind = session.get_bind()
    if bind.dialect.name != "sqlite" or "wallet_sqlite_writer" in session.info:
        return
    lock = _sqlite_writers.setdefault(bind, asyncio.Lock())
    await lock.acquire()
    try:
        if not session.in_transaction():
            await session.begin()
        session.info["wallet_sqlite_writer"] = lock
    except BaseException:
        lock.release()
        raise


async def lock_players(session: AsyncSession, ids: list[str]) -> dict:
    """Lock accounts in deterministic order and refresh any already-loaded ORM state.

    Caller owns the transaction. Reacquire after any intermediate commit before more mutations.
    Multi-account jobs must acquire the complete set at once (never actor then inviter).
    """
    from sqlalchemy import select
    from .models import Player
    await begin_write(session)
    rows = (await session.scalars(select(Player).where(Player.id.in_(ids)).order_by(Player.id)
                                  .with_for_update().execution_options(populate_existing=True))).all()
    return {p.id: p for p in rows}
