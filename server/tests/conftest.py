import os
import tempfile

_tmp = tempfile.mkdtemp()
# The whole suite runs on SQLite (default) and, in CI job «server-postgres», on PostgreSQL: set TEST_DATABASE_URL to an
# empty isolated database (postgresql+asyncpg://...) and TEST_AUX_DATABASE_URL to a second one for private-database tests.
# PostgreSQL is what Liara runs, so a query SQLite accepts but PostgreSQL refuses (28 Oct 2026: GROUP BY on a bound
# expression, a 500 for every new account) must fail in CI. Never point these at a real database: both are wiped.
TEST_DB_URL = os.environ.get("TEST_DATABASE_URL", "")
TEST_AUX_URL = os.environ.get("TEST_AUX_DATABASE_URL", "")
ON_POSTGRES = TEST_DB_URL.startswith("postgresql")
os.environ.update({
    "ENV": "dev",
    "DATABASE_URL": TEST_DB_URL if ON_POSTGRES else f"sqlite+aiosqlite:///{_tmp}/test.db",
    "BAZAAR_MODE": "fake",
    "EMAIL_SIGNUP_ENABLED": "true",  # old tests secure accounts with email; test_phone.py checks the closed switch
    "RATE_LIMIT": "false",
    "ADS_ENABLED": "true",
    "ADMIN_API_KEY": "test-admin-key",
    "JWT_SECRET": "test-secret-that-is-long-enough-123456",
})

import httpx  # noqa: E402
import pytest  # noqa: E402

from app import db  # noqa: E402
from app.main import app  # noqa: E402

ADMIN = {"X-Admin-Key": "test-admin-key"}


@pytest.fixture(scope="session", autouse=True)
async def _tables():
    if ON_POSTGRES:
        assert TEST_DB_URL.rsplit("/", 1)[-1].endswith("_test"), "TEST_DATABASE_URL must name a database ending in _test"
        from app import models  # noqa: F401
        async with db.engine.begin() as conn:
            await conn.run_sync(db.Base.metadata.drop_all)
    await db.create_tables()
    yield
    await db.engine.dispose()


@pytest.fixture
async def client():
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture(autouse=True)
def _fresh_caches():
    """The per-worker caches (app/cache.py) start empty in every test, so no test sees another test's data."""
    from app import cache
    cache.clear_all()
    yield


@pytest.fixture(autouse=True)
def _no_proof_requirement(monkeypatch):
    """Most tests solve a case at once: switch the proof-of-investigation rule off here.
    tests/test_anticheat.py turns it back on for the tests about it."""
    from app import economy
    monkeypatch.setattr(economy, "MIN_ACTIVE_SECONDS", 0)
    monkeypatch.setattr(economy, "MIN_SUSPECTS_SEEN", 0)


async def private_engine(tmp_path, name: str):
    """A private, empty database for service tests (SQLite file, or the auxiliary PostgreSQL database in the Postgres job),
    so rows made by other tests never leak into the numbers. The caller disposes the engine."""
    from sqlalchemy.ext.asyncio import create_async_engine
    from app import models  # noqa: F401
    if ON_POSTGRES:
        assert TEST_AUX_URL.rsplit("/", 1)[-1].endswith("_test"), "TEST_AUX_DATABASE_URL must name a database ending in _test"
        engine = create_async_engine(TEST_AUX_URL)
        async with engine.begin() as conn:
            await conn.run_sync(db.Base.metadata.drop_all)
    else:
        engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path}/{name}.db")
    async with engine.begin() as conn:
        await conn.run_sync(db.Base.metadata.create_all)
    return engine


async def new_player(client, device="device-1234", aged=False):
    """Registers a player like a real new one: created just now, a guest (no email, no phone). The first days have their
    own rules (hidden from the leaderboards for 48 hours, first-days prices for 3 days, young-account limits), so tests
    that are about something else and need the normal rules pass aged=True: the account is then made 100 hours old."""
    r = await client.post("/v1/auth/register", json={"device_id": device, "app_version": 1})
    assert r.status_code == 200, r.text
    body = r.json()
    if aged:
        from datetime import timedelta
        from sqlalchemy import update
        from app.models import Player, utcnow
        async with db.SessionLocal() as s:
            await s.execute(update(Player).where(Player.id == body["player_id"]).values(
                created_at=utcnow() - timedelta(hours=100)))
            await s.commit()
    body["headers"] = {"Authorization": f"Bearer {body['token']}"}
    return body


def pytest_collection_modifyitems(items):
    import inspect

    if ON_POSTGRES:
        skip = pytest.mark.skip(reason="SQLite only (see docs/operations.md, «Tests on PostgreSQL»)")
        for item in items:
            if item.get_closest_marker("sqlite_only"):
                item.add_marker(skip)

    session_loop = pytest.mark.asyncio(loop_scope="session")
    for item in items:
        if inspect.iscoroutinefunction(getattr(item, "obj", None)):
            item.add_marker(session_loop, append=False)
