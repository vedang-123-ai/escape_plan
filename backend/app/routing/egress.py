"""Egress viability checks against the corpus thresholds (pure functions).

Thresholds come from backend/corpus/egress_thresholds.json (2021 IRC baseline);
the caller loads the JSON and passes it in — this module does no I/O. Metric
values are authoritative (HomeModel is in meters).
"""

from __future__ import annotations

from dataclasses import dataclass

from app.models import (
    EgressAssessment,
    HomeModel,
    Opening,
    OpeningKind,
)


@dataclass(frozen=True)
class EgressThresholds:
    """Metric egress thresholds (see corpus egress_thresholds.json for citations)."""

    window_min_area_m2: float
    window_min_area_grade_m2: float
    window_min_height_m: float
    window_min_width_m: float
    window_max_sill_m: float
    door_min_width_m: float
    door_min_height_m: float

    @classmethod
    def from_corpus(cls, data: dict) -> "EgressThresholds":
        """Build from the parsed contents of corpus/egress_thresholds.json."""
        w = data["window_egress"]
        d = data["egress_door"]
        return cls(
            window_min_area_m2=w["min_net_clear_opening_area"]["value_m2"],
            window_min_area_grade_m2=w["min_net_clear_opening_area_grade_floor"]["value_m2"],
            window_min_height_m=w["min_net_clear_opening_height"]["value_m"],
            window_min_width_m=w["min_net_clear_opening_width"]["value_m"],
            window_max_sill_m=w["max_sill_height"]["value_m"],
            door_min_width_m=d["min_clear_width"]["value_m"],
            door_min_height_m=d["min_clear_height"]["value_m"],
        )


def check_egress(
    opening: Opening, thresholds: EgressThresholds, *, grade_floor: bool
) -> EgressAssessment:
    """Assess one opening against the thresholds.

    grade_floor: True when the opening is on a grade-level floor (level <= 0),
    which relaxes the window opening-area minimum per IRC R310.2.1.
    """
    reasons: list[str] = []
    if opening.kind == OpeningKind.door:
        if opening.width_m < thresholds.door_min_width_m:
            reasons.append(
                f"door width {opening.width_m:.3f}m < required "
                f"{thresholds.door_min_width_m:.3f}m"
            )
        if opening.height_m < thresholds.door_min_height_m:
            reasons.append(
                f"door height {opening.height_m:.3f}m < required "
                f"{thresholds.door_min_height_m:.3f}m"
            )
    else:
        min_area = (
            thresholds.window_min_area_grade_m2
            if grade_floor
            else thresholds.window_min_area_m2
        )
        area = opening.width_m * opening.height_m
        if opening.width_m < thresholds.window_min_width_m:
            reasons.append(
                f"window width {opening.width_m:.3f}m < required "
                f"{thresholds.window_min_width_m:.3f}m"
            )
        if opening.height_m < thresholds.window_min_height_m:
            reasons.append(
                f"window height {opening.height_m:.3f}m < required "
                f"{thresholds.window_min_height_m:.3f}m"
            )
        if area < min_area:
            reasons.append(
                f"window clear opening area {area:.3f}m² < required {min_area:.3f}m²"
            )
        if opening.sill_height_m > thresholds.window_max_sill_m:
            reasons.append(
                f"window sill {opening.sill_height_m:.3f}m above floor > maximum "
                f"{thresholds.window_max_sill_m:.3f}m"
            )
    return EgressAssessment(viable=not reasons, reasons=reasons)


def annotate_egress(home: HomeModel, thresholds: EgressThresholds) -> HomeModel:
    """Return a copy of the model with egress computed for every opening."""
    updated = home.model_copy(deep=True)
    for floor in updated.floors:
        grade = floor.level <= 0
        for opening in floor.openings:
            opening.egress = check_egress(opening, thresholds, grade_floor=grade)
    return updated
