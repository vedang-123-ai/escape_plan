"""Pure 2D geometry for the scan converter: wall segments → clean room polygons,
and opening → nearest-wall-edge parametric mapping.

Everything here is deterministic and I/O-free. Tolerances are module constants so
the S1.4 real-export calibration pass has one place to tune.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from app.models import Point, is_simple_polygon, signed_area

SNAP_TOL_M = 0.25
"""Endpoint gaps up to this are considered normal scan noise (no quality penalty)."""

COLLINEAR_TOL_DEG = 8.0
"""Consecutive edges turning less than this are merged into one."""

RECT_TOL_DEG = 12.0
"""Edges within this of a dominant axis get snapped onto it."""

MIN_SEGMENT_M = 0.01
"""Wall segments shorter than this are degenerate scan artifacts."""

VERTEX_DEDUP_M = 0.02

FALLBACK_QUALITY = 0.3
GAP_QUALITY_FACTOR = 0.7


@dataclass(frozen=True)
class WallSegment:
    p0: Point
    p1: Point

    @property
    def length(self) -> float:
        return math.dist(self.p0, self.p1)

    @property
    def reversed(self) -> "WallSegment":
        return WallSegment(self.p1, self.p0)


@dataclass(frozen=True)
class PolygonResult:
    polygon: list[Point]
    quality: float
    """1.0 = clean chain; multiplied down for large gaps; FALLBACK_QUALITY if bbox."""
    used_fallback: bool
    notes: list[str]


# ---------------------------------------------------------------------------
# Chaining walls into a loop
# ---------------------------------------------------------------------------

def _chain_segments(segments: list[WallSegment]) -> tuple[list[WallSegment], list[float]]:
    """Greedily order/orient segments into a loop; returns (ordered, junction gaps).

    gaps[i] is the distance between ordered[i-1].p1 and ordered[i].p0 (i=0 is the
    closing junction between the last segment and the first).
    """
    remaining = sorted(segments, key=lambda s: (-s.length, s.p0, s.p1))
    ordered = [remaining.pop(0)]
    while remaining:
        end = ordered[-1].p1
        best_i, best_flip, best_d = 0, False, math.inf
        for i, seg in enumerate(remaining):
            d0, d1 = math.dist(end, seg.p0), math.dist(end, seg.p1)
            if d0 < best_d:
                best_i, best_flip, best_d = i, False, d0
            if d1 < best_d:
                best_i, best_flip, best_d = i, True, d1
        seg = remaining.pop(best_i)
        ordered.append(seg.reversed if best_flip else seg)
    gaps = [
        math.dist(ordered[i - 1].p1, ordered[i].p0) for i in range(len(ordered))
    ]
    return ordered, gaps


def _weld_loop(ordered: list[WallSegment]) -> list[Point]:
    """Close each junction at the midpoint of the two neighboring endpoints."""
    n = len(ordered)
    return [
        (
            (ordered[i - 1].p1[0] + ordered[i].p0[0]) / 2.0,
            (ordered[i - 1].p1[1] + ordered[i].p0[1]) / 2.0,
        )
        for i in range(n)
    ]


# ---------------------------------------------------------------------------
# Polygon cleanup
# ---------------------------------------------------------------------------

def _dedupe_vertices(poly: list[Point], tol: float = VERTEX_DEDUP_M) -> list[Point]:
    out: list[Point] = []
    for p in poly:
        if not out or math.dist(p, out[-1]) > tol:
            out.append(p)
    if len(out) > 1 and math.dist(out[0], out[-1]) <= tol:
        out.pop()
    return out


def _turn_angle_deg(a: Point, b: Point, c: Point) -> float:
    """Angle between edge a→b and edge b→c, in [0, 180]."""
    v1 = (b[0] - a[0], b[1] - a[1])
    v2 = (c[0] - b[0], c[1] - b[1])
    n1, n2 = math.hypot(*v1), math.hypot(*v2)
    if n1 < 1e-12 or n2 < 1e-12:
        return 0.0
    cos = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / (n1 * n2)))
    return math.degrees(math.acos(cos))


def merge_collinear(poly: list[Point], tol_deg: float = COLLINEAR_TOL_DEG) -> list[Point]:
    """Drop vertices where the boundary turns by less than tol_deg."""
    changed = True
    poly = list(poly)
    while changed and len(poly) > 3:
        changed = False
        for i in range(len(poly)):
            a = poly[(i - 1) % len(poly)]
            b = poly[i]
            c = poly[(i + 1) % len(poly)]
            if _turn_angle_deg(a, b, c) < tol_deg:
                poly.pop(i)
                changed = True
                break
    return poly


def _line_intersection(
    p: Point, d: Point, q: Point, e: Point
) -> Point | None:
    """Intersection of line p+t·d with q+s·e; None if near-parallel."""
    cross = d[0] * e[1] - d[1] * e[0]
    if abs(cross) < 1e-9:
        return None
    t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / cross
    return (p[0] + t * d[0], p[1] + t * d[1])


def rectangularize(poly: list[Point], tol_deg: float = RECT_TOL_DEG) -> list[Point]:
    """Snap near-axis edges onto the dominant (length-weighted, mod-90°) direction.

    Each edge becomes an infinite line through its midpoint with either its snapped
    or original direction; new vertices are the intersections of consecutive lines.
    """
    n = len(poly)
    if n < 3:
        return poly
    edges = []
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        length = math.dist(p, q)
        angle = math.atan2(q[1] - p[1], q[0] - p[0])
        mid = ((p[0] + q[0]) / 2.0, (p[1] + q[1]) / 2.0)
        edges.append((mid, angle, length))

    # Dominant direction mod 90°: circular mean of 4×angle, length-weighted.
    sx = sum(length * math.cos(4 * a) for _, a, length in edges)
    sy = sum(length * math.sin(4 * a) for _, a, length in edges)
    if math.hypot(sx, sy) < 1e-9:
        return poly
    theta = math.atan2(sy, sx) / 4.0

    tol = math.radians(tol_deg)
    half_pi = math.pi / 2.0
    lines: list[tuple[Point, Point]] = []
    for mid, angle, _ in edges:
        # Distance from this edge's direction to the nearest theta + k·90°.
        delta = (angle - theta + half_pi / 2.0) % half_pi - half_pi / 2.0
        snapped = angle - delta if abs(delta) <= tol else angle
        lines.append((mid, (math.cos(snapped), math.sin(snapped))))

    out: list[Point] = []
    for i in range(n):
        prev = lines[(i - 1) % n]
        cur = lines[i]
        hit = _line_intersection(prev[0], prev[1], cur[0], cur[1])
        out.append(hit if hit is not None else poly[i])
    return out


def _ensure_ccw(poly: list[Point]) -> list[Point]:
    return poly if signed_area(poly) > 0 else list(reversed(poly))


def _bbox_polygon(points: list[Point]) -> list[Point]:
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return [
        (min(xs), min(ys)),
        (max(xs), min(ys)),
        (max(xs), max(ys)),
        (min(xs), max(ys)),
    ]


def _round_polygon(poly: list[Point], ndigits: int = 3) -> list[Point]:
    return [(round(x, ndigits), round(y, ndigits)) for x, y in poly]


def polygon_from_walls(segments: list[WallSegment]) -> PolygonResult:
    """Full per-room pipeline: chain → weld → merge collinear → rectangularize →
    normalize, with a bounding-box fallback so a messy scan never crashes."""
    notes: list[str] = []
    segments = [s for s in segments if s.length >= MIN_SEGMENT_M]
    endpoints = [p for s in segments for p in (s.p0, s.p1)]
    if len(segments) < 3:
        notes.append("fewer than 3 usable wall segments; bounding-box fallback")
        return _fallback(endpoints, notes)

    ordered, gaps = _chain_segments(segments)
    quality = 1.0
    big_gaps = [g for g in gaps if g > SNAP_TOL_M]
    if big_gaps:
        quality *= GAP_QUALITY_FACTOR ** len(big_gaps)
        notes.append(
            f"closed {len(big_gaps)} gap(s) larger than {SNAP_TOL_M} m "
            f"(max {max(big_gaps):.2f} m)"
        )

    poly = _weld_loop(ordered)
    poly = _dedupe_vertices(poly)
    poly = merge_collinear(poly)
    poly = rectangularize(poly)
    poly = _dedupe_vertices(poly)
    poly = _round_polygon(poly)

    if len(poly) < 3 or not is_simple_polygon(poly) or abs(signed_area(poly)) < 1e-6:
        notes.append("cleaned polygon degenerate or self-intersecting; bounding-box fallback")
        return _fallback(endpoints, notes)

    return PolygonResult(_ensure_ccw(poly), max(quality, 0.05), False, notes)


def _fallback(endpoints: list[Point], notes: list[str]) -> PolygonResult:
    if not endpoints:
        # No usable geometry at all: emit a 1 m placeholder cell at the origin.
        endpoints = [(0.0, 0.0), (1.0, 1.0)]
        notes.append("no wall endpoints; emitted 1 m placeholder footprint")
    xs = [p[0] for p in endpoints]
    ys = [p[1] for p in endpoints]
    if max(xs) - min(xs) < MIN_SEGMENT_M or max(ys) - min(ys) < MIN_SEGMENT_M:
        endpoints = endpoints + [(min(xs) + 1.0, min(ys) + 1.0)]
    poly = _round_polygon(_ensure_ccw(_bbox_polygon(endpoints)))
    return PolygonResult(poly, FALLBACK_QUALITY, True, notes)


# ---------------------------------------------------------------------------
# Opening → polygon edge mapping
# ---------------------------------------------------------------------------

def _point_segment_distance(p: Point, a: Point, b: Point) -> float:
    ab = (b[0] - a[0], b[1] - a[1])
    ap = (p[0] - a[0], p[1] - a[1])
    denom = ab[0] ** 2 + ab[1] ** 2
    if denom < 1e-12:
        return math.dist(p, a)
    t = max(0.0, min(1.0, (ap[0] * ab[0] + ap[1] * ab[1]) / denom))
    return math.dist(p, (a[0] + t * ab[0], a[1] + t * ab[1]))


def _project_t(p: Point, a: Point, b: Point) -> float:
    ab = (b[0] - a[0], b[1] - a[1])
    denom = ab[0] ** 2 + ab[1] ** 2
    if denom < 1e-12:
        return 0.0
    return ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / denom


@dataclass(frozen=True)
class EdgePlacement:
    edge_index: int
    t0: float
    t1: float
    distance_m: float
    """How far the opening's center sat from the chosen edge (0 = flush)."""


PARALLEL_DOT_MIN = 0.8
"""|cos| between opening and edge directions for an edge to count as parallel."""

MIN_T_SPAN = 0.01


def place_opening_on_polygon(
    polygon: list[Point],
    center: Point,
    direction: Point,
    width_m: float,
) -> EdgePlacement:
    """Map an opening (plan center + along-wall unit direction + width) to the
    nearest roughly-parallel polygon edge as (edge_index, t0, t1).

    Always succeeds: if no edge is parallel, all edges are candidates; the caller
    decides from ``distance_m`` whether to demote confidence.
    """
    n = len(polygon)
    edges = [(i, polygon[i], polygon[(i + 1) % n]) for i in range(n)]

    def edge_dir(a: Point, b: Point) -> Point:
        length = math.dist(a, b)
        if length < 1e-12:
            return (1.0, 0.0)
        return ((b[0] - a[0]) / length, (b[1] - a[1]) / length)

    parallel = [
        (i, a, b)
        for i, a, b in edges
        if abs(direction[0] * edge_dir(a, b)[0] + direction[1] * edge_dir(a, b)[1])
        >= PARALLEL_DOT_MIN
    ]
    candidates = parallel or edges

    best_i, best_a, best_b = min(
        candidates, key=lambda e: _point_segment_distance(center, e[1], e[2])
    )
    dist = _point_segment_distance(center, best_a, best_b)

    half = width_m / 2.0
    e0 = (center[0] - direction[0] * half, center[1] - direction[1] * half)
    e1 = (center[0] + direction[0] * half, center[1] + direction[1] * half)
    t0, t1 = sorted((_project_t(e0, best_a, best_b), _project_t(e1, best_a, best_b)))
    t0, t1 = max(0.0, min(1.0, t0)), max(0.0, min(1.0, t1))
    if t1 - t0 < MIN_T_SPAN:
        mid = max(MIN_T_SPAN / 2.0, min(1.0 - MIN_T_SPAN / 2.0, (t0 + t1) / 2.0))
        t0, t1 = mid - MIN_T_SPAN / 2.0, mid + MIN_T_SPAN / 2.0
    return EdgePlacement(best_i, round(t0, 4), round(t1, 4), dist)
