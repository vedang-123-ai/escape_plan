# S11.2 — Peril scoring and checklist from the new corpus, honest tiering

- **Who:** P3
- **Date(s):** 2026-09-22
- **Status when I stopped:** Done. Backend **581 passed, 1 skipped, 13 deselected** (was 557; **+24**).
  Corpus valid (36 sources, 13 files, 2 threshold files, 44 tips) — unchanged, this session added no
  corpus content. EditorCore **516 passed, 0 failed**. `scripts/typecheck-ios.sh` ok on all four targets
  against iOS 17.0. **`xcodebuild test` NOT run** — no working simulator on this machine.

## What happened

The mission was "use the S11.1 corpus in the checklist and label the tiers". The first thing I did was
run the scorer over all three fixtures, and that changed what the session was about:

```
fixture      fire   earthquake   severe_weather   composite
bungalow      70        95             95             83
apartment     65        95             95             80
twostory      60        95             95             78
```

**Earthquake and severe weather were a constant 95 on every home.** Not one earthquake or tornado item
was `scoring: true`; the only scoring item reaching them was `practice.meeting_point`, tagged `general`.
So `0.50 × min(sub_scores)` always resolved to fire, and two of the three pillars in the "weakest link"
composite carried no information at all. The weights document presented those numbers as if they meant
something. A judge reading `score.py` finds that in a minute.

So the tiering work had a precondition: give earthquake and tornado items that actually move, *without*
inventing the numbers S11.1 established do not exist.

**What I built, in order:**

1. **Repaired the two claims S11.1 deleted** but which were still shipping from `checklist.py` — the
   renter "earthquake-rated adhesive straps" item under a `shakeout-guidance` cite that resolves and is
   false, and the drywall-anchor sentence. Renters now get the no-attachment actions that *are* sourced;
   the injuries claim carries the real ShakeOut evidence (55% of Northridge injuries from falling
   furniture, 1% from building damage) instead of the `usgs-earthquake` link directory.
2. **Found three more of the same class, which the S11.1 auditor did not list.** See below.
3. **Five new earthquake items** and **four scoring tornado items**, built from the markdown docs.
4. **`basis`** — a per-peril evidence tier on `/score`, decoded in Swift and rendered by nobody yet.
5. **Three `RouteFinding.citation` tests**, the thing BLOCKERS §3 actually still needed.
6. **Rewrote the weights document** from a run.

## Decisions / surprises

All four decisions are in `docs/decisions.md` (2026-09-22). The two that matter to someone else:

- **The fixture scores are now 73 / 70 / 66, not 83 / 80 / 78.** Anyone writing pitch or demo material
  must not quote the old numbers. They were arithmetically correct and substantively empty.
- **`basis` is a label, never a weight.** A `guidance_based` item deducts through exactly the same flat
  table as a fire item — 5 points at `info`. Two tests hold that line, including one asserting that no
  earthquake or tornado item states a number at all.

### Three more citations to a page that does not carry them

This is the finding I did not expect. `shutoff_items()` cited `fema-earthquake` for gas-shutoff and
electrical-panel guidance, and `supply_kit_items()` cited it for a "72-hour kit".

I found them by grepping what `fema-earthquake` is cited for **across the whole corpus**: only securing
objects and Drop, Cover, Hold On. `ready.gov/earthquakes` has no gas content, no electrical content and
no supply-kit content. All three cites resolved, so `validate.py` and the backend suite were green over
them — the same structural blindness S11.1 documented.

The kit item was the worst of them: "Water (one gallon per person per day for three days)" is a
**quantity nothing in this corpus supports**. It is not re-pointed, it is deleted. The item now says only
what `earthquake-after-shaking.md` sources — a grab-and-go bag of medication, documents and eyewear, and
flashlights rather than candles. The item **id** is unchanged (`supply_kit.72h`) so persisted done-state
survives; the id is now slightly misleading and that is the cheaper of the two problems.

**Worth stating plainly: this is the third session in a row to find this class of defect.** The pattern
is always the same — a plausible claim, a real source id, a green validator. The only thing that has ever
caught one is a person reading the cited page.

### And four of them were mine

Before running the auditor I re-read my own new strings against the sources and deleted four things I had
written that no page carries:

- "A tornado warning can give only minutes" — **invented**. The "minutes" figure in this corpus is the
  Red Cross *two-minute fire escape* claim. I had transplanted it to a different peril.
- "A rigid gas connection is what breaks when the appliance moves" — the action is sourced, the mechanism
  is not. Exactly the call S11.1 made when it dropped "a toppled heater can rupture its gas line".
- "Anything heavy or breakable stored high becomes a projectile" — embellishment.
- A Watch/Warning paraphrase, replaced with the corpus's own framing and cited to the page that has it.

Writing four unsourced claims in one afternoon, in the session whose theme is attribution, while fixing
five of someone else's, is the useful data point here. The discipline is not "be careful"; it is **read
the page again after you write the sentence.**

### The test helper had quietly stopped matching the endpoint

`test_scoring.py::_scored` carried a comment saying it called `compute_score` "exactly as /score does".
It did not — it omitted `tornado_plan` and `earthquake_plan`. This cost nothing while no tornado item
scored; the moment `safe_room.*` became scoring, the helper and the endpoint disagreed by 15
severe-weather points. Fixed, and the endpoint test now compares `sub_scores` against the helper rather
than only the composite, so the two cannot drift silently again.

A comment asserting parity is not parity.

### No fixture reaches two of the six finding kinds

Writing the `RouteFinding.citation` tests, I added a guard asserting that the fixtures between them
produce every declared `kind`. It immediately went red: **nothing in `schema/fixtures/` produces
`no_viable_route`**, and nothing produces `no_viable_safe_room` either, under default constraints. Both
are only reachable with `RoutingConstraints(avoid_stairs=True, avoid_windows=True)` — the
mobility-limited case the high-severity composite cap exists for. The test sweep now includes that pass.

All three citation tests were verified by breaking `engine.py` on purpose and watching them go red, then
restoring it. A green test that has never failed is not evidence.

### Two playbook inaccuracies

- `OWNED FILES` says `backend/app/models.py (the RouteFinding class ONLY)`. `RouteFinding` is in
  `backend/app/routing/plan.py`. It needed no edit either way — the field already exists on both sides.
- The mission says to decode `basis` in `APIClient+Score.swift`. That file contains no struct;
  `ScoreBreakdown` is a Codable in `escape_plan/Models/ScoreModels.swift`. Checked all 13 playbook files
  — no other S11 session owns it. Edited there, logged in `decisions.md`.

## Questions for teammates

- **@whoever takes S11.3** (owns `object_hazards.py`): two items are waiting for you in `BLOCKERS.md`
  under S11.2. The higher one is `object_hazards.py:210` — "An earthquake can tip it and rupture the gas
  line — strap it to wall studs at the top and bottom", cited `fema-earthquake`. The *action* is covered
  (Ready.gov lists water heaters among heavy items to secure); the **rupture mechanism is on no page**,
  and "top and bottom" is not what the sources say — ShakeOut says **two metal straps**. S11.1 deleted
  this identical mechanism claim from `prevention_tips.json`. `docs/object-hazard-spec.md:123` needs the
  same correction.
- **@Lane B / S11.11:** `escape_plan/DrillMode/DrillInstructions.swift:74` is now the **only** caller of
  `usgs-earthquake` anywhere in the project. Re-point it to `shakeout-guidance-after` and you can delete
  the source, the `ORPHAN_SOURCE_EXCEPTIONS` entry in `validate.py`, and close that whole thread. Note
  that exception's comment still names S11.2 as a co-owner — `validate.py` is S11.1's file so I left it,
  but it is out of date.
- **@S11.5** (renders the `basis` label): it arrives as `ScoreBreakdown.basis`, `[String: String]?`, keyed
  exactly like `sub_scores`. Values are `"code_quantified"` and `"guidance_based"`. It is optional —
  render nothing if it is nil rather than defaulting to either label.
- **@S11.12 / S11.13:** the fixture scores are **73 / 70 / 66**. Do not quote 83 / 80 / 78.

## Next steps

1. **S11.11 is unblocked** — this was its prereq.
2. S11.3 should take the two `object_hazards.py` / `object-hazard-spec.md` items above before doing its
   own hazard work; they are the same defect class it will be reading around anyway.
3. The iOS suite still has not run since 2026-09-09. Nothing in this session touched app code beyond one
   optional Codable field, but the 615 is now older by one more session.
