from datetime import datetime
import pytest

from app.models import HomeModel, Floor, Room, Opening, FloorObject, ObjectCategory, Meta
from app.routing.object_hazards import analyze_object_hazards, ObjectHazardThresholds, CitedSection, CitedThreshold, EngineeringSection, EngineeringConstant

@pytest.fixture
def thresholds():
    return ObjectHazardThresholds(
        cited=CitedSection(
            heater_clearance=CitedThreshold(value_m=0.9)
        ),
        engineering_constants=EngineeringSection(
            topple_min_height_m=EngineeringConstant(value=1.2),
            topple_slenderness_ratio=EngineeringConstant(value=2.0),
            overhead_min_elevation_m=EngineeringConstant(value=0.9),
            door_approach_radius_m=EngineeringConstant(value=0.6),
                registration_tolerance_m=EngineeringConstant(value=0.3)
            )
    )

def _make_home(objects, openings=None):
    if openings is None: openings = []
    return HomeModel(
        schema_version="2.1",
        home_id="h1",
        name="test",
        meta=Meta(created=datetime.now(), modified=datetime.now()),
        floors=[
            Floor(
                id="f1",
                level=1,
                name="f1",
                height_m=3.0,
                rooms=[
                    Room(
                        id="r1",
                        name="Bedroom", source="manual", type="bedroom",
                        polygon=[(0, 0), (10, 0), (10, 10), (0, 10)]
                    )
                ],
                openings=openings,
                objects=objects
            )
        ]
    )

def test_water_heater_unsecured(thresholds):
    home = _make_home([
        FloorObject(source="manual", id="wh1", category=ObjectCategory.water_heater, center=(1, 1), size_m=(0.5, 0.5), height_m=1.0, secured=False),
        FloorObject(source="manual", id="wh2", category=ObjectCategory.water_heater, center=(2, 2), size_m=(0.5, 0.5), height_m=1.0, secured=True)
    ])
    hazards = analyze_object_hazards(home, thresholds)
    assert len(hazards) == 1
    h = hazards[0]
    assert h.rule_id == "water_heater_unsecured"
    assert h.severity == "high"
    assert h.object_id == "wh1"
    assert "water heater isn't strapped" in h.detail

def test_topple_hazard(thresholds):
    # Wardrobe is 1.9m tall, band = 1.9 outward. 
    # Center at (1.0, 1.0), size (1.0, 1.0). Band reaches up to x=2.9, y=2.9.
    # Bed at (3.5, 1.0). Should be reached.
    home = _make_home([
        FloorObject(source="manual", id="wardrobe1", category=ObjectCategory.wardrobe, center=(1, 1), size_m=(1, 1), height_m=1.9, secured=False),
        FloorObject(source="manual", id="bed1", category=ObjectCategory.bed, center=(3.2, 1), size_m=(2, 2), height_m=0.5)
    ])
    hazards = analyze_object_hazards(home, thresholds)
    assert len(hazards) == 1
    h = hazards[0]
    assert h.rule_id == "topple"
    assert h.severity == "high"
    assert h.object_id == "wardrobe1"
    assert "1.9 m tall" in h.detail
    assert "the bed" in h.detail

def test_overhead_hazard(thresholds):
    home = _make_home([
        FloorObject(source="manual", id="shelf1", category=ObjectCategory.storage, center=(1, 1), size_m=(1, 1), height_m=0.2, elevation_m=1.5, mounted=True, secured=False),
        FloorObject(source="manual", id="bed1", category=ObjectCategory.bed, center=(1.2, 1.2), size_m=(2, 2), height_m=0.5)
    ])
    hazards = analyze_object_hazards(home, thresholds)
    assert len(hazards) == 1
    h = hazards[0]
    assert h.rule_id == "overhead"
    assert h.severity == "high"
    assert h.object_id == "shelf1"
    assert "overlaps the head of the bed" in h.detail

def test_heat_clearance(thresholds):
    home = _make_home([
        FloorObject(source="manual", id="heater1", category=ObjectCategory.heat_source, center=(1, 1), size_m=(0.5, 0.5), height_m=0.5),
        FloorObject(source="manual", id="sofa1", category=ObjectCategory.sofa, center=(1.8, 1.0), size_m=(1, 1), height_m=0.5)
    ])
    # Distance between them: heater is [0.75, 1.25]. Sofa is [1.3, 2.3]. Dist is 0.05. Under 0.9.
    hazards = analyze_object_hazards(home, thresholds)
    assert len(hazards) == 1
    h = hazards[0]
    assert h.rule_id == "heat_clearance"
    assert h.severity == "high"
    assert h.object_id == "sofa1" # The encroaching object
    assert "under the 0.9 m" in h.detail


def test_negative_secured_bookcase_and_distant_heater(thresholds):
    home = _make_home([
        FloorObject(source="manual", id="bookcase1", category=ObjectCategory.bookcase, center=(1, 1), size_m=(1, 1), height_m=1.9, secured=True),
        FloorObject(source="manual", id="bed1", category=ObjectCategory.bed, center=(3.2, 1), size_m=(2, 2), height_m=0.5),
        FloorObject(source="manual", id="heater1", category=ObjectCategory.heat_source, center=(8, 8), size_m=(0.5, 0.5), height_m=0.5),
        FloorObject(source="manual", id="sofa1", category=ObjectCategory.sofa, center=(5.0, 5.0), size_m=(1, 1), height_m=0.5)
    ])
    hazards = analyze_object_hazards(home, thresholds)
    assert len(hazards) == 0

def test_severity_assignments(thresholds):
    home = _make_home([
        FloorObject(source="manual", id="shelf_sec", category=ObjectCategory.storage, center=(1, 1), size_m=(1, 1), height_m=0.2, elevation_m=1.5, mounted=True, secured=True),
        FloorObject(source="manual", id="bed1", category=ObjectCategory.bed, center=(1.2, 1.2), size_m=(2, 2), height_m=0.5),
        FloorObject(source="manual", id="shelf_unsec", category=ObjectCategory.storage, center=(5, 5), size_m=(1, 1), height_m=0.2, elevation_m=1.5, mounted=True, secured=False),
        FloorObject(source="manual", id="sofa1", category=ObjectCategory.sofa, center=(5.2, 5.2), size_m=(2, 2), height_m=0.5),
        FloorObject(source="manual", id="heater1", category=ObjectCategory.heat_source, center=(1, 8), size_m=(0.5, 0.5), height_m=0.5),
        FloorObject(source="manual", id="sofa2", category=ObjectCategory.sofa, center=(1.5, 8.0), size_m=(1, 1), height_m=0.5),
        FloorObject(source="manual", id="heater2", category=ObjectCategory.heat_source, center=(8, 1), size_m=(0.5, 0.5), height_m=0.5),
        FloorObject(source="manual", id="table1", category=ObjectCategory.table, center=(8.5, 1.0), size_m=(1, 1), height_m=0.5)
    ])
    hazards = analyze_object_hazards(home, thresholds)
    
    h_sec = next(h for h in hazards if h.object_id == "shelf_sec")
    assert h_sec.severity == "info"
    
    h_unsec = next(h for h in hazards if h.object_id == "shelf_unsec")
    assert h_unsec.severity == "info"
    
    h_sofa = next(h for h in hazards if h.object_id == "sofa2")
    assert h_sofa.severity == "high"
    
    h_table = next(h for h in hazards if h.object_id == "table1")
    assert h_table.severity == "info"

def test_detail_sentence_contains_measured_and_threshold(thresholds):
    home = _make_home([
        FloorObject(source="manual", id="heater1", category=ObjectCategory.heat_source, center=(1, 1), size_m=(0.5, 0.5), height_m=0.5),
        FloorObject(source="manual", id="sofa1", category=ObjectCategory.sofa, center=(2.25, 1.0), size_m=(1, 1), height_m=0.5)
    ])
    hazards = analyze_object_hazards(home, thresholds)
    assert len(hazards) == 1
    h = hazards[0]
    assert "0.5 m" in h.detail
    assert "0.9 m" in h.detail

import json
from pathlib import Path

def test_citations_resolve_against_sources_json(thresholds):
    home = _make_home([
        FloorObject(source="manual", id="wh1", category=ObjectCategory.water_heater, center=(1, 1), size_m=(0.5, 0.5), height_m=1.0, secured=False),
        FloorObject(source="manual", id="wardrobe1", category=ObjectCategory.wardrobe, center=(3, 3), size_m=(1, 1), height_m=1.9, secured=False),
        FloorObject(source="manual", id="bed1", category=ObjectCategory.bed, center=(4.2, 3), size_m=(2, 2), height_m=0.5),
        FloorObject(source="manual", id="shelf1", category=ObjectCategory.storage, center=(1, 8), size_m=(1, 1), height_m=0.2, elevation_m=1.5, mounted=True, secured=False),
        FloorObject(source="manual", id="bed2", category=ObjectCategory.bed, center=(1.2, 8.2), size_m=(2, 2), height_m=0.5),
        FloorObject(source="manual", id="heater1", category=ObjectCategory.heat_source, center=(8, 8), size_m=(0.5, 0.5), height_m=0.5),
        FloorObject(source="manual", id="sofa1", category=ObjectCategory.sofa, center=(8.5, 8.0), size_m=(1, 1), height_m=0.5)
    ])
    hazards = analyze_object_hazards(home, thresholds)
    assert len(hazards) > 0
    
    repo_root = Path(__file__).resolve().parents[2]
    sources_path = repo_root / "backend" / "corpus" / "sources.json"
    with open(sources_path) as f:
        data = json.load(f)
        
    valid_ids = {s["id"] for s in data["sources"]}
    for h in hazards:
        assert h.citation in valid_ids, f"Citation {h.citation} not found in sources.json"

def test_determinism(thresholds):
    home = _make_home([
        FloorObject(source="manual", id="wh1", category=ObjectCategory.water_heater, center=(1, 1), size_m=(0.5, 0.5), height_m=1.0, secured=False),
        FloorObject(source="manual", id="wardrobe1", category=ObjectCategory.wardrobe, center=(3, 3), size_m=(1, 1), height_m=1.9, secured=False),
        FloorObject(source="manual", id="bed1", category=ObjectCategory.bed, center=(4.2, 3), size_m=(2, 2), height_m=0.5),
        FloorObject(source="manual", id="shelf1", category=ObjectCategory.storage, center=(1, 8), size_m=(1, 1), height_m=0.2, elevation_m=1.5, mounted=True, secured=False),
        FloorObject(source="manual", id="bed2", category=ObjectCategory.bed, center=(1.2, 8.2), size_m=(2, 2), height_m=0.5),
        FloorObject(source="manual", id="heater1", category=ObjectCategory.heat_source, center=(8, 8), size_m=(0.5, 0.5), height_m=0.5),
        FloorObject(source="manual", id="sofa1", category=ObjectCategory.sofa, center=(8.5, 8.0), size_m=(1, 1), height_m=0.5)
    ])
    hazards1 = analyze_object_hazards(home, thresholds)
    hazards2 = analyze_object_hazards(home, thresholds)
    
    assert hazards1 == hazards2
    
    sorted_hazards = sorted(hazards1, key=lambda h: (h.floor_id, h.room_id, h.object_id, h.rule_id))
    assert hazards1 == sorted_hazards



def test_rotated_box_matches_the_nav_grid_footprint():
    """The hazard box and the routing raster must agree on where a rotated object is.
    At 30° the hazard box used to come out at -30°, so none of its corners lay
    inside the object routing saw (found on a real scan, 2026-10-11)."""
    import math
    from app.models import Source
    from app.routing.nav_grid import object_contains
    from app.routing.object_hazards import _obb_corners

    sofa = FloorObject(id="o", category=ObjectCategory.sofa, center=(1.0, 2.0),
                       size_m=(2.0, 0.5), height_m=0.8, rotation_deg=30.0,
                       source=Source.manual)
    for x, y in _obb_corners(sofa):
        inward = (1.0 + 0.98 * (x - 1.0), 2.0 + 0.98 * (y - 2.0))
        assert object_contains(sofa, inward)
    tip = (1.0 + 0.99 * math.cos(math.radians(30)), 2.0 + 0.99 * math.sin(math.radians(30)))
    assert object_contains(sofa, tip)
