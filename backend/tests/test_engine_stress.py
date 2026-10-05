"""S11.52: adversarial homes against the deterministic engine and its HTTP wrappers.

Two promises are checked here. A valid home, however odd (one room, no doors, no
exits, islands, slivers, the largest home the bounds allow, every peril), gets a
deterministic, finite, sensible answer: never a 500, never NaN, never a hang. An
invalid home gets a clean 4xx with a plain message.

Homes are built in code rather than added to schema/fixtures/ on purpose: they are
deliberately strange, and the fixtures are the realistic test bed.
"""

from __future__ import annotations

import copy
import json
import math
import time

import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app, get_thresholds
from app.models import EXTERIOR_ID, HomeModel
from app.routing.engine import _dijkstra_to_exterior, compute_route_plan, find_bottlenecks
from app.routing.graph import NodeKind, build_graph
from app.routing.plan import RoutingConstraints

from tests.conftest import load_fixture

TEST_TOKEN = "test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}
PERILS = ("fire", "tornado", "earthquake")
FIXTURES = (
    "bungalow.json",
    "apartment.json",
    "twostory.json",
    "bungalow-blocked.json",
    "bungalow-narrow.json",
    "jagged.json",
    "twostory-empty.json",
)


@pytest.fixture(autouse=True)
def _token_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture
def client() -> TestClient:
    # raise_server_exceptions=False so a server bug shows up as the 500 a phone
    # would see, not as a Python exception inside the test.
    return TestClient(app, raise_server_exceptions=False)


# --- home builders ----------------------------------------------------------


def _room(rid: str, x0: float, y0: float, x1: float, y1: float, typ: str = "bedroom") -> dict:
    return {
        "id": rid,
        "name": rid,
        "type": typ,
        "polygon": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]],
        "source": "manual",
    }


def _opening(
    oid: str, a: str, b: str, host: str, edge: int, *, t0: float = 0.4, t1: float = 0.6,
    kind: str = "door", width: float = 0.9, height: float = 2.0, sill: float = 0.0,
) -> dict:
    return {
        "id": oid,
        "kind": kind,
        "room_ids": [a, b],
        "wall_segment": {"room_id": host, "edge_index": edge, "t0": t0, "t1": t1},
        "width_m": width,
        "height_m": height,
        "sill_height_m": sill,
        "source": "manual",
    }


def _floor(fid: str, level: int, rooms: list, openings: list | None = None, objects: list | None = None) -> dict:
    return {
        "id": fid,
        "level": level,
        "name": fid,
        "height_m": 2.7,
        "rooms": rooms,
        "openings": openings or [],
        "objects": objects or [],
        "safety_points": [],
    }


def _home(floors: list, stairs: list | None = None) -> dict:
    return {
        "schema_version": "2.1",
        "home_id": "stress",
        "name": "Stress",
        "floors": floors,
        "stairs": stairs or [],
        "profiles": [],
        "meta": {"created": "2026-01-01T00:00:00Z", "modified": "2026-01-01T00:00:00Z"},
    }


def _stair(sid: str, f0: str, r0: str, f1: str, r1: str) -> dict:
    return {
        "id": sid,
        "from": {"floor_id": f0, "room_id": r0},
        "to": {"floor_id": f1, "room_id": r1},
        "footprint": [[0.2, 0.2], [1.2, 0.2], [1.2, 2.8], [0.2, 2.8]],
        "kind": "straight",
        "source": "manual",
    }


def grid_home(nx: int, ny: int, *, size: float = 3.0) -> dict:
    """nx × ny square rooms, a door between every pair of neighbours, two exits in
    opposite corners. 20 × 10 is exactly MAX_ROOMS = 200 and well inside the grid
    cell bound (200 × 900 = 180,000 < 250,000)."""
    rooms, openings = [], []
    for i in range(nx):
        for j in range(ny):
            rid = f"r{i}_{j}"
            rooms.append(_room(rid, i * size, j * size, (i + 1) * size, (j + 1) * size,
                               "bedroom" if (i + j) % 3 == 0 else "living"))
            if i + 1 < nx:
                openings.append(_opening(f"dx{i}_{j}", rid, f"r{i + 1}_{j}", rid, 1))
            if j + 1 < ny:
                openings.append(_opening(f"dy{i}_{j}", rid, f"r{i}_{j + 1}", rid, 2))
    openings.append(_opening("exit_a", "r0_0", EXTERIOR_ID, "r0_0", 0))
    openings.append(_opening("exit_b", f"r{nx - 1}_{ny - 1}", EXTERIOR_ID, f"r{nx - 1}_{ny - 1}", 1))
    return _home([_floor("f0", 0, rooms, openings)])


def _post(client: TestClient, path: str, body: dict):
    return client.post(path, json=body, headers=AUTH)


def _assert_finite(obj, where: str = "$") -> None:
    if isinstance(obj, float):
        assert math.isfinite(obj), f"non-finite number at {where}"
    elif isinstance(obj, dict):
        for k, v in obj.items():
            _assert_finite(v, f"{where}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            _assert_finite(v, f"{where}[{i}]")


def _strict_json(resp) -> object:
    """Parse as RFC 8259 JSON: NaN and Infinity are not JSON, and Swift's
    JSONDecoder refuses them."""

    def reject(token: str):
        raise AssertionError(f"response carries a non-JSON number {token}")

    return json.loads(resp.text, parse_constant=reject)


def _rooms(plan: dict) -> dict[str, dict]:
    return {r["room_id"]: r for r in plan["rooms"]}


def _kinds(room_plan: dict) -> list[str]:
    return [f["kind"] for f in room_plan["findings"]]


# --- the largest home the bounds allow must finish ----------------------------


def _brute_force_bottlenecks(home: HomeModel) -> list[tuple[str, list[str]]]:
    """The definition, spelled out: ban one opening, re-run the exit search from
    every room, report the rooms that lost their way out. This is what
    find_bottlenecks did before it was made linear, kept as the known answer."""
    graph = build_graph(home, get_thresholds())
    openings = {o.id: o for f in home.floors for o in f.openings}
    rooms = sorted(n.id for n in graph.nodes.values() if n.kind == NodeKind.room)
    none = RoutingConstraints()

    def reachable(banned: frozenset[str]) -> set[str]:
        return {r for r in rooms if _dijkstra_to_exterior(graph, r, openings, none, banned) is not None}

    base = reachable(frozenset())
    out = []
    for oid in sorted(n.id for n in graph.nodes.values() if n.kind == NodeKind.opening):
        lost = sorted(base - reachable(frozenset({oid})))
        if len(lost) >= 2:
            out.append((oid, lost))
    return out


def _bottleneck_homes() -> list[tuple[str, dict]]:
    homes = [(name, load_fixture(name)) for name in FIXTURES]
    # A corridor of rooms with one exit at one end: every internal door is a
    # bottleneck for everything beyond it.
    rooms = [_room(f"c{i}", i * 3.0, 0, (i + 1) * 3.0, 3) for i in range(6)]
    ops = [_opening(f"d{i}", f"c{i}", f"c{i + 1}", f"c{i}", 1) for i in range(5)]
    ops.append(_opening("exit", "c0", EXTERIOR_ID, "c0", 3))
    homes.append(("corridor", _home([_floor("f0", 0, rooms, ops)])))
    # Islands: some rooms never reach an exit, so they are not in the baseline and
    # must never be reported as "lost".
    rooms = [_room("a", 0, 0, 4, 4), _room("b", 10, 0, 14, 4), _room("c", 20, 0, 24, 4), _room("d", 24, 0, 28, 4)]
    ops = [_opening("da", "a", EXTERIOR_ID, "a", 0), _opening("dcd", "c", "d", "c", 1)]
    homes.append(("islands", _home([_floor("f0", 0, rooms, ops)])))
    homes.append(("grid 4x3", grid_home(4, 3)))
    return homes


@pytest.mark.parametrize("name,doc", _bottleneck_homes(), ids=lambda v: v if isinstance(v, str) else "")
def test_bottlenecks_match_the_brute_force_definition(name: str, doc: dict):
    home = HomeModel.model_validate(doc)
    graph = build_graph(home, get_thresholds())
    openings = {o.id: o for f in home.floors for o in f.openings}
    got = [(b.opening_id, b.disconnected_room_ids) for b in find_bottlenecks(graph, openings)]
    assert got == _brute_force_bottlenecks(home)


def test_corridor_bottlenecks_are_every_door_with_two_or_more_rooms_behind_it():
    rooms = [_room(f"c{i}", i * 3.0, 0, (i + 1) * 3.0, 3) for i in range(6)]
    ops = [_opening(f"d{i}", f"c{i}", f"c{i + 1}", f"c{i}", 1) for i in range(5)]
    ops.append(_opening("exit", "c0", EXTERIOR_ID, "c0", 3))
    home = HomeModel.model_validate(_home([_floor("f0", 0, rooms, ops)]))
    plan = compute_route_plan(home, get_thresholds())
    got = {b.opening_id: b.disconnected_room_ids for b in plan.bottlenecks}
    assert got == {
        "exit": ["c0", "c1", "c2", "c3", "c4", "c5"],
        "d0": ["c1", "c2", "c3", "c4", "c5"],
        "d1": ["c2", "c3", "c4", "c5"],
        "d2": ["c3", "c4", "c5"],
        "d3": ["c4", "c5"],
        # d4 strands only c5: one room, under min_rooms = 2.
    }


def test_max_rooms_home_scores_in_bounded_time(client: TestClient):
    """200 rooms (MAX_ROOMS) is a valid home. /score runs all three perils; before
    S11.52 the bottleneck search alone was ~O(rooms³) and this took minutes."""
    doc = grid_home(20, 10)
    t = time.perf_counter()
    resp = _post(client, "/score", {"home": doc})
    elapsed = time.perf_counter() - t
    assert resp.status_code == 200, resp.text[:300]
    assert elapsed < 10.0, f"/score on 200 rooms took {elapsed:.1f} s"
    body = _strict_json(resp)
    assert 0 <= body["score"] <= 100


def test_max_rooms_home_routes_every_room(client: TestClient):
    doc = grid_home(20, 10)
    for peril in PERILS:
        t = time.perf_counter()
        resp = _post(client, "/routes", {"home": doc, "peril": peril})
        elapsed = time.perf_counter() - t
        assert resp.status_code == 200
        assert elapsed < 5.0, f"/routes {peril} on 200 rooms took {elapsed:.1f} s"
        plan = _strict_json(resp)
        assert len(plan["rooms"]) == 200
        assert all(r["primary"] is not None for r in plan["rooms"]), peril
        if peril != "tornado":
            # Two exits, a fully meshed grid: every room has a second way out and
            # no single door strands two rooms.
            assert all(r["secondary"] is not None for r in plan["rooms"])
            assert plan["bottlenecks"] == []


# --- odd but valid homes: a sensible, finite, deterministic answer -----------


def _one_room_no_doors() -> dict:
    return _home([_floor("f0", 0, [_room("solo", 0, 0, 4, 4)])])


def _no_exits() -> dict:
    rooms = [_room("a", 0, 0, 4, 4), _room("b", 4, 0, 8, 4)]
    return _home([_floor("f0", 0, rooms, [_opening("ab", "a", "b", "a", 1)])])


def _islands() -> dict:
    rooms = [_room("a", 0, 0, 4, 4), _room("b", 10, 0, 14, 4), _room("c", 20, 0, 24, 4), _room("d", 24, 0, 28, 4)]
    ops = [_opening("da", "a", EXTERIOR_ID, "a", 0), _opening("dcd", "c", "d", "c", 1)]
    return _home([_floor("f0", 0, rooms, ops)])


def _sliver() -> dict:
    """A triangle 5 m long and a nanometre tall: positive area, so valid."""
    sliver = {"id": "s", "name": "Sliver", "type": "hall", "polygon": [[0, 0], [5, 0], [2.5, 1e-9]], "source": "manual"}
    return _home([_floor("f0", 0, [sliver], [_opening("d", "s", EXTERIOR_ID, "s", 0)])])


def _micro_room() -> dict:
    return _home([_floor("f0", 0, [_room("t", 0, 0, 1e-6, 1e-6)], [_opening("d", "t", EXTERIOR_ID, "t", 0)])])


def _far_corners() -> dict:
    """Rooms pressed against both corners of the ±200 m coordinate bound."""
    rooms = [_room("ne", 180, 180, 200, 200), _room("sw", -200, -200, -180, -180)]
    ops = [_opening("dne", "ne", EXTERIOR_ID, "ne", 0), _opening("dsw", "sw", EXTERIOR_ID, "sw", 0)]
    return _home([_floor("f0", 0, rooms, ops)])


def _eight_floor_tower() -> dict:
    """MAX_FLOORS floors, one room each, stacked by stairs; the only exit is on the ground."""
    floors = [_floor(f"f{i}", i, [_room(f"r{i}", 0, 0, 4, 4)]) for i in range(8)]
    floors[0]["openings"] = [_opening("front", "r0", EXTERIOR_ID, "r0", 0)]
    stairs = [_stair(f"s{i}", f"f{i}", f"r{i}", f"f{i + 1}", f"r{i + 1}") for i in range(7)]
    return _home(floors, stairs)


def _unicode_names() -> dict:
    doc = load_fixture("bungalow.json")
    doc["name"] = "家 🔥 ‮ reversed \u0000 nul"
    doc["floors"][0]["rooms"][0]["name"] = "Ünïcödé 😀 " * 2000
    return doc


ODD_HOMES = {
    "one room no doors": (_one_room_no_doors, "solo"),
    "no exits": (_no_exits, "a"),
    "islands": (_islands, "c"),
    "sliver": (_sliver, "s"),
    "micro room": (_micro_room, "t"),
    "far corners": (_far_corners, "ne"),
    "eight floor tower": (_eight_floor_tower, "r7"),
    "unicode names": (_unicode_names, "r_living"),
}


@pytest.mark.parametrize("name", sorted(ODD_HOMES))
def test_odd_valid_home_is_finite_and_byte_deterministic(client: TestClient, name: str):
    build, origin = ODD_HOMES[name]
    doc = build()
    calls = [("/routes", {"home": doc, "peril": p}) for p in PERILS]
    calls += [("/score", {"home": doc}), ("/evacuate", {"home": doc, "origin_room_id": origin})]
    for path, body in calls:
        first = _post(client, path, body)
        assert first.status_code == 200, f"{path}: {first.status_code} {first.text[:300]}"
        _assert_finite(_strict_json(first))
        second = _post(client, path, copy.deepcopy(body))
        assert first.content == second.content, f"{path} is not byte-deterministic"


@pytest.mark.parametrize("name", FIXTURES)
def test_fixtures_are_byte_deterministic_on_every_endpoint(client: TestClient, name: str):
    doc = load_fixture(name)
    origin = doc["floors"][0]["rooms"][0]["id"]
    calls = [("/routes", {"home": doc, "peril": p}) for p in PERILS]
    calls += [("/score", {"home": doc}), ("/evacuate", {"home": doc, "origin_room_id": origin})]
    for path, body in calls:
        a, b = _post(client, path, body), _post(client, path, body)
        assert a.status_code == 200
        assert a.content == b.content, f"{name} {path}"


def test_one_room_with_no_doors_reports_no_route_and_shelters_in_place(client: TestClient):
    doc = _one_room_no_doors()
    fire = _rooms(_post(client, "/routes", {"home": doc, "peril": "fire"}).json())["solo"]
    assert fire["primary"] is None and fire["secondary"] is None
    assert _kinds(fire) == ["no_viable_route"]

    quake = _rooms(_post(client, "/routes", {"home": doc, "peril": "earthquake"}).json())["solo"]
    assert quake["primary"] is None
    assert _kinds(quake) == ["no_cover_in_room", "no_viable_route"]

    # Tornado is a shelter search: with nowhere else to go, the room is its own shelter.
    tornado = _rooms(_post(client, "/routes", {"home": doc, "peril": "tornado"}).json())["solo"]
    assert tornado["primary"]["exit_id"] == "solo"
    assert tornado["primary"]["length_m"] == 0.0

    evac = _post(client, "/evacuate", {"home": doc, "origin_room_id": "solo"}).json()
    assert evac["tracks"] == []
    assert [f["kind"] for f in evac["findings"]] == ["no_viable_route"]


def test_a_home_with_no_exit_caps_the_score(client: TestClient):
    doc = _no_exits()
    plan = _post(client, "/routes", {"home": doc}).json()
    assert all(_kinds(r) == ["no_viable_route"] for r in plan["rooms"])
    assert plan["bottlenecks"] == []
    score = _post(client, "/score", {"home": doc}).json()
    # An unresolved high-severity item (no route out) caps the composite at 40.
    assert score["score"] <= 40


def test_islands_only_the_room_with_the_door_gets_out(client: TestClient):
    doc = _islands()
    plan = _rooms(_post(client, "/routes", {"home": doc}).json())
    assert plan["a"]["primary"]["exit_id"] == "da"
    assert _kinds(plan["a"]) == ["no_secondary_egress"]
    for rid in ("b", "c", "d"):
        assert plan[rid]["primary"] is None
        assert _kinds(plan[rid]) == ["no_viable_route"]

    evac = _post(client, "/evacuate", {"home": doc, "origin_room_id": "c"}).json()
    # The fire starts in c and reaches d through their shared door; it never reaches a or b.
    assert {h["room_id"] for h in evac["hazard"]} == {"c", "d"}
    assert [t["start_room_id"] for t in evac["tracks"]] == ["a"]


def test_eight_floor_tower_routes_down_every_stair(client: TestClient):
    plan = _rooms(_post(client, "/routes", {"home": _eight_floor_tower()}).json())
    top = plan["r7"]["primary"]
    assert top["exit_id"] == "front" and top["uses_stairs"]
    stair_ids = [w["node_id"] for w in top["waypoints"] if w["kind"] == "stair"]
    # Each flight contributes a waypoint at both of its ends.
    assert stair_ids == [s for i in range(6, -1, -1) for s in (f"s{i}", f"s{i}")]
    floors_visited = [w["floor_id"] for w in top["waypoints"] if w["kind"] == "room"]
    assert floors_visited == [f"f{i}" for i in range(7, -1, -1)]


def test_far_corner_rooms_keep_their_coordinates(client: TestClient):
    plan = _rooms(_post(client, "/routes", {"home": _far_corners()}).json())
    ne = plan["ne"]["primary"]["waypoints"]
    assert (ne[0]["x"], ne[0]["y"]) == (190.0, 190.0)
    assert plan["ne"]["primary"]["length_m"] == 10.0
    assert plan["sw"]["primary"]["length_m"] == 10.0


# --- invalid homes and bodies: a clean 4xx, never a 500 -----------------------


def _bungalow_with(mutate) -> dict:
    doc = load_fixture("bungalow.json")
    mutate(doc)
    return doc


def _set_t(doc: dict, t0: float, t1: float) -> None:
    doc["floors"][0]["openings"][0]["wall_segment"].update(t0=t0, t1=t1)


INVALID_HOMES = {
    "t0 equals t1": (lambda d: _set_t(d, 0.5, 0.5), "must be < t1"),
    "t0 above t1": (lambda d: _set_t(d, 0.6, 0.4), "must be < t1"),
    "t0 below 0": (lambda d: _set_t(d, -0.1, 0.5), "greater than or equal to 0"),
    "t1 above 1": (lambda d: _set_t(d, 0.5, 1.1), "less than or equal to 1"),
    "edge index out of range": (
        lambda d: d["floors"][0]["openings"][0]["wall_segment"].update(edge_index=4), "out of range"),
    "duplicate room id": (
        lambda d: d["floors"][0]["rooms"].append(_room("r_living", 20, 0, 24, 4)), "duplicate id 'r_living'"),
    "empty floor": (lambda d: d["floors"].append(
        {"id": "f2", "level": 1, "name": "Empty", "height_m": 2.7, "rooms": []}), "at least 1 item"),
    "nine floors": (lambda d: d["floors"].extend(
        {"id": f"x{i}", "level": i + 1, "name": "x", "height_m": 2.7,
         "rooms": [_room(f"xr{i}", 0, 0, 4, 4)]} for i in range(8)), "at most 8 items"),
    "stairs on one floor": (lambda d: d.update(stairs=[
        _stair("s", "f1", "r_living", "f1", "r_kitchen")]), "different floors"),
    "zero-area polygon": (lambda d: d["floors"][0]["rooms"][0].update(
        polygon=[[0, 0], [1, 0], [2, 0]]), "counter-clockwise"),
    "bow-tie polygon": (lambda d: d["floors"][0]["rooms"][0].update(
        polygon=[[0, 0], [4, 4], [4, 0], [0, 4]]), "self-intersecting"),
    "coordinate past the bound": (lambda d: d["floors"][0]["rooms"][0].update(
        polygon=[[0, 0], [1e308, 0], [1e308, 4], [0, 4]]), "outside the supported range"),
}


@pytest.mark.parametrize("name", sorted(INVALID_HOMES))
def test_invalid_home_is_a_plain_422(client: TestClient, name: str):
    mutate, phrase = INVALID_HOMES[name]
    doc = _bungalow_with(mutate)
    for path, body in (("/routes", {"home": doc}), ("/score", {"home": doc}),
                       ("/evacuate", {"home": doc, "origin_room_id": "r_living"})):
        resp = _post(client, path, body)
        assert resp.status_code == 422, f"{path}: {resp.status_code}"
        messages = " ".join(e["msg"] for e in resp.json()["detail"])
        assert phrase in messages, messages


def test_stairs_to_a_missing_room_on_another_floor_is_422(client: TestClient):
    doc = _eight_floor_tower()
    doc["stairs"][0]["to"]["room_id"] = "nope"
    resp = _post(client, "/routes", {"home": doc})
    assert resp.status_code == 422
    assert "room 'nope' does not exist on floor 'f1'" in resp.text


@pytest.mark.parametrize("version", [2.1, 2, True, ["2.1"], {"v": "2.1"}])
def test_non_string_schema_version_is_422_not_500(client: TestClient, version):
    doc = load_fixture("bungalow.json")
    doc["schema_version"] = version
    resp = _post(client, "/routes", {"home": doc})
    assert resp.status_code == 422, resp.text[:200]
    assert "schema_version" in resp.text


@pytest.mark.parametrize("stamp", ["0001-01-01T00:00:00+14:00", "9999-12-31T23:59:59-12:00"])
def test_timestamp_that_overflows_utc_is_422_not_500(client: TestClient, stamp: str):
    """Valid ISO-8601, but converting it to UTC leaves datetime's range."""
    resp = _post(client, "/score", {"home": load_fixture("bungalow.json"),
                                    "checklist_state": {"practice.drill_recent": stamp}})
    assert resp.status_code == 422, resp.text[:200]
    assert "is not an ISO-8601 timestamp" in resp.text


def test_checklist_state_clock_extremes():
    """Edges of the clock that do parse. Far future is not done, ancient is stale,
    a naive time is read as UTC, a bare date counts."""
    from datetime import datetime, timezone

    from app.scoring.checklist import _is_done

    now = datetime(2026, 10, 5, tzinfo=timezone.utc)
    assert not _is_done("x", {"x": "9999-12-31T23:59:59Z"}, 180, now)
    assert not _is_done("x", {"x": "0001-01-01T00:00:00Z"}, 180, now)
    assert _is_done("x", {"x": "2026-10-01T00:00:00"}, 180, now)
    assert _is_done("x", {"x": "2026-10-01"}, 180, now)


@pytest.mark.parametrize("value", [[1], 2, 1.5, None, "true"])
def test_checklist_state_bad_types_are_422(client: TestClient, value):
    resp = _post(client, "/score", {"home": load_fixture("bungalow.json"),
                                    "checklist_state": {"practice.drill_recent": value}})
    assert resp.status_code == 422


def _raw_post(client: TestClient, path: str, text: str):
    return client.post(path, content=text, headers={**AUTH, "Content-Type": "application/json"})


@pytest.mark.parametrize("needle,replacement", [
    ('"width_m": 0.9', '"width_m": NaN'),
    ('[5.0, 0.0], [5.0, 4.0]', '[NaN, 0.0], [5.0, 4.0]'),
    ('"height_m": 2.7', '"height_m": Infinity'),
    ('"sill_height_m": 0.8', '"sill_height_m": -Infinity'),
])
def test_nan_or_infinity_in_a_home_is_a_clean_422(client: TestClient, needle: str, replacement: str):
    """Python's JSON parser accepts the non-standard NaN/Infinity tokens. The model
    rejects them, but the 422 echoed the bad value back and the error renderer then
    crashed on it: the client got a 500 instead of the validation message."""
    text = json.dumps({"home": load_fixture("bungalow.json")})
    assert needle in text
    resp = _raw_post(client, "/routes", text.replace(needle, replacement, 1))
    assert resp.status_code == 422, resp.text[:200]
    body = _strict_json(resp)
    assert body["detail"], body


@pytest.mark.parametrize("field", ["stair_penalty_m", "window_penalty_m", "max_sill_height_m"])
@pytest.mark.parametrize("token", ["NaN", "Infinity"])
def test_non_finite_routing_constraint_is_422(client: TestClient, field: str, token: str):
    """Infinity used to be accepted and echoed back in RoutePlan.constraints as
    null, a schema-invalid plan; NaN 500'd in the error renderer."""
    text = json.dumps({"home": load_fixture("bungalow.json"), "constraints": {field: 1.5}})
    resp = _raw_post(client, "/routes", text.replace("1.5", token))
    assert resp.status_code == 422, resp.text[:300]
    _strict_json(resp)


def test_huge_but_finite_penalties_still_route(client: TestClient):
    resp = _post(client, "/routes", {"home": load_fixture("bungalow.json"),
                                     "constraints": {"stair_penalty_m": 1e308, "window_penalty_m": 1e308}})
    assert resp.status_code == 200
    plan = _rooms(_strict_json(resp))
    # Doors still win: no room's primary leaves by a window.
    assert all(not r["primary"]["uses_window"] for r in plan.values() if r["primary"])


# --- /diff_obstructions -------------------------------------------------------


def _diff_stored(objects: list | None = None) -> dict:
    rooms = [_room("a", 0, 0, 4, 4), _room("b", 4, 0, 8, 4)]
    ops = [_opening("front", "a", EXTERIOR_ID, "a", 0), _opening("ab", "a", "b", "a", 1)]
    return _home([_floor("f0", 0, rooms, ops, objects)])


def _diff_scan(objects: list) -> dict:
    return _home([_floor("f0", 0, [_room("a", 0, 0, 4, 4)], [], objects)])


def _obj(oid: str, cx: float, cy: float, w: float, d: float, **extra) -> dict:
    base = {"id": oid, "category": "wardrobe", "center": [cx, cy], "size_m": [w, d],
            "height_m": 2.0, "source": "manual"}
    return base | extra


def test_diff_reports_a_new_object_blocking_the_front_door(client: TestClient):
    """The routing engine probes an exit's approach ("the approach still matters",
    obstructions.py); the diff skipped every exit, so a wardrobe newly scanned in
    front of the only front door came back as no obstruction at all."""
    wardrobe = _obj("w1", 2.0, 0.5, 3.6, 0.8)
    resp = _post(client, "/diff_obstructions", {
        "stored_model": _diff_stored(), "scan_model": _diff_scan([wardrobe]), "target_room_id": "a"})
    assert resp.status_code == 200
    body = resp.json()
    assert [o["id"] for o in body["diff_objects"]] == ["scan_w1"]
    assert [(o["kind"], o["opening_id"], o["object_ids"]) for o in body["obstructions"]] == [
        ("blocks_opening", "front", ["scan_w1"])]

    # The same home through /routes agrees that the wardrobe blocks the front door.
    plan = _rooms(_post(client, "/routes", {"home": _diff_stored([wardrobe])}).json())
    assert ("blocked_opening", ["w1"]) in [(f["kind"], f["object_ids"]) for f in plan["a"]["findings"]]


def test_diff_does_not_blame_a_stored_object_whose_id_starts_with_scan(client: TestClient):
    """Ids from an earlier diff start with "scan_". A stored, already-known blocker
    with such an id was reported as a NEW obstruction whenever the re-scan found
    anything new anywhere in the room."""
    blocker = _obj("scan_old", 3.5, 2.0, 0.8, 3.6, source="scan", confidence=0.3)
    lamp = _obj("lamp", 0.6, 3.4, 0.3, 0.3, category="other")
    scan = _diff_scan([_obj("x1", 3.5, 2.0, 0.8, 3.6), lamp])
    resp = _post(client, "/diff_obstructions", {
        "stored_model": _diff_stored([blocker]), "scan_model": scan, "target_room_id": "a"})
    assert resp.status_code == 200
    body = resp.json()
    assert [o["id"] for o in body["diff_objects"]] == ["scan_lamp"]
    assert body["obstructions"] == []


def test_diff_missing_target_room_is_a_structured_failure(client: TestClient):
    resp = _post(client, "/diff_obstructions", {
        "stored_model": _diff_stored(), "scan_model": _diff_scan([]), "target_room_id": "nope"})
    assert resp.status_code == 200
    assert resp.json() == {"success": False, "error": "Target room not found in stored model",
                           "diff_objects": [], "obstructions": []}
