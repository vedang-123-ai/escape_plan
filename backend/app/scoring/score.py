"""The preparedness score (S3.5): a pure, explainable 0-100 function.

Not a black box and not an AI judgement — every point is arithmetic over facts
the deterministic engine already established. `compute_score` is a pure function
of (HomeModel, RoutePlan, agent findings, checklist state); the RoutePlan is
itself a pure function of the HomeModel, so the same inputs always produce the
same number, and a reviewer can reproduce any score by hand from
docs/preparedness-score-weights.md — which is the acceptance bar for this
session, so keep the doc and the constants below in lockstep.
"""

from __future__ import annotations

import math
from typing import Optional, Sequence

from pydantic import BaseModel, ConfigDict, Field

from app.models import HomeModel
from app.routing.egress import EgressThresholds
from app.routing.plan import RoutePlan
from app.scoring.checklist import (
    ChecklistItem,
    ChecklistState,
    build_checklist,
)
from app.scoring.findings import Finding

# --- weights (documented in docs/preparedness-score-weights.md) --------------

PRIMARY_ROUTE_POINTS = 30.0
SECONDARY_ROUTE_POINTS = 25.0
FINDINGS_POINTS = 20.0
SMOKE_ALARM_POINTS = 15.0
PRACTICE_POINTS = 10.0

MAX_SCORE = 100.0

#: Points subtracted from the findings component per agent finding, by severity.
SEVERITY_DEDUCTIONS: dict[str, float] = {"high": 10.0, "med": 4.0, "low": 1.0}


def _round_half_up(value: float) -> int:
    """Half-up rounding — Python's round() is banker's rounding, which would make
    the doc's hand-calculations wrong at exact .5 boundaries."""
    return int(math.floor(value + 0.5))


class ScoreComponent(BaseModel):
    """One tappable row of the breakdown screen."""

    model_config = ConfigDict(extra="forbid")

    key: str
    label: str
    earned_points: float
    max_points: float
    detail: str = Field(description="The arithmetic, in words — shown to the user.")
    rationale: str = Field(description="Why this weight; cited where applicable.")


class ScoreBreakdown(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home_id: str
    home_name: str
    score: int = Field(ge=0, le=100)
    components: list[ScoreComponent]
    checklist: list[ChecklistItem]


def _fraction(numerator: int, denominator: int) -> float:
    return numerator / denominator if denominator else 0.0


def _primary_component(plan: RoutePlan) -> ScoreComponent:
    total = len(plan.rooms)
    with_primary = sum(1 for room in plan.rooms if room.primary is not None)
    earned = PRIMARY_ROUTE_POINTS * _fraction(with_primary, total)
    return ScoreComponent(
        key="primary_routes",
        label="Every room has a way out",
        earned_points=earned,
        max_points=PRIMARY_ROUTE_POINTS,
        detail=f"{with_primary} of {total} rooms have a primary escape route.",
        rationale=(
            "The single most load-bearing fact about a home: a room with no "
            "computed route to an exterior exit is a trap. Weighted highest."
        ),
    )


def _secondary_component(plan: RoutePlan) -> ScoreComponent:
    total = len(plan.rooms)
    with_secondary = sum(1 for room in plan.rooms if room.secondary is not None)
    earned = SECONDARY_ROUTE_POINTS * _fraction(with_secondary, total)
    return ScoreComponent(
        key="secondary_routes",
        label="Two ways out of every room",
        earned_points=earned,
        max_points=SECONDARY_ROUTE_POINTS,
        detail=f"{with_secondary} of {total} rooms have a second, independent route.",
        rationale=(
            "NFPA's core escape-planning rule is two ways out of every room "
            "[cite: nfpa-escape-planning]; fire blocks the primary route often "
            "enough that this is close to as important as having one at all."
        ),
    )


def _findings_component(findings: Sequence[Finding]) -> ScoreComponent:
    counts = {
        severity: sum(1 for f in findings if f.severity == severity)
        for severity in SEVERITY_DEDUCTIONS
    }
    deduction = sum(
        SEVERITY_DEDUCTIONS[severity] * count for severity, count in counts.items()
    )
    earned = max(0.0, FINDINGS_POINTS - deduction)
    if not findings:
        detail = "No open safety findings from the home inspection."
    else:
        detail = (
            f"{counts['high']} high, {counts['med']} medium, {counts['low']} low "
            f"severity findings → -{deduction:g} points (floored at 0)."
        )
    return ScoreComponent(
        key="findings",
        label="No open safety findings",
        earned_points=earned,
        max_points=FINDINGS_POINTS,
        detail=detail,
        rationale=(
            "Deductions per finding (high 10 / med 4 / low 1) rather than "
            "all-or-nothing, so one low-severity note does not read the same as "
            "a bedroom with no egress. Two high-severity findings zero the "
            "component."
        ),
    )


def _checked(items: Sequence[ChecklistItem], component: str) -> tuple[int, int]:
    relevant = [i for i in items if i.scoring and i.component == component]
    return sum(1 for i in relevant if i.done), len(relevant)


def _smoke_alarm_component(items: Sequence[ChecklistItem]) -> ScoreComponent:
    done, total = _checked(items, "smoke_alarms")
    earned = SMOKE_ALARM_POINTS * _fraction(done, total)
    per_item = _fraction(SMOKE_ALARM_POINTS, total)
    return ScoreComponent(
        key="smoke_alarms",
        label="Smoke alarms in place and working",
        earned_points=earned,
        max_points=SMOKE_ALARM_POINTS,
        detail=(
            f"{done} of {total} smoke-alarm items confirmed "
            f"({per_item:.2f} points each)."
        ),
        rationale=(
            "Alarm placement and maintenance are what buy the household the "
            "time the routes need [cite: usfa-smoke-alarms]. Items are generated "
            "from the home itself (one per bedroom, one outside each sleeping "
            "area, one per level, plus the monthly test and 10-year "
            "replacement), so the per-item value depends on the home's size."
        ),
    )


def _practice_component(items: Sequence[ChecklistItem]) -> ScoreComponent:
    done, total = _checked(items, "practice")
    earned = PRACTICE_POINTS * _fraction(done, total)
    return ScoreComponent(
        key="practice",
        label="Plan agreed and practiced",
        earned_points=earned,
        max_points=PRACTICE_POINTS,
        detail=f"{done} of {total} practice items confirmed (5.00 points each).",
        rationale=(
            "A plan nobody has walked is barely a plan — only about 26% of "
            "families have practiced one [cite: redcross-escape-fact-sheet], and "
            "NFPA asks for twice a year [cite: nfpa-escape-planning]. Weighted "
            "lowest only because it presupposes the routes above."
        ),
    )


def compute_score(
    home: HomeModel,
    plan: RoutePlan,
    findings: Optional[Sequence[Finding]] = None,
    state: Optional[ChecklistState] = None,
    thresholds: Optional[EgressThresholds] = None,
) -> ScoreBreakdown:
    """Score a home 0-100 and return the full breakdown plus its checklist.

    Pure: no I/O, no network, no clock. `plan` must be the RoutePlan the engine
    computed for `home` — pass it in rather than recomputing so the score always
    reflects the routes the user is actually looking at (including any
    profile-derived constraints).

    `thresholds` enables the deterministic IRC R310 egress-window items; omit it
    only if you have no thresholds to hand (undersized bedroom windows then go
    unreported until /analyze runs).
    """
    findings = findings or []
    items = build_checklist(home, plan, findings, state or {}, thresholds)
    components = [
        _primary_component(plan),
        _secondary_component(plan),
        _findings_component(findings),
        _smoke_alarm_component(items),
        _practice_component(items),
    ]
    total = sum(c.earned_points for c in components)
    return ScoreBreakdown(
        home_id=plan.home_id,
        home_name=plan.home_name,
        score=_round_half_up(min(total, MAX_SCORE)),
        components=components,
        checklist=items,
    )
