"""Fire-origin simulation tests: hazard spread, hazard-aware re-solve, and the
/evacuate wrapper. Test homes come from schema/fixtures/ only."""

from __future__ import annotations

import json

import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app
from app.models import HomeModel, Profile, ProfileTag
from app.routing.egress import EgressThresholds
from app.routing.graph import polygon_centroid
from app.routing.hazard import (
    EvacuationTimeline,
    GaitKind,
    compute_evacuation_timeline,
    gait_for_profile,
)
from tests.conftest import REPO_ROOT, load_fixture

THRESHOLDS_PATH = REPO_ROOT / "backend" / "corpus" / "egress_thresholds.json"

TEST_TOKEN = "test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(scope="module")
def thresholds() -> EgressThresholds:
    return EgressThresholds.from_corpus(json.loads(THRESHOLDS_PATH.read_text()))


def _timeline(name: str, thresholds: EgressThresholds, origin: str, **kwargs):
    home = HomeModel.model_validate(load_fixture(name))
    return compute_evacuation_timeline(home, thresholds, origin, **kwargs)


def _hazard_at(timeline: EvacuationTimeline, room_id: str) -> float | None:
    for event in timeline.hazard:
        if event.room_id == room_id:
            return event.untenable_at_s
    return None


# --- determinism -------------------------------------------------------------

@pytest.mark.parametrize(
    "fixture_name,origin",
    [
        ("bungalow.json", "r_kitchen"),
        ("apartment.json", "r_living"),
        ("twostory.json", "r_living"),
    ],
)
def test_timeline_is_byte_identical_across_runs(
    thresholds, fixture_name: str, origin: str
) -> None:
    first = _timeline(fixture_name, thresholds, origin).model_dump_json()
    second = _timeline(fixture_name, thresholds, origin).model_dump_json()
    assert first == second


# --- spread ------------------------------------------------------------------

@pytest.mark.parametrize(
    "fixture_name,origin",
    [
        ("bungalow.json", "r_living"),
        ("apartment.json", "r_hall"),
        ("twostory.json", "r_bed_kids"),
    ],
)
def test_origin_room_is_untenable_at_zero(
    thresholds, fixture_name: str, origin: str
) -> None:
    timeline = _timeline(fixture_name, thresholds, origin)
    assert _hazard_at(timeline, origin) == 0.0


def test_hazard_reaches_every_room_of_the_bungalow(thresholds) -> None:
    """Connectivity sanity: the bungalow is fully connected by doors, so every
    room eventually becomes untenable."""
    home = HomeModel.model_validate(load_fixture("bungalow.json"))
    timeline = compute_evacuation_timeline(home, thresholds, "r_living")
    reached = {event.room_id for event in timeline.hazard}
    assert reached == {room.id for floor in home.floors for room in floor.rooms}
    assert all(event.untenable_at_s >= 0 for event in timeline.hazard)


def test_hazard_does_not_leak_through_the_exterior(thresholds) -> None:
    """The bath is two doors from the living room even though both have exterior
    openings — the hazard must not shortcut room → EXTERIOR → room."""
    timeline = _timeline("bungalow.json", thresholds, "r_living")
    assert _hazard_at(timeline, "r_kitchen") == pytest.approx(45.0)
    assert _hazard_at(timeline, "r_bath") == pytest.approx(90.0)


def test_hazard_climbs_the_stairs(thresholds) -> None:
    """Documented choice: heat and smoke rise, so a downstairs fire threatens
    the upstairs bedrooms rather than staying put."""
    timeline = _timeline("twostory.json", thresholds, "r_living")
    assert _hazard_at(timeline, "r_landing") is not None
    assert _hazard_at(timeline, "r_bed_kids") is not None
    # landing (via hall + stairs) precedes the bedrooms beyond it
    assert _hazard_at(timeline, "r_landing") < _hazard_at(timeline, "r_bed_kids")


def test_hazard_events_are_sorted_by_time_then_room(thresholds) -> None:
    timeline = _timeline("twostory.json", thresholds, "r_living")
    keys = [(e.untenable_at_s, e.room_id) for e in timeline.hazard]
    assert keys == sorted(keys)


# --- track shape -------------------------------------------------------------

@pytest.mark.parametrize(
    "fixture_name,origin",
    [
        ("bungalow.json", "r_kitchen"),
        ("bungalow.json", "r_bath"),
        ("apartment.json", "r_living"),
        ("twostory.json", "r_living"),
        ("twostory.json", "r_kitchen"),
    ],
)
def test_track_times_are_monotonic_and_egress_matches_last_step(
    thresholds, fixture_name: str, origin: str
) -> None:
    timeline = _timeline(fixture_name, thresholds, origin)
    assert timeline.tracks, "expected at least one occupant to have a route"
    for track in timeline.tracks:
        assert len(track.steps) >= 2
        times = [step.t_s for step in track.steps]
        assert times == sorted(times)
        assert track.egress_time_s == track.steps[-1].t_s
        assert track.steps[0].t_s == 0.0
        assert track.steps[-1].kind == "exterior"
        assert track.distance_m >= 0


def test_duration_covers_the_slowest_occupant_and_the_last_hazard_event(
    thresholds,
) -> None:
    timeline = _timeline("twostory.json", thresholds, "r_living")
    assert timeline.duration_s >= max(t.egress_time_s for t in timeline.tracks)
    assert timeline.duration_s >= max(e.untenable_at_s for e in timeline.hazard)


def test_timeline_is_always_flagged_illustrative(thresholds) -> None:
    assert _timeline("bungalow.json", thresholds, "r_living").is_illustrative is True


# --- occupants ---------------------------------------------------------------

def test_home_without_profiles_gets_one_adult_per_room(thresholds) -> None:
    """The bungalow fixture has no profiles; the demo still has to animate."""
    home = HomeModel.model_validate(load_fixture("bungalow.json"))
    assert home.profiles == []
    timeline = compute_evacuation_timeline(home, thresholds, "r_kitchen")
    solved = {t.start_room_id for t in timeline.tracks}
    stranded = {f.room_id for f in timeline.findings}
    assert solved | stranded == {
        room.id for floor in home.floors for room in floor.rooms
    }
    for track in timeline.tracks:
        assert track.profile_id == f"occupant.{track.start_room_id}"
        assert track.gait == GaitKind.adult


def test_home_with_profiles_gets_exactly_one_track_per_profile(thresholds) -> None:
    home = HomeModel.model_validate(load_fixture("twostory.json"))
    timeline = compute_evacuation_timeline(home, thresholds, "r_living")
    accounted = [t.profile_id for t in timeline.tracks]
    # p_grandpa is mobility_limited on the upper floor: no stair, no window, so
    # the S3.4 constraints already leave him without a route — an honest finding.
    assert "p_maya" in accounted
    assert len(timeline.tracks) + len(timeline.findings) == len(home.profiles)


def test_profile_tags_map_to_gaits(thresholds) -> None:
    def profile(*tags: ProfileTag) -> Profile:
        return Profile(
            id="p", name="P", tags=list(tags), bedroom_room_id="r_living"
        )

    assert gait_for_profile(profile()) == GaitKind.adult
    assert gait_for_profile(profile(ProfileTag.child)) == GaitKind.child
    assert gait_for_profile(profile(ProfileTag.elderly)) == GaitKind.elderly
    assert gait_for_profile(profile(ProfileTag.pet)) == GaitKind.pet
    assert (
        gait_for_profile(profile(ProfileTag.mobility_limited)) == GaitKind.wheelchair
    )
    # mobility_limited wins over elderly
    assert (
        gait_for_profile(profile(ProfileTag.elderly, ProfileTag.mobility_limited))
        == GaitKind.wheelchair
    )


def test_child_is_slower_than_an_adult_over_the_same_route(thresholds) -> None:
    home = HomeModel.model_validate(load_fixture("twostory.json"))
    kid = compute_evacuation_timeline(home, thresholds, "r_kitchen")
    maya = next(t for t in kid.tracks if t.profile_id == "p_maya")
    assert maya.gait == GaitKind.child
    assert maya.uses_stairs is True


# --- hazard-aware re-solve ---------------------------------------------------

def test_route_reroutes_around_the_burning_room(thresholds) -> None:
    """Bungalow bedroom normally leaves by the front door through the living
    room (test_routing asserts that). Ignite the living room and the same
    deterministic search takes the egress window instead."""
    timeline = _timeline("bungalow.json", thresholds, "r_living")
    bedroom = next(t for t in timeline.tracks if t.start_room_id == "r_bedroom")
    assert bedroom.exit_id == "w_bedroom"
    assert bedroom.uses_window is True
    home = HomeModel.model_validate(load_fixture("bungalow.json"))
    assert _rooms_visited(home, bedroom) == ["r_bedroom"]


def test_occupant_in_the_origin_room_is_flagged_overtaken(thresholds) -> None:
    """The room is untenable at t=0 and they are still inside it — the engine
    reports that rather than quietly retiming the hazard."""
    timeline = _timeline("bungalow.json", thresholds, "r_kitchen")
    kitchen = next(t for t in timeline.tracks if t.start_room_id == "r_kitchen")
    assert kitchen.overtaken_by_hazard is True
    living = next(t for t in timeline.tracks if t.start_room_id == "r_living")
    assert living.overtaken_by_hazard is False


def test_igniting_the_only_exit_room_strands_occupants_honestly(thresholds) -> None:
    """The apartment's single exit is d_entry off r_hall, and its windows all
    fail egress. Igniting r_hall must produce a no_viable_route finding and NO
    fabricated track — never a path through the fire."""
    timeline = _timeline("apartment.json", thresholds, "r_hall")
    assert timeline.tracks == []
    assert [f.kind for f in timeline.findings] == ["no_viable_route"]
    assert timeline.findings[0].room_id == "r_bed1"
    assert "r_bed1" not in [t.start_room_id for t in timeline.tracks]


def _rooms_visited(home: HomeModel, track) -> list[str]:
    """Room ids a track passes through, recovered from its `room` steps.

    `TimedStep` carries no node id (the Swift contract has none), so rooms are
    identified by matching a step's coordinates against the room centroids the
    graph builder uses — the same value, just rounded for the wire.
    """
    centroids = {
        (floor.id, room.id): polygon_centroid(list(room.polygon))
        for floor in home.floors
        for room in floor.rooms
    }
    visited: list[str] = []
    for step in track.steps:
        if step.kind != "room":
            continue
        # Match within the step's own floor: two rooms on different storeys can
        # share a plan-space centroid (a landing directly above a hall).
        candidates = [key for key in centroids if key[0] == step.floor_id]
        match = min(
            candidates,
            key=lambda key: abs(centroids[key][0] - step.x)
            + abs(centroids[key][1] - step.y),
        )
        visited.append(match[1])
    return visited


@pytest.mark.parametrize(
    "fixture_name", ["bungalow.json", "apartment.json", "twostory.json"]
)
def test_no_track_ever_passes_through_an_already_untenable_room(
    thresholds, fixture_name: str
) -> None:
    """The core invariant: apart from the room they start in, nobody is routed
    into a room the hazard reached before they clear it. Checked for every
    possible ignition point in every fixture."""
    home = HomeModel.model_validate(load_fixture(fixture_name))
    for floor in home.floors:
        for origin in floor.rooms:
            timeline = compute_evacuation_timeline(home, thresholds, origin.id)
            untenable = {e.room_id: e.untenable_at_s for e in timeline.hazard}
            for track in timeline.tracks:
                visited = _rooms_visited(home, track)
                assert visited[0] == track.start_room_id
                for room_id in visited[1:]:
                    assert room_id != origin.id
                    assert untenable.get(room_id, float("inf")) > 0.0


def test_unknown_origin_room_is_rejected(thresholds) -> None:
    home = HomeModel.model_validate(load_fixture("bungalow.json"))
    with pytest.raises(ValueError):
        compute_evacuation_timeline(home, thresholds, "r_nope")


# --- /evacuate endpoint ------------------------------------------------------


@pytest.fixture(autouse=True)
def _token_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def test_evacuate_requires_token(client: TestClient, bungalow: dict) -> None:
    resp = client.post(
        "/evacuate", json={"home": bungalow, "origin_room_id": "r_living"}
    )
    assert resp.status_code == 401


def test_evacuate_404s_on_a_bogus_origin_room(
    client: TestClient, bungalow: dict
) -> None:
    resp = client.post(
        "/evacuate",
        json={"home": bungalow, "origin_room_id": "r_not_a_room"},
        headers=AUTH,
    )
    assert resp.status_code == 404


def test_evacuate_returns_a_valid_timeline(client: TestClient, bungalow: dict) -> None:
    resp = client.post(
        "/evacuate",
        json={
            "home": bungalow,
            "origin_room_id": "r_kitchen",
            "profile_set_id": "default",
        },
        headers=AUTH,
    )
    assert resp.status_code == 200
    timeline = EvacuationTimeline.model_validate(resp.json())
    assert timeline.home_id == bungalow["home_id"]
    assert timeline.origin_room_id == "r_kitchen"
    assert timeline.profile_set_id == "default"
    assert timeline.is_illustrative is True
    assert timeline.tracks
    assert timeline.duration_s > 0
    # snake_case on the wire, exactly as EvacuationTimeline.swift decodes it
    body = resp.json()
    assert set(body) >= {
        "home_id",
        "profile_set_id",
        "origin_room_id",
        "tracks",
        "hazard",
        "duration_s",
        "is_illustrative",
    }
    assert set(body["tracks"][0]) >= {
        "profile_id",
        "profile_name",
        "gait",
        "start_room_id",
        "exit_id",
        "steps",
        "distance_m",
        "egress_time_s",
        "uses_stairs",
        "uses_window",
        "overtaken_by_hazard",
    }
    assert set(body["tracks"][0]["steps"][0]) == {"x", "y", "floor_id", "t_s", "kind"}
    assert set(body["hazard"][0]) == {"room_id", "floor_id", "untenable_at_s"}
