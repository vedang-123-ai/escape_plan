"""S8.1 — the MongoDB connection lifecycle.

No real database and no mocking library. `mongomock` has no Python 3.13 support
and no async support, and `mongomock-motor` would pull the end-of-life Motor
driver back into the tree just for tests — so the stub below implements only the
handful of operations `Database` actually performs.

A `mongo` marker is registered in pytest.ini for tests that need a real server.
**No such test exists yet** — they should be written against an actual MongoDB
rather than guessed at, and BLOCKERS.md tracks that gap.
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


class TestMalformedConfiguration:
    """A bad URI must disable the layer, never stop the service.

    `AsyncMongoClient` validates eagerly, so an Atlas password pasted in with an
    unescaped `@` raises inside the constructor. Uncaught, that propagates out of
    the lifespan handler and uvicorn serves nothing at all — /health included.
    """

    @pytest.mark.anyio
    async def test_a_raising_factory_disables_rather_than_propagates(self, configured):
        def exploding(_uri: str):
            raise ValueError("Username and password must be escaped")

        db = Database()
        await db.connect(client_factory=exploding)  # must not raise

        assert db.enabled is False
        assert await db.status() == "disabled"

    @pytest.mark.anyio
    async def test_a_half_built_client_is_closed_not_leaked(self, configured):
        """If the client is built but naming the database fails, its monitor
        tasks would leak — lifespan's `finally` never sees it."""

        class BadNameClient(StubClient):
            def __getitem__(self, name: str):
                raise ValueError(f"invalid database name: {name!r}")

        built: list[BadNameClient] = []

        def factory(uri: str):
            client = BadNameClient(uri)
            built.append(client)
            return client

        db = Database()
        await db.connect(client_factory=factory)

        assert db.enabled is False
        assert built[0].closed is True

    @pytest.mark.anyio
    async def test_the_uri_is_never_passed_to_the_logger(self, configured, caplog):
        """The failure is logged; the credential-bearing URI must not be."""

        def exploding(_uri: str):
            raise ValueError("boom")

        with caplog.at_level("ERROR"):
            await Database().connect(client_factory=exploding)

        assert "mongodb://stub:27017" not in caplog.text


class TestLifecycleEdges:
    @pytest.mark.anyio
    async def test_double_connect_does_not_replace_the_client(self, configured):
        """Overwriting a live client silently leaks its connection pool."""
        clients: list[StubClient] = []

        def factory(uri: str):
            clients.append(StubClient(uri))
            return clients[-1]

        db = Database()
        await db.connect(client_factory=factory)
        await db.connect(client_factory=factory)

        assert len(clients) == 1

    @pytest.mark.anyio
    async def test_a_failing_close_still_clears_state(self, configured):
        """Otherwise `enabled` keeps reporting True for a dead client."""

        class AngryClient(StubClient):
            async def close(self) -> None:
                raise RuntimeError("close failed")

        db = Database()
        await db.connect(client_factory=lambda uri: AngryClient(uri))

        with pytest.raises(RuntimeError):
            await db.close()
        assert db.enabled is False


class TestStatusCaching:
    """`status()` is reachable without a token and each call is a real pool
    checkout, so repeated probes must not each cost a ping."""

    @pytest.mark.anyio
    async def test_repeated_calls_ping_once(self, configured):
        client = StubClient("mongodb://stub:27017")
        db = Database()
        await db.connect(client_factory=lambda _uri: client)

        for _ in range(5):
            assert await db.status() == "ok"
        assert client.admin.commands == ["ping"]

    @pytest.mark.anyio
    async def test_the_cache_expires(self, configured, monkeypatch):
        import app.database as database_module

        client = StubClient("mongodb://stub:27017")
        db = Database()
        await db.connect(client_factory=lambda _uri: client)

        await db.status()
        monkeypatch.setattr(database_module, "STATUS_CACHE_TTL_S", -1.0)
        await db.status()

        assert client.admin.commands == ["ping", "ping"]

    @pytest.mark.anyio
    async def test_closing_clears_the_cached_status(self, configured):
        client = StubClient("mongodb://stub:27017")
        db = Database()
        await db.connect(client_factory=lambda _uri: client)
        await db.status()
        await db.close()

        assert await db.status() == "disabled"


class TestRealClientFactory:
    """The one line that builds a real AsyncMongoClient. Constructing a client
    performs no I/O, so this needs no server."""

    def test_factory_sets_the_options_the_layer_depends_on(self):
        from app.database import (
            SERVER_SELECTION_TIMEOUT_MS,
            WAIT_QUEUE_TIMEOUT_MS,
            _default_client_factory,
        )

        client = _default_client_factory("mongodb://127.0.0.1:27017")
        opts = client.options

        # Without tz_aware, BSON dates decode naive and a stored home comes back
        # unequal to the one written.
        assert opts.codec_options.tz_aware is True
        assert opts.server_selection_timeout == SERVER_SELECTION_TIMEOUT_MS / 1000
        assert opts.pool_options.wait_queue_timeout == WAIT_QUEUE_TIMEOUT_MS / 1000

    def test_a_malformed_uri_raises_here_not_silently(self):
        """Pins the behaviour `connect()` exists to contain."""
        from app.database import _default_client_factory

        with pytest.raises(Exception):
            _default_client_factory("mongodb://user:p@ss@host/db")
