"""Tests for A17-02: Backend model acceptance of homes with overlapping openings (parity with Swift validator)."""

from __future__ import annotations

import pytest

from app.models import HomeModel, Floor, Room, Opening, WallSegmentRef, Meta, RoomType, OpeningKind, Source
from datetime import datetime, timezone


def test_backend_model_accepts_overlapping_openings():
    now = datetime.now(timezone.utc)
    room = Room(
        id="room_main",
        name="Main Room",
        type=RoomType.living,
        polygon=[(0.0, 0.0), (5.0, 0.0), (5.0, 5.0), (0.0, 5.0)],
        source=Source.manual,
    )
    door_a = Opening(
        id="door_a",
        kind=OpeningKind.door,
        wall_segment=WallSegmentRef(room_id="room_main", edge_index=0, t0=0.2, t1=0.5),
        room_ids=["room_main", "EXTERIOR"],
        width_m=1.5,
        height_m=2.0,
        sill_height_m=0.0,
        source=Source.manual,
    )
    door_b = Opening(
        id="door_b",
        kind=OpeningKind.door,
        wall_segment=WallSegmentRef(room_id="room_main", edge_index=0, t0=0.4, t1=0.7),
        room_ids=["room_main", "EXTERIOR"],
        width_m=1.5,
        height_m=2.0,
        sill_height_m=0.0,
        source=Source.manual,
    )
    floor = Floor(
        id="f0",
        level=0,
        name="Ground",
        height_m=2.7,
        rooms=[room],
        openings=[door_a, door_b],
    )
    home = HomeModel(
        schema_version="2.1",
        home_id="home_overlap",
        name="Home with Overlapping Openings",
        floors=[floor],
        meta=Meta(created=now, modified=now),
    )

    # Validates without throwing ValueError / ValidationError
    assert len(home.floors[0].openings) == 2
    assert home.floors[0].openings[0].id == "door_a"
    assert home.floors[0].openings[1].id == "door_b"
