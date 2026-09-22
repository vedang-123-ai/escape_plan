from __future__ import annotations

import math
from typing import Literal, Optional, Sequence, TYPE_CHECKING
from datetime import datetime

if TYPE_CHECKING:
    from app.routing.object_hazards import ObjectHazardThresholds

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

MAX_SCORE = 100.0
COMPOSITE_CAP_HIGH_SEVERITY = 40.0

#: Points deducted for incomplete checklist items, by severity.
SEVERITY_DEDUCTIONS: dict[str, float] = {
    "high": 20.0,
    "med": 10.0,
    "low": 5.0,
    "info": 5.0,
}

#: What kind of evidence a peril's score rests on. Fire is measured against
#: codified numbers — IRC egress dimensions, NFPA alarm placement — so a fire
#: finding can say a window is 0.42 m2 against a 0.53 m2 minimum. Earthquake and
#: tornado have no app-checkable numeric threshold anywhere in the corpus, and
#: S11.1 established that this is a finding rather than a gap: the only two
#: numbers the sources carry are "two metal straps" (a practice, not a dimension)
#: and FEMA's 200-250 mph safe-room design wind speed (a construction criterion
#: no phone or scan can measure). Their items are behavioural checkboxes instead.
#:
#: This is reported so that three numbers side by side can never be read as three
#: equally rigorous pillars. It changes no arithmetic: a guidance_based item uses
#: the same flat SEVERITY_DEDUCTIONS table as a code_quantified one.
PerilBasis = Literal["code_quantified", "guidance_based"]

PERIL_BASIS: dict[str, PerilBasis] = {
    "fire": "code_quantified",
    "earthquake": "guidance_based",
    "severe_weather": "guidance_based",
}

# -----------------------------------------------------------------------------

def _round_half_up(value: float) -> int:
    return int(math.floor(value + 0.5))

class ScoreComponent(BaseModel):
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
    sub_scores: dict[str, int]
    basis: Optional[dict[str, str]] = Field(
        default=None,
        description=(
            "Per-peril evidence tier, keyed exactly like sub_scores: "
            "'code_quantified' or 'guidance_based'. Optional so clients predating "
            "S11.2 still decode; always populated by compute_score."
        ),
    )
    components: list[ScoreComponent]
    checklist: list[ChecklistItem]

def compute_score(
    home: HomeModel,
    plan: RoutePlan,
    findings: Sequence[Finding],
    state: ChecklistState,
    thresholds: Optional[EgressThresholds] = None,
    *,
    tornado_plan: Optional[RoutePlan] = None,
    earthquake_plan: Optional[RoutePlan] = None,
    object_hazard_thresholds: Optional[ObjectHazardThresholds] = None,
    now: Optional[datetime] = None,
) -> ScoreBreakdown:
    findings = findings or []
    items = build_checklist(
        home,
        plan,
        findings,
        state or {},
        thresholds,
        tornado_plan=tornado_plan,
        earthquake_plan=earthquake_plan,
        object_hazard_thresholds=object_hazard_thresholds,
        now=now,
    )

    sub_scores_raw = {"fire": 100.0, "earthquake": 100.0, "severe_weather": 100.0}
    largest_deduction_item: Optional[ChecklistItem] = None
    largest_deduction_value = -1.0

    has_unresolved_high_severity = False

    for peril in sub_scores_raw:
        peril_items = [i for i in items if i.hazard in (peril, "general") and i.category != "recommendation" and i.id != "rescan.home"]
        
        for item in peril_items:
            if not item.done:
                # Bug A fix (S6.7 merge, 2026-09-07): the high-severity cap must
                # trigger on ANY unresolved high-severity item regardless of its
                # `scoring` flag — e.g. no_viable_route/no_viable_safe_room are
                # scoring=False (structural, fixed by changing the home) but must
                # still cap the composite. Deductions themselves, however, must
                # only come from scoring=True items — the advisory categories
                # (egress, routes, safe_room, mitigation, shutoffs, supply_kit,
                # alerts, agent_finding, recommendation) never move points.
                if item.severity == "high":
                    has_unresolved_high_severity = True

                if item.scoring:
                    deduction = SEVERITY_DEDUCTIONS.get(item.severity, 5.0)
                    sub_scores_raw[peril] -= deduction

                    # We track the single largest deduction across all perils
                    if deduction > largest_deduction_value:
                        largest_deduction_value = deduction
                        largest_deduction_item = item

        sub_scores_raw[peril] = max(0.0, sub_scores_raw[peril])

    sub_scores = {k: _round_half_up(v) for k, v in sub_scores_raw.items()}

    sorted_scores = sorted(sub_scores_raw.values())
    composite_raw = 0.5 * sorted_scores[0] + 0.25 * sorted_scores[1] + 0.25 * sorted_scores[2]
    
    if has_unresolved_high_severity:
        composite_raw = min(composite_raw, COMPOSITE_CAP_HIGH_SEVERITY)

    composite = _round_half_up(min(composite_raw, MAX_SCORE))

    components = []
    if largest_deduction_item:
        components.append(ScoreComponent(
            key=largest_deduction_item.id,
            label=largest_deduction_item.title,
            earned_points=0.0,
            max_points=largest_deduction_value,
            detail=largest_deduction_item.detail,
            rationale=f"Deduction based on {largest_deduction_item.severity} severity."
        ))

    return ScoreBreakdown(
        home_id=plan.home_id,
        home_name=plan.home_name,
        score=composite,
        sub_scores=sub_scores,
        basis={peril: PERIL_BASIS[peril] for peril in sub_scores},
        components=components,
        checklist=items,
    )
