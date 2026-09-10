# The preparedness score: every weight, justified (S6.7 handoff)

The Escape Plan preparedness score is a composite number from 0 to 100 that measures a home's readiness across three perils: **Fire, Earthquake, and Severe Weather**.

It is not an AI judgement and not a black box. It is arithmetic over facts the routing engine and the agentic inspector already established, plus the boxes the family has checked.

Implementation: `backend/app/scoring/score.py` (pure function, no I/O), `backend/app/scoring/checklist.py` (item generation). Tests asserting the hand-calculations on this page: `backend/tests/test_scoring.py`.

## Three Peril Sub-Scores

Each peril (Fire, Earthquake, Severe Weather) is scored independently from 0 to 100.
A peril starts at 100 points, and we deduct points for every incomplete checklist item associated with that peril or with "general" preparedness — **but only for items whose `scoring` field is `true`**.

Every other checklist category (`routes`, `egress`, `safe_room`, `shutoffs`, `mitigation`, `supply_kit`, `alerts`, `agent_finding`, `recommendation`) is advisory: it appears on the checklist and can be checked off, but never moves a sub-score. As of the S6.7 merge (2026-09-07), that leaves exactly two `scoring: true` categories, both fixed weight-per-item:

- `smoke_alarm` — placement + maintenance items (one per bedroom, one per sleeping area, one per level, monthly test, 10-year replacement)
- `practice.meeting_point` — the single "pick an outside meeting place" item

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

## The Composite Score

```
composite = 0.50 × min(sub_scores) + 0.25 × mid(sub_scores) + 0.25 × max(sub_scores)
```

A home is only as prepared as its weakest link. A perfect fire escape plan does not save a family in an earthquake. The lowest sub-score receives 50% of the total weight, while the other two receive 25% each.

### The High-Severity Cap

If **any** unresolved checklist item across **any** peril has `high` severity — regardless of whether that item is `scoring: true` or `false` (e.g. a structural `no_viable_route` finding for a wheelchair user) — the composite score is capped at **40**. This ensures the score strictly falls into the "Needs work" (red) band on the UI, regardless of how many other boxes are checked.

### Lapsed recurring items are non-punitive

`practice.drill_recent` (6-month cadence) and `rescan.home` (6-month cadence) are both `scoring: false`. A lapsed or never-completed drill, or a stale scan, shows up as an open checklist item — but it never subtracts a point. Only checking or unchecking the meeting-point item and the smoke-alarm items moves a sub-score.

## Worked examples

All reproduce the fixtures in `schema/fixtures/`, with no agent findings and an empty checklist.

### bungalow.json

1 floor, 1 bedroom. The only `scoring: true` items are 5 smoke-alarm items (`fire`, `info`, -5 each) and 1 `practice.meeting_point` item (`general`, `info`, -5).

- **Fire:** 100 − 5×5 (alarms) − 5 (meeting point) = **70**
- **Earthquake:** 100 − 5 (meeting point, general) = **95**
- **Severe Weather:** 100 − 5 (meeting point, general) = **95**

**Composite:** `0.5×70 + 0.25×95 + 0.25×95` = 35 + 23.75 + 23.75 = 82.5 → round-half-up → **83**

### apartment.json

1 floor, 2 bedrooms, single front door (no secondary egress — a `routes` item, non-scoring, so it does NOT move the score). The `scoring: true` items are 6 smoke-alarm items (`fire`, `info`, -5 each) and 1 `practice.meeting_point` item (`general`, `info`, -5).

- **Fire:** 100 − 6×5 (alarms) − 5 (meeting point) = **65**
- **Earthquake:** 100 − 5 (meeting point, general) = **95**
- **Severe Weather:** 100 − 5 (meeting point, general) = **95**

**Composite:** `0.5×65 + 0.25×95 + 0.25×95` = 32.5 + 23.75 + 23.75 = 80

### twostory.json

2 floors, 2 bedrooms. The `scoring: true` items are 7 smoke-alarm items (`fire`, `info`, -5 each) and 1 `practice.meeting_point` item (`general`, `info`, -5).

- **Fire:** 100 − 7×5 (alarms) − 5 (meeting point) = **60**
- **Earthquake:** 100 − 5 (meeting point, general) = **95**
- **Severe Weather:** 100 − 5 (meeting point, general) = **95**

**Composite:** `0.5×60 + 0.25×95 + 0.25×95` = 30 + 23.75 + 23.75 = 77.5 → round-half-up → **78**

### bungalow.json with an unstrapped water heater

Bungalow with an unsecured `water_heater` object. This violates the `water_heater_unsecured` rule, generating an unresolved `mitigation` checklist item with `high` severity.

- The sub-score components are identical to the baseline bungalow: **Fire=70**, **Earthquake=95**, **Severe Weather=95**.
- However, because an unresolved high-severity item exists, the composite score is capped at **40**.
- Checking off the item releases the cap, returning the composite score to **83**.
