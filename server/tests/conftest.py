import os
import tempfile

_tmp = tempfile.mkdtemp()
os.environ.update({
    "ENV": "dev",
    "DATABASE_URL": f"sqlite+aiosqlite:///{_tmp}/test.db",
    "BAZAAR_MODE": "fake",
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


async def new_player(client, device="device-1234"):
    r = await client.post("/v1/auth/register", json={"device_id": device, "app_version": 1})
    assert r.status_code == 200, r.text
    body = r.json()
    body["headers"] = {"Authorization": f"Bearer {body['token']}"}
    return body


def pytest_collection_modifyitems(items):
    import inspect

    session_loop = pytest.mark.asyncio(loop_scope="session")
    for item in items:
        if inspect.iscoroutinefunction(getattr(item, "obj", None)):
            item.add_marker(session_loop, append=False)
