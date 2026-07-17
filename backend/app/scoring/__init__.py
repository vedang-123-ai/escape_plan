"""Explainable preparedness score (S3.5).

`score.compute_score` is the pure entry point; `checklist` generates the
deterministic items it scores; `findings` declares the S3.2 interface it
consumes; `recommend` is the only module here that talks to the AI, and what it
produces never affects the number. Weights: docs/preparedness-score-weights.md.
"""

from app.scoring.checklist import ChecklistItem, ChecklistState, build_checklist
from app.scoring.findings import Finding
from app.scoring.score import ScoreBreakdown, ScoreComponent, compute_score

__all__ = [
    "ChecklistItem",
    "ChecklistState",
    "Finding",
    "ScoreBreakdown",
    "ScoreComponent",
    "build_checklist",
    "compute_score",
]
