"""Revamp C1 tests: the builder tool-use loop, driven by a scripted client
(pattern from test_agent.py). No live API calls here — test_builder_live.py
covers the real model behind `-m live`."""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from app import config
from app.ai.builder import BuildResult, run_builder
from app.models import SCHEMA_VERSION

TEST_TOKEN = "test-token"


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def _tool_use(tool_id: str, name: str, tool_input: dict) -> SimpleNamespace:
    return SimpleNamespace(type="tool_use", id=tool_id, name=name, input=tool_input)


class ScriptedClient:
    def __init__(self, turns):
        self._turns = list(turns)
        self.calls = 0
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs):
        self.calls += 1
        if not self._turns:
            raise AssertionError("ScriptedClient ran out of scripted turns")
        return SimpleNamespace(content=self._turns.pop(0))


def _square(x0, y0, w, h):
    return [[x0, y0], [x0 + w, y0], [x0 + w, y0 + h], [x0, y0 + h]]


def _happy_path_turns():
    return [
        [_tool_use("t1", "start_home", {"name": "Bungalow"})],
        [_tool_use("t2", "add_floor", {"level": 0, "name": "Ground Floor"})],
        [
            _tool_use("t3", "add_room", {
                "floor_id": "floor_1", "name": "Living Room", "type": "living",
                "polygon": _square(0, 0, 5, 4),
            }),
            _tool_use("t4", "add_room", {
                "floor_id": "floor_1", "name": "Bedroom", "type": "bedroom",
                "polygon": _square(5, 0, 4, 4),
            }),
        ],
        [
            _tool_use("t5", "add_opening", {
                "kind": "door", "room_id": "room_1", "edge_index": 0, "t": 0.5,
            }),
            _tool_use("t6", "add_opening", {
                "kind": "door", "room_id": "room_1", "edge_index": 1, "t": 0.5,
            }),
            _tool_use("t7", "add_opening", {
                "kind": "window", "room_id": "room_2", "edge_index": 1, "t": 0.5,
            }),
        ],
        [_tool_use("t8", "validate_model", {})],
        [_tool_use("t9", "submit_home", {})],
    ]


def test_happy_path_builds_a_valid_ai_plan_home():
    client = ScriptedClient(_happy_path_turns())
    result = run_builder(description="two-room bungalow", client=client,
                         home_id="11111111-2222-3333-4444-555555555555",
                         now_iso="2026-07-23T12:00:00Z")
    assert isinstance(result, BuildResult)
    assert not result.truncated
    home = result.home
    assert home is not None
    assert home.schema_version == SCHEMA_VERSION
    rooms = home.floors[0].rooms
    assert [r.name for r in rooms] == ["Living Room", "Bedroom"]
    # Interior door derived from the shared wall; front door is an exit.
    door_between = next(o for o in home.floors[0].openings if o.id == "door_2")
    assert sorted(door_between.room_ids) == ["room_1", "room_2"]
    front = next(o for o in home.floors[0].openings if o.id == "door_1")
    assert front.is_exit
    # Provenance is structural.
    assert all(r.source.value == "ai_plan" for r in rooms)
    # The trace records every construction call.
    assert [t.tool_name for t in result.trace][:2] == ["start_home", "add_floor"]


def test_invalid_submission_is_rejected_and_model_can_fix_then_resubmit():
    turns = [
        [_tool_use("t1", "start_home", {"name": "Broken"})],
        [_tool_use("t2", "add_floor", {"level": 0, "name": "Ground"})],
        # Submitting with an empty floor must bounce with the validation errors...
        [_tool_use("t3", "submit_home", {})],
        # ...after which the model repairs the draft and succeeds.
        [_tool_use("t4", "add_room", {
            "floor_id": "floor_1", "name": "Room", "type": "other",
            "polygon": _square(0, 0, 3, 3),
        })],
        [_tool_use("t5", "add_opening", {
            "kind": "door", "room_id": "room_1", "edge_index": 0, "t": 0.5,
        })],
        [_tool_use("t6", "submit_home", {})],
    ]
    client = ScriptedClient(turns)
    result = run_builder(description="x", client=client,
                         home_id="11111111-2222-3333-4444-555555555555",
                         now_iso="2026-07-23T12:00:00Z")
    assert result.home is not None
    rejected = next(t for t in result.trace if t.id == "t3")
    assert rejected.output["errors"], "the bad submission must carry the errors"


def test_action_errors_flow_back_as_tool_results_not_exceptions():
    turns = [
        [_tool_use("t1", "start_home", {"name": "X"})],
        [_tool_use("t2", "add_room", {  # floor doesn't exist yet
            "floor_id": "floor_1", "name": "R", "type": "other",
            "polygon": _square(0, 0, 3, 3),
        })],
        [],  # plain-text turn ends the loop
    ]
    client = ScriptedClient(turns)
    result = run_builder(description="x", client=client)
    errored = next(t for t in result.trace if t.id == "t2")
    assert "no such floor_id" in errored.output["error"]
    assert result.home is None
    assert result.truncated


def test_iteration_cap_returns_partial_with_issues_never_a_broken_home():
    turns = [[_tool_use("t1", "start_home", {"name": "X"})],
             [_tool_use("t2", "add_floor", {"level": 0, "name": "G"})]]
    client = ScriptedClient(turns)
    result = run_builder(description="x", client=client, max_iterations=2)
    assert result.truncated
    assert result.home is None
    assert result.issues


def test_builder_has_no_routing_tools():
    from app.ai.builder import TOOLS
    names = {t["name"] for t in TOOLS}
    assert not names & {"compute_routes", "check_egress"}, (
        "the builder must never see routing/egress tools — the engine routes, "
        "after human review"
    )


def test_requires_description_or_image():
    from app.ai.builder import BuilderError
    with pytest.raises(BuilderError):
        run_builder(client=ScriptedClient([]))
