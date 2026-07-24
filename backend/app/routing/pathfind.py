"""Deterministic A* + line-of-sight smoothing over a RoomGrid (revamp B3).

Pure functions. Determinism recipe: integer cell indices, integer step costs
(10 straight / 14 diagonal), heap tie-break by (f, h, row, col), and greedy
smoothing that only ever compares integers — two runs on the same input are
byte-identical.
"""

from __future__ import annotations

import heapq
import math

from app.models import Point
from app.routing.nav_grid import (
    _SQRT2_SCALED,
    _STRAIGHT_SCALED,
    RoomGrid,
    nearest_walkable,
)


def grid_path(
    grid: RoomGrid,
    start: Point,
    goal: Point,
    *,
    start_radius_m: float = 1.5,
    goal_radius_m: float = 0.6,
) -> list[Point] | None:
    """Shortest walkable polyline from `start` to `goal` inside the grid, or
    None when no path exists (e.g. an object walls off the goal). The returned
    polyline begins/ends at the EXACT start/goal points; intermediate points
    are smoothed cell centers.

    The landing radii differ on purpose: a START (a room centroid) may sit
    inside furniture — the person stands beside the bed, not in it — so it
    lands generously. A GOAL (a doorway midpoint) must be reachable AT the
    doorway; a generous goal radius would "reach" a blocked door by standing
    next to the wardrobe in front of it."""
    start_cell = nearest_walkable(grid, start, max_radius_m=start_radius_m)
    goal_cell = nearest_walkable(grid, goal, max_radius_m=goal_radius_m)
    if start_cell is None or goal_cell is None:
        return None

    cells = _astar(grid, start_cell, goal_cell)
    if cells is None:
        return None

    smoothed = _smooth(grid, cells)
    points: list[Point] = [start]
    points.extend(grid.center_of(c, r) for (c, r) in smoothed)
    points.append(goal)
    points = _dedupe(points)
    # The first/last cell centers are landing artifacts when they sit within a
    # cell of the exact endpoints — drop them so an unobstructed leg is (near)
    # straight instead of kinked at the raster.
    if len(points) > 2 and math.hypot(points[1][0] - points[0][0],
                                      points[1][1] - points[0][1]) <= 2 * _CELL_DROP_M:
        del points[1]
    if len(points) > 2 and math.hypot(points[-1][0] - points[-2][0],
                                      points[-1][1] - points[-2][1]) <= 2 * _CELL_DROP_M:
        del points[-2]
    return points


_CELL_DROP_M = 0.1


def path_length(points: list[Point]) -> float:
    return sum(
        math.hypot(points[i + 1][0] - points[i][0], points[i + 1][1] - points[i][1])
        for i in range(len(points) - 1)
    )


def _astar(
    grid: RoomGrid, start: tuple[int, int], goal: tuple[int, int]
) -> list[tuple[int, int]] | None:
    """8-connected A*; diagonals never cut corners (both orthogonal neighbors
    must be walkable). Octile-distance heuristic in the same integer units."""

    def heuristic(c: int, r: int) -> int:
        dc = abs(c - goal[0])
        dr = abs(r - goal[1])
        return _STRAIGHT_SCALED * max(dc, dr) + (_SQRT2_SCALED - _STRAIGHT_SCALED) * min(dc, dr)

    start_i = grid.index(*start)
    g: dict[int, int] = {start_i: 0}
    came: dict[int, int] = {}
    h0 = heuristic(*start)
    heap: list[tuple[int, int, int, int]] = [(h0, h0, start[1], start[0])]
    done: set[int] = set()

    steps = (
        (1, 0, _STRAIGHT_SCALED), (-1, 0, _STRAIGHT_SCALED),
        (0, 1, _STRAIGHT_SCALED), (0, -1, _STRAIGHT_SCALED),
        (1, 1, _SQRT2_SCALED), (1, -1, _SQRT2_SCALED),
        (-1, 1, _SQRT2_SCALED), (-1, -1, _SQRT2_SCALED),
    )

    while heap:
        _f, _h, r, c = heapq.heappop(heap)
        i = grid.index(c, r)
        if i in done:
            continue
        done.add(i)
        if (c, r) == goal:
            path = [(c, r)]
            while i in came:
                i = came[i]
                path.append((i % grid.cols, i // grid.cols))
            path.reverse()
            return path
        for dc, dr, step in steps:
            nc, nr = c + dc, r + dr
            if not grid.is_walkable(nc, nr):
                continue
            if dc != 0 and dr != 0:
                # No corner cutting: both orthogonal companions must be open.
                if not (grid.is_walkable(c + dc, r) and grid.is_walkable(c, r + dr)):
                    continue
            ni = grid.index(nc, nr)
            ng = g[i] + step
            if ng < g.get(ni, 1 << 30):
                g[ni] = ng
                came[ni] = i
                nh = heuristic(nc, nr)
                heapq.heappush(heap, (ng + nh, nh, nr, nc))
    return None


def _smooth(
    grid: RoomGrid, cells: list[tuple[int, int]]
) -> list[tuple[int, int]]:
    """Greedy line-of-sight shortcutting: from each kept cell, jump to the
    furthest later cell reachable by a straight walkable line. An unobstructed
    room collapses to [start, goal] — a straight leg, exactly the pre-grid
    behavior."""
    if len(cells) <= 2:
        return cells
    kept = [cells[0]]
    i = 0
    while i < len(cells) - 1:
        j = len(cells) - 1
        while j > i + 1 and not _line_walkable(grid, cells[i], cells[j]):
            j -= 1
        kept.append(cells[j])
        i = j
    return kept


def _line_walkable(grid: RoomGrid, a: tuple[int, int], b: tuple[int, int]) -> bool:
    """Every cell a supercover Bresenham line touches must be walkable — the
    supercover (include both cells on exact corner crossings) keeps the smoothed
    tube from clipping obstacle corners."""
    c0, r0 = a
    c1, r1 = b
    dc = abs(c1 - c0)
    dr = abs(r1 - r0)
    sc = 1 if c1 > c0 else -1
    sr = 1 if r1 > r0 else -1
    err = dc - dr
    c, r = c0, r0
    while True:
        if not grid.is_walkable(c, r):
            return False
        if (c, r) == (c1, r1):
            return True
        e2 = 2 * err
        if e2 == 0 and dc and dr:
            # Exact corner crossing: both adjacent cells must be open.
            if not (grid.is_walkable(c + sc, r) and grid.is_walkable(c, r + sr)):
                return False
            c += sc
            r += sr
            err += dc - dr
            continue
        if e2 > -dr:
            err -= dr
            c += sc
        else:
            err += dc
            r += sr


def _dedupe(points: list[Point]) -> list[Point]:
    out: list[Point] = []
    for p in points:
        if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > 1e-9:
            out.append(p)
    return out
