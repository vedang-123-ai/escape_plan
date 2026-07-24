"""Live golden for the LLM house builder (revamp C1). Runs only with
`-m live` and a real ANTHROPIC_API_KEY:

    cd backend && ANTHROPIC_API_KEY=... python3 -m pytest tests/test_builder_live.py -m live -v
"""

from __future__ import annotations

import os

import pytest

from app.ai.builder import run_builder

pytestmark = pytest.mark.live

DESCRIPTION = """\
A single-story 2-bedroom bungalow, roughly 10m x 8m. Front door opens into a
living room (5m x 4m) at the front-left; kitchen (5m x 4m) front-right,
connected to the living room. Behind the living room a main bedroom (5m x 4m)
with a window; behind the kitchen a second bedroom (5m x 4m) with a window.
Interior doors connect living->main bedroom and kitchen->second bedroom.
A queen bed in each bedroom and a sofa in the living room.
"""


@pytest.mark.skipif(not os.environ.get("ANTHROPIC_API_KEY"), reason="needs live API key")
def test_builder_constructs_a_valid_bungalow_from_text():
    result = run_builder(description=DESCRIPTION)

    assert not result.truncated, f"builder hit the cap; issues: {result.issues}"
    home = result.home
    assert home is not None

    # Structure: one floor, 4 rooms, at least one exterior door, bedroom windows.
    assert len(home.floors) == 1
    floor = home.floors[0]
    assert len(floor.rooms) == 4
    assert sum(1 for r in floor.rooms if r.type.value == "bedroom") == 2
    assert any(o.is_exit and o.kind.value == "door" for o in floor.openings)
    bedroom_ids = {r.id for r in floor.rooms if r.type.value == "bedroom"}
    windowed = {
        rid
        for o in floor.openings if o.kind.value == "window"
        for rid in o.room_ids
    }
    assert bedroom_ids <= windowed, "every bedroom needs a window"

    # Provenance: EVERYTHING is a draft.
    for entity in [*floor.rooms, *floor.openings, *floor.objects, *home.stairs]:
        assert entity.source.value == "ai_plan"
        assert entity.confidence is not None

    # Furniture made it in.
    assert any(o.category.value == "sofa" for o in floor.objects)
    assert sum(1 for o in floor.objects if o.category.value == "bed") >= 2
