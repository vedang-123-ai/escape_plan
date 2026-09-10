# Everything still to do

> **⛔ [`BLOCKERS.md`](BLOCKERS.md) is the board — read it first.** It carries everything
> blocking or unverified, ranked by critical path, and it is the file to update when you find
> something undone. **This file is the long-tail backlog**: the detail, the history, and the
> items that are real but not on the critical path. If the two ever disagree, `BLOCKERS.md`
> wins and this file is what needs fixing.
>
> [`../START-HERE.md`](../START-HERE.md) remains the long-form brief for the device pass.

_Last verified: 2026-09-08 on `main` (tracker reconciliation + config declutter, then the S7
scoping session) — three suites re-run and green: backend **348** not-live (13 live-deselected),
EditorCore **270**, corpus valid (**17** sources, **8** files). **iOS was NOT run** this session;
the last recorded run is 598/0/8 and predates the Swift in this tree, so it is NOT a current
number. Disk is no longer the constraint it was (39% used, 19 GB free), so the simulator can be
run again — but the owner's standing "ask first" restriction still applies. Also verified against
the live deployment: the Render service is on schema 2.0 and serves all nine routes.
`backend/.venv` now EXISTS (created 2026-09-08 from `requirements.txt`, python3.13) — bare
`python3` on this machine is 3.9 and cannot run the suite, so use `backend/.venv/bin/python`.
The S7 object-hazard arc was scoped and approved the same day — see the S7 section below,
`docs/object-hazard-spec.md`, and `docs/decisions.md` (2026-09-08).
See `notes/2026-09-08-tracker-reconciliation.md` and `notes/2026-09-08-s7-scoping.md`._

_Prior stamp, 2026-09-06 on `main` (S6.1–S6.3 review + reconciliation) — backend **344** not-live,
EditorCore **270**, corpus valid. The orchestrator's S6.1/S6.2/S6.3 landed on `origin/main`
unreviewed; two review agents were run against it and **three blocking defects were found and
fixed**. See `notes/2026-09-06-s6-1-merge.md`._

_Prior stamp, 2026-08-05 on `main` (camera interaction-feel pass) — full gate re-run and
**fully green**: corpus valid (11 sources, 6 files), backend **295** not-live (13
live-deselected), EditorCore **270** (was 261), iOS **586 passed / 0 failed / 8 skipped**
(was 563/1/8). The known `EntryPointUITests` tab-bar flake did not reproduce this run. See
`notes/2026-08-05-camera-feel.md`._

_Prior stamp, 2026-08-05 on `main` (UI/UX pass) — full gate re-run and green: backend **264**
not-live (13 live-deselected), EditorCore **192**, iOS **337** (was 323 — +8 BackendFailure,
+6 PeopleLayer), corpus valid (11 sources, 6 files). The deployed backend answered `/health` in
0.6 s (warm, not a cold start) via `scripts/demo-preflight.py`; `/explain` still 502s on credit.
See `notes/2026-08-05-uiux-pass.md`._

_Prior stamp, 2026-08-04 on `main` (full-app test sweep) — **every suite re-run this session
and green**: backend **264** not-live (13 live-deselected), EditorCore **186**, iOS **320**
(315 unit + UI, 8 skipped), corpus valid. Endpoints exercised by hand too: `/routes` on all
three fixtures (16/16 rooms routed), `/convert` on two synthetic scans, `/score` on all three.
See `notes/2026-08-04-full-app-test-sweep.md`._

_**AI is entirely down — the Anthropic account is out of credits.** One `/explain` succeeded
this session (200, 26.0s, good grounded output) and the balance ran out mid-sweep. `/explain`,
`/analyze`, `/chat` and every `-m live` suite are blocked on a top-up, not on code. Read the
first blocker section below before planning any AI work or filming._

_**Do not trust a single iOS run.** Three identical back-to-back full runs went pass / fail
(10 failures) / pass. Every failure was `Simulator device failed to launch … Busy
("Application failed preflight checks")` — environmental, kills both test targets, says nothing
about the code. Also: `xcodebuild`'s console prints `Executed 16 tests` because the unit target
runs under Swift Testing; the real count is in the result bundle
(`xcrun xcresulttool get test-results summary --path <bundle>` → 320)._

_Prior stamp, 2026-08-02 on `main` (check_obstructions agent tool) — backend 258 not-live pass,
corpus valid. EditorCore and iOS were not re-run that session._

_Prior stamp, 2026-07-24 on `main` (route-fix + live-AI session) — backend 248 not-live + 12
live pass, editorcore 186, corpus valid, iOS FULL suite (unit + UI) TEST SUCCEEDED. Escape
routes confirmed rendering on the simulator after the stale-@State fix. (The 2026-07-30 merge
moved backend to 252 without refreshing this table.)_

This is the single source of truth for open work. It replaces the old `board.md` +
`checklist.md`, which had drifted into contradicting each other.

**Rules**

- Only things **not yet done** live here. Finished work is in git and in `notes/`.
- Check a box only after you verified it yourself. "The code exists" is not verification.
- Every line names the concrete next action. If you can't name one, it isn't ready to be here.
- The `(S3.2)` tag links back to `docs/playbook/S3-2.md` for the original spec.

**Last recorded green per suite** (dates differ — the newest full-gate run per row, not one
snapshot; if you change code, re-run `/verify`):

| Suite | Count | Command |
|---|---|---|
| Backend pytest | 348 pass, 13 live-deselected (2026-09-08) | `backend/.venv/bin/python -m pytest backend/tests/ -m "not live"` |
| Backend live suites | 12 pass (2026-07-24); the 13th (`agent_bungalow_blocked`) has never run. **Blocked on credits as of 2026-08-04, not just on a key** | `set -a; . ./.env; set +a; python3 -m pytest backend/tests/ -m "live"` (latency bounds can flake on API variance) |
| EditorCore (SwiftPM) | 270 pass (2026-09-08; the 261 previously listed here contradicted the 2026-08-05 stamp's own 270 — table was stale) | `swift test --package-path tools/editorcore` |
| iOS (unit + UI) | 563 pass, 8 skipped (2026-08-05 — **predates the S6 Swift; NOT current**) — launch flake still real, re-run before believing a red | `xcodebuild test -scheme escape_plan …` (owner go-ahead required on this machine) |
| Corpus | 17 sources, 8 files (2026-09-08) | `python3 backend/corpus/validate.py` |

**Heads-up on `python3`:** machine-dependent, check before assuming. On the machine used
2026-09-08, system `python3` is 3.9 (cannot import pydantic) and **`backend/.venv` now exists**
(created that session from `backend/requirements.txt`, python3.13) — use
`backend/.venv/bin/python`. An earlier machine (2026-08-04) had a 3.13.5 system python and no
venv; both states have been true on "this" machine at different times.

---

## APPROVED ARC — object hazard detection (S7.1–S7.10, approved 2026-09-08)

Scoped, vetted and approved 2026-09-08; 4 sessions are done. Rule book:
[`../object-hazard-spec.md`](../object-hazard-spec.md) (authoritative over session files);
charter: [`../playbook/07-object-hazard-intro.md`](../playbook/07-object-hazard-intro.md); one
paste-ready prompt per session in `../playbook/S7-1.md` … `S7-10.md`; orchestration brief in
`../playbook/S7-EXECUTE.md`. Scope-lock reversal ("furniture detection" was out of scope until
this approval) recorded in `docs/decisions.md` (2026-09-08) with the lockstep edits to
`CLAUDE.md`, `.claude/rules/global/conventions.md` and `playbook/01-product-spec.md`.

**What it is:** RoomPlan's already-detected objects (currently thrown away between
`apple-raw.json` and `/convert`) plus a guided manual "hazard hunt" feed a deterministic
object-hazard engine: topple arcs vs. beds, overhead loads over sleepers, heater clearances,
blocked egress windows, unstrapped water heaters — every finding carrying a number, a
threshold, a citation and an action. No custom ML (explicitly out of scope); optional Vision
photo-assist sessions at the tail suggest tags the user must confirm. ~45h core (S7.1–S7.7)
+ ~16h stretch/optional. Cut order: S7.10 → S7.9 → S7.8 → S7.7's visual half; never cut
S7.1–S7.5.

- [x] S7.1 — schema 2.1 (`elevation_m`, `mounted`, categories bookcase/tv/water_heater/heat_source). **DONE 2026-09-09.** Lockstep across JSON Schema, pydantic, Swift Codable, the bundled fixture copies and `ai/builder.py`'s tool schema; `schema-contract-guardian` run and its findings acted on. Backend **360** not-live, EditorCore **273**, corpus valid, all six fixtures pass `app.validate`. **S7.3/S7.4/S7.6 are unblocked.** Two acceptance items could not be closed on this machine (simulator-gated) and are now **STEP 0 of S7.2** — see `docs/playbook/S7-2.md` and `BLOCKERS.md` §3. See `notes/2026-09-09-s7-1-schema-2-1.md`.
  - Also resolved here: the logged "`schema_version` breadth disagrees three ways". Ruling — JSON Schema lists every version the migrators accept (it validates documents on disk), pydantic is `Literal` current-only (it validates the post-migration in-memory model), Swift stays a bare `String` (it must read the old stamp before it can migrate it). Three breadths, one reason each; documented in `decisions.md`.
- [x] S7.2 — corpus: heating/electrical fire sources + `object_hazard_thresholds.json`. Blocks S7.4. DONE 2026-09-09. 23 sources, 9 files. NFPA/USFA URLs verified and stamped.
- [x] S7.3 — scan objects through the pipeline (RawScanExport v3, RPObject parsing, category map, elevation). Needs S7.1. DONE 2026-09-09. Unblocks S7.8.
- [x] S7.4 — the object-hazard engine (`routing/object_hazards.py` — `hazard.py` is TAKEN; R4 widens `obstructions.py`). Needs S7.1+S7.2. DONE 2026-09-09. All rules implemented and tests pass. Unblocks S7.5 and S7.8.
- [x] S7.5 — surfacing: checklist (`hazard.<rule>.<obj_id>`, category `mitigation`, supersedes `mitigation.secure.*` per object), score-cap verification, agent tool `check_object_hazards`. Needs S7.4. DONE 2026-09-09. **S7.7 is now unblocked.**
- [x] S7.6 — editor: secured/elevation/mounted controls + the guided hazard hunt (zero network). Needs S7.1. DONE 2026-09-09. `HazardHuntView.swift` added, `EditAction` extended with `setObjectSecured`/`setObjectMounted`/`setObjectElevation`, `HouseScreen` inspector updated. iOS suite: 598 passed, 0 failed, 8 skipped (iPhone 17 Pro / iOS 26.5). See `notes/2026-09-09-s7-6-hazard-hunt.md`.
- [ ] S7.7 — 3D emphasis + the device pass (real scan with objects; frame-time number). Needs S7.4+S7.5+S7.6 (all done). Next action: 3D hazard highlighting on the dollhouse (non-device half), then human with an iPhone for the device pass; extends `field-test-lidar.md`.
  - [ ] Real-scan object verification: confirm objects (furniture, doors, windows) are accurately captured in the real scan export.
- [ ] S7.8 — STRETCH: exit-path re-check (partial re-scan diff, "something new", never a guessed category). Needs S7.3+S7.4. First core-adjacent cut after the Vision pair.
- [ ] S7.9 — OPTIONAL: Vision photo-assist feasibility spike + capture. Needs S7.6 (done). A documented NO-GO that cuts S7.10 is a SUCCESS outcome.
- [ ] S7.10 — OPTIONAL: Vision suggestions → editor flow. Needs S7.9. First to cut.

## ~~APPROVED PIVOT — the readiness arc (S6.1–S6.9, approved 2026-09-05)~~ CODE LANDED — reconciled 2026-09-08

Scoped 2026-09-05; **all nine sessions' code is now on `main`** (S6.4–S6.9 arrived via the
2026-09-08 merge of `origin/main`; commits `7a3d1a5`…`df9d0a2` incl. the Wave-2 UI redesign
merge `732a5c8`). Full brief: [`../playbook/06-pivot-intro.md`](../playbook/06-pivot-intro.md);
one paste-ready long-horizon prompt per feature in `../playbook/S6-1.md` … `S6-9.md`.
**Reconciliation basis (2026-09-08): code verified present + three cheap suites green on the
merged tree — NOT a re-walk of every session's acceptance criteria.** The S6.1–S6.3 review
items below remain open where unchecked.

**What it is:** the app stops being "we compute your fire escape route" (a route an able-bodied
owner already knows) and becomes a readiness system — AI-narrated household interview → a
deterministic, corpus-cited, hazard-tagged checklist that becomes the Home tab → fire **plus
earthquake and severe weather**, each with a genuinely different routing objective → composite
score → opt-in anonymous responder snapshot. The finding the engine already produces for a
`mobility_limited` upstairs sleeper (`no_viable_route`) is the product; the animated path is not.

**APPROVED 2026-09-05 — this is sanctioned work now, not a proposal.** The scope locks in
`CLAUDE.md`, `.claude/rules/global/conventions.md` and `playbook/01-product-spec.md` were updated to
match (fire + earthquake + severe weather). See `docs/decisions.md` (2026-09-05, approval).
_(`rules/global/` was deleted 2026-09-08 and folded into `CLAUDE.md` — the lock now lives there
only. See decisions.md, 2026-09-08.)_
It remains a much larger scope than the open UI/UX handoff and **the Oct 24 deadline has not
moved** — 56h estimated across nine sessions.

- [x] ~~**Decide: pivot or finish the current app.**~~ Answered 2026-09-05: **pivot.**
- [x] S6.1 — schema 2.0 (household facts, sensory tags, safety points, `secured`, `last_scanned`). Blocks S6.3/S6.4/S6.5. Completed 2026-09-05.
- [x] S6.2 — corpus: earthquake + severe weather, fully sourced. Done 2026-09-05. Unblocks S6.3/S6.4.
- [x] S6.3 — peril engine (earthquake cover search, tornado safe-room search). Needs S6.1+S6.2. Completed 2026-09-05.

### Review of the orchestrator's S6.1–S6.3 (2026-09-06) — 3 blocking defects fixed, rest filed

The arc landed on `origin/main` with no review. Under the 2026-09-06 policy (agent review, no
human sign-off) it was audited by `grounding-auditor` and `schema-contract-guardian`. **Fixed
this session** — tornado "leave the house" defect, the grounding desync, the uncited shelter
claim, two mis-citations, `household` nullability, `profile.tags` required, and the migrator's
lexical version compare. **Still open:**

- [ ] **`/build` serializes `confidence: null` and `egress: null`, which the schema rejects.**
      Pre-existing and confirmed by the guardian: 2.0 made `meta.last_scanned` and
      `household.tenure` nullable but left `confidence` and `opening.egress` as bare types.
      `/convert` sets `response_model_exclude_none=True` and is masked; **`/build` does not and
      is exposed** — `BuildResult.home` emits both. Next action: either declare both nullable or
      set `response_model_exclude_none=True` on `/build`, then widen the serialize test to the
      whole document.
- [ ] **FEMA over-claim in the new corpus.** `severe-weather-tornado.md:18` says a basement
      "provides near-absolute protection". That is FEMA P-361/P-320 language reserved for safe
      rooms **built to FEMA criteria**, not a property of basements generally. Next action: split
      the sentence — near-absolute for the FEMA-rated safe room, "substantially safer" for an
      ordinary basement.
- [ ] **Dead URL carrying a fresh retrieved date.** `sources.json:129` has
      `fema.gov/plan/prevent/saferoom` (retired years ago) stamped `"retrieved": "2026-09-05"`.
      A retrieved date asserts somebody fetched it — this is an originality claim a judge could
      check. Current path is `/emergency-managers/risk-management/safe-rooms`. Next action:
      re-verify all six new URLs resolve, then correct.
- [ ] **`shakeout-guidance` cite precision.** `sources.json:113` points at
      `earthquakecountry.org/step5/` (Drop, Cover, Hold On) but is cited for furniture securing,
      which is step 1.
- [ ] **`test_perils.py` tornado assertion is weak.** It asserts only
      `primary.exit_id != "d_front"`, which passes trivially now that `exit_id` holds a room id.
      The shelter actually chosen for all 7 twostory rooms is `r_hall1` — the room containing the
      front door. Next action: assert on `ext_openings == 0` or on room type, not a door id.
- [ ] **`exterior_edges` mixes int indices with `f"op_{id}"` strings**
      (`routing/perils/tornado.py:63-91`). If the `else` at :70 ever fires the same wall is
      counted twice, inflating `ext_walls` and corrupting the ranking. Zero hits on current
      fixtures; a live trap for scan-derived homes. Next action: use one key space.
- [ ] **`routing/perils/objective.py` is a stub** — four unused imports and a "we will put
      shared logic here if needed" comment. Delete or implement.
- [ ] **`RouteFinding` has no `citation` field**, so finding-level safety text is validated by
      nothing — which is exactly why the uncited shelter directive shipped green.
      `test_citation_resolution` only walks `ChecklistItem.source_citation`. Next action: add
      `citation: str | None` plus a test that imperative safety text in `detail` resolves.
- [ ] **Fixtures are thinly seeded compared to what S6.4/S6.6 were promised.** Only `twostory`
      has a household, **no** fixture has `meta.last_scanned`, and **no** profile carries
      `hearing_impaired`/`vision_impaired` — so two 2.0 additions have zero fixture coverage.
      The independent S6.1 branch (`my-s6-1-and-policy`) seeded both sides of every branch:
      apartment as renter + smoke alarm, twostory as owner + gas shutoff + panel, jagged with a
      `secured` wardrobe and a `hearing_impaired` profile, bungalow with a stale `last_scanned`.
      **Deliberately not merged** — S6.3/S6.4 tests are written against the current fixtures and
      changing them under unreviewed code risks breaking a green tree. Next action: whoever runs
      S6.4 decides which seeding it needs and does it once.
- [ ] **19 contract tests exist only on the `my-s6-1-and-policy` branch**, not on `main`:
      every safety-point/household/tenure/equipment invariant, the bundled-fixture drift guard,
      `test_safety_points_are_not_obstacles`, the two sensory-tag routing-neutrality tests, and
      all 8 of `SchemaV2ContractTests.swift`. Most port cleanly (their pydantic already enforces
      the invariants); a few depend on the fixture seeding above. Next action: port the
      seeding-independent ones.
- [x] **Three files still self-describe as v1.1** after the bump — fixed in S7.1 (2026-09-09):
      all three now say v2.1, as does `docs/schema-summary.md`, which had missed 2.0 entirely.
- [x] **`schema_version` breadth disagrees three ways** — RULED in S7.1 (2026-09-09). The three
      breadths are deliberate and each is documented at its definition; see the S7.1 line above
      and `decisions.md`. The observation that JSON Schema cannot tell a 1.1 document from a 2.1
      one stands and is inherent: every addition since 1.1 has been optional, so the stamp is the
      only signal — which is exactly why the migrators rewrite it.
- [ ] **`FloorObject.size_m` is unbounded `[Double]` in Swift** but exactly 2 elements in schema
      and pydantic — Swift accepts a 3-element size the other two reject. Pre-existing v1.1.

- [x] S6.4 — household facts → checklist rule table. Verified in the tree 2026-09-08: `household_items()` at `backend/app/scoring/checklist.py:618`, tenure/equipment branches, ids stable (`household.sleep_near_exit.<profile>` etc.). It extended `checklist.py` rather than forking it, as required.
- [x] S6.5 — household interview (iOS onboarding). Verified 2026-09-08: `escape_plan/Onboarding/OnboardingFlowView.swift` + `OnboardingState.swift` capture tenure and sensory tags and dispatch `.setHousehold(...)`. Zero network calls, as required.
- [x] S6.6 — checklist becomes the Home tab. Verified 2026-09-08: `HomeScreen.swift` renders the checklist natively (critical section, tiles, `ChecklistStateStore`) — one renderer, not two.
- [x] S6.7 — composite score across three perils. Merged in `732a5c8` (2026-09-07), which also fixed two real scoring bugs (`ChecklistItem.scoring` was ignored; `practice.drill_recent` was punitive). Worked examples updated in `docs/preparedness-score-weights.md`.

**All nine S6 sessions now have code in the tree.** What remains for the arc is verification,
not construction — the open review findings below and in [`BLOCKERS.md`](BLOCKERS.md) §3.
- [x] S6.8 — earthquake + severe-weather drill modes. Needs S6.3. Note: citation-coverage fixed (Triangle of Life).
- [x] S6.9 — responder snapshot (opt-in, anonymous, manual, no backend). Needs S6.1+S6.3. Note: fixed gaps for stale last_scanned handling and twostory.json testing.

**Locked decisions (interrogated 2026-09-05 — do not relitigate inside a session):** three perils
for real; deterministic rule table, AI interviews only; all hazards always on; HomeModel stays
source of truth with a time-based rescan nudge; one unified hazard-tagged list; checklist replaces
Home; local-only/no-accounts survives (sharing is a manual one-way export); safe room is
engine-computed with no override; one composite score with per-peril breakdown; fixed branching
wizard, not free chat; every question skippable, profile editable later; insurance and responder
stories are designed, **not** integrated.

**Prompt audit, 2026-09-05 (`ef0f03f`).** All 46 path references across the ten S6 files were
checked against the tree. Three would have broken a paste-ready session and are fixed: S6.8 named
`escape_plan/Drill/` (it is `DrillMode/`), S6.9 named `escape_plan/Screens/ShareSheet.swift` (it is
`Export/`), and S6.9 called for a `security-reviewer` agent that does not exist (the six real ones
live in `.claude/agents/quality/`; the built-in `/security-review` skill was meant). Every other
unresolved path is a file the sessions themselves create. Also added to S6.9: `escape_plan/Export/`
is already a complete PDF pipeline (`EscapePlanPDF`, `FloorPlanDrawing`, `PlanProjection`,
`PlanInk`, `PDFText`, `EscapePlanExporter`) and `RouteNarration` already narrates engine waypoints —
the snapshot re-targets them rather than building a second renderer, which the arc's own
"what already exists" table had missed.

Still open from that audit:

- [x] ~~**`CLAUDE.md` and the playbook contradict each other on scope.**~~ Resolved 2026-09-05 on
      approval. All five places that asserted the old lock were found by grep and updated in
      lockstep: `CLAUDE.md`, `.claude/rules/global/conventions.md` (both auto-loaded every session
      at the time; `rules/global/` was deleted 2026-09-08 and folded into `CLAUDE.md`),
      `playbook/01-product-spec.md` (two lines), and `06-pivot-intro.md`'s status line. The fifth,
      `docs/demo/script-v1.md`, is a content rewrite rather than a lock — see below.
- [ ] **`docs/demo/script-v1.md` now pitches a product that is not the plan.** It sells fire-only,
      its closing line offers "other disasters" as *future* work, and its truth-ledger row 17 cites
      the CLAUDE.md scope lock that just changed. Not rewritten here — the script is content, and
      rewriting it before the arc is built would be inventing a demo of software that does not
      exist. Next action: leave until enough of S6 has landed to film honestly, then rewrite
      against the shipped build (folds into the existing S5.1 tech-accuracy pass).
- [ ] **Decide what happens to the `START-HERE.md` UI/UX handoff.** It is still
      `handoff_status: active`, so every session still opens with "finish the camera feel and the
      device pass". That work is still real — S6.6 replaces the Home tab but does not touch the
      camera rig — yet the two now compete for the same weeks. Next action: owner decides whether
      the handoff pauses, closes, or interleaves (a defensible split: the device-feel items gate
      any filming regardless of perils, so they may still be first).
- [ ] **Dependency map vs. session headers disagree about S6.6.** `06-pivot-intro.md`'s map draws
      S6.3 → S6.6, but `S6-6.md`'s header lists prereqs as S6.4 + S6.5 only. S6.6 does render
      `no_viable_safe_room`, which only S6.3 produces, so S6.3 looks like a real prereq. Left
      unchanged deliberately — editing a prereq declaration either strands a session or makes one
      wait for nothing. Next action: whoever owns the arc confirms which is right and makes the two
      agree.

---

## ~~BLOCKER — escape routes do not render~~ FIXED 2026-07-24

Root cause: `HouseScreen`'s `onRebuild` closure read `@State routePlan` from a stale captured
View snapshot (always nil), and `updateUIView` rebuilds the scene empty on every render, so
routes were wiped as fast as they were drawn. Fixed by caching draw inputs + view state in the
`RouteOverlayHolder` class and redrawing from it in `onRebuild`. The explode slider had the
same latent bug (snapped to 0 on rebuild); after the 2026-07-30 merge that half is carried by
the UI branch's separate `SceneViewStateHolder`, and both boxes now coexist. **Confirmed rendering**
on the simulator (orange primary + blue secondary, all 7 primaries in "Everyone", exit glows).
Details: decisions.md 2026-07-24 (later) + `notes/2026-07-24-look-and-feel-*.md`.

**Re-confirmed on the merged build 2026-08-02** — the open "nobody has looked at the merge on a
simulator" item is now closed. Routes draw, and they survive a committed edit (the exact thing
the fix protects). Evidence: `docs/evidence/route-redraw-2026-08-02/`; regression guard:
`escape_planUITests/RouteRedrawAfterEditUITests` (env-gated, needs a local backend).

## 3D revamp (approved 2026-07-23 — spec/plan: `~/.claude/plans/i-want-you-to-tender-flask.md`)

**ALL SIX PHASES LANDED 2026-07-23** (A1–A3 unified free-camera HouseScreen; B1–B3 schema
v1.1 objects + obstacle-aware grid routing; C1–C2 LLM house builder + forced review gate).
Notes: `notes/2026-07-23-revamp-a1-camera-rig.md`, `-a2-unified-editing.md`,
`-a3-housescreen.md`, `-b-c-objects-routing-builder.md`. Remaining follow-ups:

- [ ] Device-acceptance pass on the whole revamp: unified HouseScreen gesture feel (orbit
      sensitivity, pinch anchor, dock height on small screens), object editing, plan-import
      flow + review gate, tour. Simulator + recording-driver verified; real-device feel and
      real-photo floor plans are the open items.
- [ ] Fixture-kit renderer (landed 2026-07-29, `notes/2026-07-29-fixture-kit-renderer.md`):
      include in the device-acceptance pass above — node count is ~3-4× the old builder and
      the editor rebuilds per commit; profile one edit-drag session on hardware. Next
      actions if custom assets land: register via `FixtureCatalog.shared.door =
      AssetFixture(named:)` at startup, then eyeball joins on all three schema fixtures.
- [x] ~~Live builder golden~~ — run 2026-07-24 with the key in `.env`; PASSES after removing
      the deprecated `temperature` param from `builder.py` (the model 400s on it). See
      decisions.md 2026-07-24 (later). (The 2026-07-29 branch still listed this as blocked on
      the key — it was closed on the other branch before the merge.)
- [x] ~~Surface `blocked_opening` in /score~~ — done 2026-07-24, and went further per Anish:
      `app/routing/obstructions.py` names WHICH object blocks (counterfactual attribution)
      and how far to move it (measured), surfaced in `RouteFinding.detail` + `object_ids`
      and as a `usfa-escape-plans`-cited checklist item. 10 tests.
- [x] ~~Give the S3.2 **agent** a `check_obstructions` tool~~ — done 2026-08-02. Optional
      `room_id` filter, returns the engine's fields verbatim including its `detail`
      sentence; prompt rule 1 now forbids estimating a move distance, rule 4 maps
      `blocks_opening`/`narrows_route` to severities. 6 deterministic tests (backend 248 →
      258). See decisions.md 2026-08-02. **The live case is unrun** — next item.
- [ ] Review the golden for `test_blocked_bungalow_agent_names_the_wardrobe`
      (`backend/tests/test_agent_live.py`, `-m live`). It has never executed: there is no
      `ANTHROPIC_API_KEY` on every machine — the `.env` in the stamp above is gitignored and
      machine-local, so a fresh clone does not inherit it. On the first machine with the key,
      run the live agent suite; the golden writes itself and `pytest.skip`s for review, then
      commit `backend/tests/golden/agent_bungalow_blocked.json`. (S3.2)

## Camera interaction feel (landed 2026-08-05)

Ten defects in how the 3D dollhouse handles orbit/pan/pinch — the scene rendered correctly, the
controls did not feel connected to the finger. Note: `notes/2026-08-05-camera-feel.md`.
Shipped: correct ortho-vs-perspective pan math, a pinch anchor resolved once instead of a
full-scene hit test per frame, one `simdTransform` write in place of `position` + `look(at:)`,
continuous rendering for the whole gesture, one shared `CameraGestureDriver` for both 3D hosts,
pan inertia, latching two-finger arbitration, and looser movement limits. Open:

- [ ] **Nothing here has been felt by a human.** Every change is reasoned and test-backed;
      "feel" is not a thing `xcodebuild` can report. Next action on a device, in this order:
      (1) hold a corner of the house under your thumb and pan — it must stay under the thumb, in
      both orientations; (2) pinch and confirm the point between your fingers does not crawl;
      (3) flick to orbit and confirm it coasts and eases rather than stopping dead; (4) pan to
      the edge and confirm the rubber band springs back visibly rather than snapping.
- [ ] **#10 frame-time profiling was NOT done — no target hardware.** MSAA 4X, camera SSAO and
      the route pulse shader are all still on during gestures. Per the brief's own instruction
      ("profile before tuning further") nothing was changed on guesswork, and dropping MSAA
      mid-gesture is a visible change to a scene the brief said not to alter. Next action:
      Instruments → Game Performance on the oldest supported device, orbiting a two-storey home
      with routes drawn. If frame time is the binding constraint, the levers are MSAA 4X → 2X
      and SSAO off for the duration of a gesture, both already isolated behind
      `CameraGestureDriver.onPhaseChange`.
- [ ] The tuning constants (#8/#9) are a **starting point, not an answer**: apron `0.6 ×`
      extent, distance `0.35…4.0 ×` extent, orbit `0.6 π` per view height, axis-lock sample
      20 pt. Tune by feel on device; the orbit rate and the axis-lock threshold interact.
- [ ] `RouteRedrawAfterEditUITests` detects the route by counting **orange** pixels
      (`r > 190, g 80–180, b < 90`). Routes have been blue since the 2026-08-05 colour pass, so
      that test can no longer pass. It is skipped unless `ROUTE_REDRAW=1`, so it does not gate
      CI — which is exactly why it will stay broken until someone needs it. Next action: retune
      the predicate to `DollhousePalette.routePrimary` (`#123FB0`).
- [ ] `UnifiedSceneView` (DrillScreen) and `EditorSceneView` (HouseScreen) now share
      `CameraGestureDriver`, but still duplicate their `shouldRecognizeSimultaneouslyWith`
      policy and their recognizer setup. Fold the recognizer installation into the driver too,
      so a third surface cannot be added with a fourth gesture model.

## Fire-origin simulation + accessibility (landed 2026-08-05, 8 parallel lanes)

Shipped this session: `backend/app/routing/hazard.py` + `POST /evacuate` (31 tests);
`Models/EvacuationPlayback.swift` + ignite UI + scrubber; colorblind-safe route encoding (cool
routes, warm hazard, real dashed geometry, numbered stops); a full accessibility pass over
sixteen screens; drill practice log + corpus-cited reminders + time-to-exit; the printable
per-floor PDF; and one failure classifier everywhere. Note:
`notes/2026-08-05-fire-origin-simulation.md`. Open follow-ups:

- [x] ~~**Deploy the new backend to Render.**~~ Verified 2026-09-08: the deployed service serves
      `/evacuate` (all nine routes present in its `/openapi.json`). Render's auto-deploy from
      `main` is working. **Not yet exercised with a payload** — that needs the bearer token, so it
      folds into the pre-filming preflight rather than standing as its own item. (S1.6)
- [x] ~~**Codex/renderer lane binding.**~~ Landed 2026-08-05 (see
      `notes/2026-08-05-evacuation-renderer-integration.md`). `HouseScreen.attach(_:)` now calls
      `controller.bindEvacuationPlayback(playback, …)`. `EvacuationPlaybackModel` stays the sole
      clock; the coordinator suspends the ordinary route overlay for the duration of a timeline
      and restores it on clear. Renderer issues surface in the simulation dock.
- [x] ~~**`EvacuationPalette.swift` duplicates `routeSecondary` as `#4A86D8`.**~~ Stale as
      written — verified 2026-08-05 that every colour in that file references `DollhousePalette`
      and no hex literal remains. `0x4A86D8` now appears nowhere in the tree.
- [ ] **Confirm the scene-rebuild gating on hardware.** `UnifiedSceneController.rebuildIfNeeded`
      now skips a rebuild when `(home, activeFloorId)` is unchanged, because `updateUIView` ran a
      full dollhouse rebuild on every frame of playback. Unit tests can't see this — it is a
      frame-rate and animation-continuity change. Next action: run a simulation on device and
      confirm figures move continuously instead of restarting, and that editing still redraws
      immediately after a commit. (`notes/2026-08-05-evacuation-renderer-integration.md`)
- [ ] Device-acceptance for everything above: ignite → playback on hardware, the scrubber's feel,
      Reduce Motion in the camera tour, VoiceOver end-to-end with a real screen reader (not just
      the label assertions), and the PDF printed on actual paper in greyscale. **None of this
      has been seen by a human on a device** — the whole session is simulator + unit tests.
- [ ] `AccentColor.colorset`'s light value is **4.45:1 on white** — passes as a fill, fails as
      text, which is why `Theme.accentText` exists as a workaround. Darkening the asset to
      `#0B7233` would let `accentText` be deleted. Deferred because the renderer reads
      `AccentColor` directly and the 3D consequence needs a device.
- [ ] `OnboardingState.LoadState.failed` still carries a `String`; the classified
      `BackendFailure` rides alongside as `analysisFailure`/`scoreFailure`. Retry is now gated
      correctly, but the payload should become the failure itself so the two cannot disagree.
- [ ] `RenderOrder` has no named band for route stop chips — they use `RenderOrder.badges - 1`.
      Promote to `RenderOrder.routeStops`.
- [ ] The evacuation timeline is deliberately **not** cached for offline use (unlike
      `RoutePlanCache`). Confirm that's still the right call once the feature has been demoed —
      a stale timeline is a picture of a fire that isn't happening, which is why it was skipped.

## BLOCKER — the Anthropic account is out of credits (found 2026-08-04)

Every AI feature is dead. `/explain`, `/analyze` and `/chat` fail with
`Your credit balance is too low to access the Anthropic API`. One `/explain` succeeded earlier
in the same session (200 in 26.0s, good grounded output), so this happened just now — the key
in `.env` is valid, the balance is not. The deterministic half (`/routes`, `/score`,
`/convert`) is completely unaffected, which is the architecture working as designed.

Re-confirmed still dry on 2026-08-05 via `python3 scripts/demo-preflight.py` (new — see below):
`/explain` → 502 `Your credit balance is too low`. The 502-vs-503 split shipped 2026-08-04 is
working, so the failure now names itself instead of hiding in a generic 500.

- [ ] **Top up the Anthropic account.** Blocks: the AI half of the demo, the never-executed
      `agent_bungalow_blocked` live golden, all 13 `-m live` tests, and any filming that shows
      the assistant. Nothing else on this list is closer to the critical path.
- [x] ~~AI API errors surfaced as a bare `500 Internal Server Error`~~ — fixed 2026-08-04.
      Each AI module only guarded the *missing-key* case; the `client.messages.create` calls
      were unguarded, so a dry account / rate limit / outage escaped as a 500 with nothing the
      app could show. One app-level `@app.exception_handler(anthropic.APIError)` now returns
      **502** (operator must act: no credit, bad key) or **503** (retryable: rate limit,
      overload, network), with the API's own sentence as `detail`. Verified against the real
      dry account. 6 tests (backend 258 → 264). See decisions.md 2026-08-04.
- [x] ~~Decide what the **app** shows for the new 502 vs 503~~ — done 2026-08-05.
      `Networking/BackendFailure.swift` is now the one classifier; it replaced six disagreeing
      `catch` ladders. 502 → "AI features are unavailable right now" plus what still works, and
      **no Retry button** (retrying a dry account cannot help); 503 → busy, with Retry.
      `BackendFailureBanner` is the single notice component. 8 tests. (S1.6/S4.4)

## Blocked on a real API key

2026-07-23 (Lane C): a real key was used locally — the entire live battery below was run and
hand-reviewed; goldens are committed in `backend/tests/golden/`. What remains here is only
what a dev machine cannot close.

- [x] ~~Key not persisted anywhere locally~~ — Anish placed it in repo-root `.env`
      (gitignored) on 2026-07-24; live suites and local AI now work. (Deployed Render backend
      still needs its own dashboard env var — next item.)
- [ ] Set `ANTHROPIC_API_KEY` in the Render dashboard so the deployed backend's AI endpoints
      work at all. Until this happens `/explain`, `/analyze`, and `/chat` 502 in production.
      Exact steps: dashboard → `escape-plan-backend` service → Environment → add
      `ANTHROPIC_API_KEY` → save (auto-redeploys). Then verify: `/health` 200, one
      token-authed `/explain` on a fixture returns 200 with resolving citations. (S1.6)
- [ ] **p95 `/explain` < 6s is UNMET — DEFERRED 2026-07-24**, not resolved. Anish's call: the
      submission is an edited video, so a slow call can be cut around; revisit only if the
      app is ever judged live. The criterion stays formally unmet. Original measurement — measured 2026-07-23 on
      claude-sonnet-5, cache hits confirmed on every request: warm mean 26.3s, p95 30.2s
      (haiku-4-5 comparison ~18.5s). Output-bound (~2k output tokens/whole-home explanation),
      so caching can't fix it. Options: terser output, per-room explain calls, streaming UX,
      faster model, or revise the target. See decisions.md 2026-07-23. (S3.1)
- [x] ~~Garbled-generation glitch: decide retry vs tolerate~~ — Anish chose **tolerate +
      document**, 2026-07-24. See decisions.md. No code; revisit only if it recurs more often.

## ~~Needs real LiDAR hardware~~ — FIELD TRIP DONE 2026-09-08, IT WORKED

**First attempt, and it worked.** Scanned a friend's house: RoomPlan mapped it correctly, the
conversion held, and the routes animated well on the result. This was the single largest
unknown in the project — an untested hardware dependency on the critical path — and it is now
closed. The remaining lines below are **optional polish, not blockers**: nothing here gates the
demo any more.

_Historical framing, kept because the procedure is still the right one if a second trip happens:
the simulator has no LiDAR, so none of this could be closed from a dev machine. The scan entry
point and the `/convert` upload path were wired 2026-07-22._

**Everything in this section is one device trip.** The procedure — hardware gate, pre-flight,
capture technique, triage loop, symptom→cause table, and which acceptance line each step
closes — is written up in [`field-test-lidar.md`](field-test-lidar.md) (2026-08-05). Run
`python3 backend/scripts/triage_scan.py <raw.roomplan.json>` on each export before touching
any code: it checks the converter's _assumed_ format assumptions (transform majorness first)
rather than just whether conversion succeeded, because the worst failure mode converts
cleanly and silently produces bounding boxes.

- [x] ~~Scan a real 2–3 room space; confirm the raw JSON export has walls/doors/windows.~~
      Done 2026-09-08 — a friend's house, mapped correctly on the first attempt. (S1.4)
- [x] ~~Real scan → `/convert` → valid HomeModel that renders.~~ Done 2026-09-08 — the
      conversion held and the routes animated well on the result. **Not separately confirmed:
      the ≥1 exterior door + ≥1 window mapping assertion; check it against the export when one
      is committed.** (S1.5)
- [ ] Scan the same space twice in a row without crashing. Not attempted on the trip. (S1.4)
- [ ] Commit one clean and one messy real export to `schema/fixtures/scans/`. The trip proved
      the path works; capturing the artifacts is what is still open, and everything in the
      converter section below is waiting on it. (S1.4)
- [ ] Messy real scan → valid model with low-confidence flags and no crash. (S1.5)
- [ ] Confirm conversion is idempotent on a real export. (S1.5)
- [ ] Promote the assumed-format risks in `backend/app/convert/README.md` into
      `decisions.md` once a real export shows which assumptions held. (S1.5)
- [ ] Fix a misplaced door on a **real converted scan** in under 2 min, and confirm flagged
      items appear. The equivalent was observed on the twostory fixture; the real-scan half
      is open. (S2.2)
- [ ] Full golden path on one real home without touching Xcode. (S4.1)

## Needs a physical device (no LiDAR required)

- [ ] All three fixtures render legibly at 60fps on-device. Observed working on simulator;
      the frame-rate claim needs real hardware. (S1.3)
- [ ] Floor toggling on-device — chips AND tapping a ghosted floor in the 3D view, with the
      0.35 s focus glide. (The exploded view this line used to name was REMOVED in the
      2026-08-05 White Model overhaul; ghost-floor stacking replaced it.) (S1.3)
- [ ] `jagged` fixture on-device: activate the basement, confirm the two floors above ghost,
      all three slab outlines stay legible at once, and there is no z-fighting or murk. This
      is the stacking acceptance model and it has only been verified in the simulator.
      (White Model overhaul, `notes/2026-08-05-white-model-dollhouse.md`)
- [ ] Build the bungalow shape by hand on-device in under 5 min from an empty model, and
      confirm drags feel smooth. (S2.1)
- [ ] Confirm no gesture can produce an invalid model. (S2.1)
- [ ] Kill and relaunch the app: everything persists, two saved homes coexist. (S2.4)
- [ ] Confirm chat conversation survives background/foreground. (S3.3)
- [ ] Kill the backend mid-flow and confirm the app degrades gracefully. Every failure state
      exists in code and is unit-tested; this is the live pass. (S4.1)
- [ ] Complete a drill for two different profiles (twostory, Grandpa + Maya). The entry point
      is now wired — Home tab → swipe a home → "Drill". (S4.2)
- [ ] Confirm practiced-state persists and moves the preparedness score across a relaunch. (S4.2)

## Claude Design implementation (2026-09-07 — restyle landed, uncommitted)

Design project `66734cd4-4e07-4cf5-a116-5ded7e6dec0c`, exported to `docs/design/claude-design-export/`.
Home, Assistant, Settings, Onboarding, Score and the House dock now follow it via
`Screens/DesignKit.swift`; a **Beta** tab (leftmost) hosts the old home library. Session note:
`notes/2026-09-07-claude-design-implementation.md`; deviations: decisions.md 2026-09-07.

- [x] ~~**Redeploy the Render backend from `main`.**~~ **Already current — verified 2026-09-08.**
      Its `/openapi.json` reports `schema_version const "2.0"`, a `Household` schema, and `peril`
      on `RoutesRequest`; local `main` and `origin/main` are identical. The 2026-09-07 "still
      pre-2.0, `/score` 422s" diagnosis was true of a *local* uvicorn started before the schema
      commits, not of Render. **Note the trap that caused it:** `/health` reports `v1.0`, which is
      a hardcoded FastAPI `app.version` (`backend/app/main.py:44`) and says nothing about the
      deployed schema. Probe `/openapi.json` instead. Cold start on the free tier is still real
      (~30 s) — warm it before filming.
- [ ] Decide whether the Beta tab ships in Release. Visible in all configurations today (owner's
      request). Next action: owner call; `#if DEBUG` around the tab item in `ContentView` if not.
- [x] ~~Collapsing House model card (design: 400pt → 190pt sticky on scroll)~~ — done later the
      same day via `onScrollGeometryChange` (decisions.md 2026-09-07). Verify feel on device:
      SceneKit resizes per scroll frame; check for jank on hardware.
- [ ] **Confirm the Assistant composer rides the keyboard on a device.** It now sits in the list's
      bottom safe-area inset (the canonical placement) but the simulator session would not show
      the on-screen keyboard. Next action: open Assistant on the phone, tap the field, confirm the
      capsule sits on the keyboard's top edge and the list scrolls behind it.
- [ ] **Feel the haptics on hardware.** Every button clicks on press-down; the gauge ratchets 25
      notches. If it reads as too busy, the single knob is `Haptics.press()` (soft → nothing) and
      `HapticSweep.tick` intensity. Next action: one pass over Home, House dock, Beta swipes.
- [ ] House title-row Export / Edit pills from the design. Skipped; both live in the toolbar menu.
- [ ] `DSPill` person picker on House. Kept the native `Picker` to preserve `plan.profile.picker`
      accessibility identifiers. Next action: only with a matching UI-test update.
- [ ] Re-run the **UI** tests (`escape_planUITests`) after the restyle. Unit tests are the gate
      being run in-session; the UI suite is slow and keys on identifiers that were preserved but
      not re-verified end-to-end.

## iOS — real code gaps

- [ ] **A unit test writes a demo home into the app's real `Documents/Homes`.** Every
      `-only-testing:escape_planTests` run on the simulator left a new `*.homeplan.json` in the
      app container (17:39 on 2026-09-07, matching the suite's start time) — the test host shares
      the app's sandbox, so a test that calls the onboarding seed against the default
      `HomeDocumentStore()` pollutes the tester's library. Next action: point that test at a
      temporary directory store — it is `escape_planTests/OnboardingTests.swift:150`
      (`state.seedIfNeeded()` on a default `OnboardingState`).
- [ ] **Onboarding seeds a new "Demo Home (scanned)" on every run**, not only into an empty
      library. `OnboardingState.seedIfNeeded()` fires from "Get started"; each re-run of the
      interview (flag reset, fresh install over an iCloud-restored library) adds a duplicate.
      Seen 2026-09-07: two extra demo homes after one verification pass. Next action: make the
      seed conditional on the library being empty, or reuse an existing demo home by a stable id.

_2026-07-24: three closed. The three demo homes now seed on first launch
(`FixtureSeeder.seedStarterHomes`) — nothing created them before, which is why the screenshot
driver silently skipped the profile-switch shot. The House tab got its visual pass (dark
stage backdrop, plate-backed legible labels, dock 240→200 pt). The stale "Plan tab" copy in
the assistant banner + onboarding is now "House tab"._

_The four 2026-07-22 editor bugs (HomeModelPersisting unconformed, stale toolbar after
tap-selection, second-tap redo, "unwired" bridge) are fixed and verified on `lane/editor` —
see `notes/2026-07-23-lane-a-editor-completion.md`. Stairs on a hand-built two-story home
verified in the recorded manual-build run. The old "Render URL is not the app's default"
item is closed by S4.4 Lane B: `APIClient` now defaults to the deployed Render URL._

- [x] `setOpeningWidth` exists in the reducer with tests but has **no UI entry point** — add a
      width control (stepper/slider) to the opening inspector in `HouseScreen` (EditorScreen
      was merged into it in revamp A3). (Lane A). **Closed in S7.6 via `HouseScreen` inspector stepper.**
- [ ] The House *tab*'s standalone `HouseScreen()` has no `HomeLibrary`, so the
      delete-under-editor seam only protects the HomeScreen→Editor push path. Cross-tab
      delete while the House tab holds the same home is still unguarded — share one library
      instance (or an app-level environment object) if that matters. (Lane A)
- [x] ~~Spec §10-12 app chrome pass~~ — done 2026-08-05. `Screens/Theme.swift` is the
      semantic scale (accent / caution / warning / supporting + a type scale). The substance
      was not "apply the accent": it was that **seven screens used `.orange` for warnings**, so
      route-orange and warning-orange appeared in the same product. Chrome now contains no
      route orange at all; advisories use a dark amber that cannot be mistaken for a lit route.
      `Theme.routeInk`/`exitInk` exist only for legends that label an actual route or exit.
- [x] ~~Live 3D thumbnails in the homes list~~ — done 2026-08-05. `Renderer/HomeThumbnail.swift`
      renders offscreen via `SCNRenderer`; `HomeThumbnailView` caches by home id + modified
      date. Shadows and SSAO are off for tiles — at ~74×54 pt the shadow map samples below its
      own texel density and speckles every wall face.
- [x] ~~Spec §11 app icon redesign~~ — done 2026-08-05. `scripts/make_app_icon.swift` regenerates
      the light/dark/tinted trio: white house in section, orange route, green exit pad.
- [x] ~~"People" layer~~ — done 2026-08-05, **with a deliberate divergence**: the handoff asked
      for one route colour per person; that is rejected. Four saturated hues is the exact
      problem the White Model overhaul removed, and route orange must stay the only hot colour.
      Instead `Renderer/PeopleLayer.swift` + `Fixtures/PersonFixture.swift` stand a white figure
      with a name pill in each profile's bedroom, and the **selected** person's figure takes the
      accent green. 6 tests. See decisions.md 2026-08-05.
- [ ] Tap a figure in the 3D view to select that person (`PeopleLayer.profileID(forHit:)` exists
      and is tested; the picker is currently the only way in). Needs an `onPersonTapped` hook in
      `UnifiedSceneController` alongside `onFloorTapped`. (White Model overhaul)
- [ ] Per-profile routes fetched together, so "Everyone" can show whose route is whose without
      re-fetching on each pick. Needs `/routes` for every profile at once — an `APIClient+Routes`
      change, not a rendering one. (S3.4)
      Brief + prototype: Claude Design project `344e3e53-37d2-4471-831c-aa50067e9d55`.
- [x] ~~Selecting an opening or stairs draws no marker in the 3D view~~ — done 2026-08-05.
      `highlightPlacement` replaces `highlightCenter`: openings get an upright ring standing in
      the host wall's plane at the opening's mid-height (derived from the parametric wall
      segment, so it follows a dragged wall), stairs get a floor ring on their footprint.
- [x] ~~Custom launch screen~~ — done 2026-08-05 via `INFOPLIST_KEY_UILaunchScreen_BackgroundColor`
      + a `LaunchBackground` colorset (light/dark). No logo on purpose — per Apple's HIG a launch
      screen should look like the app's first screen, not a splash; matching the background makes
      launch feel instant instead of like a branding interstitial. (S4.4)
- [ ] Real-device check of the renderer: 60fps on all FOUR fixtures (bungalow, apartment,
      twostory, jagged) on a physical phone, and haptics feel (simulator can't verify either).
      The White Model overhaul made walls opaque and shadow-casting and turned on SSAO — both
      cost fill rate, so this number genuinely needs re-measuring, not just re-asserting.
      (S4.4 / White Model overhaul)
- [ ] On-device check of orthographic framing specifically. `orthographicScale` is a
      half-HEIGHT, so portrait aspect correction is the difference between a framed house and
      one cropped at both sides — and it is invisible on a square-ish simulator window.
      (White Model overhaul)
- [ ] Camera feel on hardware: turntable axis lock, release inertia, pan rubber-band spring,
      double-tap zoom, and the recenter chip's appear/disappear threshold. All are tuned by
      numbers that only a real finger can judge. (White Model overhaul)
- [ ] Drop the real shared bearer token into `escape_plan/BackendConfig.local.json`
      (`{"bearer_token": "..."}`, gitignored) on the build machine before any demo/device
      build — without it a fresh install reaches the Render URL but gets 401s until the
      token is typed in Settings. Mechanism + decision: decisions.md 2026-07-23. (S4.4)
      **Confirmed missing on this machine 2026-08-05** by `scripts/demo-preflight.py`.
- [ ] Run `python3 scripts/demo-preflight.py` immediately before filming (new 2026-08-05).
      It checks, against the deployed backend and in the app's own terms: the bearer token
      file, `/health` (and whether Render's free tier was asleep — a ~50s cold start reads on
      camera as a broken app), `/routes` + `/score`, and `/explain`, which is the check that
      catches a dry Anthropic account or a missing Render env var. Exit 0 = ready to film.
      Baseline run 2026-08-05: `/health` 0.6s warm, token file absent, credits still dry.

## Client/server contract (added 2026-08-02)

- [x] ~~Score screen dead on apartment + twostory~~ — fixed 2026-08-02. Backend emitted
      `category: "egress"` (R310 work, 2026-07-27); Swift's `ChecklistCategory` had no case,
      and a throwing enum failed the whole `ScoreBreakdown`. Also fixed the whitelist behind
      it (`ScoreScreen.categoryOrder`) that would have made the fix look successful while
      still rendering nothing. Verified by 315 unit tests (a decode test using the real
      `egress` category + a whitelist-exhaustiveness test), and by curl against the backend
      confirming which categories each fixture emits. **Not yet seen on screen** — next item.
- [x] ~~Screenshot the fixed Score screen~~ — **done 2026-08-04, TEST SUCCEEDED.** Evidence:
      `docs/evidence/score-screen-2026-08-04/` (twostory, 75/100, all five components
      rendered, no decode-failure state). Disk was a real factor in the earlier attempts, but
      the test *also* asserted `navigationBars["Score"]` while `ScoreScreen` sets
      `.navigationTitle(breakdown?.home_name ?? "Score")` — "Score" is the **loading** title,
      so the assertion failed on exactly the runs that worked, and would have failed forever.
      Now waits on the "How it's scored" header. See decisions.md 2026-08-04. (S3.5)
- [x] ~~Enum tolerance sweep~~ — done 2026-08-02, all ten enums checked. `FindingKind`,
      `WaypointKind`, `Severity` made tolerant; the six schema enums left strict on purpose
      (they round-trip user data — see decisions.md). iOS unit suite 309 → 315.
- [x] ~~**Surface `narrows_route` as a RouteFinding**~~ — done 2026-08-25. The engine only
      ran the obstruction analysis when something was already fully blocked, and a narrowing
      is by definition NOT blocked, so the finding was computed and thrown away on every
      request. Gate widened to "the home has furniture"; `narrows_route` now emitted,
      decoded, styled ("Tight squeeze"), narrated, and given a checklist row. New fixture
      `schema/fixtures/bungalow-narrow.json`. Backend 295 → 310, iOS +3. (S2.3/revamp)
- [ ] **Two things surfacing it exposed, both now fixed — read before touching this area.**
      (1) `route_items` in `checklist.py` had an `else` that titled any unrecognised kind
      "<room> has no usable way out"; a squeeze would have shipped claiming a passable
      doorway was a dead end. (2) `Obstruction.detail` compared the measured width against
      the CODE width for narrowings when they are judged against the COMFORT width, printing
      "squeezes to 0.90 m — under the 0.81 m a door needs". Both had been latent since B3
      because nothing rendered the kind. **Any new FindingKind needs an explicit branch in
      `route_items`, `RouteFindingStyle.of`, and `RouteNarration.findingSentence`** — the
      first fails silently and the other two are exhaustive switches that fail loudly.
- [ ] **Consider a third, milder warning tint for `narrows_route`.** It currently shares
      `warningBadge` with `blocked_opening` and `no_secondary_egress`, so a passable-but-tight
      doorway looks exactly as grave as "no second way out". Deliberately not invented
      mid-fix: START-HERE forbids new colours and the White Model overhaul exists to undo
      colour proliferation. A call for the UI/UX pass. (decisions.md 2026-08-25)
- [ ] Consider a contract test that diffs the backend's `Literal`/enum values against the
      Swift cases automatically. Today's sweep was by hand and found the gap six days late;
      nothing stops the next one. Cheapest version: a pytest that imports the enums, greps
      the Swift sources, and asserts the value sets match.

## Backend

- [x] **DECISION NEEDED (P1): a home that has never been analysed scores full marks for
      safety.** `/score` defaults `findings=[]`, so the 20-point "No open safety findings"
      component pays out in full when `/analyze` has simply never run — bungalow and twostory
      both read 75/100 on a home nobody has audited. "We didn't look" and "we looked and it's
      clean" produce the same number, which is a safety claim the app hasn't earned. Fix
      would be to distinguish absent from empty (e.g. `findings: Optional[...] = None` →
      component reported as *not assessed*, its 20 pts subtracted from a new `max_possible`
      so the UI renders "55 / 80"). **Not done unilaterally: it changes `ScoreBreakdown`, the
      `ScoreScreen`/`ScoreModels` Swift contract, and every worked example in the weights
      doc.** Mitigated in part 2026-07-27 — undersized bedroom egress windows are now caught
      deterministically without `/analyze` (see `egress.window.*` items). **Now visible in a
      committed screenshot** (`docs/evidence/score-screen-2026-08-04/`): the twostory home
      reads "No open safety findings — 20/20" having never been analysed. Worth deciding
      before the demo script locks, since the score is on camera. (S3.5)
      *Note (2026-09-08): Resolved/Obsoleted by the S6.7 merge on 2026-09-07, which made `agent_finding` strictly advisory and removed the 20-point component entirely (see `docs/preparedness-score-weights.md`).*
- [ ] Phone-on-cellular timing against the deployed backend was never measured natively.
      Warm curl from a dev machine was ~0.27–0.39s, well under the 2s bar. (S1.6)
- [x] TODO(integration): `/analyze` findings now carry a stable server-stamped `id`
      (2026-07-23); Swift's `AgentFinding` ignores it and `ChecklistStateStore` still sees
      positional `agent_finding.<index>` keys via the fallback. Thread the `id` through the
      Swift decode (add to CodingKeys) and key checkmarks on `agent_finding.<id>` — old
      positional checkmarks are deliberately orphaned (see decisions.md 2026-07-23). (S3.2/S3.5)
      *Note (2026-09-08): Resolved. The persistence path already keys on `ChecklistItem.id`, which `checklist.py:360` populates with the backend's stable `finding.id`. `AgentFinding` is unreferenced by the UI, so no Swift changes were necessary.*

## Demo & submission

- [ ] Table-read the script aloud, confirm under 3:15. On paper it's 436 words ≈ 2:54 at
      150 wpm, but the box means an actual read-aloud. (S5.1)
- [ ] Tech-accuracy pass: verify every claim in `docs/demo/script-v1.md` against the shipped
      build. The script's truth-ledger appendix is a self-audit, not an independent check. (S5.1)
- [ ] Golden path on a **real device** — the simulator half is done (2026-07-23, Lane B):
      onboarding loop green live against the local backend, routes rendered on 3/3 fixtures,
      plan/chat/score/drill walked with backend up AND pointed at a dead port (graceful
      banners, zero crashes; `S44BackendDownUITests` + `docs/evidence/s44-after/offline-*`).
      Remaining: same pass on a phone. (S4.3)
- [ ] Polish pass: the before/after artifact is built and committed
      (`docs/evidence/s44-before-after.md` + `s44-before/` + `s44-after/`, 2026-07-23) —
      remaining: the team actually looks at it and prefers the after. (S4.4)
- [ ] Film + edit; three non-team viewers name the wow moment unprompted. (S5.2)
- [ ] Submit, save the confirmation screenshot in the repo, finish `tools-used.md`, and write
      the app description + "what we learned" answers. (S5.3)

## Process & repo hygiene

- [x] **`.build-assess/` is tracked in git — 2,826 derived-data files.** Committed in `ce18f63`
      (2026-07-22) before `.build-*/` reached `.gitignore`; ignore rules never untrack. Every
      `xcodebuild … -derivedDataPath .build-assess` run since then dirties the tree with hundreds
      of module-cache "deletions" and index "modifications", which hides real changes in
      `git status`. Next action: `git rm -r --cached .build-assess` in its own commit (no source
      change), then confirm `git status` is clean after a build. Found 2026-09-07. Note: Done 2026-09-08.

- [ ] **iOS test runs are ~1-in-3 flaky at launch (found 2026-08-04).** Three identical
      back-to-back full runs: pass / fail (10 failures) / pass. Every failure was
      `Simulator device failed to launch cac.Escape-Plan … Busy ("Application failed preflight
      checks")` — it takes down both test targets, so a red run says nothing about the code.
      Disk is the most likely lever (93% used, 31 GB free; the previous blocker was 99%).
      Next action: free disk, run the gate 5× in a row, and record the pass rate here. If it
      persists it will bite during filming. Until then, **re-run before believing a red**.
      **2026-08-05 adds a second signature, and it is not a launch failure.**
      `EntryPointUITests.testScanEntryPointPresentsCaptureFlow` failed with
      `Failed to tap "Home" Button: … is no longer valid after interruption handling` — the app
      was already up and the *tab bar button* went stale mid-tap, which XCTest attributes to a
      system interruption. The UI target re-ran clean immediately. So the flake has at least two
      faces and "launch flake" undersells it; anything that parses for `Simulator device failed
      to launch` alone will miss this one. There are **no** `addUIInterruptionMonitor` handlers
      anywhere in `escape_planUITests/` — adding one is the obvious next experiment.
- [ ] Console output undercounts the iOS suite — `xcodebuild` prints `Executed 16 tests`
      because the unit target runs under Swift Testing, which doesn't emit the old
      `Test Suite` lines. The true count (320) is only in the result bundle. Anything that
      parses the console tail for a pass count is wrong. Next action: when someone touches
      the `/verify` skill, have it read
      `xcrun xcresulttool get test-results summary --path <bundle>` instead.

- [ ] Backfill curated evidence for the S2.2/S2.3/S3.4/S3.5 handoffs (their ~45 MB of
      screenshots/recordings still live only in one machine's gitignored `artifacts/`).
      The convention + home for it now exists: `docs/evidence/` (see its README; S4.4's
      before/after sets are the first committed example). (process)
- [ ] `docs/demo/broll/s41-golden-path-simulator.mp4` (19 MB) is committed to git history.
      Removing it needs a history rewrite. At minimum, gitignore future broll.
- [ ] Corpus sign-off: someone other than the author should actually read
      `docs/corpus-summary.md` and confirm it's sufficient for the AI layer, or reopen it if
      thin. It was marked done without an independent read. (S0.4)
- [ ] `escape_plan/CLAUDE.md` is copied into the shipped `.app` bundle as a resource by the
      `PBXFileSystemSynchronizedRootGroup`. Gitignored so it never reaches git, but it will
      ship in a release build. Exclude it from Copy Resources.
- [ ] Residual `P1`/`P2`/`P3` prose mentions remain in ~20 archived docs (playbook narrative,
      demo storyboards, `decisions.md` history). The mechanical lane labels are gone; these
      are sentences that need rewriting by hand, and `docs/tracker/notes/` is deliberately
      left untouched as a dated archive.
