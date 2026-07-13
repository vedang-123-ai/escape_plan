"""S1.6 acceptance: /health and /routes over the schema fixtures."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app
from app.routing.plan import RoutePlan

TEST_TOKEN = "test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(autouse=True)
def _token_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def test_health_is_open(client: TestClient):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_routes_requires_token(client: TestClient, bungalow: dict):
    assert client.post("/routes", json={"home": bungalow}).status_code == 401


def test_routes_rejects_wrong_token(client: TestClient, bungalow: dict):
    resp = client.post(
        "/routes",
        json={"home": bungalow},
        headers={"Authorization": "Bearer wrong-token"},
    )
    assert resp.status_code == 401


@pytest.mark.parametrize("fixture_name", ["bungalow", "apartment", "twostory"])
def test_routes_on_all_fixtures(
    client: TestClient, fixture_name: str, request: pytest.FixtureRequest
):
    home = request.getfixturevalue(fixture_name)
    resp = client.post("/routes", json={"home": home}, headers=AUTH)
    assert resp.status_code == 200
    plan = RoutePlan.model_validate(resp.json())
    assert plan.home_id == home["home_id"]
    assert plan.rooms
    # Every room either has a primary route or a structured finding saying why not.
    for room in plan.rooms:
        assert room.primary is not None or room.findings


def test_routes_applies_constraints(client: TestClient, twostory: dict):
    resp = client.post(
        "/routes",
        json={"home": twostory, "constraints": {"avoid_windows": True}},
        headers=AUTH,
    )
    assert resp.status_code == 200
    plan = RoutePlan.model_validate(resp.json())
    assert plan.constraints.avoid_windows is True
    for room in plan.rooms:
        for route in (room.primary, room.secondary):
            if route is not None:
                assert route.uses_window is False


def test_routes_rejects_invalid_home(client: TestClient, bungalow: dict):
    broken = dict(bungalow)
    broken.pop("floors")
    assert (
        client.post("/routes", json={"home": broken}, headers=AUTH).status_code == 422
    )


def test_routes_rejects_unknown_fields(client: TestClient, bungalow: dict):
    resp = client.post(
        "/routes", json={"home": bungalow, "unexpected": 1}, headers=AUTH
    )
    assert resp.status_code == 422


def test_missing_token_env_fails_closed(
    client: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.delenv("BACKEND_BEARER_TOKEN")
    config.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match="BACKEND_BEARER_TOKEN"):
        client.post("/routes", json={"home": bungalow}, headers=AUTH)
