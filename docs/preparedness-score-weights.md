# The preparedness score: every weight, justified

_Weights set in S6.7; peril depth and the `basis` tiering added in S11.2 (2026-09-22). Worked examples below re-derived from a run on that date._

The Escape Plan preparedness score is a composite number from 0 to 100 that measures a home's readiness across three perils: **Fire, Earthquake, and Severe Weather**.

It is not an AI judgement and not a black box. It is arithmetic over facts the routing engine and the agentic inspector already established, plus the boxes the family has checked.

Implementation: `backend/app/scoring/score.py` (pure function, no I/O), `backend/app/scoring/checklist.py` (item generation). Tests asserting the hand-calculations on this page: `backend/tests/test_scoring.py`. **Change the two together or this page lies** — that has happened before.

## Three Peril Sub-Scores

Each peril (Fire, Earthquake, Severe Weather) is scored independently from 0 to 100.
A peril starts at 100 points, and we deduct points for every incomplete checklist item associated with that peril or with "general" preparedness — **but only for items whose `scoring` field is `true`**.

Every other checklist category (`routes`, `egress`, `shutoffs`, `supply_kit`, `agent_finding`, `recommendation`) is advisory: it appears on the checklist and can be checked off, but never moves a sub-score.

As of **S11.2 (2026-09-22)** the `scoring: true` items are, all at fixed weight-per-item:

- `smoke_alarm` — placement + maintenance (one per bedroom, one per sleeping area, one per level, monthly test, 10-year replacement). **Fire.**
- `practice.meeting_point` — the single "pick an outside meeting place" item. **General**, so it counts toward all three.
- `eq.*` — earthquake preparation: move tall furniture away from beds and seating, heavy objects to lower shelves, TV/computer straps, cabinet latches (homes with a kitchen), flexible gas connectors (homes with a water heater or a tagged gas shutoff). **Earthquake.**
- `safe_room.know`, `safe_room.head_protection`, `safe_room.practice_the_move`, `alerts.weather_radio` — **Severe weather.**

`practice.drill_recent` and `rescan.home` are both `scoring: false`: a lapsed or never-done drill, and a stale scan, flag staleness on the checklist but never lower the score (non-punitive recurring items — see "Lapsed items" below).

**AI recommendations are non-scoring** (they provide advice, but do not move the number).

### Severity Deductions

Every checklist item has a severity. Incomplete **scoring** items deduct the following points from their applicable peril sub-scores (every current `scoring: true` item happens to carry `info` severity, so a scoring deduction is always 5 points today; the table exists because a future `scoring: true` item at another severity must use it):

| Severity | Deduction |
|---|---|
| `high` | 20 |
| `med` | 10 |
| `low` | 5 |
| `info` | 5 |

A `no_viable_route` or `no_viable_safe_room` engine finding is `scoring: false` — it's structural (fixed by changing the home, not by checking a box) and never deducts points directly. It is always `high` severity, though, so it still triggers the high-severity cap below, exactly for the "wheelchair user can't get out" scenario the cap exists for.

## The three perils are not equally rigorous, and the score says so

Before S11.2, **no earthquake or tornado item scored at all.** Both sub-scores were a constant 95 on every home, so `0.50 × min(sub_scores)` always resolved to fire and two of the three pillars in the composite carried no information. That is now fixed — but fixing it raises the question the `basis` field answers.

`/score` returns a `basis` map keyed exactly like `sub_scores`:

| Peril | `basis` | What that means |
|---|---|---|
| Fire | `code_quantified` | Measured against codified numbers — IRC R310 egress dimensions, NFPA alarm placement. The engine can say a window is 0.42 m² against a 0.53 m² minimum. |
| Earthquake | `guidance_based` | FEMA/USGS/ShakeOut practice. **No app-checkable numeric threshold exists.** |
| Severe weather | `guidance_based` | FEMA/NOAA/Red Cross practice. Same. |

The absence of numbers for the latter two is a **finding, not a gap** (`docs/decisions.md`, 2026-09-21). The sources carry exactly two numbers and neither is something a phone or a scan can check: "two metal straps" is a practice rather than a dimensioned value, and FEMA's 200–250 mph safe-room design wind speed is a *construction* criterion. Manufacturing a number to make scoring tidier is the precise failure this tier exists to prevent.

**The tier is a label, never a weight.** A `guidance_based` item deducts through exactly the same `SEVERITY_DEDUCTIONS` table as a `code_quantified` one — a flat 5 points at `info` severity. There is no multiplier, no discount, and no decimal the sources do not support. `test_guidance_based_perils_use_the_same_flat_deduction_as_fire` asserts this. `test_no_authored_earthquake_or_tornado_item_invents_a_threshold` asserts that no item **this project authored** for those perils states a figure, across its title, detail and why, with sourced statistics allowed by name. **It does not cover engine-generated items** (`hazard.*`, `engine.*`, `mitigation.secure.*`), which legitimately state measured geometry — that is the code-quantified half working — and it cannot see a spelled-out number. Stated here because a guard is only worth what its scope actually is.

What earthquake and tornado items *are* is behavioural: "have you fitted cabinet latches", "does everyone know where the safe room is". A checkbox is a fact the resident asserts, not a measurement — which is why scoring them adds no false precision.

### Two items that are deliberately non-scoring

- **`alerts.same_receiver.*` and `alerts.strobe.*`** (SAME-programmed weather radio, strobe/bed-shaker alarms, emitted for a `hearing_impaired` profile). The actions are real and sourced. They are non-scoring because **a household must not score lower because someone in it is deaf or hard of hearing.** Asserted by `test_accessible_alert_items_never_lower_the_score`.
- **`eq.stay_if_undamaged`** (after shaking, staying in an undamaged building is the sourced default — the opposite of fire). This is information, not a task anyone completes, so it must never move the number.

## The Composite Score

```
composite = 0.50 × min(sub_scores) + 0.25 × mid(sub_scores) + 0.25 × max(sub_scores)
```

A home is only as prepared as its weakest link. A perfect fire escape plan does not save a family in an earthquake. The lowest sub-score receives 50% of the total weight, while the other two receive 25% each.

Until S11.2 this weighting was decorative: earthquake and severe weather were pinned at 95 on every home, so `min(sub_scores)` was always fire and the formula never had a choice to make. It does now — on `twostory.json` the three sub-scores are 60 / 70 / 75, three different numbers from three different sets of items.

### The High-Severity Cap

If **any** unresolved checklist item across **any** peril has `high` severity — regardless of whether that item is `scoring: true` or `false` (e.g. a structural `no_viable_route` finding for a wheelchair user) — the composite score is capped at **40**. This ensures the score strictly falls into the "Needs work" (red) band on the UI, regardless of how many other boxes are checked.

### Bands

The app shows every score in one of three bands, defined once in `escape_plan/Readiness/ScoreBand.swift` and used by both
the Home card and the Score screen (they disagreed, 85/60 against 80/50, until 2026-09-25):

| Band | Score | Words on screen |
| --- | --- | --- |
| Well prepared | 85–100 | "Well prepared" |
| Some gaps | 60–84 | "Some gaps to close" |
| Needs work | 0–59 | "Needs work" |

The bands are presentation, not scoring: they never change a number. They are pinned by `ReadinessScoreBandTests`,
including that the high-severity cap above (40) always reads "Needs work", and that the three fixture scores (73 / 70 /
66) are mid-band — an unedited demo home must not read "Well prepared".

### Lapsed recurring items are non-punitive

`practice.drill_recent` (6-month cadence) and `rescan.home` (6-month cadence) are both `scoring: false`. A lapsed or never-completed drill, or a stale scan, shows up as an open checklist item — but it never subtracts a point. The scoring items are listed above.

### Recurrence through `/score` (S11.34)

`/score` accepts a completion time per recurring item (`checklist_state` value: an ISO-8601 UTC timestamp, or a bare `true`) and judges it against the server clock. Intervals: `practice.drill_recent` and `rescan.home` 183 days; `alarm.test_monthly` 30 days (corpus: "test every alarm monthly", `usfa-smoke-alarms`). A bare `true` means "done at an unknown time" and stays done until a timestamp replaces it. The response carries each item's `recurrence_days` and the `completed_at` the server used.

`alarm.test_monthly` is a `scoring: true` smoke-alarm item, so unlike the drill and the rescan, **a lapsed monthly test does lower the score** (one smoke-alarm item's share, until the user tests again). Weights are unchanged; only the item can now lapse. Pinned by `backend/tests/test_recurrence.py`.

## Worked examples

All reproduce the fixtures in `schema/fixtures/`, with no agent findings and an empty checklist. **Every number below was read off a `compute_score` run on 2026-09-22, not derived by hand** — `backend/tests/test_scoring.py` asserts each one.

### bungalow.json

1 floor, 1 bedroom, a kitchen, no water heater.

| Peril | Scoring items | Arithmetic | Sub-score |
|---|---|---|---|
| Fire | 5 smoke-alarm + meeting point | 100 − 5×5 − 5 | **70** |
| Earthquake | 4 `eq.*` + meeting point | 100 − 4×5 − 5 | **75** |
| Severe weather | 4 tornado + meeting point | 100 − 4×5 − 5 | **75** |

Earthquake gets four of the five `eq.*` items: there is a kitchen (so `eq.cabinet_latches` fires) but no water heater and no tagged gas shutoff, so `eq.flexible_gas_connectors` does not.

**Composite:** `0.5×70 + 0.25×75 + 0.25×75` = 35 + 18.75 + 18.75 = 72.5 → round-half-up → **73**

### apartment.json

1 floor, 2 bedrooms, single front door (no secondary egress — a `routes` item, non-scoring, so it does NOT move the score).

| Peril | Scoring items | Arithmetic | Sub-score |
|---|---|---|---|
| Fire | 6 smoke-alarm + meeting point | 100 − 6×5 − 5 | **65** |
| Earthquake | 4 `eq.*` + meeting point | 100 − 4×5 − 5 | **75** |
| Severe weather | 4 tornado + meeting point | 100 − 4×5 − 5 | **75** |

**Composite:** `0.5×65 + 0.25×75 + 0.25×75` = 32.5 + 18.75 + 18.75 = **70**

### twostory.json

2 floors, 2 bedrooms, and a water heater.

| Peril | Scoring items | Arithmetic | Sub-score |
|---|---|---|---|
| Fire | 7 smoke-alarm + meeting point | 100 − 7×5 − 5 | **60** |
| Earthquake | 5 `eq.*` + meeting point | 100 − 5×5 − 5 | **70** |
| Severe weather | 4 tornado + meeting point | 100 − 4×5 − 5 | **75** |

The water heater is why earthquake is 70 here and 75 on the bungalow: `eq.flexible_gas_connectors` is emitted. This is the point of the S11.2 work — **the three sub-scores are no longer locked together**, so the composite's "weakest link" weighting now has something to choose between.

**Composite:** `0.5×60 + 0.25×70 + 0.25×75` = 30 + 17.5 + 18.75 = 66.25 → round-half-up → **66**

### bungalow.json with an unstrapped water heater

Bungalow with an unsecured `water_heater` object, scored **without** the peril plans (`tornado_plan` / `earthquake_plan` omitted), which is how `test_object_hazard_item_capping_score_roundtrip` calls it. This violates the `water_heater_unsecured` rule, generating an unresolved `mitigation` checklist item with `high` severity.

- Sub-scores: **Fire=70**, **Earthquake=70** (the water heater also emits `eq.flexible_gas_connectors`), **Severe Weather=90** (with no tornado plan, only the alerts item scores there).
- Because an unresolved high-severity item exists, the composite is capped at **40**.
- Checking off the item releases the cap: `0.5×70 + 0.25×70 + 0.25×90` = **75**.

### What changed in S11.2, and why the old numbers are gone

The previous version of this page recorded 83 / 80 / 78, with earthquake and severe weather at a constant 95 on all three fixtures. Those numbers were arithmetically correct and substantively empty: **no earthquake or tornado checklist item scored**, so the only thing moving any of those sub-scores was the shared meeting-point item. A judge reading `score.py` would have found that in a minute.
