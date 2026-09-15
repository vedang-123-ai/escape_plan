"""S8.1 — the MongoDB connection lifecycle.

No real database and no mocking library. `mongomock` has no Python 3.13 support
and no async support, and `mongomock-motor` would pull the end-of-life Motor
driver back into the tree just for tests — so the stub below implements only the
handful of operations `Database` actually performs. Tests needing a real server
are marked `mongo` and excluded by default (see pytest.ini).
"""

from __future__ import annotations

import pytest

from app.config import get_settings
from app.database import CloudSyncDisabled, Database


class StubAdmin:
    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.commands: list[str] = []

    async def command(self, name: str):
        self.commands.append(name)
        if self.fail:
            raise RuntimeError("no server reachable")
        return {"ok": 1}


class StubClient:
    """Implements exactly what Database touches: __getitem__, admin, close."""

    def __init__(self, uri: str, fail_ping: bool = False) -> None:
        self.uri = uri
        self.admin = StubAdmin(fail=fail_ping)
        self.closed = False
        self.databases: list[str] = []

    def __getitem__(self, name: str):
        self.databases.append(name)
        return {"__name__": name}

    async def close(self) -> None:
        self.closed = True


@pytest.fixture(autouse=True)
def _clear_settings_cache():
    """get_settings is lru_cached; env changes are invisible without this."""
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
def configured(monkeypatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", "test-token")
    monkeypatch.setenv("MONGODB_URI", "mongodb://stub:27017")
    monkeypatch.setenv("MONGODB_DB_NAME", "escape_plan_test")
    get_settings.cache_clear()


@pytest.fixture
def unconfigured(monkeypatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", "test-token")
    monkeypatch.delenv("MONGODB_URI", raising=False)
    get_settings.cache_clear()


class TestDisabled:
    """An unset MONGODB_URI must degrade, never crash — the pre-S8 backend and
    the demo path have no database and must keep working."""

    @pytest.mark.anyio
    async def test_connect_without_uri_is_a_noop(self, unconfigured):
        db = Database()
        await db.connect()
        assert db.enabled is False

    @pytest.mark.anyio
    async def test_status_reports_disabled(self, unconfigured):
        db = Database()
        await db.connect()
        assert await db.status() == "disabled"

    @pytest.mark.anyio
    async def test_db_access_raises_a_named_error(self, unconfigured):
        """Not None — a None handle would surface as an AttributeError far from
        the actual cause."""
        db = Database()
        await db.connect()
        with pytest.raises(CloudSyncDisabled):
            _ = db.db

    @pytest.mark.anyio
    async def test_close_without_connect_is_safe(self, unconfigured):
        db = Database()
        await db.close()  # must not raise


class TestConnected:
    @pytest.mark.anyio
    async def test_connect_uses_the_configured_uri_and_db_name(self, configured):
        created: list[StubClient] = []

        def factory(uri: str):
            client = StubClient(uri)
            created.append(client)
            return client

        db = Database()
        await db.connect(client_factory=factory)

        assert db.enabled is True
        assert created[0].uri == "mongodb://stub:27017"
        assert created[0].databases == ["escape_plan_test"]

    @pytest.mark.anyio
    async def test_status_ok_pings_the_server(self, configured):
        client = StubClient("mongodb://stub:27017")
        db = Database()
        await db.connect(client_factory=lambda _uri: client)

        assert await db.status() == "ok"
        assert client.admin.commands == ["ping"]

    @pytest.mark.anyio
    async def test_unreachable_server_reports_rather_than_raises(self, configured):
        """A down database is a fact to report, not a 500."""
        client = StubClient("mongodb://stub:27017", fail_ping=True)
        db = Database()
        await db.connect(client_factory=lambda _uri: client)

        assert await db.status() == "unreachable"

    @pytest.mark.anyio
    async def test_close_awaits_the_client_and_is_idempotent(self, configured):
        """AsyncMongoClient.close() is a coroutine, unlike Motor's."""
        client = StubClient("mongodb://stub:27017")
        db = Database()
        await db.connect(client_factory=lambda _uri: client)

        await db.close()
        assert client.closed is True
        assert db.enabled is False
        await db.close()  # second call must not raise
