"""Grounded checklist recommendations (the AI edge of S3.5).

Everything else in app.scoring is pure. This module is the one place that calls
out to the S3.1 grounded layer, and it stays deliberately thin: it asks S3.1 for
recommendations about an already-computed RoutePlan and maps them to checklist
items. The items it produces are always `scoring=False` — the AI suggests what
else a family might do; it never moves the number, which stays a deterministic
function of the model, the findings, and the boxes the user checked.
"""

from __future__ import annotations

from typing import Optional, Sequence

import anthropic

from app.ai.grounded import (
    GroundingError,
    Recommendation,
    explain_routes,
    valid_source_ids,
)
from app.models import HomeModel, Profile
from app.routing.plan import RoutePlan
from app.scoring.checklist import ChecklistItem, ChecklistState


def recommendation_items(
    home: HomeModel,
    plan: RoutePlan,
    state: Optional[ChecklistState] = None,
    profile: Optional[Profile] = None,
    *,
    client: Optional[anthropic.Anthropic] = None,
) -> list[ChecklistItem]:
    """Ask the S3.1 layer for cited recommendations and map them to items.

    S3.1 already validates citations and retries uncited output, so a returned
    recommendation should always cite a real source. We re-check here anyway —
    this is the boundary where AI text becomes a user-facing safety claim, and
    an uncited claim must never reach the checklist. Raises GroundingError if
    one somehow survives.
    """
    explanation = explain_routes(home, plan, profile, client=client)
    return _map_recommendations(explanation.recommendations, state or {})


def _map_recommendations(
    recommendations: Sequence[Recommendation], state: ChecklistState
) -> list[ChecklistItem]:
    valid = valid_source_ids()
    items: list[ChecklistItem] = []
    for index, rec in enumerate(recommendations):
        citation = rec.source_citation.strip()
        if citation not in valid:
            raise GroundingError(
                f"recommendation[{index}] cites unknown source '{citation}' — "
                "refusing to put an uncited safety claim on the checklist"
            )
        # Positional id: the model's ordering is not stable across calls, so a
        # done-state on a recommendation item may not survive a regeneration.
        # Acceptable because these items are non-scoring; revisit if S3.3 or the
        # iOS checklist wants them to persist.
        item_id = f"recommendation.{index}"
        items.append(
            ChecklistItem(
                id=item_id,
                category="recommendation",
                title=rec.action,
                detail=rec.claim,
                done=state.get(item_id, False),
                source_citation=citation,
                scoring=False,
            )
        )
    return items
