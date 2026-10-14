import os
import tempfile

_tmp = tempfile.mkdtemp()
os.environ.update({
    "ENV": "dev",
    "DATABASE_URL": f"sqlite+aiosqlite:///{_tmp}/test.db",
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


async def new_player(client, device="device-1234", aged=True):
    """Registers a player. By default the account is made 100 hours old, so it is not hidden from the leaderboards
    (new unsecured accounts are hidden for 48 hours); pass aged=False for a really new account."""
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

    session_loop = pytest.mark.asyncio(loop_scope="session")
    for item in items:
        if inspect.iscoroutinefunction(getattr(item, "obj", None)):
            item.add_marker(session_loop, append=False)
