"""S1.6 acceptance: /health and /routes over the schema fixtures."""

from __future__ import annotations

import json

import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app
from app.models import HomeModel
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


def test_health_names_the_deployed_commit(client: TestClient, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("RENDER_GIT_COMMIT", "abc1234deadbeef")
    assert client.get("/health").json()["commit"] == "abc1234deadbeef"


def test_health_commit_is_unknown_off_render(client: TestClient, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.delenv("RENDER_GIT_COMMIT", raising=False)
    assert client.get("/health").json()["commit"] == "unknown"


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


def test_routes_by_profile_id_derives_constraints(client: TestClient, twostory: dict):
    """S3.4: the demo's profile switch, over HTTP."""
    resp = client.post(
        "/routes", json={"home": twostory, "profile_id": "p_grandpa"}, headers=AUTH
    )
    assert resp.status_code == 200
    plan = RoutePlan.model_validate(resp.json())
    assert plan.profile_id == "p_grandpa"
    assert plan.constraints.avoid_stairs is True
    assert plan.constraints.avoid_windows is True


def test_routes_profile_switch_changes_the_answer(client: TestClient, twostory: dict):
    def bedroom_route(profile_id: str, room_id: str):
        resp = client.post(
            "/routes", json={"home": twostory, "profile_id": profile_id}, headers=AUTH
        )
        assert resp.status_code == 200
        plan = RoutePlan.model_validate(resp.json())
        return next(r for r in plan.rooms if r.room_id == room_id)

    grandpa = bedroom_route("p_grandpa", "r_bed_master")
    maya = bedroom_route("p_maya", "r_bed_kids")
    assert grandpa.primary is None
    assert "no_viable_route" in [f.kind for f in grandpa.findings]
    assert maya.primary is not None


def test_routes_unknown_profile_id_is_404(client: TestClient, twostory: dict):
    resp = client.post(
        "/routes", json={"home": twostory, "profile_id": "p_nobody"}, headers=AUTH
    )
    assert resp.status_code == 404


def test_routes_profile_id_and_constraints_conflict_is_422(
    client: TestClient, twostory: dict
):
    resp = client.post(
        "/routes",
        json={
            "home": twostory,
            "profile_id": "p_grandpa",
            "constraints": {"avoid_windows": True},
        },
        headers=AUTH,
    )
    assert resp.status_code == 422


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


def test_convert_scan_fixture(client: TestClient):
    from tests.conftest import load_fixture

    scan = load_fixture("scans/synthetic-bungalow.roomplan.json")
    resp = client.post(
        "/convert", json={"scan": scan, "home_name": "Test Scan"}, headers=AUTH
    )
    assert resp.status_code == 200
    home = HomeModel.model_validate(resp.json())
    assert home.name == "Test Scan"
    assert home.floors[0].rooms


def test_convert_response_has_no_null_optionals(client: TestClient):
    """Regression (S1.4 lane finding): /convert used to serialize unset optionals
    as explicit nulls — e.g. ``"egress": null`` on every opening — which is
    schema-invalid. The route must omit unset fields entirely."""
    from tests.conftest import load_fixture

    scan = load_fixture("scans/synthetic-bungalow.roomplan.json")
    resp = client.post("/convert", json={"scan": scan}, headers=AUTH)
    assert resp.status_code == 200

    def assert_no_nulls(node: object, path: str = "$") -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                assert value is not None, f"null value at {path}.{key}"
                assert_no_nulls(value, f"{path}.{key}")
        elif isinstance(node, list):
            for i, value in enumerate(node):
                assert_no_nulls(value, f"{path}[{i}]")

    assert_no_nulls(resp.json())


def test_build_response_has_no_null_optionals(
    client: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    """/build returns a nested HomeModel, so its entire document must be JSON-Schema-shaped."""
    from app import main
    from app.ai.builder import BuildResult

    monkeypatch.setattr(
        main,
        "run_builder",
        lambda **_kwargs: BuildResult(
            home=HomeModel.model_validate(bungalow), trace=[], truncated=False
        ),
    )
    response = client.post("/build", json={"description": "a bungalow"}, headers=AUTH)
    assert response.status_code == 200

    def assert_no_nulls(node: object, path: str = "$") -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                assert value is not None, f"null value at {path}.{key}"
                assert_no_nulls(value, f"{path}.{key}")
        elif isinstance(node, list):
            for index, value in enumerate(node):
                assert_no_nulls(value, f"{path}[{index}]")

    assert_no_nulls(response.json())


def test_convert_requires_token(client: TestClient):
    assert client.post("/convert", json={"scan": {}}).status_code == 401


def test_convert_rejects_garbage_scan(client: TestClient):
    resp = client.post("/convert", json={"scan": {"rooms": "nope"}}, headers=AUTH)
    assert resp.status_code == 422
    # Curated: no Python or pydantic internals, no field paths.
    detail = resp.json()["detail"]
    assert "rooms" not in detail and "validation" not in detail.lower()


def test_convert_server_bug_is_500_and_logged_with_traceback(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
):
    def boom(*_a, **_k):
        raise KeyError("secret internal detail")

    monkeypatch.setattr("app.main.convert_scan", boom)
    # raise_server_exceptions=False: we want the response the phone would see.
    resp = TestClient(app, raise_server_exceptions=False).post(
        "/convert", json={"scan": {}}, headers=AUTH
    )
    assert resp.status_code == 500
    assert "secret internal detail" not in resp.text
    assert any(r.levelname == "ERROR" and r.exc_info for r in caplog.records)


def test_missing_token_env_fails_closed(
    client: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.delenv("BACKEND_BEARER_TOKEN")
    config.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match="BACKEND_BEARER_TOKEN"):
        client.post("/routes", json={"home": bungalow}, headers=AUTH)

def test_routes_peril_defaults_to_fire_byte_for_byte(client: TestClient, bungalow: dict):
    # Test that omitting peril and passing peril="fire" yield byte-for-byte identical json
    res_default = client.post("/routes", json={"home": bungalow}, headers=AUTH)
    assert res_default.status_code == 200
    
    res_explicit = client.post("/routes", json={"home": bungalow, "peril": "fire"}, headers=AUTH)
    assert res_explicit.status_code == 200
    
    assert res_default.text == res_explicit.text


# --- S11.25 (AUD-004): the server refuses an oversized home ---------------

def _oversize(home: dict) -> dict:
    """Stretch a fixture's first room past MAX_TOTAL_GRID_CELLS.

    A 200 m x 200 m room: valid topology, valid coordinates, and ~4,000,000
    navigation-grid cells — about 100 s of routing per peril before S11.25.
    """
    import copy

    d = copy.deepcopy(home)
    d["floors"][0]["rooms"][0]["polygon"] = [
        [0.0, 0.0], [200.0, 0.0], [200.0, 200.0], [0.0, 200.0]
    ]
    return d


@pytest.mark.parametrize("endpoint", ["/routes", "/score"])
def test_oversized_home_is_422_and_names_the_bound(
    client: TestClient, bungalow: dict, endpoint: str
):
    resp = client.post(endpoint, json={"home": _oversize(bungalow)}, headers=AUTH)
    assert resp.status_code == 422
    detail = json.dumps(resp.json())
    assert "span" in detail or "navigation-grid cells" in detail


def test_oversized_home_never_reaches_the_router(
    client: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    """The point of the bound: rejection happens before any rasterizing."""
    import app.main as main_mod

    called = False

    def _boom(*args: object, **kwargs: object) -> None:
        nonlocal called
        called = True
        raise AssertionError("compute_route_plan must not run on an oversized home")

    monkeypatch.setattr(main_mod, "compute_route_plan", _boom)
    resp = client.post("/routes", json={"home": _oversize(bungalow)}, headers=AUTH)
    assert resp.status_code == 422
    assert not called


def test_a_home_inside_the_bounds_still_scores(client: TestClient, bungalow: dict):
    """The bounds must not cost the demo path anything."""
    resp = client.post("/score", json={"home": bungalow}, headers=AUTH)
    assert resp.status_code == 200
    assert 0 <= resp.json()["score"] <= 100
