# Profile → routing constraint mappings (S3.4)

**Why this document exists:** the profile feature is the "personalized, not generic" claim, so
it has to survive the question *"did the AI decide that?"* It did not. A profile's tags map
through the fixed table below into `RoutingConstraints`, and the same deterministic Dijkstra
engine from S1.2 does the routing. No model is consulted anywhere in this path.

- Table implementation: `backend/app/routing/profiles.py` (`constraints_for_profile`) — pure,
  total, no I/O.
- Constraint model: `backend/app/routing/plan.py` (`RoutingConstraints`).
- Where they bite: `backend/app/routing/engine.py` (`_edge_cost`).
- Tests: `backend/tests/test_profiles.py`, plus `/routes` cases in `backend/tests/test_api.py`.
- Grounding: every mapping below traces to `backend/corpus/special-considerations.md`, which
  cites USFA and NFPA. **No mapping exists without a corpus line justifying its direction.**

## Two kinds of constraint

| Kind | Fields | Effect on the search |
|---|---|---|
| **Hard** | `avoid_stairs`, `avoid_windows`, `max_sill_height_m` | The edge is removed. If a room has nothing left, the plan returns a `no_viable_route` finding. |
| **Soft** | `stair_penalty_m`, `window_penalty_m` | The edge stays usable but costs more, so it loses to any comparable alternative — and still wins over no route at all. |

The distinction is the honesty mechanism. A wheelchair user cannot use a staircase, so that
edge must *disappear* — showing them a route they cannot walk is worse than showing none. An
older adult *prefers* to avoid stairs, so that edge must merely *cost more*; banning it would
manufacture a no-viable-route flag that isn't true.

## The table

| Tag | Constraints produced | Corpus justification |
|---|---|---|
| `mobility_limited` | `avoid_stairs = True`, `avoid_windows = True` | "Stairs and window egress are generally not usable routes for a wheelchair user" — USFA fire safety for people with disabilities (`usfa-disabilities`). The corpus states the app mapping explicitly. |
| `elderly` | `stair_penalty_m = 10.0`, `max_sill_height_m = window_max_sill_m` (1.118 m) | "Prefer stair-free routes where available" — NFPA escape planning (`nfpa-escape-planning`). *Where available* is why this is soft, not hard. |
| `child` | `window_penalty_m = 20.0` | "Window egress deprioritized" for children; adults are assigned to assist young children — NFPA escape planning (`nfpa-escape-planning`). |
| `pet` | *(none)* | "People escape first"; the corpus is explicit that pets drive checklist items and phrasing only, and **never** alter route computation — Red Cross (`redcross-escape-plan`). A test asserts this stays a no-op. |

Tags **compose by strictest-wins**: someone tagged both `elderly` and `mobility_limited` gets
the hard `avoid_stairs`, not the soft penalty. The mapping is order-independent (tested).
An untagged profile produces exactly the default (unconstrained) S1.2 behaviour.

### Where the numbers come from — and where they don't

The corpus supplies **thresholds**, not **preference weights**. So:

- `max_sill_height_m = 1.118 m` **is** a corpus value: the 2021 IRC R310.2.2 maximum sill
  height, from `backend/corpus/egress_thresholds.json` (44 in; metric is authoritative). It is
  read from the thresholds object at runtime, never hardcoded in the table. It is already
  enforced for *everyone* by the egress checker — restating it for older adults keeps the
  constraint visible in the returned plan.
- `stair_penalty_m = 10.0` and `window_penalty_m = 20.0` are **engineering choices, not safety
  thresholds**, and we say so rather than dressing them up with a citation. The corpus says
  "prefer" and "deprioritize"; it gives no number, and we will not invent one and attribute it
  to NFPA. Their magnitudes were picked for one property each:
  - 10.0 > `STAIR_TRAVERSAL_COST` (6.0), so a stair-free route wins whenever a comparable one
    exists, while a stair route still beats no route.
  - 20.0 stacks on the engine's universal `WINDOW_EXIT_PENALTY` (12.0), so a child's window
    exit costs 32 m-equivalent — it loses to any realistic door route, but is still returned
    when it is the only way out.

## Known limitation: the `child` penalty currently changes no route

On all three fixtures (`bungalow`, `apartment`, `twostory`) the child surcharge changes
**zero** routes, because the universal 12 m window penalty already dominates every door/window
choice those homes offer. The mapping encodes the corpus's intent and would bite in a home
where the choice is close, but today the `child` tag's observable effect is the
accompanied-adult phrasing in the S3.1 explanation, not the geometry. This is asserted by
`test_child_penalty_is_a_no_op_on_the_current_fixtures` so nobody can quietly overclaim it in
a demo. By contrast, `elderly` and `mobility_limited` both demonstrably change the twostory
outcome.

## The demo moment (twostory.json)

| Profile | Bedroom | Result |
|---|---|---|
| **Grandpa** (`mobility_limited`) | Master Bedroom (floor 2) | `primary = None`, finding `no_viable_route` |
| **Maya** (`child`) | Kids' Bedroom (floor 2) | Route out via the front door (`d_front`), 14.19 m, using the stairs |

Grandpa's flag is not a bug — it is the product's most valuable output. His bedroom is upstairs
in a home whose only stair-free, window-free path to the exterior doesn't exist, and the corpus
guidance is precisely that a person with mobility limitations should **sleep near an accessible
exit, ideally on the ground floor** (`usfa-disabilities`). The app surfaces a true, actionable,
high-severity finding instead of animating a staircase he cannot use.

## Request contract (`/routes`)

The S3.4 change is **additive** — every pre-S3.4 request behaves identically.

```jsonc
POST /routes
{
  "home": { ...HomeModel... },
  "profile_id": "p_grandpa",     // NEW (optional): derive constraints from this profile's tags
  "constraints": { ... }         // pre-existing (optional): explicit constraints
}
```

- `profile_id` resolves against `home.profiles` (profiles already live in the HomeModel
  schema — **S3.4 required no schema change**).
- `profile_id` and `constraints` are **mutually exclusive** → `422`. Silently letting explicit
  constraints override the derived table would break the guarantee this document makes.
- Unknown `profile_id` → `404`. Falling back to unconstrained routing would hand a
  mobility-limited user a staircase.
- Response: `RoutePlan` gains `profile_id` (nullable), alongside the `constraints` it already
  returned, so a client can prove which table row produced the paths it is drawing.

`/explain` already accepts an optional full `profile` object (built in S3.1) and passes it into
the grounded prompt, so explanations reflect the person. Route computation stays with the
engine — the AI only narrates the result.

## Not mapped, deliberately

- **`hearing_impaired`** and **`vision_impaired`** — **now expressible, still routing-neutral.**
  Schema 2.0 (S6.1, 2026-09-05) added both to the `ProfileTag` enum, so the earlier "not in the
  schema" half of this entry no longer applies. The reasoning that mattered does: this is
  *alarm* guidance, not *routing* guidance (strobe alarms and bed-shakers —
  `usfa-smoke-alarms`; NOAA weather radio with an alert function). Neither tag changes a single
  edge in the graph, and `constraints_for_profile` returns the same `RoutingConstraints` with
  or without them.

  They were added to the contract so the S6.4 readiness checklist can act on them, not so
  routing can. Two tests pin that and are the contract for anyone tempted to change it:
  `test_sensory_tags_produce_no_routing_constraints` (the table) and
  `test_sensory_tags_do_not_alter_a_computed_route` (end-to-end — same home, same person, one
  tag added, byte-identical plan). Wiring either tag to a routing constraint is a decision to
  argue for in `decisions.md`, not something to slip in because it seems intuitive.

  A note on why this is not an oversight: neither impairment changes *which way out is
  usable*. A person who cannot hear needs to be **woken**; a person who cannot see needs the
  route **rehearsed and described** (which is what `RouteNarration` already exists for). Both
  are readiness problems, and modelling them as routing penalties would produce worse routes
  for no safety reason.
- **Age band** — not in the schema; `child` / `elderly` tags already carry what routing needs.
