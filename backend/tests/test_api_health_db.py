"""S8.1 acceptance: /health/db reports cloud-sync connectivity.

Uses `TestClient` as a context manager on purpose — that is what runs the
`lifespan` handler, so these also cover the app starting and shutting down with
the database layer wired in.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import config
from app.database import database
from app.main import app

TEST_TOKEN = "test-token-not-a-secret"


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    monkeypatch.delenv("MONGODB_URI", raising=False)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def test_app_starts_and_shuts_down_without_mongo():
    """The whole point of making cloud sync optional: no MONGODB_URI must not
    stop the service from booting."""
    with TestClient(app) as client:
        assert client.get("/health").status_code == 200


def test_health_db_reports_disabled_when_unconfigured():
    with TestClient(app) as client:
        body = client.get("/health/db").json()
    assert body == {"database": "disabled", "db_name": None}


def test_health_db_is_open_like_health():
    """A platform probe has no bearer token."""
    with TestClient(app) as client:
        assert client.get("/health/db").status_code == 200


class StubAdmin:
    def __init__(self, fail: bool) -> None:
        self.fail = fail

    async def command(self, name: str):
        if self.fail:
            raise RuntimeError("no server reachable")
        return {"ok": 1}


class StubClient:
    """Fakes only the driver. connect(), status() and the endpoint all run for
    real — unlike monkeypatching `database.status` to a literal, which proves
    nothing beyond the endpoint copying a string into a field."""

    def __init__(self, fail_ping: bool = False) -> None:
        self.admin = StubAdmin(fail_ping)

    def __getitem__(self, name: str):
        return {"__name__": name}

    async def close(self) -> None:
        return None


def _use_stub_driver(monkeypatch: pytest.MonkeyPatch, *, fail_ping: bool = False) -> None:
    import app.database as database_module

    monkeypatch.setattr(
        database_module, "_default_client_factory", lambda _uri: StubClient(fail_ping)
    )


def test_health_db_reports_ok_when_reachable(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("MONGODB_URI", "mongodb://stub:27017")
    monkeypatch.setenv("MONGODB_DB_NAME", "escape_plan_test")
    config.get_settings.cache_clear()
    _use_stub_driver(monkeypatch)

    with TestClient(app) as client:
        body = client.get("/health/db").json()
    assert body == {"database": "ok", "db_name": "escape_plan_test"}


def test_unreachable_database_is_200_not_500(monkeypatch: pytest.MonkeyPatch):
    """A down database must not look like the service itself is broken."""
    monkeypatch.setenv("MONGODB_URI", "mongodb://unreachable:27017")
    config.get_settings.cache_clear()
    _use_stub_driver(monkeypatch, fail_ping=True)

    with TestClient(app) as client:
        resp = client.get("/health/db")
    assert resp.status_code == 200
    assert resp.json()["database"] == "unreachable"


def test_health_db_never_leaks_the_connection_string(monkeypatch: pytest.MonkeyPatch):
    """The URI carries credentials and must never reach a response body."""
    monkeypatch.setenv("MONGODB_URI", "mongodb://user:sup3rsecret@cluster0.example.net/db")
    config.get_settings.cache_clear()
    _use_stub_driver(monkeypatch)

    with TestClient(app) as client:
        raw = client.get("/health/db").text
    assert "sup3rsecret" not in raw
    assert "cluster0.example.net" not in raw


def test_db_name_is_null_whenever_the_layer_is_disabled(monkeypatch: pytest.MonkeyPatch):
    """The body must never contradict itself.

    Reading `db_name` from the environment while `database` came from the live
    client let a malformed MONGODB_URI produce {"database": "disabled",
    "db_name": "escape_plan"} — a state the response model's own docstring says
    cannot happen. Both fields now derive from the client.
    """
    monkeypatch.setenv("MONGODB_URI", "mongodb://user:p@ss@host/db")  # unescaped @
    config.get_settings.cache_clear()

    with TestClient(app) as client:  # real lifespan, real factory
        body = client.get("/health/db").json()

    assert body == {"database": "disabled", "db_name": None}


def test_a_malformed_uri_does_not_stop_the_service(monkeypatch: pytest.MonkeyPatch):
    """A credential typo for an unbuilt feature must not take down routing.

    AsyncMongoClient validates in its constructor, so this raised out of the
    lifespan handler and uvicorn served nothing at all — /health included.
    """
    monkeypatch.setenv("MONGODB_URI", "mongodb://user:p@ss@host/db")
    config.get_settings.cache_clear()

    with TestClient(app) as client:
        assert client.get("/health").status_code == 200
