"""Navigation graph builder: HomeModel → NavGraph (S1.1). Pure functions, no I/O.

Nodes: rooms, openings, the EXTERIOR pseudo-node, with 2D positions + floor ids
so the renderer can turn paths into waypoints. Edges:

- room ↔ opening        weight = straight-line distance room centroid → opening midpoint
- opening ↔ EXTERIOR    weight 0 (exit crossing; door/window preference is applied
                        by the S1.2 engine as penalties, not baked in here)
- room ↔ room via stair weight = STAIR_TRAVERSAL_COST (cross-floor connector)

Windows that fail the egress thresholds keep their room ↔ opening edge but get
NO exterior edge — flagged, never silently dropped (graph.excluded_exits records
the reasons; a dead-end node can't appear on any shortest path to EXTERIOR).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum

from app.models import (
    EXTERIOR_ID,
    HomeModel,
    OpeningKind,
    Point,
)
from app.routing.egress import EgressThresholds, annotate_egress

STAIR_TRAVERSAL_COST = 6.0
"""Meters-equivalent cost of traversing a staircase (deliberately > a typical
same-floor hop so ground-floor exits are preferred when comparable)."""


class NodeKind(str, Enum):
    room = "room"
    opening = "opening"
    exterior = "exterior"


class EdgeKind(str, Enum):
    room_opening = "room_opening"
    exit_crossing = "exit_crossing"
    stair = "stair"


@dataclass(frozen=True)
class Node:
    id: str
    kind: NodeKind
    floor_id: str | None  # None only for EXTERIOR
    position: Point | None  # None only for EXTERIOR
    opening_kind: OpeningKind | None = None  # set for opening nodes


@dataclass(frozen=True)
class Edge:
    a: str
    b: str
    weight: float
    kind: EdgeKind
    via: str | None = None  # stair id for stair edges, else None

    def other(self, node_id: str) -> str:
        return self.b if node_id == self.a else self.a


@dataclass
class NavGraph:
    nodes: dict[str, Node] = field(default_factory=dict)
    adjacency: dict[str, list[Edge]] = field(default_factory=dict)
    exits: list[str] = field(default_factory=list)
    """Opening ids with a viable crossing to EXTERIOR, sorted."""
    excluded_exits: dict[str, list[str]] = field(default_factory=dict)
    """Exterior openings excluded as escape paths: opening id → reasons."""

    def neighbors(self, node_id: str) -> list[Edge]:
        return self.adjacency.get(node_id, [])


def polygon_centroid(polygon: list[Point]) -> Point:
    """Area-weighted centroid of a simple polygon."""
    area2 = 0.0
    cx = 0.0
    cy = 0.0
    n = len(polygon)
    for i in range(n):
        x1, y1 = polygon[i]
        x2, y2 = polygon[(i + 1) % n]
        cross = x1 * y2 - x2 * y1
        area2 += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    if area2 == 0:
        xs = [p[0] for p in polygon]
        ys = [p[1] for p in polygon]
        return (sum(xs) / n, sum(ys) / n)
    return (cx / (3.0 * area2), cy / (3.0 * area2))


def opening_midpoint(polygon: list[Point], edge_index: int, t0: float, t1: float) -> Point:
    """Midpoint of the opening's t-range on its host edge (edge i → i+1 mod n)."""
    p = polygon[edge_index]
    q = polygon[(edge_index + 1) % len(polygon)]
    t = (t0 + t1) / 2.0
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


def _dist(a: Point, b: Point) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def build_graph(home: HomeModel, thresholds: EgressThresholds) -> NavGraph:
    """Build the navigation graph for an entire home.

    The model is egress-annotated first (idempotent); viability drives which
    exterior openings get an exit crossing. Deterministic: node insertion and
    adjacency lists are sorted by id.
    """
    annotated = annotate_egress(home, thresholds)
    graph = NavGraph()
    edges: list[Edge] = []

    graph.nodes[EXTERIOR_ID] = Node(
        id=EXTERIOR_ID, kind=NodeKind.exterior, floor_id=None, position=None
    )

    room_centroids: dict[str, Point] = {}
    room_floor: dict[str, str] = {}
    room_polygons: dict[str, list[Point]] = {}

    for floor in annotated.floors:
        for room in floor.rooms:
            centroid = polygon_centroid(list(room.polygon))
            room_centroids[room.id] = centroid
            room_floor[room.id] = floor.id
            room_polygons[room.id] = list(room.polygon)
            graph.nodes[room.id] = Node(
                id=room.id, kind=NodeKind.room, floor_id=floor.id, position=centroid
            )

    for floor in annotated.floors:
        for op in floor.openings:
            host_polygon = room_polygons[op.wall_segment.room_id]
            midpoint = opening_midpoint(
                host_polygon,
                op.wall_segment.edge_index,
                op.wall_segment.t0,
                op.wall_segment.t1,
            )
            graph.nodes[op.id] = Node(
                id=op.id,
                kind=NodeKind.opening,
                floor_id=floor.id,
                position=midpoint,
                opening_kind=op.kind,
            )
            for rid in op.room_ids:
                if rid == EXTERIOR_ID:
                    continue
                edges.append(
                    Edge(
                        a=rid,
                        b=op.id,
                        weight=_dist(room_centroids[rid], midpoint),
                        kind=EdgeKind.room_opening,
                    )
                )
            if op.is_exit:
                assert op.egress is not None  # annotate_egress always sets it
                if op.egress.viable:
                    graph.exits.append(op.id)
                    edges.append(
                        Edge(
                            a=op.id,
                            b=EXTERIOR_ID,
                            weight=0.0,
                            kind=EdgeKind.exit_crossing,
                        )
                    )
                else:
                    graph.excluded_exits[op.id] = list(op.egress.reasons)

    for stair in annotated.stairs:
        edges.append(
            Edge(
                a=stair.from_.room_id,
                b=stair.to.room_id,
                weight=STAIR_TRAVERSAL_COST,
                kind=EdgeKind.stair,
                via=stair.id,
            )
        )

    graph.exits.sort()
    for node_id in graph.nodes:
        graph.adjacency[node_id] = []
    for edge in edges:
        graph.adjacency[edge.a].append(edge)
        graph.adjacency[edge.b].append(edge)
    for node_id in graph.adjacency:
        graph.adjacency[node_id].sort(key=lambda e: (e.other(node_id), e.kind.value))
    return graph
