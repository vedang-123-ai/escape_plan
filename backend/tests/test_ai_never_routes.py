"""S11.4: the separation the project is defended on, asserted structurally.

CLAUDE.md: "The AI never computes a route and never invents safety guidance.
That separation is the answer to a judge asking 'isn't this an AI wrapper?'"

Everything else asserting this is prose — in prompts, in docs, in the pitch. These
tests assert it about the code: every tool the model can call either reads the
HomeModel it was given or delegates to `app.routing` / `app.scoring`, and the
route a tool returns is byte-identical to the one the deterministic engine
produces when called directly. A tool that fabricated, rounded, re-ordered or
"helpfully" adjusted a route would fail here even if every prompt still said the
right thing.
"""

from __future__ import annotations

import ast
import inspect
from pathlib import Path

import pytest

from app import config
from app.ai import agent
from app.models import HomeModel
from app.routing.egress import check_egress
from app.routing.engine import compute_route_plan
from app.routing.plan import RoutePlan, RoutingConstraints
from tests.conftest import load_fixture

AGENT_SRC = Path(inspect.getfile(agent))

# Tools that answer purely by reading the HomeModel the caller supplied. They
# compute nothing, so they have no engine to delegate to.
READ_ONLY_TOOLS = {"get_home_summary", "get_room", "list_openings"}

# Tools that must delegate: tool name -> the deterministic callable it must use.
DELEGATING_TOOLS = {
    "compute_routes": "compute_route_plan",
    "check_egress": "check_egress",
    "check_obstructions": "analyze_obstructions",
    "check_object_hazards": "analyze_object_hazards",
}

# search_corpus reads the corpus; submit_findings ends the loop. Neither computes
# anything about the home.
NON_COMPUTING_TOOLS = {"search_corpus", "submit_findings"}


@pytest.fixture(scope="module")
def thresholds():
    return config.get_thresholds()


@pytest.fixture(scope="module")
def twostory() -> HomeModel:
    return HomeModel.model_validate(load_fixture("twostory.json"))


def test_every_registered_tool_is_accounted_for() -> None:
    """A new tool must be classified here before this file can pass.

    Without this, adding a route-computing tool would simply not be tested, and
    the guarantee would erode silently rather than fail.
    """
    registered = {t["name"] for t in agent.TOOLS}
    classified = READ_ONLY_TOOLS | set(DELEGATING_TOOLS) | NON_COMPUTING_TOOLS
    assert registered == classified, (
        f"unclassified tools: {sorted(registered - classified)}; "
        f"stale entries: {sorted(classified - registered)}"
    )


def test_the_agent_module_imports_its_engines_rather_than_reimplementing_them() -> None:
    """Bound names only.

    This used to accept `or callable_name in AGENT_SRC.read_text()`, which a
    comment mentioning the name satisfies — the assertion could pass on a module
    that had deleted the import (grounding-auditor, N7).
    """
    tree = ast.parse(AGENT_SRC.read_text())
    imported: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            imported |= {a.asname or a.name for a in node.names}
    for callable_name in DELEGATING_TOOLS.values():
        assert callable_name in imported or hasattr(agent, callable_name), (
            f"{callable_name} is not imported into agent.py — a tool claiming to "
            f"delegate to it cannot be doing so"
        )


def test_no_tool_dispatch_branch_does_its_own_geometry() -> None:
    """`_dispatch_tool` may read and delegate; it may not do route maths.

    Parsed rather than grepped so a comment mentioning sqrt does not fail the
    test and a real call does.
    """
    tree = ast.parse(AGENT_SRC.read_text())
    banned = {"sqrt", "hypot", "dist", "atan2", "cos", "sin", "radians"}
    # Every function in the module, not only `_dispatch_tool`: geometry moved one
    # call deeper into a private helper would otherwise escape the check
    # (grounding-auditor, N7). The module has no legitimate reason to do
    # trigonometry anywhere — that is what app.routing is for.
    for func in ast.walk(tree):
        if not isinstance(func, ast.FunctionDef):
            continue
        for node in ast.walk(func):
            if isinstance(node, ast.Call):
                called = getattr(node.func, "attr", None) or getattr(node.func, "id", None)
                assert called not in banned, (
                    f"agent.{func.name}() calls {called}() — geometry belongs in "
                    f"app.routing, not in the layer that talks to the model"
                )


def test_compute_routes_returns_exactly_what_the_engine_returns(twostory, thresholds):
    """The tool is a wrapper, and this proves it byte for byte."""
    via_tool = agent._dispatch_tool("compute_routes", {}, twostory, thresholds)
    direct = compute_route_plan(twostory, thresholds).model_dump(mode="json")
    assert via_tool == direct


def test_compute_routes_passes_constraints_through_unaltered(twostory, thresholds):
    via_tool = agent._dispatch_tool(
        "compute_routes", {"avoid_stairs": True, "avoid_windows": True}, twostory, thresholds
    )
    direct = compute_route_plan(
        twostory,
        thresholds,
        constraints=RoutingConstraints(avoid_stairs=True, avoid_windows=True),
    ).model_dump(mode="json")
    assert via_tool == direct
    # and the constrained plan really is different, or the test above proves nothing
    assert via_tool != compute_route_plan(twostory, thresholds).model_dump(mode="json")


def test_check_egress_returns_the_checkers_verdict_not_the_models(twostory, thresholds):
    """Including the failing case — the one a model would be tempted to soften."""
    opening = next(
        o for f in twostory.floors for o in f.openings if o.id == "w_kids"
    )
    floor = next(f for f in twostory.floors if any(o.id == "w_kids" for o in f.openings))
    direct = check_egress(opening, thresholds, grade_floor=floor.level <= 0)
    via_tool = agent._dispatch_tool("check_egress", {"opening_id": "w_kids"}, twostory, thresholds)
    assert via_tool["viable"] is direct.viable is False
    assert via_tool["reasons"] == direct.reasons


def test_no_tool_output_contains_a_route_the_engine_did_not_produce(twostory, thresholds):
    """Sweep every tool: any route-shaped payload must match the engine's own.

    This is the one that would catch a future tool quietly returning its own
    idea of a path alongside the engine's.
    """
    engine_plan = compute_route_plan(twostory, thresholds).model_dump(mode="json")
    # RoutePlan.rooms is a list of RoomRoutePlan: room_id + primary/secondary Route.
    engine_routes = {r["room_id"]: r for r in engine_plan["rooms"]}

    inputs: dict[str, dict] = {
        "get_home_summary": {},
        "get_room": {"room_id": "r_bed_kids"},
        "list_openings": {"floor_id": twostory.floors[0].id},
        "compute_routes": {},
        "check_egress": {"opening_id": "w_kids"},
        "check_obstructions": {},
        "check_object_hazards": {},
        "search_corpus": {"topic": "window egress"},
    }

    def routes_in(node) -> list[dict]:
        found: list[dict] = []
        if isinstance(node, dict):
            if "room_id" in node and ("primary" in node or "secondary" in node):
                found.append(node)
            for v in node.values():
                found.extend(routes_in(v))
        elif isinstance(node, list):
            for v in node:
                found.extend(routes_in(v))
        return found

    for tool_name, tool_input in inputs.items():
        out = agent._dispatch_tool(tool_name, tool_input, twostory, thresholds)
        for route in routes_in(out):
            room_id = route["room_id"]
            assert room_id in engine_routes, (
                f"{tool_name} returned a route for {room_id}, which the engine did not"
            )
            assert route == engine_routes[room_id], (
                f"{tool_name} returned a route for {room_id} that differs from the "
                f"engine's own output"
            )


def test_the_grounded_explainer_is_given_a_plan_and_has_no_engine_to_call() -> None:
    """/explain cannot compute a route even if the model asked it to.

    `explain_routes` takes an already-computed RoutePlan and exposes no tool at
    all except `submit_explanation`, whose schema carries prose and citations —
    no coordinates, no room sequence, no timings.
    """
    from app.ai.grounded import EXPLAIN_TOOL, ExplainResponse

    assert EXPLAIN_TOOL["name"] == "submit_explanation"
    schema_text = str(ExplainResponse.model_json_schema())
    for route_field in ("polygon", "path", "waypoints", "distance_m", "seconds"):
        assert route_field not in schema_text, (
            f"the /explain output schema has a {route_field} field — the model "
            f"would be able to state route geometry of its own"
        )
    # The plan it is handed really is the engine's shape, and that shape is the
    # only place route geometry exists in an /explain request.
    assert "rooms" in set(RoutePlan.model_fields)


def test_the_chat_assistant_has_no_tools_at_all() -> None:
    """The bluntest form of the guarantee, for the surface a user actually types at."""
    import app.ai.chat.service as chat_service

    src = Path(inspect.getfile(chat_service)).read_text()
    tree = ast.parse(src)
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and getattr(node.func, "attr", "") == "create":
            kwargs = {k.arg for k in node.keywords}
            assert "tools" not in kwargs, (
                "the chat service passes tools to the model; it is supposed to "
                "answer from the corpus and the plan it was handed"
            )
