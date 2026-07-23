"""Deterministic checklist generation (pure; no I/O, no AI).

Items come from three deterministic sources — the HomeModel itself (smoke-alarm
placement per the corpus), the routing engine's findings, and the S3.2 agent's
findings — plus a fixed pair of practice items. Every item id is stable for a
given (home, plan, findings) so a done-state persisted on the home document
survives recomputation.

Grounded AI recommendations are appended separately (app.scoring.recommend) and
are always non-scoring: the AI advises, it never moves the number.
"""

from __future__ import annotations

from typing import Literal, Optional, Sequence

from pydantic import BaseModel, ConfigDict, Field

from app.models import HomeModel, RoomType
from app.routing.plan import RoutePlan
from app.scoring.findings import Finding

ItemCategory = Literal[
    "smoke_alarm", "practice", "routes", "agent_finding", "recommendation"
]

#: The two scoring components whose points are earned by *checking boxes*
#: (as opposed to fixing the model). See docs/preparedness-score-weights.md.
SMOKE_ALARM_COMPONENT = "smoke_alarms"
PRACTICE_COMPONENT = "practice"

ChecklistState = dict[str, bool]
"""item id -> done. Persisted on the home document by the iOS app (S2.4)."""


class ChecklistItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    category: ItemCategory
    title: str
    detail: str
    done: bool = False
    source_citation: Optional[str] = Field(
        default=None,
        description="Corpus source id backing this item, when it makes a safety claim.",
    )
    scoring: bool = Field(
        description="True if checking this box moves the score by points_if_done."
    )
    component: Optional[str] = Field(
        default=None, description="Score component this item contributes to, if any."
    )


def _bedrooms(home: HomeModel) -> list[tuple[str, str, str]]:
    """(floor_id, room_id, room_name) for every bedroom, in document order."""
    return [
        (floor.id, room.id, room.name)
        for floor in home.floors
        for room in floor.rooms
        if room.type == RoomType.bedroom
    ]


def smoke_alarm_items(home: HomeModel, state: ChecklistState) -> list[ChecklistItem]:
    """Alarm placement + maintenance items, exactly as corpus/smoke-alarms-usfa.md
    prescribes: one per bedroom, one outside each sleeping area, one per level,
    plus the monthly test and the 10-year replacement."""
    bedrooms = _bedrooms(home)
    floors_with_bedrooms = {floor_id for floor_id, _, _ in bedrooms}
    items: list[ChecklistItem] = []

    def add(item_id: str, title: str, detail: str) -> None:
        items.append(
            ChecklistItem(
                id=item_id,
                category="smoke_alarm",
                title=title,
                detail=detail,
                done=state.get(item_id, False),
                source_citation="usfa-smoke-alarms",
                scoring=True,
                component=SMOKE_ALARM_COMPONENT,
            )
        )

    for _, room_id, room_name in bedrooms:
        add(
            f"alarm.bedroom.{room_id}",
            f"Smoke alarm inside {room_name}",
            "A working smoke alarm belongs inside every room used for sleeping.",
        )
    for floor in home.floors:
        if floor.id in floors_with_bedrooms:
            add(
                f"alarm.sleeping_area.{floor.id}",
                f"Smoke alarm outside the sleeping area on {floor.name}",
                "An alarm goes outside each separate sleeping area — the hallway "
                "serving the bedrooms.",
            )
    for floor in home.floors:
        add(
            f"alarm.level.{floor.id}",
            f"Smoke alarm on {floor.name}",
            "Every level of the home needs at least one smoke alarm.",
        )
    add(
        "alarm.test_monthly",
        "Test every smoke alarm this month",
        "Press the test button on every alarm once a month.",
    )
    add(
        "alarm.replace_10y",
        "Confirm no alarm is over 10 years old",
        "Replace every smoke alarm 10 years from its manufacture date.",
    )
    return items


def practice_items(state: ChecklistState) -> list[ChecklistItem]:
    """The two fixed plan-practice items. Drill mode (S4.2) checks
    `practice.drill_recent` when a drill completes."""
    return [
        ChecklistItem(
            id="practice.meeting_point",
            category="practice",
            title="Pick an outside meeting place",
            detail="Choose one safe spot a distance from the home — a mailbox, a "
            "tree, a neighbor's porch — where everyone gathers after escaping.",
            done=state.get("practice.meeting_point", False),
            source_citation="nfpa-escape-planning",
            scoring=True,
            component=PRACTICE_COMPONENT,
        ),
        ChecklistItem(
            id="practice.drill_recent",
            category="practice",
            title="Practice the plan (twice a year)",
            detail="Run the drill with everyone in the household; the Red Cross "
            "benchmark is everyone at the meeting place in under two minutes.",
            done=state.get("practice.drill_recent", False),
            source_citation="nfpa-escape-planning",
            scoring=True,
            component=PRACTICE_COMPONENT,
        ),
    ]


def route_items(plan: RoutePlan, state: ChecklistState) -> list[ChecklistItem]:
    """Items mirroring the routing engine's structured findings.

    Non-scoring: these are fixed by changing the home (adding an egress window,
    unblocking a route) and re-running the engine, which moves the routes
    components on its own. Checking the box must never double-count.
    """
    items: list[ChecklistItem] = []
    for room in plan.rooms:
        for finding in room.findings:
            item_id = f"routes.{finding.kind}.{room.room_id}"
            title = (
                f"Add a second way out of {room.room_name}"
                if finding.kind == "no_secondary_egress"
                else f"{room.room_name} has no usable way out"
            )
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="routes",
                    title=title,
                    detail=finding.detail,
                    done=state.get(item_id, False),
                    source_citation="nfpa-escape-planning",
                    scoring=False,
                )
            )
    return items


def finding_items(
    findings: Sequence[Finding], state: ChecklistState
) -> list[ChecklistItem]:
    """Items from the S3.2 agent's findings.

    Non-scoring for the same reason as route_items: the findings component is
    driven by the findings the agent reports, so points return when a re-run of
    /analyze stops reporting the issue — not when the user ticks a box.

    Ids key on the finding's server-stamped content hash
    (`agent_finding.<finding.id>`, see app.scoring.findings.finding_id), so a
    re-analysis that reorders findings keeps checkmarks on the right rows. For
    findings without an id (requests predating the id scheme), the key falls
    back to the old positional `agent_finding.<index>` — the pre-id status quo.
    Checkmarks saved under positional keys are orphaned once ids arrive; see
    docs/decisions.md (2026-07-23).
    """
    items: list[ChecklistItem] = []
    for index, finding in enumerate(findings):
        item_id = (
            f"agent_finding.{finding.id}" if finding.id else f"agent_finding.{index}"
        )
        items.append(
            ChecklistItem(
                id=item_id,
                category="agent_finding",
                title=finding.finding,
                detail=finding.recommendation,
                done=state.get(item_id, False),
                source_citation=finding.citation,
                scoring=False,
            )
        )
    return items


def build_checklist(
    home: HomeModel,
    plan: RoutePlan,
    findings: Sequence[Finding],
    state: ChecklistState,
) -> list[ChecklistItem]:
    """The full deterministic checklist, ordered scoring-items-first."""
    return [
        *smoke_alarm_items(home, state),
        *practice_items(state),
        *route_items(plan, state),
        *finding_items(findings, state),
    ]
