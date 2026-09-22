# S11.2 — Peril scoring and checklist from the new corpus, honest tiering

- **Who:** P3
- **Date(s):** 2026-09-22
- **Status when I stopped:** Done. Backend **583 passed, 1 skipped, 13 deselected** (was 557; **+26**).
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
  table as a fire item — 5 points at `info`. Two tests hold that line: one on the deduction, one on
  authored earthquake/tornado items stating no figure. The second has a stated scope and a known blind
  spot (spelled-out numbers) — see the auditor section; my first version of it, and the two docs I wrote
  about it, all overclaimed.

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

## What the grounding-auditor found

Verdict: **VIOLATIONS**. Six findings, all now closed. It earned its run — two were blocking and one
was the kind of defect no validator can see.

1. **My headline repair was close to cosmetic.** `mitigation_items` suppresses its own renter item for
   any object that produced a `topple` hazard, so for the exact case the repair targeted — a renter with
   a toppling wardrobe — the only text shown still came from `object_hazards.py:292`, carrying the
   deleted adhesive-strap claim. I had logged that line for S11.3 and moved on. **I ran it on
   `jagged.json` and the auditor was right**: the bookcase over the bed and the wardrobe across the
   doorway both showed the deleted claim, while my repaired item appeared only on a boiler that had not
   tripped a hazard rule. Fixed here, outside OWNED FILES, because the alternative was a session about
   removing that claim shipping it as the primary guidance.
2. **I reintroduced a misattribution S11.1 had fixed.** `safe_room.know` put "as many walls" back under
   `noaa-tornado`; `decisions.md` 2026-09-21 records that exact phrase being re-pointed to
   `noaa-tornado-shelter`. Re-pointed, with a comment in the code so it does not happen a third time.
3. **The severe-weather sub-score rewarded having no safe room** — 90 with no shelter against 75 with
   one, because I gated the two new scoring items on `has_shelter`. The composite hid it behind the
   high-severity cap, but `sub_scores` is what S11.5 renders next to the new `guidance_based` label.
4. **"At least two independent ways"** to receive a warning is nowhere in the sources — my synthesis, on
   a scoring item, so an invented requirement was moving a real number.
5. **The no-safe-room item stated the manufactured-home reason unconditionally** on a pure reachability
   finding, against a corpus line saying nothing may tell a resident the app identified their home as
   manufactured.
6. **My no-numbers guard was weaker than the two docs I wrote about it.** It omitted `why` — where the
   figures actually are — excluded every engine-generated item, and cannot see a spelled-out number.
   Widened, and both doc sentences corrected to state the real scope.

**Two claims I checked and did not accept.** It reported both `usgs-earthquake` callers clean and
recommended deleting the source; `DrillInstructions.swift:74` still cites it, so deleting it would break
that citation — only the exception's owner text is stale. And it reported uncommitted hunks in the diff:
that was a mid-session snapshot, and the tree was clean when the gate ran.

The pattern across findings 2, 4 and 5 is the same as the four I caught myself: I wrote plausible safety
text and attached a real source id to it. **Three of my six mistakes this session were in the direction
of making the guidance sound more definite than the source is** — "two independent channels", "mobile
homes are not safe" as this home's reason, a tornado lead time borrowed from a fire statistic. That is
worth naming, because it is not carelessness, it is the instinct to write good advice.

## Questions for teammates

- **@whoever takes S11.3** (owns `object_hazards.py`): **I edited two detail strings in your file** —
  the `topple` renter claim and the `water_heater_unsecured` mechanism — and `docs/object-hazard-spec.md`
  to match. Both were misattributions; the reason I did not leave them for you is in the auditor section
  above. `test_agent.py`'s citation and detail assertions moved with them. Nothing else in the hazard
  engine was touched, and the rest of the hazard QA is still yours. The new
  `test_no_deleted_corpus_claim_survives_anywhere_on_the_checklist` sweeps your engine's output too, so
  reintroducing any of the six banned phrases will go red.
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
2. S11.3 can start on hazard QA proper; the two attribution defects in its file are already closed.
3. The iOS suite still has not run since 2026-09-09. Nothing in this session touched app code beyond one
   optional Codable field, but the 615 is now older by one more session.
