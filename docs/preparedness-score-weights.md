# The preparedness score: every weight, justified (S3.5 handoff)

The Escape Plan preparedness score is a number from 0 to 100 that answers one
question: **if a fire started tonight, how ready is this household?**

It is not an AI judgement and not a black box. It is arithmetic over facts the
deterministic routing engine (S1.2) and the agentic inspector (S3.2) already
established, plus the boxes the family has checked. Same home, same findings,
same checklist → same number, every time. Anyone can reproduce it with a
calculator from this page, and the worked examples at the bottom do exactly
that for all three test fixtures.

Implementation: `backend/app/scoring/score.py` (pure function, no I/O),
`backend/app/scoring/checklist.py` (item generation). Tests asserting the
hand-calculations on this page: `backend/tests/test_scoring.py`.

## The five components

| # | Component | Max | Earned by |
|---|---|---|---|
| 1 | Every room has a way out | **30** | fraction of rooms with a primary route |
| 2 | Two ways out of every room | **25** | fraction of rooms with a secondary route |
| 3 | No open safety findings | **20** | 20 minus per-finding deductions, floored at 0 |
| 4 | Smoke alarms in place and working | **15** | fraction of smoke-alarm checklist items confirmed |
| 5 | Plan agreed and practiced | **10** | fraction of the 2 practice items confirmed |
| | **Total** | **100** | |

The score is the sum of the five components, rounded **half-up** to the nearest
integer (`floor(x + 0.5)` — deliberately not Python's banker's rounding, which
would round 77.5 to 78 but 76.5 to 76 and make this page wrong).

### Why these five, in this order

The ordering is a claim about what actually saves lives, and it follows the
corpus rather than intuition. Routes first: a room with no computed path to an
exterior exit is a trap, and no amount of smoke alarms or practice fixes that —
hence 30, the largest single weight. Two ways out is NFPA's central escape-
planning rule [cite: nfpa-escape-planning], because fire blocks the primary
route often enough that a plan with one exit per room is a plan with a single
point of failure; that earns nearly as much, 25. Findings (20) capture what the
geometry alone cannot — a too-small egress window, a bedroom whose only exit
passes the kitchen. Smoke alarms (15) do not create escape routes but they buy
the household the roughly two minutes the routes need [cite: redcross-two-minutes],
which is why they sit below the routes and above practice. Practice (10) is last
only because it presupposes everything above it — but it is not optional: only
about 26% of families have actually practiced a plan [cite: redcross-escape-fact-sheet],
and NFPA asks for twice a year [cite: nfpa-escape-planning].

Together the routes components are 55 of 100, so a home the engine cannot route
can never reach a passing-looking score no matter how many boxes get checked.
That is intentional. The apartment fixture demonstrates it: fully checklisted,
it still caps at 75.

## Component 1 — Every room has a way out (30)

```
earned = 30 × (rooms with a primary route ÷ total rooms)
```

Rooms are every room in the RoutePlan (which is every room in the HomeModel, on
every floor). Bathrooms and halls count: a person can be in them.

Partial credit rather than all-or-nothing, so that fixing one trapped bedroom
visibly moves the score — the component is meant to be actionable, not a pass/fail
light.

**Source of truth:** `RoomRoutePlan.primary is not None`, computed by the
deterministic engine. The score never decides what a route is.

## Component 2 — Two ways out of every room (25)

```
earned = 25 × (rooms with a secondary route ÷ total rooms)
```

Same denominator, same partial-credit reasoning. A secondary route is the
engine's second, independent path — the one that survives the primary being
blocked. Grounded in the two-ways-out rule [cite: nfpa-escape-planning]; the
engine's `no_secondary_egress` findings are the same fact in structured form,
and each becomes a (non-scoring) checklist item pointing at the room.

## Component 3 — No open safety findings (20)

```
earned = max(0, 20 − Σ deduction(finding))
```

| Severity | Deduction |
|---|---|
| `high` | 10 |
| `med` | 4 |
| `low` | 1 |

Per-finding deductions rather than the playbook's all-or-nothing "no
high-severity findings (20)", because all-or-nothing makes one low-severity note
read identically to a bedroom with no viable egress, and gives a household with
two high-severity findings no way to show progress by fixing one. Two
high-severity findings zero the component; the floor at 0 keeps the total score
from going negative.

Findings come from `/analyze` (S3.2), where each one is already validated
server-side to link to real tool-call evidence. Scoring trusts that validation
and reads only `severity` — **the AI does not score, it reports.** With no
findings supplied (e.g. the user has not run an inspection yet) the component
sits at full marks: the score reports what is known, it does not penalise the
household for a step they have not taken.

**TODO(integration):** the `Finding` interface lives in
`backend/app/scoring/findings.py`, transcribed from `docs/playbook/S3-2.md`
while S3.2 was still in a parallel lane. If S3.2's severity spelling differs
(`"medium"` vs `"med"`), `SEVERITY_DEDUCTIONS` and this table must follow.

## Component 4 — Smoke alarms in place and working (15)

```
earned = 15 × (confirmed alarm items ÷ total alarm items)
```

The item set is generated from the home itself, exactly as the corpus prescribes
[cite: usfa-smoke-alarms]:

| Item id | One per | Claim |
|---|---|---|
| `alarm.bedroom.<room_id>` | bedroom-type room | an alarm inside every sleeping room |
| `alarm.sleeping_area.<floor_id>` | floor that has a bedroom | an alarm outside each separate sleeping area |
| `alarm.level.<floor_id>` | floor | an alarm on every level |
| `alarm.test_monthly` | home | test every alarm monthly |
| `alarm.replace_10y` | home | replace alarms 10 years from manufacture |

So the per-item value depends on the home: a one-bedroom bungalow generates 5
items worth 3.00 each; the two-story generates 7 items worth 15/7 ≈ 2.142857
each. This is deliberate — a bigger home needs more alarms, and each one should
be worth proportionally less, so the component measures *coverage* rather than
count.

These are self-reported. The app cannot see a smoke alarm; RoomPlan does not
detect them and furniture detection is out of scope. The score treats a checked
box as truth, and the breakdown screen says so.

## Component 5 — Plan agreed and practiced (10)

```
earned = 10 × (confirmed practice items ÷ 2) → 5.00 points each
```

| Item id | Claim |
|---|---|
| `practice.meeting_point` | one outside meeting place, a safe distance away [cite: nfpa-escape-planning] |
| `practice.drill_recent` | practice the plan twice a year [cite: nfpa-escape-planning] |

Drill mode (S4.2) checks `practice.drill_recent` when a drill completes, which
is what makes the score move on its own during the demo.

## What deliberately does *not* score

- **Grounded AI recommendations.** `/score` with `include_recommendations: true`
 asks the S3.1 layer for cited suggestions and appends them to the checklist as
 `scoring: false` items. The AI advises; it never moves the number. This is the
 same division of labour as the rest of the app, and it is the honest answer to
 "isn't the score just the AI's opinion?" — no, and here is the arithmetic.
- **Route findings and agent-finding checklist items.** Both are `scoring: false`.
 They are fixed by changing the home and re-running the engine (or re-running
 `/analyze`), which moves components 1–3 on its own. If ticking the box *also*
 paid out, the same fix would be counted twice.
- **Egress-window items (`egress.window.*`).** Bedroom escape windows that fail
 IRC R310, checked deterministically by `routing.egress.check_egress` — the same
 function the engine and the agent both call, no AI involved. `scoring: false`
 for the same reason as route findings. These exist because the check is free
 and the alternative was silence: `twostory.json`'s planted kids'-bedroom window
 (0.4 m wide against the 0.508 m minimum) raises no RoutePlan finding — the
 whole-house router is satisfied by a secondary route out of a *different* exit
 — so before these items existed it appeared on the checklist only if someone
 ran `/analyze`. Scoped to sleeping rooms, which is where R310 applies.

So of the checklist, only the smoke-alarm and practice items are scoring items —
together the 25 points a family can earn without touching the floor plan.

## Worked examples

All three reproduce the fixtures in `schema/fixtures/`, with **no agent findings
and an empty checklist** unless stated. Asserted in
`backend/tests/test_scoring.py`.

### bungalow.json — 75

4 rooms (Living Room, Kitchen, Bedroom, Bathroom), 1 floor, 1 bedroom. The
engine finds a primary and a secondary route for all 4.

| Component | Arithmetic | Points |
|---|---|---|
| Primary routes | 30 × 4/4 | 30.00 |
| Secondary routes | 25 × 4/4 | 25.00 |
| Findings | 20 − 0 | 20.00 |
| Smoke alarms | 15 × 0/5 | 0.00 |
| Practice | 10 × 0/2 | 0.00 |
| | **Total** | **75** |

The 5 alarm items: `alarm.bedroom.r_bedroom`, `alarm.sleeping_area.f1`,
`alarm.level.f1`, `alarm.test_monthly`, `alarm.replace_10y` → 3.00 points each.
Check them all and set both practice items → 30 + 25 + 20 + 15 + 10 = **100**.

### apartment.json — 50

5 rooms, 1 floor, 2 bedrooms, and one front door — the fixture's planted
single-point-of-failure. Every room routes to that door; none has a second way
out.

| Component | Arithmetic | Points |
|---|---|---|
| Primary routes | 30 × 5/5 | 30.00 |
| Secondary routes | 25 × 0/5 | 0.00 |
| Findings | 20 − 0 | 20.00 |
| Smoke alarms | 15 × 0/6 | 0.00 |
| Practice | 10 × 0/2 | 0.00 |
| | **Total** | **50** |

6 alarm items (2 bedrooms + 1 sleeping area + 1 level + 2 maintenance) → 2.50
each. Fully checklisted the apartment reaches **75** and stops: the missing 25
is the second way out, and only a real change to the home buys it back.

With one high-severity finding on Bedroom 1: 50 − 10 = **40**. With three:
findings floors at 0 → **30**.

### twostory.json — 75

7 rooms over 2 floors, 2 bedrooms (both upstairs). All 7 rooms get both routes.

| Component | Arithmetic | Points |
|---|---|---|
| Primary routes | 30 × 7/7 | 30.00 |
| Secondary routes | 25 × 7/7 | 25.00 |
| Findings | 20 − 0 | 20.00 |
| Smoke alarms | 15 × 0/7 | 0.00 |
| Practice | 10 × 0/2 | 0.00 |
| | **Total** | **75** |

7 alarm items: 2 bedrooms + `alarm.sleeping_area.f2` (the Landing serves the
bedrooms; the ground floor has none, so no `alarm.sleeping_area.f1`) + 2 levels
+ 2 maintenance → 15/7 ≈ 2.142857 each.

Check one alarm item: 75 + 2.142857 = 77.142857 → **77**.

## Notes for reviewers

- The score is computed against the RoutePlan **the user is looking at**,
 including profile constraints. Scoring the two-story under Grandpa's
 `mobility_limited` profile (`avoid_stairs`) strands the upstairs rooms and the
 score drops below 75 — correct behaviour: the home is genuinely less ready for
 him than for the rest of the household.
- Weights are constants at the top of `backend/app/scoring/score.py`. Changing
 one means changing this page and the assertions in `test_scoring.py` together
 — that pairing is what keeps "reproducible by hand" true rather than aspirational.

## Remaining work

- **iOS score screen and count-up animation (P2, out of scope for S3.5's backend
 half).** The breakdown is already shaped for it: `ScoreBreakdown.components`
 is an ordered list of tappable rows, each carrying `earned_points`,
 `max_points`, a plain-language `detail`, and the `rationale` above.
- **S3.2 merge:** reconcile `app/scoring/findings.py` with the real agent models.
- **S4.2 drill mode:** write `practice.drill_recent` on drill completion.
- **S2.4 persistence:** `checklist_state` (item id → done) is a flat
 `dict[str, bool]` on the home document; ids are stable per home.
