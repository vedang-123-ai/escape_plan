# BLOCKERS — what is not done

**This file is the board.** Anything blocking, unverified, or not-yet-done gets written here
the session it is discovered. [`TODO.md`](TODO.md) holds the long-tail backlog; this file holds
what actually stops the project from shipping, ranked by what is on the critical path.

**Deadline: submit by Oct 24, 2026.** End-to-end demo path working by Oct 5.

_Last verified 2026-09-15 on `s8-3-ios-auth-ui` (the S8.3 iOS auth session). **Re-run and green
this session:** EditorCore **388** pass (was 295; **+93**, all of them S8.3's auth layer — the
whole client, token store, session state machine, error mapping and validation are Foundation-only
and symlinked into `tools/editorcore`, so they execute on a machine with no simulator). Backend
**526** pass / 1 skipped / 13 deselected, unchanged — S8.3 touched no Python. Corpus valid (**24**
sources, **9** files, **2** threshold files).

**NEW this session — the whole iOS app type-checks.** `swiftc -typecheck` over all **150** files in
`escape_plan/` against the iOS 26.5 simulator SDK, in **both** configurations (`-DDEBUG` and
release): **exit 0, 0 errors** each. Warnings are all pre-existing and none are in new code.
Running both matters — the release-only run never type-checks `SettingsScreen`'s `#if DEBUG`
Developer section, and the DEBUG-only run misses code excluded from it. Command:

```bash
find escape_plan -name '*.swift' > /tmp/srcs.txt
xcrun swiftc -typecheck -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios26.5-simulator -swift-version 5 @/tmp/srcs.txt
```

**Read that claim narrowly.** It is strictly more than the `swiftc -parse` the FIRST-PRIORITY
brief rightly dismisses — it resolves every type, member and protocol conformance across the
module, so the four previously-uncompiled bodies of Swift do now type-check. It is **not** a
build (no SIL, no IRGen, no linking, no resource compilation) and it is **not** a test run. It
does not close §0; it narrows what §0 still has to find.

**NOT run this session:** `xcodebuild test` — this machine cannot. The iOS count remains **615
passed, 0 failed, 8 skipped** as of 2026-09-09 (`Test-escape_plan-2026.09.09_23-31-03--0700.xcresult`),
which now predates five bodies of Swift including S8.3's. **S8.3 is NOT ticked in TODO.md** —
all three of its acceptance criteria need a simulator. Treat it as stale, not as a pass.
`RouteRedrawAfterEditUITests` run live separately with `TEST_RUNNER_ROUTE_REDRAW=1` against a local
backend — still red, see §3._


**Rules**
- One line per blocker: what it blocks · who can clear it · the concrete next action.
- Remove an item only when you personally verified it. "The code exists" is not verification.
- Discovered something undone? It goes here, this session. Not in a note, not in your head.

---

## 0 · FIRST PRIORITY — before any other work

- [ ] **Compile and test the app on a working simulator, and record a real count.**
      **Owner: Anish / Yuki.** Full brief, command and follow-ups:
      [`FIRST-PRIORITY.md`](FIRST-PRIORITY.md). Four bodies of Swift have landed since the last
      verified iOS run (615 passed, 2026-09-09) and none has a recorded result: S7.7's
      `HazardHuntView` rewrite, S7.8's `DiffReviewSheet`, S9.1/S9.2 (a note claims `xcodebuild
      test` passed but records no count and no bundle), and S9.3's `ARDrillView` (no test claim at
      all). All seven new files pass `swiftc -parse` — syntax only, not a compile. The machine
      this was last worked on cannot run the simulator, so it could not be checked there.
      Surfaced at the top of every new session by the SessionStart hook; clear it by setting
      `gate_status: closed` in `FIRST-PRIORITY.md`.

      **Narrowed 2026-09-15 (S8.3), not cleared.** All 149 app files now `swiftc -typecheck`
      clean against the iOS 26.5 simulator SDK (exit 0, 0 errors) — see the header stamp for the
      command. So "do these seven files even compile?" is answered for the type system:
      `ARDrillView`, `SemanticMatcher`, `DrillRelocalizationController/View`, `HazardHuntView`
      and `DiffReviewSheet` all resolve. What is STILL unanswered and still needs a simulator:
      whether the app links and launches, whether the 620-test suite passes, and the two §3
      defects below. **Do not set `gate_status: closed` on the strength of a type-check.**

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

## 2 · Device blocks — things that require the physical iPhone 17 Pro

- [x] ~~**The auth wire contract has only ever met a stub.**~~ **MET PRODUCTION 2026-09-16.**
      Walked by hand against the DEPLOYED backend (`escape-plan-backend.onrender.com`, live
      Atlas), sending the exact bytes `FormURLEncoding.body()` emits: register → **201**,
      duplicate → **409**, form-encoded login → **200** + JWT, `/auth/me` → `UserPublic` with
      **no hash on the wire**, wrong password → **401**, no token → **401**, `GET /homes` → `[]`,
      `POST /homes` → **201** returning `id` (not `_id`, so S8.2's fix holds on the deployed
      service, which S8.4 depends on).
      Two results worth keeping. **The `+`-in-password trap is real and the encoder defeats it:**
      the password `Escape+Plan test 2026` logs in when `+` is sent as `%2B` and returns **401**
      when it is not — so `URLComponents.query` would have silently broken login for any user
      with a `+` in their password. And **cold start measured at 42 s**, which is why
      `AuthClient` uses a 90 s timeout and a distinct "waking up" message rather than "offline".
      The returned `bungalow.json` (schema 2.1) decodes in Swift and compares **equal** to the
      fixture-loaded `HomeModel`.
      **This does NOT close acceptance criterion 1.** It proves the contract, not the app — no
      iOS binary has been built or launched. Test account and home were created and are pending
      deletion by the owner (see the session note).

- [ ] **S8.4 note: a home that has been through the server differs from the local one BY BYTES,
      though not by value.** pydantic serialises absent optionals as explicit `null` and fills
      `objects: []`, so the JSON that comes back has 21 keys the sent JSON did not — measured
      2026-09-16 on `bungalow.json`. Swift decodes it to an **equal** `HomeModel`, so the model
      layer is fine, but any S8.4 dirty-check or merge that compares **encoded JSON** rather
      than decoded models will see every synced home as permanently modified. Compare models,
      or compare `revision`.

- [ ] **Nothing has ever run below iOS 26.5, and the deployment target is now 17.0.**
      Changed 2026-09-16 (see §3) because 26.5 was an Xcode default that would have made the
      app installable only on the newest iOS. The lower floor is compile-verified, not
      run-verified. Next action: during the device pass, boot ONE simulator on an older runtime
      (17.x or 18.x) and walk the golden path — the risks are SwiftUI layout differences,
      `@Observable` behaviour, and RoomPlan/ARKit availability, none of which a type-check sees.
      If an older runtime is not installed, say so on this line rather than deleting it.

- [ ] **S8.3's three auth SCREENS have never been rendered.** `AuthGateView`, `LoginView`,
      `SignupView` (plus `AuthSheetView` and `RootView`) type-check and nothing more. Everything
      they sit on is tested — 84 tests, `swift test --package-path tools/editorcore` — but layout,
      keyboard behaviour, the Password AutoFill prompts (`.username`/`.password`/`.newPassword`)
      and the gate→app transition are unobserved. Next action: run them on the simulator and walk
      register → sign out → sign in → relaunch.

- [ ] **`KeychainTokenStore` has never touched a real Keychain.** A macOS unit-test bundle has no
      keychain-access entitlement, so it cannot be exercised in the SwiftPM package.
      `escape_planTests/KeychainTokenStoreTests.swift` is written and ready — it runs the SAME
      `assertTokenStoreContract` the in-memory double passes — but has never executed. Until it
      does, "the token persists across app restarts" (an S8.3 acceptance criterion) is **argued,
      not verified**. Be precise about why the existing tests do not cover it: the "relaunch"
      tests (`testSignOutSurvivesARelaunch`, `testSecondLaunchDoesNotPurge`,
      `testConstructionAloneRestoresTheSession`) construct a second `AuthSession` over the **same
      in-process `InMemoryTokenStore` object**. They prove the state machine re-reads its store.
      **Nothing crosses a process boundary**, so they say nothing at all about persistence — and
      the one component that could persist anything is the one that has never run. Next action: run that test class on the simulator, then kill and relaunch
      the app while signed in.

- [ ] **The 8 UI tests now pass `-auth.gate.dismissed YES` and nobody has confirmed it works.**
      The flag is the same UserDefaults-override trick the suite already uses for
      `-onboarding.completed`, so it *should* land, but if `AuthSession` reads it at the wrong
      moment every one of those tests opens on the gate and fails hunting for a tab bar. Next
      action: the FIRST-PRIORITY run answers this for free — check the count did not drop.

- [ ] **S7.7 Device Pass: Real Scan Verification.** Real-scan objects (furniture, doors, windows) must be confirmed to accurately capture and map to schema `v2.1` via physical RoomPlan scan. Owner must run on device.
- [ ] **S7.7 Device Pass: Camera feel and Frame-time metrics.** The updated SceneKit renderer and object rendering frame-times must hit 60fps on physical silicon. Owner must run on device and record the frame-time number in `field-test-lidar.md`.

Nothing in this section can be closed from a simulator, and none of it has ever been done.
This is the largest remaining body of work and it gates filming. Order matters — 2.1 first,
because if it fails nothing downstream is worth tuning.

### Device-pass checklist

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

- [x] ~~**The root `CLAUDE.md` says "iOS 17+"; the project builds against iOS 26.5.**~~
      **RESOLVED 2026-09-16 — the docs were right and the project file was wrong.**
      `IPHONEOS_DEPLOYMENT_TARGET` was `26.5` in all four configurations, which would have
      shipped an app installable only on the newest iOS — for a submission judges may open on
      any device, close to a disqualifying detail. Nobody on the team put it there deliberately
      (owner confirmed); it is the value Xcode defaults a new project to.
      **Measured rather than assumed before changing it:** the app type-checks clean against the
      simulator SDK at **iOS 17.0** and 18.0 (exit 0, both `-DDEBUG` and release), and fails at
      iOS 16.0 with exactly **38** `is only available in iOS 17.0 or newer` errors. So 17.0 is
      precisely the floor — the number `CLAUDE.md` has claimed all along, for the documented
      reason (RoomPlan's merged multi-room `CapturedStructure` API). All four configurations are
      now `17.0`.
      **What this does NOT mean:** the app has never been RUN below iOS 26.5. It compiles for
      17.0; that is a different claim from working there. Anything version-sensitive at runtime —
      SwiftUI layout, `@Observable`, RoomPlan, ARKit — is unverified on 17.x and should be spot
      checked during the device pass. Carried as a device-pass item in §2.

- [ ] **S9.3 renders every AR waypoint at a hardcoded 1.0 m, ignoring which floor it is on.**
      `ARDrillView.swift:68` — `wpNode.position = SCNVector3(Float(wp.x), 1.0, Float(wp.y))`, and
      the file's only other mention of "floor" is the comment above that line. There is no floor
      or level term anywhere in the placement. On `twostory.json` (levels 0 and 1 — a core
      fixture) a route from an upstairs bedroom down to an exit draws the whole path at one
      height, so a user standing upstairs sees the ground-floor leg floating at eye level. The
      horizontal mapping (model `y` → AR `z`) is correct; only height is wrong. Multi-floor homes
      are in scope and stairs are modelled, so this is not an edge case. Found by review
      2026-09-14, never seen on a device.

- [ ] **A room with no doors scores a perfect 0 and outranks correctly-matched rooms.**
      `SemanticMatcher.swift` — the door-distance branch falls through to `totalDist = 0` whenever
      *either* side has no doors, and lower is better. So a candidate whose openings are missing
      (a closet, or a scan that missed a doorway) always sorts above a correct room that matched
      its doors at, say, 0.35 m. Absence of evidence is being scored as perfect evidence. The
      2026-09-14 ambiguity fix means such a room now always returns `.ambiguous` rather than a
      confident wrong match — but the *correct* room can be excluded from the candidate list
      entirely, so the user is asked to disambiguate among only wrong answers. Next action: score
      the no-evidence case as neutral-or-worst, not best, and exclude it from `best` selection.

- [ ] **RoomPlan splits long walls, and `extractedLongestWall` does not account for it.**
      Anish's own S9.1 audit raised this as MEDIUM and the S9.2 audit confirms it was deliberately
      left unfixed ("I haven't fixed the 'Group walls by their normal vectors' issue yet"). A 10 m
      wall broken into three segments by doors loses to an unbroken 4 m perpendicular wall,
      producing a permanent 90° alignment error. Everything in the matcher keys off the longest
      wall, so this failure is silent and total. Only reproducible on a real scan.

- [ ] **"Verified fixes with `xcodebuild test` successfully" carries no count and no bundle.**
      `notes/2026-09-14-S9.2-UI-Setup.md`. The claim is plausible — it was presumably run on the
      author's machine, not this one — but this repo's own rule is that true counts come only from
      `xcrun xcresulttool get test-results summary --path <bundle>`, never a console tail, because
      the unit target runs under Swift Testing and prints `Executed 16 tests`. **S9.3's note makes
      no test claim at all.** So the iOS status is: S9.1/S9.2 claimed-green-unevidenced, S9.3
      never claimed. Next action: whoever next has a working simulator records a real count.

Carried from the 2026-09-06 agent review of the orchestrator's S6.1–S6.3 and later sessions.
These are real, reproduced or reasoned, and several would read badly to a judge.

**Contract / correctness**
- [x] `/build` serialized `confidence: null` and `egress: null`, **which the schema rejects.**
      Fixed 2026-09-09 by applying `response_model_exclude_none=True`, matching `/convert`.
      `test_build_response_has_no_null_optionals` recursively checks the complete HTTP document.
- [x] **`schema_version` breadth disagrees three ways** — RULED and closed in S7.1 (2026-09-09).
      The three breadths are deliberate: JSON Schema lists every migrator-accepted version
      (it validates documents on disk), pydantic is `Literal` current-only (it validates the
      post-migration in-memory model), Swift is a bare `String` (it must read the old stamp
      before it can migrate it). Each is documented at its definition. See `decisions.md`.

**Opened by S7.1 (2026-09-09) — schema 2.1**
- [x] **The deployed backend is on schema 2.0; this checkout is on 2.1.** (Also folded into
      S7.2's STEP 0.) Render auto-deploys
      from `main`, so pushing S7.1 should clear it, but it is NOT verified. Until it is,
      `/convert` and `/routes` against the live service are answering from a different contract
      than the app now writes. Next action: after the push, run `python3 scripts/demo-preflight.py`
      and confirm `check_deployed_schema()` reports 2.1. (Preflight cannot run on this machine
      today — see §4.) (Closed in S7.2 STEP 0: preflight verifies schema 2.1 deployed)
- [x] **Two S7.1 acceptance items are simulator-gated and were NOT run — assigned to S7.2 as
      its STEP 0** (`docs/playbook/S7-2.md`), so it is the first thing that session does rather
      than a line on this board someone can skim past.
      `HomeModelRoundTripTests` and `PersistenceTests` live outside the symlinked EditorCore
      package, so `swift test` does not reach them. **The fix for the vacuous drift guard
      (`testCurrentVersionMatchesTheSchemaContract`) is in `PersistenceTests` and has therefore
      never executed.** Next action: run S7.2's STEP 0 — one `xcodebuild` command, spelled out
      there. Tick this line only after the run is green, not on the strength of the code existing. (Closed in S7.2 STEP 0: 23 tests passed, drift guard passed.)
- [x] **`bookcase` and `water_heater` produce NO mitigation checklist item.**
      `backend/app/scoring/checklist.py:504` filters on `heavy_categories = {"wardrobe",
      "storage", "appliance"}`. A bookcase is the ShakeOut-canonical topple hazard and a water
      heater the canonical strap target, so **a user who picks the newer, more accurate category
      loses a recommendation they would have gotten yesterday.** Deliberately deferred, not
      overlooked: extending the set here would collide with S7.4's `hazard.topple.<id>` items and
      produce exactly the duplicate strap-it item ruled out at scoping. **This is an S7.4
      obligation, and S7.4 is not done until it is discharged.** Verified 2026-09-09:
      `test_bookcase_and_water_heater_use_specific_hazards_without_generic_duplicates` proves
      both specific `hazard.*` items exist and no generic `mitigation.secure.*` duplicate exists.
- [ ] **Routing is elevation-blind — latent, but mechanically real.** Nothing under
      `backend/app/routing/` reads `elevation_m` or `mounted`; `build_room_grid` rasterizes any
      footprint it is handed, so a wall-mounted TV erodes walkable floor (proved: moving
      `o_u_tv_over_bed` mid-room drops free cells 5476 → 5296). It does not bite today only
      because the seeded TV overlaps the bed, which the fixture already blocks — meaning the
      fixture hides it. Next action: when the router learns about elevation, add the mid-room
      mounted case to the fixtures so the guard is real.
- [x] **The no-golden-churn guard lost its multi-floor coverage.** `test_obstacles.py`'s
      object-free fixture list is now derived rather than hardcoded (good), but seeding
      `twostory` means the derived set is exactly `['bungalow.json']` — the only multi-floor,
      stairs-carrying fixture dropped out, so "no objects ⇒ straight legs" is no longer verified
      across floors. Next action: add an object-free multi-floor fixture, or assert the property
      per-room instead of per-home.
- [x] **Three files still self-describe as v1.1** after the bump — `homemodel.schema.json:5`,
      `backend/app/models.py:1`, `escape_plan/Models/HomeModel.swift:2`. Verified 2026-09-09:
      all three headers describe v2.1; no edit was needed.
- [x] **`FloorObject.size_m` was unbounded `[Double]` in Swift** while exactly 2 elements in schema
      and pydantic. Fixed 2026-09-09 at the Codable boundary: decode and encode now reject any
      size other than `[width, depth]`; `testFloorObjectRejectsASizeWithMoreThanWidthAndDepth` and
      `testFloorObjectCannotEncodeAMutatedInvalidSize` prove both paths.
- [x] **`exterior_edges` mixed int indices with `f"op_{id}"` strings**
      (`routing/perils/tornado.py:63-91`). Fixed 2026-09-09 with one integer key space
      throughout. **Correction (independent review, 2026-09-09):** the `else` branch this closed
      was already unreachable for any pydantic-validated `HomeModel` — `Opening._check` in
      `models.py` requires `wall_segment.room_id` be one of the opening's two `room_ids` and never
      `EXTERIOR_ID`, and `count_exterior_walls` only enters the branch when `room_ids` is exactly
      `[room.id, EXTERIOR_ID]`, leaving `room.id` as the only legal `wall_segment.room_id` value.
      So this was defensive hardening of dead code, not a fix for a live "scan-derived homes"
      trap as the original line implied — scan-derived homes go through the same validation.
      Harmless and now simpler either way; `test_paired_room_opening_uses_the_polygon_edge_key_once`
      constructs an opening via `.model_construct()` specifically because normal validation can't
      reach that branch.

**Grounding — every one of these is an originality claim a judge could check**
- [x] **FEMA over-claim.** `severe-weather-tornado.md:18` said a basement "provides near-absolute
      protection". That is FEMA P-361/P-320 language reserved for safe rooms **built to FEMA
      criteria**, not a property of basements generally. Fixed 2026-09-09: FEMA safe-room guidance
      supports near-absolute protection only for a safe room built to FEMA criteria; ordinary
      basement guidance cites NWS.
- [x] **Dead URL carrying a fresh retrieved date.** `sources.json:129` had
      `fema.gov/plan/prevent/saferoom` (retired years ago) stamped `"retrieved": "2026-09-05"`.
      A retrieved date asserts somebody fetched it. Verified 2026-09-09: FEMA returned HTTP 200
      at `/emergency-managers/risk-management/building-science/safe-rooms` and its rendered HTML
      contains the FEMA-criteria and near-absolute-protection claim; the source now records that URL
      and date.
- [x] **`shakeout-guidance` cite precision.** `sources.json:113` pointed at
      `earthquakecountry.org/step5/` (Drop, Cover, Hold On) but is cited for furniture securing,
      which is step 1. Verified 2026-09-09: `https://www.earthquakecountry.org/step1/` returned
      HTTP 200 and contains securing guidance for bookcases, furniture, and water heaters; source
      metadata now uses Step 1.
- [x] **`RouteFinding` has no `citation` field**, so finding-level safety text is validated by
      nothing — which is exactly how the uncited shelter directive shipped green.
      `test_citation_resolution` only walks `ChecklistItem.source_citation`. Next action: add
      `citation: str | None` plus a test that imperative safety text in `detail` resolves.

**Test and hygiene gaps**
- [x] **`test_perils.py` tornado assertion was weak.** It asserted only `primary.exit_id !=
      "d_front"`, which passed trivially now that `exit_id` holds a room id. The shelter chosen
      for all 7 twostory rooms is `r_hall1` — the room containing the front door. Fixed
      2026-09-09: the test now asserts the selected shelter has an approved interior room type.
- [x] **A unit test wrote a demo home into the app's real `Documents/Homes`.** The test host
      shares the app's sandbox, so `escape_planTests/OnboardingTests.swift:150`
      (`state.seedIfNeeded()` on a default `OnboardingState`) polluted the tester's library on
      every run. Fixed 2026-09-09: the test injects `HomeDocumentStore(directory: scratch)`.
- [x] **Onboarding seeded a new "Demo Home (scanned)" on every run**, not only into an empty
      library — two extra demo homes after one verification pass on 2026-09-07. Fixed 2026-09-09:
      `seedDemoHome` only seeds an empty library; `testSeedDemoHomeDoesNotAddADuplicateToANonemptyLibrary`
      and `testOnboardingSkipsTheDemoAndExitsCleanlyForAnExistingLibrary` cover the repeat and
      existing-library paths.
- [x] **`RouteRedrawAfterEditUITests` counted orange pixels** (`r > 190, g 80–180, b < 90`) but
      routes have been blue since the 2026-08-05 colour pass, so it can no longer pass. Fixed
      2026-09-09 to recognize `DollhousePalette.routePrimary` (`#123FB0` = R18/G63/B176), which
      satisfies the new predicate (`b>110`, `r<80`, `35<g<115`, `b-r>75`) by direct calculation —
      the previous predicate never would have. **Not fully closed:** running it live with
      `TEST_RUNNER_ROUTE_REDRAW=1` against a local backend (verified 2026-09-09, see below) gets
      past the color check to a *different*, pre-existing failure — see the new line right below.
- [x] **`RouteRedrawAfterEditUITests` fails before it reaches the pixel check at all**, discovered
      2026-09-09 running it live for the first time (it has apparently never actually been run:
      `-onboarding.completed YES` in its launch args skips `OnboardingFlowView` entirely, which is
      the only place anything calls `FixtureSeeder.seedDemoHome` — so a fresh simulator install has
      no home for House screen to show, and `XCTAssertTrue(app.staticTexts["Explode"]...)` fails
      with "House screen never finished loading" before either screenshot is taken. Next action:
      seed a home some other way for this test (a launch argument the app reads before
      `ContentView` renders, or a pre-populated `Documents/Homes` the test installs before
      launching), then re-run and confirm the pixel assertions themselves pass. Fixed 2026-09-10 by force-seeding `twostory` via the `-TEST_SEED_DEMO_HOME` launch argument, replacing the deprecated `Explode` element with `house.addMenu`, and resolving pixel ghosting by tapping the `Upstairs` floor button to make it active before the screenshot.
- [x] **`routing/perils/objective.py` was a stub** — four unused imports and a "shared logic here
      if needed" comment. Verified no imports with `rg`, then deleted 2026-09-09.
- [ ] **The hazard hunt's iOS half is unverified.** `HazardHuntView.swift` was rewritten
      2026-09-10 to render `HazardHuntPlan` (three defects fixed — see
      `notes/2026-09-10-hazard-hunt-rough-edges.md`). The planner is green on EditorCore
      (**295** tests) but **the iOS target has not been compiled since**, so the view is
      typechecked by nothing. **Handed to S7.7 as its STEP 0** (`docs/playbook/S7-7.md`) so it
      is the first thing that session does — one `xcodebuild build`, spelled out there — rather
      than a line here someone can skim past. Do not tick this on the strength of EditorCore
      being green; it does not compile SwiftUI.

- [ ] **The hunt's scan-seeding has never met a real scan.** The new relabel questions ("the
      scan found a tall storage unit — is it a bookcase?") are driven by scanned objects, and
      every test feeds them synthetic ones. Whether RoomPlan actually returns a tall `storage`
      for a real bookcase, or an `appliance` for a real water heater, is unknown. Folded into
      the §2 device pass via S7.7's STEP 0 — walk the hunt in a real scanned room.

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

- [x] ~~**S8.2's auth layer has never met a real MongoDB either.**~~ **MET ONE 2026-09-15.**
      Against a live Atlas M0 (`escape-plan.6bak6dr.mongodb.net`, db `escape_plan`), walked by
      hand: register → **201**, duplicate register → **409** (so `DuplicateKeyError` IS matched
      correctly by class name against the real driver), login → token, `/auth/me` → `UserPublic`
      with no hash on the wire, wrong password → **401**. A `bungalow.json` fixture (schema 2.1,
      1 floor / 4 rooms / 7 openings) round-tripped through BSON and compared **semantically
      identical**. Test user and home deleted afterwards; collections left at 0 documents.
      **Still open — see the new line below: no `@pytest.mark.mongo` test exists, so none of
      this is re-checked by the gate.**

- [x] ~~**The `@pytest.mark.mongo` tests still do not exist.**~~ **WRITTEN 2026-09-15.**
      `backend/tests/test_cloud_mongo.py` — **22 tests, all passing against live Atlas**
      (`pytest -m mongo` with `MONGODB_URI` set; skips cleanly without it, and is deselected from
      the default gate, which stays infrastructure-free at 526 pass / 34 deselected). Covers the
      gap the in-memory fake cannot reach: index creation on a real server, `DuplicateKeyError`
      matched by class name against the real driver, a **genuinely concurrent** 10-way
      registration race (the earlier duplicate check was sequential, which passes even with no
      index at all), BSON timestamp and float fidelity, cross-owner write rejection, and the
      document shape actually written to Mongo. Every test runs against a throwaway per-run
      database that is dropped afterwards, so it can never touch real data.
      Both findings this line used to carry are now **fixed**, not just encoded — see
      `decisions.md` (2026-09-15): timestamps are truncated at generation, and `/homes` returns
      `id` rather than `_id`. Two further defects were found and fixed in the same pass:
      `created_at` was being overwritten on every update, and an unreachable database returned
      500 instead of 503.

- [x] ~~**Atlas is not allow-listing Render's egress IPs.**~~ **CLEARED 2026-09-15** by the owner
      (`0.0.0.0/0` added to the Atlas IP access list — Render's free tier has no static egress
      IPs, so there is nothing narrower to allow-list; the database user's password is
      consequently the only protection and must stay long and random).
      **The DEPLOYED backend is now end-to-end working**, verified against
      `https://escape-plan-backend.onrender.com`: `/health/db` → `{"database":"ok"}`, register →
      201, duplicate → 409, login → token, `/auth/me` → no hash, wrong password → 401. Test
      account deleted; `escape_plan` back to 0 users / 0 homes.
      **S8.3 and S8.4 are now unblocked against the real backend** — this was the last thing
      standing between the S8 backend arc and the iOS half of it.

- [x] ~~**`JWT_SECRET_KEY` is set LOCALLY but not on Render.**~~ **SET BY THE OWNER 2026-09-15**,
      along with `MONGODB_URI`. Both are now present on the deployed service; the owner replaced
      the secret Render had generated at blueprint apply, which invalidates every previously
      issued token — harmless here, because no account existed yet. A 64-byte secret also lives
      in the gitignored root `.env` for local work. Note the deployed service still cannot
      actually reach the database — that is the Atlas allow-list line above, not this one.

- [x] ~~**S8.1's MongoDB layer has never met a real MongoDB server.**~~ **CLEARED 2026-09-15.**
      An Atlas M0 free-tier cluster now exists; `MONGODB_URI` is in the gitignored root `.env`.
      `/health/db` returns `{"database":"ok","db_name":"escape_plan"}` — the S8.1 acceptance
      criterion ("backend starts successfully and connects to MongoDB"), met for the first time.
      Documents have now been written and read. Verified personally, not inferred from code.
      **`MONGODB_URI` is still NOT set on Render** — this clears the local half only.

- [x] **S8.2's unique email index is WRITTEN — but never created by a real MongoDB.**
      `cloud_repo.ensure_indexes()` creates it, called from `Database.connect()`; failure is
      non-fatal (it needs a reachable server) but logged at ERROR. The duplicate-email race IS
      tested, against an in-memory fake that enforces the index. What is unproven is that a real
      server creates it — if it silently does not, registration is back to the account-takeover
      shape below. ~~**Next action: with a real MongoDB, confirm `db.users.getIndexes()` shows
      `uniq_email` and that a concurrent duplicate registration returns 409.**~~ **CONFIRMED
      2026-09-15 on live Atlas:** `users` carries `uniq_email` on `email` with `unique=True`, and
      `homes` carries `by_user` on `user_id` — both created by `ensure_indexes()` on connect, by a
      real server. Duplicate registration returns 409. The account-takeover shape is closed in
      fact, not just in code. Original finding:

- [ ] ~~S8.2 must create a unique index on `User.email` before it writes a login path.~~ There is
      no index-creation code anywhere in the backend, and email normalisation is a convention
      enforced only in pydantic. Two concurrent registrations for the same address both pass an
      application-level "is it taken?" check and both insert; `find_one({"email": ...})` then
      returns an arbitrary one of them and password reset becomes ambiguous — an account-takeover
      shape. `Database.connect()` is the natural home. Cannot be written or verified without a
      real server, which is why it is here and not done.

- [x] ~~**Three S8.2 landmines, named now so they are not discovered later.**~~ **ALL THREE
      HANDLED — verified in code 2026-09-15.** This line was written as guidance *before* S8.2
      and was never ticked afterwards, so it sat on the board as an open defect for a day while
      the code already addressed it. (1) `@app.exception_handler(CloudSyncDisabled)` at
      `backend/app/main.py:135` maps it to 503, and `_users()`/`_homes()` fail at the top through
      `database.db` rather than branching on `database.enabled`. (2) `UserPublic`
      (`backend/app/cloud_models.py:129`) is the response model and has nowhere to put a hash;
      `/auth/me` returns it — confirmed live, no hash on the wire. (3) `verify_password`
      (`backend/app/auth/passwords.py:42`) returns `False` on a `None` hash before reaching the
      hasher. Original text: (1) `CloudSyncDisabled`
      subclasses `RuntimeError`, so a cloud route hitting it returns a bare 500 — add an exception
      handler mapping it to 503, and make routes fail at the top rather than branching on
      `database.enabled`, which would silently skip writes. (2) Never return a `User` from an
      endpoint: `to_document()` deliberately includes `hashed_password` because it is the
      persistence path, so a public response model is needed. (3) A `User` with
      `hashed_password=None` must never authenticate — that is an explicit acceptance criterion,
      not an implementation detail.

- [ ] **`pymongo`'s command logger writes whole documents at DEBUG.** Harmless today
      (`logging.basicConfig(level=logging.INFO)`), but once S8.4 syncs homes, raising the root
      level to DEBUG would write users' home layouts into the logs. Pin the pymongo logger to INFO
      before then.

- [ ] **The S8 arc now competes with the device pass for the weeks before Oct 24.** **Updated
      2026-09-15:** the backend half is finished and verified end-to-end (S8.1 + S8.2, deployed
      and working), so what remains is **S8.3–S8.4 only — ~13h, and both are iOS**. That sharpens
      rather than softens the trade: the remaining S8 work now queues behind the *same* gate as
      §2's device pass and `FIRST-PRIORITY.md`, competing for the one scarce resource, which is
      time on a working simulator and a physical iPhone. §2's device pass still gates filming and
      has never been started; four bodies of Swift remain uncompiled. A scheduling fact, not an
      argument against the arc — the owner approved it 2026-09-14 — but it belongs on the board so
      the trade is made deliberately rather than by drift.

- [ ] **The S9 Swift has never been compiled ON THIS MACHINE, and its green claim is unevidenced.** Merged to
      `main` 2026-09-14 as `33ef233`. New/changed: `escape_plan/Drill/SemanticMatcher.swift`
      (282 lines, new), `escape_plan/Screens/DiffReviewSheet.swift` (new),
      `escape_plan/Screens/HomeScreen.swift` (modified), plus two new test files
      `SemanticMatcherTests.swift` / `SemanticMatcherRotTests.swift`. None of it has been through
      `xcodebuild` on this machine (owner's standing simulator restriction). **Target membership
      is NOT a concern** — verified 2026-09-14: the project is `objectVersion = 77` with
      `PBXFileSystemSynchronizedRootGroup` on `escape_plan`/`escape_planTests`/`escape_planUITests`
      and zero exception sets, so files are included by folder, not by pbxproj entry (existing
      files like `HomeScreen.swift` have 0 references too). The new files WILL build and the new
      tests WILL run. What is unknown is whether they compile clean and pass.
      What IS verified post-merge: backend **394** not-live pass, EditorCore **295** pass, corpus
      valid (24 sources / 9 files / 2 threshold files).
      **Correction (2026-09-14):** `notes/2026-09-14-S9.2-UI-Setup.md` claims "Verified fixes with
      `xcodebuild test` successfully", so S9.1/S9.2 were probably compiled on the author's machine
      — an earlier version of this line asserted flatly that they never had been, which overstated
      what is known. No count and no result bundle were recorded, so it stays unverified rather
      than green, per this repo's xcresulttool rule. S9.3's note claims no test run at all, and
      S9.2/S9.3 added `ARDrillView.swift`, `DrillRelocalizationController.swift` and
      `DrillRelocalizationView.swift` (481 lines) after that claim. All seven new files parse
      clean (`swiftc -parse`), which is syntax only and not type-checking. Next action: whoever
      has a working simulator records a real count — this stacks on S7.7's STEP 0.

- [ ] **15 `patch_*.py` scratch scripts were committed to the repo root by `0103a74`.**
      `patch_apiclient.py`, `patch_diff*.py`, `patch_homescreen*.py`, `patch_main.py`,
      `patch_object_hazards.py`, `patch_test*.py`, `patch_tests.py`, `patch_trackers.py`. They are
      one-shot string-replacement scripts used to author that commit, not project code, and they
      are dead weight in a repo whose originality story gets read by judges. Left in place during
      the merge deliberately — deleting another author's files is not a merge resolution. Next
      action: confirm with the author, then `git rm` them.

- [x] **`backend/.venv` EXISTS and the backend suite runs here.** The 2026-09-10 claim that no
      interpreter on this machine has `pytest` was wrong — it was tested from the repo root, where
      `.venv` does not exist. The venv is at **`backend/.venv`** (Python 3.13.9, pytest 9.1.1).
      Verified 2026-09-14: `cd backend && .venv/bin/python -m pytest tests/ -m "not live" -q` →
      **394 passed, 13 deselected**. Backend work is NOT unverifiable on this machine. Note the
      invocation: bare `python3` is 3.9 and will still say `No module named pytest`.

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
- [x] **Plain `python3` now works and the machine's trust store validates.** `demo-preflight.py` CAN reach the backend because the preflight script uses a working request mechanism, and one-off HTTP checks used `certifi` (note: `validate.py` itself remains stdlib-only).
- [x] **`/health` reports `v1.0` and that is meaningless** — it is a hardcoded FastAPI `app.version`
      (`backend/app/main.py:145`), not a deploy or schema signal. It read as "stale backend" on
      2026-09-07 and cost a diagnosis. Verified 2026-09-10: already resolved, not by this
      session — `demo-preflight.py:167` deliberately does not print `body["version"]` (comment
      explains why), and `check_deployed_schema()` already probes `/openapi.json` for
      `schema_version` instead, exactly the fix this line asked for.

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
