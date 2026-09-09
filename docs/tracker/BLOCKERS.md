# BLOCKERS — what is not done

**This file is the board.** Anything blocking, unverified, or not-yet-done gets written here
the session it is discovered. [`TODO.md`](TODO.md) holds the long-tail backlog; this file holds
what actually stops the project from shipping, ranked by what is on the critical path.

**Deadline: submit by Oct 24, 2026.** End-to-end demo path working by Oct 5.

_Last verified 2026-09-08 on `main`. Re-run this session and green: backend **348** pass
(13 live-deselected), EditorCore **270** pass, corpus valid (**17** sources, **8** files).
**iOS not run this session** — the last recorded number (598/0/8) predates the Swift in this
tree, so it is not a current figure._

**Rules**
- One line per blocker: what it blocks · who can clear it · the concrete next action.
- Remove an item only when you personally verified it. "The code exists" is not verification.
- Discovered something undone? It goes here, this session. Not in a note, not in your head.

---

## 1 · Ship blockers — only the owner can clear these

- [ ] **Anthropic account is out of credits.** `/explain`, `/analyze` and `/chat` return **502**
      by design; all 13 `-m live` tests and the never-executed `agent_bungalow_blocked` golden are
      blocked. The deterministic half (`/routes`, `/score`, `/convert`, `/evacuate`) is unaffected
      — that separation is the architecture working. **Do not debug the AI layer; it is billing.**
      Next action: top up the account. Nothing else is closer to the critical path for filming
      anything that shows the assistant.

- [ ] **Bearer token missing on the build machine.** `escape_plan/BackendConfig.local.json` does
      not exist, so a fresh install reaches the deployed backend and gets **401 on everything**.
      The app is not broken, it is unauthenticated. Next action (owner, manual — the file is
      gitignored and `.env` is read-guarded): create it as `{"bearer_token": "<shared token>"}`,
      then re-run `python3 scripts/demo-preflight.py` and confirm exit 0.

---

## 2 · Device-gated — needs a physical iPhone, roughly one focused session

Nothing in this section can be closed from a simulator, and none of it has ever been done.
This is the largest remaining body of work and it gates filming. Order matters — 2.1 first,
because if it fails nothing downstream is worth tuning.

- [ ] **2.1 Camera feel — four checks, in order.** (1) Put a corner of the house under your thumb
      and pan; it must stay under your thumb, in both orientations and both projections — **if
      this fails, stop and report it**, the projection branch is reading the wrong camera.
      (2) Pinch: the point between your fingers must not crawl. (3) Flick to orbit: it must coast
      and ease out, not stop dead. (4) Pan to the edge: the rubber band must spring back visibly.
      Then tune by feel — the constants are a guess, not a result: apron `0.6`, distance
      `0.35…4.0 × extent`, orbit rate `0.6 π`, axis-lock `20 pt` (`CameraRigModel` +
      `OrbitCameraRig`). **Orbit rate and axis-lock interact — move them together.**
- [ ] **2.2 Frame rate, measured not guessed.** Never profiled on hardware. MSAA 4X, SSAO and the
      route pulse shader all run during gestures. Measure frame time on the oldest phone available,
      on **all four** fixtures (bungalow, apartment, twostory, jagged), and **write the number
      here**. Levers, already isolated behind `CameraGestureDriver.onPhaseChange`: MSAA 4X → 2X
      during gestures, SSAO off mid-gesture. Do not touch either without a measurement — both are
      visible changes.
- [ ] **2.3 Orthographic framing on a real phone.** `orthographicScale` is a half-*height*, so the
      portrait aspect correction is the difference between a framed house and one cropped at both
      sides — invisible on a square-ish simulator window.
- [ ] **2.4 Walk the golden path as a judge would.** Onboarding → build or open a home → routes
      render → switch profiles → drill → score. Note every hesitation, every re-read label, every
      dead tap. That list is the polish backlog — file it here.
- [ ] **2.5 Haptics.** Every button clicks on press-down and the score gauge ratchets 25 notches;
      the simulator cannot verify one of them. If it reads as busy, the knobs are `Haptics.press()`
      and `HapticSweep.tick` intensity. One pass over Home, the House dock, and Beta swipes.
- [ ] **2.6 Assistant composer rides the keyboard.** It sits in the list's bottom safe-area inset
      (the canonical placement) but the simulator would not show the on-screen keyboard. Confirm
      the capsule sits on the keyboard's top edge and the list scrolls behind it.
- [ ] **2.7 Scene-rebuild gating during playback.** `UnifiedSceneController.rebuildIfNeeded` now
      skips a rebuild when `(home, activeFloorId)` is unchanged. Unit tests cannot see this.
      Confirm figures move continuously instead of restarting, and that editing still redraws
      immediately after a commit.
- [ ] **2.8 Floor toggling and the `jagged` stack.** Chips *and* tapping a ghosted floor, with the
      0.35 s focus glide. On `jagged`: activate the basement, confirm the two floors above ghost,
      all three slab outlines stay legible at once, no z-fighting or murk.
- [ ] **2.9 The rest of the on-device sweep.** Kill/relaunch persistence with two saved homes;
      a drill for two profiles (twostory: Grandpa + Maya) with practiced-state moving the score
      across a relaunch; chat surviving background/foreground; the backend killed mid-flow
      degrading gracefully; VoiceOver end-to-end with a real screen reader; the per-floor PDF
      printed on actual paper in greyscale.

---

## 3 · Known defects — found by review, not yet fixed

Carried from the 2026-09-06 agent review of the orchestrator's S6.1–S6.3 and later sessions.
These are real, reproduced or reasoned, and several would read badly to a judge.

**Contract / correctness**
- [ ] `/build` serializes `confidence: null` and `egress: null`, **which the schema rejects.**
      Schema 2.0 made `meta.last_scanned` and `household.tenure` nullable but left these as bare
      types. `/convert` sets `response_model_exclude_none=True` and is masked; `/build` does not
      and is exposed. Next action: declare both nullable or set the flag on `/build`, then widen
      the serialize test to the whole document.
- [ ] **`schema_version` breadth disagrees three ways** — JSON Schema `enum ["1.1","2.0"]`,
      pydantic `Literal["2.0"]` (confirmed live on the deployed service), Swift a bare `String`.
      And because every 2.0 addition is optional, the JSON Schema cannot actually tell a 1.1
      document from a 2.0 one. Next action: consider `const: "2.0"`, `"1.1"` accepted only by
      the migrators.
- [ ] **Three files still self-describe as v1.1** after the bump — `homemodel.schema.json:5`,
      `backend/app/models.py:1`, `escape_plan/Models/HomeModel.swift:2`.
- [ ] **`FloorObject.size_m` is unbounded `[Double]` in Swift** but exactly 2 elements in schema
      and pydantic — Swift accepts a 3-element size the other two reject. Pre-existing from v1.1.
- [ ] **`exterior_edges` mixes int indices with `f"op_{id}"` strings**
      (`routing/perils/tornado.py:63-91`). If the `else` at :70 ever fires, the same wall is
      counted twice, inflating `ext_walls` and corrupting the shelter ranking. Zero hits on
      current fixtures; a live trap for scan-derived homes. Next action: one key space.

**Grounding — every one of these is an originality claim a judge could check**
- [ ] **FEMA over-claim.** `severe-weather-tornado.md:18` says a basement "provides near-absolute
      protection". That is FEMA P-361/P-320 language reserved for safe rooms **built to FEMA
      criteria**, not a property of basements generally. Next action: split the sentence —
      near-absolute for the FEMA-rated safe room, "substantially safer" for an ordinary basement.
- [ ] **Dead URL carrying a fresh retrieved date.** `sources.json:129` has
      `fema.gov/plan/prevent/saferoom` (retired years ago) stamped `"retrieved": "2026-09-05"`.
      A retrieved date asserts somebody fetched it. Current path is
      `/emergency-managers/risk-management/safe-rooms`. Next action: re-verify all six new URLs
      resolve, then correct.
- [ ] **`shakeout-guidance` cite precision.** `sources.json:113` points at
      `earthquakecountry.org/step5/` (Drop, Cover, Hold On) but is cited for furniture securing,
      which is step 1.
- [ ] **`RouteFinding` has no `citation` field**, so finding-level safety text is validated by
      nothing — which is exactly how the uncited shelter directive shipped green.
      `test_citation_resolution` only walks `ChecklistItem.source_citation`. Next action: add
      `citation: str | None` plus a test that imperative safety text in `detail` resolves.

**Test and hygiene gaps**
- [ ] **`test_perils.py` tornado assertion is weak.** It asserts only `primary.exit_id !=
      "d_front"`, which passes trivially now that `exit_id` holds a room id. The shelter chosen
      for all 7 twostory rooms is `r_hall1` — the room containing the front door. Next action:
      assert on `ext_openings == 0` or room type, not a door id.
- [ ] **A unit test writes a demo home into the app's real `Documents/Homes`.** The test host
      shares the app's sandbox, so `escape_planTests/OnboardingTests.swift:150`
      (`state.seedIfNeeded()` on a default `OnboardingState`) pollutes the tester's library on
      every run. Next action: point it at a temporary-directory store.
- [ ] **Onboarding seeds a new "Demo Home (scanned)" on every run**, not only into an empty
      library — two extra demo homes after one verification pass on 2026-09-07. Next action:
      make the seed conditional on an empty library, or reuse a stable demo id.
- [ ] **`RouteRedrawAfterEditUITests` counts orange pixels** (`r > 190, g 80–180, b < 90`) but
      routes have been blue since the 2026-08-05 colour pass, so it can no longer pass. Skipped
      unless `ROUTE_REDRAW=1`, so it does not gate CI — which is why it will stay broken.
      Next action: retune to `DollhousePalette.routePrimary` (`#123FB0`).
- [ ] **`routing/perils/objective.py` is a stub** — four unused imports and a "shared logic here
      if needed" comment. Delete it or implement it.
- [ ] **19 contract tests exist only on the `my-s6-1-and-policy` branch**, not on `main`: the
      safety-point/household/tenure/equipment invariants, the bundled-fixture drift guard,
      `test_safety_points_are_not_obstacles`, the two sensory-tag routing-neutrality tests, and
      all 8 of `SchemaV2ContractTests.swift`. Most port cleanly. Next action: port the
      seeding-independent ones.
- [ ] **Fixtures are thinly seeded.** Only `twostory` has a household, **no** fixture has
      `meta.last_scanned`, and **no** profile carries `hearing_impaired`/`vision_impaired` — two
      schema-2.0 additions with zero fixture coverage. The `my-s6-1-and-policy` branch seeded both
      sides of every branch and was deliberately not merged. Next action: decide the seeding once
      and do it in one pass.

---

## 4 · Flake and process — known, live, will bite during filming

- [ ] **iOS runs are ~1-in-3 environmental flake, with two distinct faces.** (a) `Simulator device
      failed to launch … Busy ("Application failed preflight checks")`, which kills both test
      targets and says nothing about the code; (b) a tab-bar button going stale mid-tap, which
      XCTest attributes to a system interruption. **Re-run once before believing a red.** Anything
      that greps only for the launch string misses face (b). There are no `addUIInterruptionMonitor`
      handlers in `escape_planUITests/` — adding one is the obvious next experiment.
- [ ] **Console undercounts the iOS suite.** `xcodebuild` prints `Executed 16 tests` because the
      unit target runs under Swift Testing. True counts come only from
      `xcrun xcresulttool get test-results summary --path <bundle>`. Next action: when someone
      touches the `/verify` skill, have it read the result bundle.
- [ ] **`/health` reports `v1.0` and that is meaningless** — it is a hardcoded FastAPI `app.version`
      (`backend/app/main.py:44`), not a deploy or schema signal. It read as "stale backend" on
      2026-09-07 and cost a diagnosis. Next action: have `demo-preflight.py` probe
      `/openapi.json` for `schema_version` instead, or stop printing the version.

---

## 5 · Submission path

- [ ] **`docs/demo/script-v1.md` pitches a product that no longer exists** — it sells fire-only,
      offers "other disasters" as *future* work, and its truth-ledger row 17 cites the superseded
      scope lock. Rewrite it **only** against what actually shipped. Next action: fold into the
      S5.1 tech-accuracy pass once the device pass is done.
- [ ] Table-read the script aloud, confirm under 3:15 (436 words ≈ 2:54 at 150 wpm — the box means
      an actual read-aloud).
- [ ] Tech-accuracy pass: verify every claim in the script against the shipped build. The script's
      truth-ledger appendix is a self-audit, not an independent check.
- [ ] Run `python3 scripts/demo-preflight.py` immediately before filming. Exit 0 = ready.
- [ ] Film + edit; three non-team viewers name the wow moment unprompted.
- [ ] Submit, save the confirmation screenshot in the repo, finish `docs/tools-used.md`, write the
      app description and the "what we learned" answers.

---

## Recently cleared — do not re-open without evidence

- **LiDAR field trip — DONE 2026-09-08, first attempt, worked.** Scanned a friend's house; it
  mapped correctly, conversion held, and the animations looked good. This closed the entire
  "needs real LiDAR hardware" section. Remaining scan work is optional polish, not a blocker:
  commit one clean and one messy real export to `schema/fixtures/scans/`, and promote the
  assumed-format risks in `backend/app/convert/README.md` into `docs/decisions.md` now that a
  real export has shown which assumptions held.
- **Render backend is current — verified 2026-09-08.** `/openapi.json` on the deployed service
  reports `schema_version const "2.0"`, a `Household` schema, and `peril` on `RoutesRequest`,
  and serves all nine routes including `/evacuate`. Local `main` and `origin/main` are identical,
  so Render's auto-deploy is working. The 2026-09-07 "still pre-2.0, `/score` 422s" note is
  **stale** — it was true of a local uvicorn started before the schema commits.
- **S6.4–S6.7 shipped.** Verified in the tree 2026-09-08: `household_items()` in
  `backend/app/scoring/checklist.py` (S6.4), the interview in `escape_plan/Onboarding/` (S6.5),
  the checklist rendering natively in `HomeScreen.swift` (S6.6), and the composite score merged
  in `732a5c8` (S6.7). The tracker had carried all four as open.
- **`.build-assess/` untracked** (`07e413a`), and `AgentFinding.id` threaded through the Swift
  decode (`df9d0a2`).
