"""Within-room occupancy grid (revamp B3). Pure functions, no I/O, deterministic.

The room graph stays the architecture: rooms are nodes, openings are edges. What
this module adds is the INSIDE of a room — a uniform occupancy grid over one
room's polygon with the floor's objects rasterized as blocked cells — so a
room ↔ opening leg can path AROUND furniture, and a doorway an object fully
blocks yields no leg at all (the graph then re-plans at room level).

Grid over navmesh, deliberately: integer cell indices and integer A* costs are
deterministic by construction (same input → byte-identical output), trivially
testable, and box primitives rasterize exactly. Cell size 0.1 m resolves the
egress width thresholds in corpus/egress_thresholds.json.

Clearance: a cell is traversable only when its distance to the nearest blocked
cell (object or outside the room) is at least half the door clear-width
threshold — an object that shrinks a passage below the egress width blocks the
leg even without touching the walls. The threshold arrives from the corpus
(metric authoritative), never hardcoded here.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from app.models import Floor, FloorObject, Point, Polygon

CELL_M = 0.1
"""Grid resolution in meters."""

_SQRT2_SCALED = 14
_STRAIGHT_SCALED = 10
"""Integer step costs (diagonal ≈ √2·straight) — integer arithmetic keeps A*
byte-deterministic across platforms."""


@dataclass(frozen=True)
class RoomGrid:
    """Occupancy + clearance for one room. Cells indexed (col, row) from
    (min_x, min_y); cell (c, r) covers [min_x + c·CELL, min_x + (c+1)·CELL) ×
    [min_y + r·CELL, ...). `walkable` marks cells whose CENTER is inside the
    room polygon, outside every object, and clearance-satisfying."""

    min_x: float
    min_y: float
    cols: int
    rows: int
    walkable: tuple[bool, ...]  # row-major: index = r * cols + c

    def index(self, c: int, r: int) -> int:
        return r * self.cols + c

    def contains(self, c: int, r: int) -> bool:
        return 0 <= c < self.cols and 0 <= r < self.rows

    def is_walkable(self, c: int, r: int) -> bool:
        return self.contains(c, r) and self.walkable[self.index(c, r)]

    def cell_for(self, p: Point) -> tuple[int, int]:
        return (
            int(math.floor((p[0] - self.min_x) / CELL_M)),
            int(math.floor((p[1] - self.min_y) / CELL_M)),
        )

    def center_of(self, c: int, r: int) -> Point:
        return (
            self.min_x + (c + 0.5) * CELL_M,
            self.min_y + (r + 0.5) * CELL_M,
        )


def point_in_polygon(polygon: Polygon, p: Point) -> bool:
    """Ray-cast containment; boundary points count as inside."""
    x, y = p
    inside = False
    n = len(polygon)
    for i in range(n):
        x1, y1 = polygon[i]
        x2, y2 = polygon[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            x_cross = x1 + (y - y1) / (y2 - y1) * (x2 - x1)
            if x < x_cross:
                inside = not inside
    return inside


def object_contains(obj: FloorObject, p: Point) -> bool:
    """Point-in-rotated-rect, mirroring the editor's HitTesting.objectContains."""
    w, d = obj.size_m
    angle = -math.radians(obj.rotation_deg)
    dx = p[0] - obj.center[0]
    dy = p[1] - obj.center[1]
    local_x = dx * math.cos(angle) - dy * math.sin(angle)
    local_y = dx * math.sin(angle) + dy * math.cos(angle)
    return abs(local_x) <= w / 2 and abs(local_y) <= d / 2


def obstructs_floor(obj: FloorObject) -> bool:
    """Whether an object takes floor away from someone walking past it.

    **A `mounted` object does not.** `mounted` is the schema's answer to "how is
    this installed" (v2.1, S7.1) — a wall-mounted TV, a ceiling fixture, a
    floating shelf — as opposed to `secured`, which answers "is it strapped
    down". Something hanging on a wall is not standing on the floor, so the floor
    beneath it is walkable and routing must not erode it.

    Without this the rasterizer blocks any footprint it is handed, whatever its
    elevation: moving `jagged.json`'s `o_u_tv_over_bed` into the middle of the
    room drops that room's free cells **5476 → 5296**, purely because a television
    is bolted to the wall 1.35 m up. The fixture hides it today only because the
    TV overlaps the bed, which is blocked anyway — so the bug was real, latent,
    and invisible to every test.

    **What this deliberately does NOT model:** how far a mounted object protrudes.
    A deep wall cabinet at chest height is treated as not obstructing, the same as
    a flat TV. Modelling that needs a body-envelope check the engine has no
    concept of, and the error is small and in the safe direction for egress —
    routing may offer a path a shoulder brushes, never one that does not exist.
    `elevation_m` is intentionally unused here for the same reason: a floor-
    standing object always has `elevation_m == 0`, and a raised one that is not
    mounted (a box on a table) is still something you cannot walk through.
    """
    return not obj.mounted


def objects_intersecting(polygon: Polygon, objects: list[FloorObject]) -> list[FloorObject]:
    """Objects whose bounding circle overlaps the room's bounding box — a cheap,
    conservative filter (false positives cost only rasterization time)."""
    if not objects:
        return []
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]
    out: list[FloorObject] = []
    for obj in objects:
        radius = math.hypot(obj.size_m[0], obj.size_m[1]) / 2
        if (
            obj.center[0] + radius >= min(xs)
            and obj.center[0] - radius <= max(xs)
            and obj.center[1] + radius >= min(ys)
            and obj.center[1] - radius <= max(ys)
        ):
            out.append(obj)
    return out


def build_room_grid(
    polygon: Polygon, objects: list[FloorObject], clearance_m: float
) -> RoomGrid:
    """Rasterize one room: inside-polygon minus objects, then erode by
    `clearance_m` via an exact (scaled-integer) two-pass distance transform."""
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]
    min_x, min_y = min(xs), min(ys)
    cols = max(1, int(math.ceil((max(xs) - min_x) / CELL_M)))
    rows = max(1, int(math.ceil((max(ys) - min_y) / CELL_M)))

    poly = list(polygon)
    open_cells = [False] * (cols * rows)
    for r in range(rows):
        for c in range(cols):
            center = (min_x + (c + 0.5) * CELL_M, min_y + (r + 0.5) * CELL_M)
            if not point_in_polygon(poly, center):
                continue
            if any(object_contains(o, center) for o in objects if obstructs_floor(o)):
                continue
            open_cells[r * cols + c] = True

    walkable = _erode_by_clearance(open_cells, cols, rows, clearance_m)
    return RoomGrid(
        min_x=min_x, min_y=min_y, cols=cols, rows=rows, walkable=tuple(walkable)
    )


def _erode_by_clearance(
    open_cells: list[bool], cols: int, rows: int, clearance_m: float
) -> list[bool]:
    """Chamfer distance transform (3-4 mask, scaled ints) to the nearest
    non-open cell; cells closer than `clearance_m` become non-walkable."""
    inf = 1 << 30
    # Distance in scaled units where straight = 10, diagonal = 14 (≈ ×CELL_M/10 meters).
    dist = [0 if not open_cells[i] else inf for i in range(cols * rows)]

    def at(c: int, r: int) -> int:
        if c < 0 or c >= cols or r < 0 or r >= rows:
            return 0  # outside the raster counts as blocked
        return dist[r * cols + c]

    # Forward pass (top-left → bottom-right), then backward.
    for r in range(rows):
        for c in range(cols):
            i = r * cols + c
            if dist[i] == 0:
                continue
            dist[i] = min(
                dist[i],
                at(c - 1, r) + _STRAIGHT_SCALED,
                at(c, r - 1) + _STRAIGHT_SCALED,
                at(c - 1, r - 1) + _SQRT2_SCALED,
                at(c + 1, r - 1) + _SQRT2_SCALED,
            )
    for r in range(rows - 1, -1, -1):
        for c in range(cols - 1, -1, -1):
            i = r * cols + c
            if dist[i] == 0:
                continue
            dist[i] = min(
                dist[i],
                at(c + 1, r) + _STRAIGHT_SCALED,
                at(c, r + 1) + _STRAIGHT_SCALED,
                at(c + 1, r + 1) + _SQRT2_SCALED,
                at(c - 1, r + 1) + _SQRT2_SCALED,
            )

    # dist is center-to-center; the blocked cell's own half-extent means the
    # true obstacle boundary is ~CELL/2 nearer. Threshold accordingly.
    needed = max(0, int(math.ceil((clearance_m - CELL_M / 2) / CELL_M * _STRAIGHT_SCALED)))
    return [open_cells[i] and dist[i] >= needed for i in range(cols * rows)]


def nearest_walkable(grid: RoomGrid, p: Point, max_radius_m: float = 1.5) -> tuple[int, int] | None:
    """The walkable cell nearest to `p` within `max_radius_m` — used to land
    endpoints. Generous radius on purpose: an opening midpoint sits ON the room
    boundary (its own cell is eroded away), and a room centroid can sit INSIDE
    furniture (a bed mid-bedroom) — the person starts beside it, not in it.
    Deterministic: scan by ring, then row, then column."""
    c0, r0 = grid.cell_for(p)
    max_ring = int(math.ceil(max_radius_m / CELL_M))
    for ring in range(max_ring + 1):
        best: tuple[float, int, int] | None = None
        for r in range(r0 - ring, r0 + ring + 1):
            for c in range(c0 - ring, c0 + ring + 1):
                if max(abs(c - c0), abs(r - r0)) != ring:
                    continue
                if not grid.is_walkable(c, r):
                    continue
                center = grid.center_of(c, r)
                d = math.hypot(center[0] - p[0], center[1] - p[1])
                key = (d, r, c)
                if best is None or key < best:
                    best = key
        if best is not None:
            return (best[2], best[1])
    return None
