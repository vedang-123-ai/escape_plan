"""Tests for A06-05: RoutePlan nested list bounds."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from app import config
from app.limits import (
    MAX_ROUTE_BOTTLENECK_DISCONNECTED_ROOMS,
    MAX_ROUTE_BOTTLENECKS,
    MAX_ROUTE_FINDING_OBJECTS,
    MAX_ROUTE_FINDINGS_PER_ROOM,
    MAX_ROUTE_ROOMS,
    MAX_ROUTE_WAYPOINTS,
)
from app.models import HomeModel
from app.routing.engine import compute_route_plan
from app.routing.plan import (
    Bottleneck,
    RoomRoutePlan,
    Route,
    RouteFinding,
    RoutePlan,
    RoutingConstraints,
    Waypoint,
)


def test_golden_fixtures_route_plans_pass_validation(bungalow: dict, apartment: dict, twostory: dict):
    thresholds = config.get_thresholds()
    for fixture in (bungalow, apartment, twostory):
        home = HomeModel.model_validate(fixture)
        for peril in ("fire", "tornado", "earthquake"):
            plan = compute_route_plan(home, thresholds, peril=peril)
            # RoutePlan model validates successfully
            assert len(plan.rooms) <= MAX_ROUTE_ROOMS
            assert len(plan.bottlenecks) <= MAX_ROUTE_BOTTLENECKS
            for room in plan.rooms:
                if room.primary:
                    assert len(room.primary.waypoints) <= MAX_ROUTE_WAYPOINTS
                if room.secondary:
                    assert len(room.secondary.waypoints) <= MAX_ROUTE_WAYPOINTS
                assert len(room.findings) <= MAX_ROUTE_FINDINGS_PER_ROOM


def test_oversized_waypoints_rejected():
    wp = Waypoint(x=1.0, y=2.0, floor_id="f1", node_id="r1", kind="room")
    oversized = [wp] * (MAX_ROUTE_WAYPOINTS + 1)
    with pytest.raises(ValidationError) as exc:
        Route(waypoints=oversized, length_m=10.0, uses_stairs=False, uses_window=False, exit_id="e1")
    assert "waypoints" in str(exc.value)


def test_oversized_rooms_rejected():
    room_plan = RoomRoutePlan(room_id="r1", room_name="Room", floor_id="f1")
    oversized_rooms = [room_plan] * (MAX_ROUTE_ROOMS + 1)
    with pytest.raises(ValidationError) as exc:
        RoutePlan(
            home_id="h1",
            home_name="Home",
            peril="fire",
            constraints=RoutingConstraints(),
            rooms=oversized_rooms,
        )
    assert "rooms" in str(exc.value)


def test_oversized_bottlenecks_rejected():
    bn = Bottleneck(opening_id="op1", disconnected_room_ids=["r1"])
    oversized_bn = [bn] * (MAX_ROUTE_BOTTLENECKS + 1)
    with pytest.raises(ValidationError) as exc:
        RoutePlan(
            home_id="h1",
            home_name="Home",
            peril="fire",
            constraints=RoutingConstraints(),
            rooms=[],
            bottlenecks=oversized_bn,
        )
    assert "bottlenecks" in str(exc.value)


def test_oversized_findings_rejected():
    f = RouteFinding(kind="blocked_opening", room_id="r1", detail="Blocked")
    oversized_findings = [f] * (MAX_ROUTE_FINDINGS_PER_ROOM + 1)
    with pytest.raises(ValidationError) as exc:
        RoomRoutePlan(room_id="r1", room_name="Room", floor_id="f1", findings=oversized_findings)
    assert "findings" in str(exc.value)
