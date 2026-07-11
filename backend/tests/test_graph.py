"""S1.1 tests: navigation graph on the three fixtures, hand-verified expectations."""

from __future__ import annotations

import json

import pytest

from app.models import EXTERIOR_ID, HomeModel
from app.routing.egress import EgressThresholds, annotate_egress, check_egress
from app.routing.graph import (
    EdgeKind,
    build_graph,
    opening_midpoint,
    polygon_centroid,
)
from tests.conftest import REPO_ROOT, load_fixture

THRESHOLDS_PATH = REPO_ROOT / "backend" / "corpus" / "egress_thresholds.json"


@pytest.fixture(scope="module")
def thresholds() -> EgressThresholds:
    return EgressThresholds.from_corpus(json.loads(THRESHOLDS_PATH.read_text()))


def _model(name: str) -> HomeModel:
    return HomeModel.model_validate(load_fixture(name))


def _adjacent(graph, a: str, b: str) -> bool:
    return any(e.other(a) == b for e in graph.neighbors(a))


# --- geometry helpers -------------------------------------------------------

def test_polygon_centroid_rectangle() -> None:
    assert polygon_centroid([(0, 0), (4, 0), (4, 2), (0, 2)]) == (2.0, 1.0)


def test_opening_midpoint_on_edge() -> None:
    poly = [(0.0, 0.0), (5.0, 0.0), (5.0, 4.0), (0.0, 4.0)]
    x, y = opening_midpoint(poly, 0, 0.4, 0.6)
    assert (x, y) == (2.5, 0.0)


# --- egress checks ----------------------------------------------------------

def test_egress_thresholds_load(thresholds: EgressThresholds) -> None:
    assert thresholds.window_min_width_m == 0.508
    assert thresholds.window_max_sill_m == 1.118


def test_annotate_egress_bungalow(thresholds: EgressThresholds) -> None:
    home = annotate_egress(_model("bungalow.json"), thresholds)
    egress = {o.id: o.egress for o in home.floors[0].openings}
    assert egress["w_bedroom"].viable
    assert egress["w_living"].viable
    assert not egress["w_bath"].viable
    assert any("sill" in r for r in egress["w_bath"].reasons)
    assert egress["d_front"].viable


def test_annotate_egress_does_not_mutate_input(thresholds: EgressThresholds) -> None:
    home = _model("bungalow.json")
    annotate_egress(home, thresholds)
    assert all(o.egress is None for o in home.floors[0].openings)


def test_kids_window_fails_width_and_area(thresholds: EgressThresholds) -> None:
    home = _model("twostory.json")
    kids = next(
        o for f in home.floors for o in f.openings if o.id == "w_kids"
    )
    result = check_egress(kids, thresholds, grade_floor=False)
    assert not result.viable
    assert any("width" in r for r in result.reasons)
    assert any("area" in r for r in result.reasons)


# --- bungalow graph ---------------------------------------------------------

def test_bungalow_graph_shape(thresholds: EgressThresholds) -> None:
    graph = build_graph(_model("bungalow.json"), thresholds)
    # 4 rooms + 7 openings + EXTERIOR
    assert len(graph.nodes) == 12
    # viable exits: front door + 2 egress windows; bath window excluded
    assert graph.exits == ["d_front", "w_bedroom", "w_living"]
    assert set(graph.excluded_exits) == {"w_bath"}
    # hand-verified adjacency
    assert _adjacent(graph, "r_living", "d_front")
    assert _adjacent(graph, "r_living", "d_living_kitchen")
    assert _adjacent(graph, "r_kitchen", "d_living_kitchen")
    assert _adjacent(graph, "r_bedroom", "d_living_bedroom")
    assert _adjacent(graph, "d_front", EXTERIOR_ID)
    assert _adjacent(graph, "w_bedroom", EXTERIOR_ID)
    assert not _adjacent(graph, "w_bath", EXTERIOR_ID)  # excluded, still a node
    assert "w_bath" in graph.nodes
    assert not _adjacent(graph, "r_living", "r_kitchen")  # rooms only meet via openings


def test_room_opening_edge_weight_is_distance(thresholds: EgressThresholds) -> None:
    graph = build_graph(_model("bungalow.json"), thresholds)
    edge = next(e for e in graph.neighbors("r_living") if e.other("r_living") == "d_front")
    # living centroid (2.5, 2.0); d_front midpoint t=0.49 on edge (0,0)->(5,0) = (2.45, 0)
    assert edge.weight == pytest.approx(((2.5 - 2.45) ** 2 + 2.0**2) ** 0.5)


# --- apartment graph (bottleneck home) ---------------------------------------

def test_apartment_single_viable_exit(thresholds: EgressThresholds) -> None:
    graph = build_graph(_model("apartment.json"), thresholds)
    # all windows have 1.4m sills -> only the entry door is a viable exit
    assert graph.exits == ["d_entry"]
    assert set(graph.excluded_exits) == {"w_bed1", "w_bed2", "w_living"}
    for reasons in graph.excluded_exits.values():
        assert any("sill" in r for r in reasons)
    # every room reaches the hall through its door
    for rid, door in [
        ("r_bed1", "d_hall_bed1"),
        ("r_bed2", "d_hall_bed2"),
        ("r_living", "d_hall_living"),
        ("r_kitchen", "d_hall_kitchen"),
    ]:
        assert _adjacent(graph, rid, door)
        assert _adjacent(graph, "r_hall", door)


# --- twostory graph (cross-floor stair edge) ---------------------------------

def test_twostory_stair_edge(thresholds: EgressThresholds) -> None:
    graph = build_graph(_model("twostory.json"), thresholds)
    stair_edges = [
        e for e in graph.neighbors("r_hall1") if e.kind == EdgeKind.stair
    ]
    assert len(stair_edges) == 1
    assert stair_edges[0].other("r_hall1") == "r_landing"
    assert stair_edges[0].via == "s_main"
    assert stair_edges[0].weight > 2.0  # costlier than a typical same-floor hop


def test_twostory_exits_and_exclusions(thresholds: EgressThresholds) -> None:
    graph = build_graph(_model("twostory.json"), thresholds)
    assert graph.exits == ["d_back", "d_front", "w_living1", "w_master"]
    assert set(graph.excluded_exits) == {"w_bath2", "w_kids"}


def test_nodes_carry_floor_and_position(thresholds: EgressThresholds) -> None:
    graph = build_graph(_model("twostory.json"), thresholds)
    assert graph.nodes["r_bed_kids"].floor_id == "f2"
    assert graph.nodes["d_front"].floor_id == "f1"
    assert graph.nodes[EXTERIOR_ID].position is None
    assert graph.nodes["r_landing"].position == (5.0, 4.0)


# --- determinism / purity -----------------------------------------------------

def test_build_graph_is_deterministic(thresholds: EgressThresholds) -> None:
    g1 = build_graph(_model("twostory.json"), thresholds)
    g2 = build_graph(_model("twostory.json"), thresholds)
    assert g1.exits == g2.exits
    assert g1.excluded_exits == g2.excluded_exits
    assert list(g1.nodes) == list(g2.nodes)
    for node_id in g1.adjacency:
        assert g1.adjacency[node_id] == g2.adjacency[node_id]
