"""Make scanned rooms fit together: one floor axis, no wall jogs, shared walls stitched.

RoomPlan returns each room separately. Cleaned one at a time, neighbours come out
rotated a degree or two against each other, a straight wall shows up as a staircase
of short stubs, and the wall between two rooms is two parallel lines with a gap or an
overlap. This module is a small constraint pass, not a solver: every rule is a local
snap with a tolerance, applied once, in a fixed order, so it is fast and deterministic.

- `remove_jogs`: an edge shorter than `JOG_M` is scan noise. If its neighbours are
  parallel they become one line at their length-weighted offset; otherwise they meet
  at a corner.
- `stitch_rooms`: two rooms' walls that face each other within `STITCH_GAP_M` move onto
  their shared midline; same-facing walls within `ALIGN_OFFSET_M` of each other (one
  facade split across two rooms) move onto one line.

Any room the pass would make self-intersecting, or whose area it would change by more
than `MAX_AREA_CHANGE`, keeps its input polygon: a messy scan is never made worse.
"""

from __future__ import annotations

import math

from app.models import Point, is_simple_polygon, signed_area

JOG_M = 0.25
"""Edges shorter than this are scan stubs, not walls."""

STITCH_GAP_M = 0.35
"""Facing walls of two rooms closer than this are one wall (thickness + scan error)."""

STITCH_OVERLAP_M = 0.10
"""How far two rooms may overlap across a shared wall and still be stitched."""

ALIGN_OFFSET_M = 0.15
"""Same-facing walls of two rooms this close in offset are one straight facade."""

ALIGN_REACH_M = 0.5
"""...when their spans overlap or end within this of each other."""

MIN_SHARED_M = 0.3
"""Facing walls must share at least this much length to be stitched."""

PARALLEL_SIN = math.sin(math.radians(3.0))
JOG_PARALLEL_SIN = math.sin(math.radians(10.0))
MAX_AREA_CHANGE = 0.20

Line = tuple[Point, Point]
"""(point on the line, unit direction)."""


def _unit(a: Point, b: Point) -> Point:
    length = math.dist(a, b)
    if length < 1e-12:
        return (1.0, 0.0)
    return ((b[0] - a[0]) / length, (b[1] - a[1]) / length)


def _cross(u: Point, v: Point) -> float:
    return u[0] * v[1] - u[1] * v[0]


def _dot(u: Point, v: Point) -> float:
    return u[0] * v[0] + u[1] * v[1]


def _intersect(l1: Line, l2: Line) -> Point | None:
    (p, d), (q, e) = l1, l2
    cross = _cross(d, e)
    if abs(cross) < 1e-9:
        return None
    t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / cross
    return (p[0] + t * d[0], p[1] + t * d[1])


def _rebuild(lines: list[Line]) -> list[Point] | None:
    """Vertex k is where line k-1 meets line k (edge k runs from vertex k to k+1)."""
    out: list[Point] = []
    for k in range(len(lines)):
        hit = _intersect(lines[k - 1], lines[k])
        if hit is None:
            return None
        out.append(hit)
    return out


def _acceptable(candidate: list[Point] | None, original: list[Point]) -> bool:
    if candidate is None or len(candidate) < 3 or not is_simple_polygon(candidate):
        return False
    a0, a1 = abs(signed_area(original)), abs(signed_area(candidate))
    if a0 < 1e-9 or a1 < 1e-9:
        return False
    if (signed_area(original) > 0) != (signed_area(candidate) > 0):
        return False
    return abs(a1 - a0) / a0 <= MAX_AREA_CHANGE


# ---------------------------------------------------------------------------
# One room: remove jogs
# ---------------------------------------------------------------------------

def remove_jogs(poly: list[Point], min_edge_m: float = JOG_M) -> list[Point]:
    """Collapse edges shorter than `min_edge_m`, shortest first."""
    original = list(poly)
    poly = list(poly)
    tried: set[tuple[Point, Point]] = set()
    while len(poly) > 4:
        n = len(poly)
        edges = sorted(
            (math.dist(poly[i], poly[(i + 1) % n]), i)
            for i in range(n)
            if (poly[i], poly[(i + 1) % n]) not in tried
        )
        if not edges or edges[0][0] >= min_edge_m:
            break
        _, i = edges[0]
        key = (poly[i], poly[(i + 1) % n])
        prev_i, next_i = (i - 1) % n, (i + 1) % n
        lines: list[Line] = [(poly[k], _unit(poly[k], poly[(k + 1) % n])) for k in range(n)]
        dp, dn = lines[prev_i][1], lines[next_i][1]

        if abs(_cross(dp, dn)) < JOG_PARALLEL_SIN and _dot(dp, dn) > 0:
            # A step between two parallel walls: one wall at their weighted offset.
            normal = (-dp[1], dp[0])
            lp = math.dist(poly[prev_i], poly[i])
            ln = math.dist(poly[next_i], poly[(next_i + 1) % n])
            op, on = _dot(poly[prev_i], normal), _dot(poly[next_i], normal)
            offset = (lp * op + ln * on) / (lp + ln) if lp + ln > 0 else op
            base = poly[prev_i]
            shift = offset - op
            merged: Line = ((base[0] + shift * normal[0], base[1] + shift * normal[1]), dp)
            drop = {i, next_i}
            new_lines = [merged if k == prev_i else lines[k] for k in range(n) if k not in drop]
        else:
            # A clipped corner: let the neighbours meet.
            new_lines = [lines[k] for k in range(n) if k != i]

        candidate = _rebuild(new_lines)
        if _acceptable(candidate, original):
            poly = candidate  # type: ignore[assignment]
        else:
            tried.add(key)
    return poly


# ---------------------------------------------------------------------------
# Many rooms: stitch shared walls and align facades
# ---------------------------------------------------------------------------

def stitch_rooms(polys: list[list[Point]]) -> list[list[Point]]:
    """Move near-coincident walls of different rooms onto common lines.

    Polygons must be CCW (interior on the left of each edge). Each edge collects the
    offsets (along its outward normal) towards every partner wall it matches; it moves
    by their mean. Rooms are rebuilt from their moved lines and rejected individually.
    """
    edges: list[list[tuple[Point, Point, Point, float]]] = []
    for poly in polys:
        n = len(poly)
        room_edges = []
        for k in range(n):
            a, b = poly[k], poly[(k + 1) % n]
            room_edges.append((a, b, _unit(a, b), math.dist(a, b)))
        edges.append(room_edges)

    shifts: dict[tuple[int, int], list[float]] = {}
    for r, room_edges in enumerate(edges):
        for k, (a, _b, d, length) in enumerate(room_edges):
            outward = (d[1], -d[0])
            for s, other in enumerate(edges):
                if s == r:
                    continue
                for c, e_end, e, _ in other:
                    if abs(_cross(d, e)) > PARALLEL_SIN:
                        continue
                    offset = _dot((c[0] - a[0], c[1] - a[1]), outward)
                    t0, t1 = sorted((
                        _dot((c[0] - a[0], c[1] - a[1]), d),
                        _dot((e_end[0] - a[0], e_end[1] - a[1]), d),
                    ))
                    shared = min(length, t1) - max(0.0, t0)
                    if _dot(d, e) < 0:
                        # Facing walls: the partner lies just outside this room.
                        if -STITCH_OVERLAP_M <= offset <= STITCH_GAP_M and shared >= MIN_SHARED_M:
                            shifts.setdefault((r, k), []).append(offset / 2)
                    elif abs(offset) <= ALIGN_OFFSET_M and shared >= -ALIGN_REACH_M:
                        shifts.setdefault((r, k), []).append(offset / 2)

    out: list[list[Point]] = []
    for r, poly in enumerate(polys):
        moved = False
        lines: list[Line] = []
        for k, (a, _b, d, _) in enumerate(edges[r]):
            amounts = shifts.get((r, k))
            if amounts:
                delta = sum(amounts) / len(amounts)
                outward = (d[1], -d[0])
                lines.append(((a[0] + delta * outward[0], a[1] + delta * outward[1]), d))
                moved = True
            else:
                lines.append((a, d))
        if not moved:
            out.append(poly)
            continue
        candidate = _rebuild(lines)
        out.append(candidate if _acceptable(candidate, poly) else poly)  # type: ignore[arg-type]
    return out
