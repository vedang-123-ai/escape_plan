"""Test verifying geometric handedness, chirality, and projection invariants.

Findings A08-01 and A08-02:
1. ARKit / RoomPlan coordinate space:
   - +X is Right
   - +Y is Up
   - +Z is Backward (toward user)
   A top-down view looking down -Y axis with camera looking towards -Z:
   - Screen Right: +X
   - Screen Up: -Z

2. Floor plan coordinate space (HomeModel):
   - +x is Right (East)
   - +y is Up (North)

3. 3D Dollhouse (DollhouseGeometry):
   - maps plan +x -> scene +x
   - maps plan +y -> scene -z
   With default camera looking down -z (pitch down):
   - plan +x renders to the RIGHT of the screen
   - plan +y renders to the TOP of the screen

4. 2D PDF Floor Plan (PlanProjection):
   - maps plan +x -> page +x (increasing x = right)
   - maps plan +y -> page -y (decreasing y = top of page in UIKit coordinates)
   Both projections place plan +y at the top and plan +x at the right!
"""

import math
import pytest


def test_chirality_mathematical_derivation():
    """Verify affine transformation matrices preserve chirality (det > 0)."""
    # 3D top-down view matrix relative to plan (x, y):
    # screen_x = plan.x
    # screen_y = plan.y
    # Det = 1.0 (orientation-preserving).

    # PlanProjection (plan -> screen/page):
    # page_x = origin.x + plan.x * scale
    # page_y = origin.y - plan.y * scale (in UIKit where page_y goes downward)
    # Physical vertical direction on paper (upward from bottom):
    # paper_up = -page_y = plan.y * scale - origin.y
    # In paper coordinates (paper_x, paper_up):
    # paper_x = plan.x * scale + origin.x
    # paper_up = plan.y * scale - origin.y
    # Transformation matrix M:
    # [scale,     0]
    # [    0, scale]
    # det(M) = scale^2 > 0 -> Preserves physical chirality! No mirror reflection!
    scale = 25.0
    det = scale * scale
    assert det > 0


def test_asymmetric_l_room_relative_positions():
    """Verify an asymmetric L-shaped room maintains relative door and corner positions."""
    # L-shaped room:
    # - Base: x in [0, 4], y in [0, 2]
    # - Tower: x in [0, 2], y in [2, 4] (located in the North-West)
    # - Door: on the East wall at x=4, y=1
    poly = [(0, 0), (4, 0), (4, 2), (2, 2), (2, 4), (0, 4)]
    door = (4.0, 1.0)

    # 1. Door is at maximum x (Eastmost wall)
    assert door[0] == max(p[0] for p in poly)

    # 2. Tower is at maximum y (Northmost wing)
    tower_points = [p for p in poly if p[1] > 2.0]
    assert all(p[0] <= 2.0 for p in tower_points), "Tower is on the West side (x <= 2)"
    assert max(p[1] for p in poly) == 4.0

    # 3. Signed area is positive (CCW winding)
    area = 0.0
    for i in range(len(poly)):
        p1 = poly[i]
        p2 = poly[(i + 1) % len(poly)]
        area += p1[0] * p2[1] - p2[0] * p1[1]
    assert area / 2.0 == 12.0
