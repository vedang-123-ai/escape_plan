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


def test_health_db_reports_ok_when_reachable(monkeypatch: pytest.MonkeyPatch):
    async def fake_status():
        return "ok"

    monkeypatch.setenv("MONGODB_URI", "mongodb://stub:27017")
    monkeypatch.setenv("MONGODB_DB_NAME", "escape_plan_test")
    config.get_settings.cache_clear()
    monkeypatch.setattr(database, "status", fake_status)
    monkeypatch.setattr(database, "connect", _noop)

    with TestClient(app) as client:
        body = client.get("/health/db").json()
    assert body == {"database": "ok", "db_name": "escape_plan_test"}


def test_unreachable_database_is_200_not_500(monkeypatch: pytest.MonkeyPatch):
    """A down database must not look like the service itself is broken."""

    async def fake_status():
        return "unreachable"

    monkeypatch.setenv("MONGODB_URI", "mongodb://unreachable:27017")
    config.get_settings.cache_clear()
    monkeypatch.setattr(database, "status", fake_status)
    monkeypatch.setattr(database, "connect", _noop)

    with TestClient(app) as client:
        resp = client.get("/health/db")
    assert resp.status_code == 200
    assert resp.json()["database"] == "unreachable"


def test_health_db_never_leaks_the_connection_string(monkeypatch: pytest.MonkeyPatch):
    """The URI carries credentials and must never reach a response body."""
    secret_uri = "mongodb://user:sup3rsecret@cluster0.example.net/db"

    async def fake_status():
        return "ok"

    monkeypatch.setenv("MONGODB_URI", secret_uri)
    config.get_settings.cache_clear()
    monkeypatch.setattr(database, "status", fake_status)
    monkeypatch.setattr(database, "connect", _noop)

    with TestClient(app) as client:
        raw = client.get("/health/db").text
    assert "sup3rsecret" not in raw
    assert "cluster0.example.net" not in raw


async def _noop() -> None:
    """Stand-in for `database.connect` so lifespan does not build a real client."""
    return None
