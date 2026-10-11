"""Scanned rooms fit together: shared axis, no jogs, stitched walls (app/convert/stitch.py)."""

from __future__ import annotations

import math
from datetime import datetime, timezone

import pytest

from app.convert import convert_scan
from app.convert.stitch import remove_jogs, stitch_rooms
from app.models import signed_area


def _rect(x0: float, y0: float, x1: float, y1: float) -> list[tuple[float, float]]:
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def test_a_short_step_in_a_straight_wall_is_removed() -> None:
    # A 4 x 3 room whose top wall has a 0.08 m step halfway along.
    stepped = [(0.0, 0.0), (4.0, 0.0), (4.0, 3.0), (2.0, 3.0), (2.0, 3.08), (0.0, 3.08)]
    clean = remove_jogs(stepped)
    assert len(clean) == 4
    ys = sorted({round(y, 3) for _, y in clean})
    assert ys[0] == 0.0 and 3.0 < ys[1] < 3.08  # one top wall at the weighted offset


def test_a_real_alcove_is_kept() -> None:
    # A 0.6 m deep alcove is architecture, not noise.
    alcove = [(0.0, 0.0), (4.0, 0.0), (4.0, 3.0), (2.5, 3.0), (2.5, 3.6), (1.5, 3.6), (1.5, 3.0), (0.0, 3.0)]
    assert remove_jogs(alcove) == alcove


def test_facing_walls_across_a_gap_are_stitched_onto_one_line() -> None:
    left, right = _rect(0.0, 0.0, 3.0, 3.0), _rect(3.2, 0.0, 6.0, 3.0)
    a, b = stitch_rooms([left, right])
    left_max = max(x for x, _ in a)
    right_min = min(x for x, _ in b)
    assert left_max == pytest.approx(3.1)
    assert right_min == pytest.approx(3.1)


def test_overlapping_rooms_are_stitched_too() -> None:
    a, b = stitch_rooms([_rect(0.0, 0.0, 3.0, 3.0), _rect(2.95, 0.0, 6.0, 3.0)])
    assert max(x for x, _ in a) == pytest.approx(min(x for x, _ in b))


def test_a_split_facade_becomes_one_straight_wall() -> None:
    a, b = stitch_rooms([_rect(0.0, 0.0, 3.0, 3.0), _rect(3.0, 0.1, 6.0, 3.0)])
    assert min(y for _, y in a) == pytest.approx(min(y for _, y in b))


def test_rooms_far_apart_are_left_alone() -> None:
    left, right = _rect(0.0, 0.0, 3.0, 3.0), _rect(4.0, 0.0, 7.0, 3.0)
    assert stitch_rooms([left, right]) == [left, right]


# ---------------------------------------------------------------------------
# End to end through the converter


def _wall(ident: str, p0: tuple[float, float], p1: tuple[float, float]) -> dict:
    cx, cz = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    length = math.dist(p0, p1)
    dx, dz = (p1[0] - p0[0]) / length, (p1[1] - p0[1]) / length
    transform = [dx, 0, dz, 0, 0, 1, 0, 0, -dz, 0, dx, 0, cx, 1.25, cz, 1]
    return {"identifier": ident, "transform": transform, "dimensions": [length, 2.5, 0],
            "confidence": {"high": {}}}


def _room(ident: str, corners: list[tuple[float, float]]) -> dict:
    n = len(corners)
    return {"identifier": ident, "walls": [
        _wall(f"{ident}-w{i}", corners[i], corners[(i + 1) % n]) for i in range(n)
    ], "doors": [], "windows": [], "openings": []}


def _rotate(points, deg, about=(0.0, 0.0)):
    r = math.radians(deg)
    return [
        (about[0] + (x - about[0]) * math.cos(r) - (y - about[1]) * math.sin(r),
         about[1] + (x - about[0]) * math.sin(r) + (y - about[1]) * math.cos(r))
        for x, y in points
    ]


def test_converted_neighbours_share_one_axis_and_one_wall() -> None:
    left = _rect(0.0, 0.0, 4.0, 3.0)
    right = _rotate(_rect(4.2, 0.0, 7.0, 3.0), 2.0, about=(4.2, 0.0))  # 2° off, 0.2 m gap
    home, _ = convert_scan(
        {"rooms": [_room("A", left), _room("B", right)]},
        timestamp=datetime(2026, 10, 11, tzinfo=timezone.utc),
    )
    rooms = home.floors[0].rooms
    angles = []
    for room in rooms:
        assert signed_area(list(room.polygon)) > 0
        for i, p in enumerate(room.polygon):
            q = room.polygon[(i + 1) % len(room.polygon)]
            angles.append(math.degrees(math.atan2(q[1] - p[1], q[0] - p[0])) % 90)
    assert max(angles) - min(angles) < 0.1, "every wall on the floor's one shared axis"
    # The shared wall: A's east edge and B's west edge lie on one line.
    theta = math.radians(angles[0])
    along = (math.cos(theta), math.sin(theta))
    a_east = max(x * along[0] + y * along[1] for x, y in rooms[0].polygon)
    b_west = min(x * along[0] + y * along[1] for x, y in rooms[1].polygon)
    assert abs(a_east - b_west) < 0.02, "the shared wall is one line, not two"
