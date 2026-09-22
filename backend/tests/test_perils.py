import json
import re

import pytest
from app.models import EXTERIOR_ID, Floor, HomeModel, Opening, Room, Source, WallSegmentRef
from app.routing.plan import RoutingConstraints
from app.routing.engine import compute_route_plan
from app.routing.egress import EgressThresholds
from app.routing.perils.tornado import count_exterior_walls

from tests.conftest import load_fixture, REPO_ROOT

@pytest.fixture
def twostory():
    return HomeModel.model_validate(load_fixture("twostory.json"))

@pytest.fixture
def jagged():
    return HomeModel.model_validate(load_fixture("jagged.json"))

@pytest.fixture
def bungalow_narrow():
    return HomeModel.model_validate(load_fixture("bungalow-narrow.json"))

@pytest.fixture
def thresholds():
    with open(REPO_ROOT / "backend/corpus/egress_thresholds.json") as f:
        return EgressThresholds.from_corpus(json.load(f))

def test_fire_vs_tornado_different_destinations(twostory, thresholds):
    # For a given room on twostory, e.g., the Master Bedroom, fire route exit is an exterior door
    plan_fire = compute_route_plan(twostory, thresholds, peril="fire")
    plan_tornado = compute_route_plan(twostory, thresholds, peril="tornado")
    
    room_fire = next(r for r in plan_fire.rooms if r.room_id == "r_bed_master")
    room_tornado = next(r for r in plan_tornado.rooms if r.room_id == "r_bed_master")
    
    # Fire routes to an exterior door
    assert room_fire.primary.exit_id == "d_front"
    
    # Tornado routes to a designated interior shelter type, not a door id.
    shelter = next(room for room in twostory.floors[0].rooms if room.id == room_tornado.primary.exit_id)
    assert shelter.type.value in {"bathroom", "closet", "hall"}


def test_paired_room_opening_uses_the_polygon_edge_key_once():
    """Exercise the non-host-room opening branch without double-counting its wall."""
    room = Room(
        id="room", name="Room", type="other", polygon=[(0, 0), (2, 0), (2, 2), (0, 2)],
        source=Source.manual,
    )
    # This representation cannot arrive through standard HomeModel validation:
    # an Opening validates its host room against room_ids.  Construct it directly
    # to pin the defensive branch for imported/pre-validation routing input.
    opening = Opening.model_construct(
        id="exit", kind="door", room_ids=["room", EXTERIOR_ID],
        wall_segment=WallSegmentRef(room_id="paired-room", edge_index=1, t0=0.25, t1=0.75),
        width_m=1, height_m=2, sill_height_m=0, source=Source.manual,
    )
    floor = Floor.model_construct(
        id="floor", level=0, name="Ground", height_m=2.5, rooms=[room], openings=[opening]
    )

    assert count_exterior_walls(room, floor) == 4

def test_mobility_limited_tornado_no_viable_safe_room(twostory, thresholds):
    constraints = RoutingConstraints(avoid_stairs=True)
    plan_tornado = compute_route_plan(twostory, thresholds, constraints=constraints, peril="tornado")
    
    room_tornado = next(r for r in plan_tornado.rooms if r.room_id == "r_bed_master")
    
    # Should be no_viable_safe_room
    assert room_tornado.primary is None
    assert any(f.kind == "no_viable_safe_room" for f in room_tornado.findings)

def test_a_site_built_home_always_gets_an_interior_shelter(bungalow_narrow, thresholds):
    """Replaces test_mobile_home_tornado_no_viable_safe_room (removed 2026-09-06).

    That test asserted a single-storey home whose every room touches an exterior wall has
    NO safe room — and ran it on `bungalow_narrow`, an ordinary site-built bungalow. It was
    pinning a defect: the engine told every bungalow and apartment occupant to leave the
    house during a tornado warning, while the corpus committed alongside it says to use the
    most interior room, "such as a bathroom, closet, or hallway"
    (severe-weather-tornado.md, [cite: noaa-tornado]).

    Construction type is not derivable from a footprint polygon, so geometry must never be
    used to infer a mobile home. Leave-the-house advice needs an explicit modelled fact.
    """
    plan = compute_route_plan(bungalow_narrow, thresholds, peril="tornado")

    assert plan.rooms[0].primary is not None, "a site-built home must be given a shelter"
    assert not any(
        f.kind == "no_viable_safe_room" for r in plan.rooms for f in (r.findings or [])
    )


@pytest.mark.parametrize(
    "fixture_name", ["bungalow", "apartment", "bungalow-blocked", "bungalow-narrow", "twostory", "jagged"]
)
def test_no_fixture_with_an_interior_room_is_told_to_leave(fixture_name, thresholds):
    """The regression guard for the above. Every committed fixture is a site-built home with
    at least one room carrying no exterior opening, so none of them may ever produce
    `no_viable_safe_room`. This is the assertion that would have caught the original defect:
    it fired on 4 of 5 fixtures and every suite still passed."""
    home = HomeModel.model_validate(load_fixture(f"{fixture_name}.json"))
    plan = compute_route_plan(home, thresholds, peril="tornado")

    unsheltered = [
        r.room_id
        for r in plan.rooms
        if any(f.kind == "no_viable_safe_room" for f in (r.findings or []))
    ]
    assert not unsheltered, f"{fixture_name}: no shelter found for {unsheltered}"

def test_earthquake_cover_points(jagged, thresholds):
    plan = compute_route_plan(jagged, thresholds, peril="earthquake")
    
    kitch = next(r for r in plan.rooms if r.room_id == "r_g_kitch")
    assert kitch.cover_object_id == "o_g_table"
    
    bath = next(r for r in plan.rooms if r.room_id == "r_g_live")
    assert bath.cover_object_id is None
    assert any(f.kind == "no_cover_in_room" for f in bath.findings)

def test_earthquake_cover_nearest_table(jagged, thresholds):
    # Add two tables to the same room, one closer to the centroid
    home = jagged.model_copy(deep=True)
    room = next(r for f in home.floors for r in f.rooms if r.id == "r_g_kitch")
    floor = next(f for f in home.floors if room in f.rooms)
    
    cx = sum(p[0] for p in room.polygon) / len(room.polygon)
    cy = sum(p[1] for p in room.polygon) / len(room.polygon)
    
    from app.models import FloorObject
    # Clear existing objects
    floor.objects = []
    
    table1 = FloorObject(
        id="t1", source="manual", category="table", center=(cx + 1, cy), size_m=(1, 1), height_m=1.0, rotation_deg=0
    )
    table2 = FloorObject(
        id="t2", source="manual", category="table", center=(cx + 5, cy), size_m=(1, 1), height_m=1.0, rotation_deg=0
    )
    floor.objects.extend([table2, table1]) # Added in reverse to ensure sorting by distance works
    
    plan = compute_route_plan(home, thresholds, peril="earthquake")
    r_plan = next(r for r in plan.rooms if r.room_id == room.id)
    assert r_plan.cover_object_id == "t1" # The closer one

def test_triangle_of_life_never_recommended(twostory, thresholds):
    plan = compute_route_plan(twostory, thresholds, peril="earthquake")
    for room in plan.rooms:
        for finding in room.findings:
            assert "beside" not in finding.detail.lower()
            assert "triangle" not in finding.detail.lower()

def test_earthquake_finding_has_valid_citation(twostory, thresholds):
    plan = compute_route_plan(twostory, thresholds, peril="earthquake")
    bath = next(r for r in plan.rooms if r.room_id == "r_bath2")
    finding = next(f for f in bath.findings if f.kind == "no_cover_in_room")
    assert finding.citation == "shakeout-guidance-dcho"
    
    with open(REPO_ROOT / "backend/corpus/sources.json") as f:
        sources = json.load(f)
    assert any(s["id"] == "shakeout-guidance-dcho" for s in sources["sources"])

def test_determinism_perils(twostory, thresholds):
    plan_t1 = compute_route_plan(twostory, thresholds, peril="tornado")
    plan_t2 = compute_route_plan(twostory, thresholds, peril="tornado")
    assert plan_t1.model_dump_json() == plan_t2.model_dump_json()
    
    plan_e1 = compute_route_plan(twostory, thresholds, peril="earthquake")
    plan_e2 = compute_route_plan(twostory, thresholds, peril="earthquake")
    assert plan_e1.model_dump_json() == plan_e2.model_dump_json()


# ---------------------------------------------------------------------------
# RouteFinding.citation (S11.2)
#
# The field already existed on both sides of the wire (app/routing/plan.py and
# escape_plan/Models/RoutePlan.swift). What did not exist was anything holding it
# honest. BLOCKERS §3 listed the field as closed while its text still read as a
# next action; this is the test that settles it.
#
# The policy is a known-answer table, not a self-consistent assertion. Listing
# which kinds give advice — rather than asking the code what it currently does —
# is what makes the test able to disagree with the code.
# ---------------------------------------------------------------------------

#: Finding kinds whose `detail` tells the resident to DO something. Every one of
#: these is a safety claim and must carry a citation that resolves.
CITED_FINDING_KINDS = {
    "blocked_opening",
    "narrows_route",
    "no_cover_in_room",
    "no_viable_safe_room",
}

#: Finding kinds that only describe the home's geometry — "there is no second way
#: out of this room". No advice, so no citation is required. They are guarded
#: below: the moment someone adds advice to one, the test goes red.
DESCRIPTIVE_FINDING_KINDS = {
    "no_viable_route",
    "no_secondary_egress",
}

#: Imperative openers that mark a sentence as guidance rather than description.
IMPERATIVE_ADVICE = re.compile(
    r"\b(?:drop|cover|go now|get out|get to|move to|seek shelter|call|shut off|"
    r"stay away|leave|evacuate|take shelter|crawl|hold on)\b",
    re.IGNORECASE,
)


def _valid_source_ids() -> frozenset[str]:
    """The same helper the AI layer validates model citations against.

    Deliberately not a second reader of sources.json: if the deterministic engine
    and the AI disagreed about which ids exist, this test would not notice.
    """
    from app.ai.grounded import valid_source_ids

    return valid_source_ids()


def _all_findings(home, thresholds):
    """Every finding the engine can produce for this home.

    The unconstrained pass alone never reaches `no_viable_route` or
    `no_viable_safe_room` on any fixture in schema/fixtures/ — a site-built home
    with working stairs always has both. The `avoid_stairs` pass is what makes
    those two kinds observable, which is the same scenario the high-severity
    composite cap exists for (see docs/preparedness-score-weights.md).
    """
    # The unconstrained pass alone reaches only four of the six kinds. The second
    # is the mobility-limited case the high-severity composite cap exists for
    # (docs/preparedness-score-weights.md): someone who can use neither the stairs
    # nor a window. That is what makes `no_viable_route` and `no_viable_safe_room`
    # observable at all — no fixture produces them otherwise.
    passes = (
        None,
        RoutingConstraints(avoid_stairs=True, avoid_windows=True),
    )
    for peril in ("fire", "earthquake", "tornado"):
        for constraints in passes:
            plan = compute_route_plan(
                home, thresholds, constraints=constraints, peril=peril
            )
            for room in plan.rooms:
                for finding in room.findings:
                    yield peril, finding


@pytest.mark.parametrize(
    "fixture_name",
    ["bungalow.json", "apartment.json", "twostory.json", "bungalow-blocked.json",
     "bungalow-narrow.json"],
)
def test_every_route_finding_citation_resolves(fixture_name, thresholds):
    """No RouteFinding may cite a source id that is not in sources.json.

    This is the same class of defect S11.1 spent a session removing from the
    corpus: a cite that looks fine because nothing ever crossed it against the
    source list.
    """
    home = HomeModel.model_validate(load_fixture(fixture_name))
    valid = _valid_source_ids()
    for peril, finding in _all_findings(home, thresholds):
        if finding.citation is not None:
            assert finding.citation in valid, (
                f"{fixture_name}/{peril}: finding {finding.kind!r} cites "
                f"{finding.citation!r}, which is not in sources.json"
            )


@pytest.mark.parametrize(
    "fixture_name",
    ["bungalow.json", "apartment.json", "twostory.json", "bungalow-blocked.json",
     "bungalow-narrow.json"],
)
def test_advice_bearing_findings_are_cited(fixture_name, thresholds):
    """A finding that tells the resident what to do must say where that came from."""
    home = HomeModel.model_validate(load_fixture(fixture_name))
    seen_kinds = set()
    for peril, finding in _all_findings(home, thresholds):
        seen_kinds.add(finding.kind)
        if finding.kind in CITED_FINDING_KINDS:
            assert finding.citation, (
                f"{fixture_name}/{peril}: {finding.kind!r} gives guidance "
                f"({finding.detail!r}) with no citation"
            )
    assert seen_kinds, f"{fixture_name} produced no findings at all — test is vacuous"


def test_the_fixtures_between_them_exercise_every_finding_kind(thresholds):
    """The anti-vacuity guard for the two tests above.

    Each of those is parametrized per fixture and can only check the kinds that
    fixture happens to produce. Without this, a kind that stopped being emitted
    anywhere would make its citation policy silently untested rather than red.
    """
    from typing import get_args
    from app.routing.plan import RouteFinding

    seen: set[str] = set()
    for fixture_name in ("bungalow.json", "apartment.json", "twostory.json",
                         "bungalow-blocked.json", "bungalow-narrow.json"):
        home = HomeModel.model_validate(load_fixture(fixture_name))
        for _peril, finding in _all_findings(home, thresholds):
            seen.add(finding.kind)

    declared = set(get_args(RouteFinding.model_fields["kind"].annotation))
    assert seen == declared, (
        f"finding kinds no fixture produces, so their citation policy is untested: "
        f"{sorted(declared - seen)}"
    )


@pytest.mark.parametrize(
    "fixture_name",
    ["bungalow.json", "apartment.json", "twostory.json", "bungalow-blocked.json",
     "bungalow-narrow.json"],
)
def test_uncited_findings_stay_purely_descriptive(fixture_name, thresholds):
    """The guard that keeps the table above from rotting.

    `no_viable_route` and `no_secondary_egress` carry no citation because they
    describe geometry rather than advise action. If someone later writes advice
    into one of them without adding a source, this goes red instead of shipping
    an uncited safety claim.
    """
    home = HomeModel.model_validate(load_fixture(fixture_name))
    for peril, finding in _all_findings(home, thresholds):
        if finding.kind in DESCRIPTIVE_FINDING_KINDS and finding.citation is None:
            match = IMPERATIVE_ADVICE.search(finding.detail)
            assert match is None, (
                f"{fixture_name}/{peril}: {finding.kind!r} now gives advice "
                f"({match.group(0)!r} in {finding.detail!r}) but carries no citation. "
                f"Either cite it and move the kind into CITED_FINDING_KINDS, or "
                f"keep the detail descriptive."
            )


def test_the_two_finding_tables_cover_every_kind():
    """A new RouteFinding kind must be classified, not silently unguarded."""
    from typing import get_args
    from app.routing.plan import RouteFinding

    declared = set(get_args(RouteFinding.model_fields["kind"].annotation))
    classified = CITED_FINDING_KINDS | DESCRIPTIVE_FINDING_KINDS
    assert declared == classified, (
        f"RouteFinding kinds not classified as advice-bearing or descriptive: "
        f"{declared - classified}. Add each to one of the two tables in this file."
    )
