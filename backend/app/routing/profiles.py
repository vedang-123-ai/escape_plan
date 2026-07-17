"""Profile tag → RoutingConstraints mapping (S3.4). Pure, deterministic, total.

This is the "personalized, not generic" half of the product, and it is
deliberately NOT an AI decision: a profile's tags map through a fixed table to
the S1.2 constraints hook, and the same deterministic engine does the routing.
Every mapping is justified from backend/corpus/special-considerations.md; the
rationale table lives in docs/profile-constraint-mappings.md.

Two kinds of constraint come out of this table:

- Hard (avoid_stairs / avoid_windows / max_sill_height_m): the edge is removed
  from the search. A room with no route left produces an honest
  `no_viable_route` finding rather than a route the person cannot use.
- Soft (stair_penalty_m / window_penalty_m): the edge stays usable but costs
  more, so it loses to any comparable alternative. These are preference weights,
  not safety thresholds — the corpus gives no numeric basis for "prefer", so the
  magnitudes are engineering choices and are documented as such.
"""

from __future__ import annotations

from app.models import Profile, ProfileTag
from app.routing.egress import EgressThresholds
from app.routing.plan import RoutingConstraints

ELDERLY_STAIR_PENALTY_M = 10.0
"""Soft penalty for an older adult's stair traversal.

Corpus says "prefer stair-free routes where available" — a preference, not a
prohibition. Chosen > graph.STAIR_TRAVERSAL_COST (6.0) so a stair-free route
wins whenever one is comparable, while a stair route still beats no route.
Not a corpus threshold; see docs/profile-constraint-mappings.md.
"""

CHILD_WINDOW_PENALTY_M = 20.0
"""Additional soft penalty on a child's window egress.

Corpus: "window egress deprioritized" for children. Stacks on the engine's
universal WINDOW_EXIT_PENALTY (12.0), so a child's window exit costs 32m-
equivalent and loses to any door route in a typical home — but a window is
still returned when it is the only way out. Not a corpus threshold.
"""


def constraints_for_profile(
    profile: Profile, thresholds: EgressThresholds
) -> RoutingConstraints:
    """Deterministic tag → constraints mapping.

    Tags compose by taking the strictest value of each field, so a person who is
    both `elderly` and `mobility_limited` gets the hard `avoid_stairs` rather
    than the soft stair penalty. Unmapped tags (`pet`) contribute nothing —
    per corpus, pets never alter route computation.
    """
    avoid_stairs = False
    avoid_windows = False
    max_sill_height_m: float | None = None
    stair_penalty_m = 0.0
    window_penalty_m = 0.0

    for tag in profile.tags:
        if tag == ProfileTag.mobility_limited:
            # Corpus: stairs and window egress are generally not usable routes.
            avoid_stairs = True
            avoid_windows = True
        elif tag == ProfileTag.elderly:
            # Corpus: prefer stair-free routes where available (soft).
            stair_penalty_m = max(stair_penalty_m, ELDERLY_STAIR_PENALTY_M)
            # A window whose sill exceeds the code maximum is already excluded
            # for everyone by the egress checker; restating it here keeps the
            # constraint explicit in the returned plan for older adults.
            max_sill_height_m = thresholds.window_max_sill_m
        elif tag == ProfileTag.child:
            # Corpus: window egress deprioritized (soft).
            window_penalty_m = max(window_penalty_m, CHILD_WINDOW_PENALTY_M)

    return RoutingConstraints(
        avoid_stairs=avoid_stairs,
        avoid_windows=avoid_windows,
        max_sill_height_m=max_sill_height_m,
        stair_penalty_m=stair_penalty_m,
        window_penalty_m=window_penalty_m,
    )


def find_profile(home_profiles: list[Profile], profile_id: str) -> Profile | None:
    """Resolve a profile id against a home's profile list."""
    for profile in home_profiles:
        if profile.id == profile_id:
            return profile
    return None
