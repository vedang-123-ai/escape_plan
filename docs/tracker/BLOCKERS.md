# BLOCKERS — what is not done

**This file is the board.** Anything blocking, unverified, or not-yet-done gets written here
the session it is discovered. [`TODO.md`](TODO.md) holds the long-tail backlog; this file holds
what actually stops the project from shipping, ranked by what is on the critical path.

**Deadline: submit by Oct 24, 2026.** End-to-end demo path working by Oct 5.

_Last verified 2026-09-16 on `s8-4-ios-cloud-sync` (the S8.4 iOS cloud-sync session). **Re-run and
green this session:** EditorCore **515** pass (was 388; **+127** — S8.4's sync layer, plus
`SemanticMatcher` and `WallGrouping` newly symlinked into the package and so tested here for
the first time, plus the ported `SchemaV2ContractTests` —
the client, the reconciler, the fingerprint, the sidecar and the manager are Foundation-only and
symlinked into `tools/editorcore`, so they execute on a machine with no simulator). Backend
**556** pass / 1 skipped / 13 deselected (was 526; **+30** — the pymongo log-privacy guard,
the mounted-object routing guard, the fixture-coverage guards, and 13 contract tests ported off
`my-s6-1-and-policy`). Corpus valid
(**24** sources, **9** files, **2** threshold files), unchanged.

`scripts/typecheck-ios.sh` green on all four targets against **iOS 17.0**: the app at **161**
files in both `-DDEBUG` and release, `escape_planTests` at **73**, `escape_planUITests` at **9**.

**Read that claim narrowly.** It resolves every type, member and protocol conformance across the
module, so the new Swift does type-check. It is **not** a build (no SIL, no IRGen, no linking, no
resource compilation) and it is **not** a test run. It does not close §0; it narrows what §0
still has to find.

**NOT run this session:** `xcodebuild test` — this machine cannot. The iOS count remains **615
passed, 0 failed, 8 skipped** as of 2026-09-09 (`Test-escape_plan-2026.09.09_23-31-03--0700.xcresult`),
which now predates six bodies of Swift including S8.3's and S8.4's. **Neither S8.3 nor S8.4 is
ticked in TODO.md** — their acceptance criteria need a simulator, and one of S8.4's needs two
devices. Treat the 615 as stale, not as a pass.
`RouteRedrawAfterEditUITests` run live separately with `TEST_RUNNER_ROUTE_REDRAW=1` against a local
backend — still red, see §3._


**Rules**
- One line per blocker: what it blocks · who can clear it · the concrete next action.
- Remove an item only when you personally verified it. "The code exists" is not verification.
- Discovered something undone? It goes here, this session. Not in a note, not in your head.

---

## S11 · The reframe arc: where every open item now lives

Everything below this section is the pre-S11 board, still true unless a line says otherwise. The plan for closing it is
[`../playbook/README.md`](../playbook/README.md): 13 sessions, three lanes, one branch each. Put your findings under your
own session heading here so three people editing at once do not collide.

**Baseline verified 2026-09-18 on `s11-0-baseline`** (local `main` merged with `origin/main`, 164 commits behind):
EditorCore **516** passed, 0 failed (515 from origin + the new 30 degree matcher test); backend **556** passed, 1 skipped,
13 deselected; corpus valid (24 sources, 9 files, 2 threshold files); `scripts/typecheck-ios.sh` ok on all four targets
against iOS 17.0. **`xcodebuild test` was NOT run**, so the iOS app count is still unknown (last recorded: 615 on
2026-09-09, stale). That is what S11.8 is for.

| Open item on this board | Owned by |
| --- | --- |
| §0 first priority: run the iOS suite, record real counts | S11.8 |
| §1 Anthropic credits, bearer token mismatch (owner-only) | owner; S11.4 covers what works without a key |
| §2 device checklist 2.1-2.3, 2.7-2.8 (camera, frame rate, framing, floors) | S11.9 |
| §2 device checklist 2.4-2.6, 2.9, real-scan verification, AR Drill on device | S11.10 |
| S8 auth screens, Keychain, sync criteria that need a simulator or two devices | S11.7 (signed-out proof, privacy, delete) and S11.8 |
| S8.4 "do local homes belong to whoever signs in" (ruled 2026-09-16: first account adopts, second never) | S11.7 confirms the ruling in the UI |
| §3 hazard-engine defects BUG-01..04 | S11.3 |
| §3 `RouteFinding.citation`, earthquake/tornado depth | S11.2, S11.1 |
| §4 flake, console undercount | S11.8 |
| §5 submission path (script, table-read, film, submit) | S11.12, S11.13 |

### New findings from the baseline session (2026-09-18)

- [ ] **The baseline is not pushed.** `s11-0-baseline` is merged locally only. Nobody else can branch from it until the
      owner merges it to `main` and pushes. Next action (owner): `git switch main && git merge --no-ff s11-0-baseline &&
      git push`, then tell the other two to `git fetch origin`.
- [ ] **`.claude/settings.json` and the hook scripts still need owner-approved edits.** The planned changes were blocked
      by the auto-mode classifier as self-modification and were NOT applied: (1) wire the new
      `.claude/hooks/pre-commit/branch-guard.sh` (written, unexecutable, unwired) into PreToolUse(Bash) and `chmod +x`
      it; (2) add shared allow rules for `xcodebuild test`, `swift test`, `xcrun xcresulttool|simctl`, `bash scripts/*`,
      `python3 scripts/*`, `git fetch|switch|branch|worktree list`; (3) update the stale wording in
      `handoff-banner.sh` (it still says "615 passed" and "S8.2") and `schema-guard.sh` ("team sign-off"). Next action
      (owner): apply them yourself or tell Claude to.
- [ ] **SemanticMatcher candidate filter: perimeter or bounding-box area?** Origin uses area; unmerged local commit
      `dde7f08` argued for perimeter (and flipped the rotation, which a 30 degree known-answer test disproved). Decide with
      a failing real-scan case, not by argument. Owner: S11.10. See `decisions.md` 2026-09-18.
- [ ] **Stale worktree with uncommitted files:** `../wt-s6-1` (branch `lane-a-s6.1`, merged into `main`) holds modified
      or untracked files, so it was not removed. Next action (owner): look at `git -C ../wt-s6-1 status`, keep or discard.
- [x] **`origin/s6-1-schema-2-0` is 12 commits ahead of `main`** and unmerged (old S6.1 policy branch; some of its
      contract tests were ported by origin). Decide: archive-tag and delete, or merge. **Resolved 2026-09-19: merged
      (`d6e982c`) — and the merge broke the backend, see "Out-of-band" below.** Also three
      `subagent-*` branches and worktrees under `~/.gemini/antigravity/...` were left alone.
- [x] **`backend/.venv` created on this machine 2026-09-18** (Python 3.13, `pip install -r requirements.txt`);
      backend suite 556 passed there. It is gitignored, so each person creates their own.

### Out-of-band 2026-09-19 · the `s6-1-schema-2-0` merge broke the backend and failed the Render deploy

- [x] **`main` was red and undeployable from `d6e982c` (2026-09-19 04:40 UTC) to `cf9ea46`.** Render deploy
      `6537170320` failed 73s in; `backend/app/builder/actions.py` imported `SCHEMA_VERSION` from `app.models`,
      which has never defined it, so `uvicorn app.main:app` could not import and the service never bound a port.
      The backend suite was 13 collection errors, not 556 passed. **Cause: a textually clean merge.** `d6e982c`
      took main's `models.py` (schema 2.1, no such constant) and `s6-1-schema-2-0`'s `actions.py` (which needs
      the 2.0-era constant) — different files, so git reported no conflict, and the gate was not run before the
      push. Fixed on `fix-schema-version-import` by pointing at `schema_migrator.CURRENT_VERSION`, main's existing
      single source of truth; regression test added in `test_builder_actions.py`. Backend **556 passed, 1 skipped,
      13 deselected** verified on that branch 2026-09-19.
- [ ] **The Render redeploy is unverified.** Prod served the 2026-09-17 deploy (`b45446a3`) throughout — `/health`
      returned 200, after a ~14s free-tier cold start — so nothing was down, but the deployed backend is two days
      behind `main` until the next deploy goes green. Next action (whoever pushes): watch deployment status on the
      merge commit and confirm `success`, then re-check `/health`.
- [ ] **Nothing in this repo runs the gate before a deploy.** There is no `.github/workflows/`; Render deploys
      every push to `main` and a broken import is only caught by the deploy failing. A CI job running the backend
      suite and the corpus validator on push would have caught this before Render did. Owner: unassigned — see
      `TODO.md` if it is not picked up.

### S11.1 to S11.13: session findings (append under your heading)

_S11.1_ none yet · _S11.2_ none yet · _S11.3_ none yet · _S11.4_ none yet · _S11.5_ none yet · _S11.6_ none yet ·
_S11.7_ none yet · _S11.8_ none yet · _S11.9_ none yet · _S11.10_ none yet · _S11.11_ none yet · _S11.12_ none yet ·
_S11.13_ none yet

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

      **Widened 2026-09-16 (S8.4): the "four bodies of Swift" above is now SIX** — the list
      predates S8.3's auth screens and S8.4's sync badge, both of which landed since and neither
      of which has been built or run either. `FIRST-PRIORITY.md`'s table has been updated to
      match; this paragraph and the header stamp both say six. The run has two more things to
      check and two more reasons to happen. See §2.

      **Narrowed further 2026-09-16:** the two TEST targets type-check too — `escape_planTests`
      (**70** files as of S8.4) and `escape_planUITests` (9) both clean against the app's
      testable module, so `@testable import escape_plan` resolves and every unit-test and
      UI-test method references real symbols. That removes the likeliest reason the `xcodebuild`
      run would die in its first minute on a machine that is hard to get time on.
      Reproduce with `scripts/typecheck-ios.sh`.

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

- [ ] **The shared bearer token in `.env` does NOT match the one on the deployed backend.**
      **Narrowed 2026-09-16, and the remaining half is the owner's.** The file half is done:
      `escape_plan/BackendConfig.local.json` now exists, created from `BACKEND_BEARER_TOKEN` in
      the gitignored root `.env` (15 chars), and preflight reports `PASS app bearer token`.
      **But `/routes` still returns 401** — `deployed schema` and `/health` both PASS, so the
      backend is healthy and current (schema 2.1, 15 routes); it is specifically the token that
      is wrong. Either `.env` is stale or Render's `BACKEND_BEARER_TOKEN` was rotated.
      **Only the owner can settle it** (it needs the Render dashboard): make the two match, in
      whichever direction is correct, then re-run preflight. Until then a fresh install gets
      **401 on every deterministic endpoint** — `/routes`, `/score`, `/convert`, `/evacuate` —
      which is the entire demo path. This is the single closest thing to the critical path for
      filming.

      **Run preflight with `backend/.venv/bin/python`, not `python3`** — see §4.

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

- [x] ~~**S8.4 note: a home that has been through the server differs from the local one BY BYTES,
      though not by value.**~~ **HANDLED 2026-09-16 in S8.4.** The dirty check is
      `HomeFingerprint`, which canonically re-encodes the **decoded** `HomeModel` and digests
      that, so a byte-different-but-equal copy fingerprints identically and never reads as an
      edit. `HomeFingerprintTests.testAServerRoundTripDoesNotLookLikeAnEdit` pins it against the
      REAL bytes `model_dump_json()` emits for `bungalow.json` — not a hand-written
      approximation — and a companion test asserts those bytes genuinely differ from the fixture
      so the first one cannot pass vacuously. Original finding: pydantic serialises absent
      optionals as explicit `null` and fills `objects: []`, so the JSON that comes back has 21
      keys the sent JSON did not; any dirty-check comparing encoded JSON would have marked every
      synced home permanently modified.

- [ ] **S8.4's acceptance criterion 2 CANNOT be met on this machine: "App pulls down homes
      created on other devices" needs two physical devices.** There is one. What the rule
      reduces to is tested — `SyncManagerTests.testAHomeCreatedOnAnotherDeviceIsWrittenToThisOne`
      drives the real `CloudHomesClient` against a fake `/homes` backend and asserts the home
      lands verbatim, under the same `home_id`, with `meta.modified` intact — and
      `testAPulledHomeIsNotImmediatelyPushedBack` proves it does not bounce straight back. **A
      test is not a second phone.** What remains unknown is everything between the two: whether
      device B's `GET /homes` actually returns device A's record from live Atlas, whether the
      schema `home_id` really survives both round trips, and whether two real devices converge
      rather than fighting. Next action: sign the same account in on two phones, create a home on
      A, sync, sync on B, confirm it arrives with the same `home_id` and the same
      `meta.modified`. Then edit it on both while offline and sync both, to exercise the
      last-write-wins tiebreak against real clocks.

- [ ] **UNRESOLVED SCOPE QUESTION: do local homes belong to whoever signs in?** The app is
      local-first, so a home document on the device belongs to the device, not to an account.
      The consequence, surfaced by the S8.4 review: when any user signs in, **every** home on
      that device is pushed into **their** account — including homes a previous user of the
      same device created, `meta.address_optional` and `household` included. S8.4 fixed the
      stale-record half of this (the sidecar is now scoped by `AccessToken.subject`, so user B
      cannot act on user A's server record ids), but not the question itself, which is a
      product decision rather than a bug: answering "no, they don't" means deciding what
      happens to those homes instead. Shared devices are plausible for this app's audience
      (a family phone, a demo iPad). **Owner's call.** Next action: decide, then either leave
      it as documented behaviour or gate the first push behind an explicit "add these homes to
      your account?" prompt.

- [ ] **Two test classes have never executed on any platform, and both cover things nothing
      else does.** `escape_planTests/KeychainTokenStoreTests.swift` (S8.3 — token persistence)
      and `escape_planTests/HomeDocumentSyncRepositoryTests.swift` (S8.4, 14 tests). The second
      is not optional coverage: `Persistence/` is not symlinked into `tools/editorcore`, so the
      package's `InMemoryHomeRepository` — whose `writePulledHome` is a single dictionary
      assignment — **cannot reproduce** either hazard the real adapter defuses (the
      `meta.modified` re-stamping that makes two devices trade a home forever, and the guard
      against overwriting an open editor). Until it runs, those two guarantees are argued from
      code, not verified. Folded into `FIRST-PRIORITY.md` step 3.

- [x] ~~**Sync fires at launch, on sign-in, and on a badge tap — an EDIT does not trigger one.**~~
      **DECIDED AND WIRED 2026-09-16**, as the line predicted: editor CLOSE plus a foreground
      observer, deliberately not autosave. The close sync is gated on something actually having
      been committed, so a plain tab switch does not fire a `GET` at a service measured at a
      42 s cold start; the foreground sync is on `scenePhase` becoming `.active`, because iOS
      keeps an app suspended for days and a user who never fully quits would otherwise sync once
      at install and never again. **Unverified like everything else in the UI layer** — neither
      trigger has been observed firing on a device.

- [ ] **S8.4's other two criteria are simulator-gated, like S8.3's.** "`HomeModel` changes are
      successfully pushed to `/homes`" has only ever run against `AuthStubURLProtocol`; no iOS
      binary has been built or launched, so the app has never sent a real request to the deployed
      backend. (The wire contract itself WAS walked by hand on 2026-09-16 — see the closed item
      at the top of this section — which proves the contract, not the app.) "Sync state correctly
      reflects in the UI" rests on `SyncStatusBadge`, which **has never been rendered**: its
      layout, its popover, the `.symbolEffect(.pulse)` spinner and its VoiceOver value are all
      unobserved. Next action: run the app, sign in, and walk sync → edit → sync while watching
      the badge.

- [ ] **Nothing has ever run below iOS 26.5, and the deployment target is now 17.0.**
      Changed 2026-09-16 (see §3) because 26.5 was an Xcode default that would have made the
      app installable only on the newest iOS. The lower floor is compile-verified, not
      run-verified. **The owner CANNOT check this: only the iOS 26.5 runtime is installed and
      there is not enough disk space for the ~7 GB older-runtime download** (confirmed
      2026-09-16). It needs whoever has room, or a physical device still on 17.x/18.x — most
      phones auto-update, so that may not exist either.
      **Mitigated as far as a compiler can:** all three targets — app (150 files, both
      configurations), `escape_planTests` (64), `escape_planUITests` (9) — type-check clean
      against iOS **17.0**, so nothing anywhere references an API newer than the floor. What a
      type-check cannot see is runtime behaviour: SwiftUI layout, `@Observable`, RoomPlan/ARKit
      availability at launch.
      **Judgement, stated so it can be overruled:** 17.0 is still right. The failure it avoids
      (a judge cannot install the app at all) is certain and total; the one it risks (a layout
      quirk on an old iOS) is possible and partial. Next action: `scripts/typecheck-ios.sh 18.0`
      occasionally as cheap insurance, and a spot check if anyone ever has the space.

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

- [x] ~~**S9.3 renders every AR waypoint at a hardcoded 1.0 m, ignoring which floor it is on.**~~
      **FIXED IN CODE 2026-09-16 — still never seen on a device.** Height now comes from
      `DollhouseGeometry.floorBaseHeights(of:)` keyed by the waypoint's own `floor_id`, plus a
      1.0 m hover. That helper is the SAME stacking the dollhouse uses to place its floors,
      reused rather than reimplemented, so the AR view and the 3D view cannot disagree about
      where a floor sits. An unknown `floor_id` falls back to 0 rather than dropping the
      waypoint — a marker in the wrong place beats a hole in the path the user is following.
      **Not verified:** this is ARKit inside a `UIViewRepresentable` and there is no test for
      it on any machine — it type-checks and nothing more. Confirm on the device pass by
      standing upstairs in a `twostory` drill and checking the ground-floor leg is below you
      rather than at eye level. Original finding: `wpNode.position = SCNVector3(Float(wp.x),
      1.0, Float(wp.y))` had no floor or level term anywhere in the placement, so a route from
      an upstairs bedroom to an exit drew the whole path at one height.

- [x] ~~**A room with no doors scores a perfect 0 and outranks correctly-matched rooms.**~~
      **FIXED AND TESTED 2026-09-16.** Candidates whose score came from actually matched doors
      are the only ones ranked; a no-evidence candidate carries a 0 meaning "nothing to
      compare", not "a perfect fit", and is kept out of `best` selection.
      **Deliberately NOT changed:** when NOTHING has door evidence the matcher still returns
      `.ambiguous` rather than guessing — a 180° rotation cannot be resolved without doors.
      The existing `testNoDoorAmbiguity` caught an attempt to widen the fix to `.noMatch`,
      which is the second time this session a pre-existing test earned its keep.
      **This one IS verified on this machine**, unlike almost everything else in §3:
      `SemanticMatcher.swift` is now symlinked into `tools/editorcore` (its RoomPlan half was
      already `#if canImport(RoomPlan)`-guarded, so it compiles as pure Foundation + simd on
      macOS), and its tests moved to `escape_planTests/EditorCore/`. Nine tests run under
      `swift test` — three of them new, and the regression test was confirmed to FAIL against
      the old ranking before the fix landed, so it is not vacuous. Original finding: the
      door-distance branch fell through to `totalDist = 0` whenever *either* side had no doors,
      and lower is better, so a candidate whose openings were missing always sorted above a
      correct room that matched its doors at 0.35 m — absence of evidence scored as perfect
      evidence, which pushed the right room out of the candidate list entirely.

- [x] ~~**RoomPlan splits long walls, and `extractedLongestWall` does not account for it.**~~
      **FIXED AND TESTED 2026-09-16.** Segments now merge when parallel **and collinear** —
      parallel alone would fuse the two long sides of a corridor into one wall — and the merged
      length is the span along the wall's own direction, so the doorway gaps count toward it.
      The merging lives in a new `WallGrouping` over plain values, deliberately **outside** the
      `#if canImport(RoomPlan)` block: logic written against `CapturedRoom` cannot run on a
      machine with no simulator, which is how this survived two audits that both identified it
      correctly. **11 tests**, including the old longest-raw-segment rule written out as an
      executable statement of the defect, and a tolerance test for the few-degrees wobble a real
      scan produces. Original finding: a 10 m wall broken into three segments by doors lost to
      an unbroken 4 m perpendicular wall, producing a permanent 90° alignment error that
      everything downstream keys off.
      **Still only fully provable on a real scan** — the tolerances (10°, 0.25 m) are reasoned,
      not measured against RoomPlan output. Carried into the §2 device pass.

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
      its STEP 0** (`archive/playbook-v1:docs/playbook/S7-2.md`), so it is the first thing that session does rather
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
- [x] ~~**Routing is elevation-blind — latent, but mechanically real.**~~ **FIXED AND TESTED
      2026-09-16.** `build_room_grid` now skips objects that do not obstruct the floor, and
      `obstructs_floor` decides that on **`mounted`**, not `elevation_m`: `mounted` is the
      schema's "how is this installed" and means the thing is not standing on the floor,
      whereas a box raised on a table is still something you cannot walk through. Four tests,
      including the unmounted twin of the same object so the guard cannot pass vacuously, and a
      sweep asserting every other fixture object still obstructs.
      **What it deliberately does not model** — how far a mounted object protrudes — is
      documented at the helper and errs in the safe direction for egress. Original finding:
      moving `o_u_tv_over_bed` mid-room dropped free cells 5476 → 5296; it did not bite only
      because the seeded TV overlaps the bed, so the fixture hid it.
      **Note the first version of the test passed for the wrong reason:** it placed the object
      at the polygon centroid, which falls OUTSIDE a `jagged` room, so it blocked nothing.
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
      typechecked by nothing. **Handed to S7.7 as its STEP 0** (`archive/playbook-v1:docs/playbook/S7-7.md`) so it
      is the first thing that session does — one `xcodebuild build`, spelled out there — rather
      than a line here someone can skim past. Do not tick this on the strength of EditorCore
      being green; it does not compile SwiftUI.

- [ ] **The hunt's scan-seeding has never met a real scan.** The new relabel questions ("the
      scan found a tall storage unit — is it a bookcase?") are driven by scanned objects, and
      every test feeds them synthetic ones. Whether RoomPlan actually returns a tall `storage`
      for a real bookcase, or an `appliance` for a real water heater, is unknown. Folded into
      the §2 device pass via S7.7's STEP 0 — walk the hunt in a real scanned room.

- [x] ~~**19 contract tests exist only on the `my-s6-1-and-policy` branch**, not on `main`.~~
      **PORTED 2026-09-16 — and two of them found real defects the moment they landed.**
      13 backend invariants + 3 routing-neutrality/safety-point tests + all 8 of
      `SchemaV2ContractTests.swift`.
      **`test_the_apps_bundled_fixtures_match_the_contracts`** caught `escape_plan/Fixtures/`
      (byte-identical copies bundled into the iOS app, because it cannot reach outside its
      bundle) having silently desynced from `schema/fixtures/` — drift created hours earlier by
      this same session's fixture seeding, which nothing on `main` could see. Both re-copied,
      and the guard was confirmed to fail on a deliberately corrupted copy before being trusted.
      **`SchemaV2ContractTests`** caught `EditorValidation`'s global id pass claiming floors,
      rooms, openings, objects, stairs and profiles but **not safety points** — so the editor
      accepted a home pydantic rejects with a 422, and the user found out at save time from an
      error that does not name the offending id. Now checked client-side like every other kind.
      **Deliberately NOT ported:** the branch's assertions about which fixture carries which
      household and scan date. That seeding was superseded the same day (see the line below),
      and porting both would have put two contradictory claims in one suite.
- [x] ~~**Fixtures are thinly seeded.**~~ **SEEDED IN ONE PASS 2026-09-16**, as the line asked.
      `apartment` is now the scanned, owner-occupied, hearing-impaired side and gains Biscuit
      the cat; `jagged` is scanned and gains `vision_impaired`; `bungalow` and `twostory` stay
      unscanned, and `bungalow` stays household-less and profile-less as the plain baseline —
      **a field present everywhere is as untested as one present nowhere**, which is how
      `meta.last_scanned` ended up with an iOS rescan prompt no fixture could trigger.
      No declared equipment anywhere: both the empty and the `smoke_alarm` cases are already
      covered by unit tests that build a `Household` directly, and declaring an alarm would
      raise the score of the fixture whose whole job is to be the deliberately-bad one.
      `backend/tests/test_fixture_coverage.py` pins all of it, and **immediately found a third
      gap this line never mentioned**: the `pet` tag, which drives a checklist item and its own
      gait in the evacuation animation, appeared in no fixture at all.

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

      > **Original finding (2026-09-14), kept for the reasoning — NOT an open item.** It carried
      > an unchecked `- [ ]` box until 2026-09-16, so every scan of this board counted a
      > resolved defect as open. Preserved text follows.
      >
      > ~~S8.2 must create a unique index on `User.email` before it writes a login path.~~ There is
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

- [x] ~~**`pymongo`'s command logger writes whole documents at DEBUG.**~~ **FIXED AND TESTED
      2026-09-16.** `backend/app/main.py` pins `pymongo`, `pymongo.command`,
      `pymongo.connection` and `pymongo.serverSelection` to INFO explicitly, so the protection
      survives someone raising the ROOT logger to DEBUG while chasing an unrelated bug — which
      is the scenario that matters, since "we happen to run at INFO" is a coincidence rather
      than a safeguard. `backend/tests/test_logging_privacy.py` (3 tests) sets the root logger
      to DEBUG and asserts pymongo still will not emit at that level, that INFO and above still
      flow, and that the app's own loggers are left debuggable. Backend **529** pass, up from
      526. Original finding: pymongo logs every command with the full document at DEBUG, and
      since S8.4 those documents are users' home layouts — floor polygons, room names,
      `meta.address_optional`, household composition — which on a hosted service are retained
      and readable by anyone with dashboard access.

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

- [x] ~~**15 `patch_*.py` scratch scripts were committed to the repo root by `0103a74`.**~~
      **DELETED 2026-09-16 on the owner's explicit instruction.** There were **13**, not 15 —
      the original count was wrong. Verified before removing: each is a handful of lines that
      opens a source file, does `str.replace`, and writes it back (the edits are long since
      applied), and nothing in the repo references any of them except this board and the
      activity log. Backend still **529** pass afterwards. They were dead weight in a repo whose
      originality story gets read by judges. Left in place at merge time deliberately, because
      deleting another author's files is not a merge resolution — the owner has now made that
      call.

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
- [ ] **CORRECTION 2026-09-16: plain `python3` does NOT validate TLS on this machine.** This
      line previously claimed the opposite, marked done. Measured today: `python3
      scripts/demo-preflight.py` fails `/health`, `deployed schema` AND `/routes` with
      `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate` — the system Python
      3.9 has no usable trust store. The SAME script under `backend/.venv/bin/python` (3.13.9,
      which has `certifi`) reaches the backend fine and passes `/health` and the schema check.
      So the earlier claim was true of the venv interpreter and false of the one the command
      line actually names, and anyone following the documented `python3 scripts/demo-preflight.py`
      would read three TLS errors as "the backend is down" minutes before filming.
      **Always `backend/.venv/bin/python scripts/demo-preflight.py`.** Next action: either fix
      the system trust store (`Install Certificates.command`) or change the documented command
      everywhere it appears — `CLAUDE.md`, `FIRST-PRIORITY.md` and §5 all still say `python3`.
      Note `backend/corpus/validate.py` is unaffected and must stay stdlib-only.

      **Also worth knowing:** preflight exits **0 even when it reports NOT READY TO FILM**, so
      "confirm exit 0" is not a usable gate. Read the summary line.
- [x] **`/health` reports `v1.0` and that is meaningless** — it is a hardcoded FastAPI `app.version`
      (`backend/app/main.py:145`), not a deploy or schema signal. It read as "stale backend" on
      2026-09-07 and cost a diagnosis. Verified 2026-09-10: already resolved, not by this
      session — `demo-preflight.py:167` deliberately does not print `body["version"]` (comment
      explains why), and `check_deployed_schema()` already probes `/openapi.json` for
      `schema_version` instead, exactly the fix this line asked for.

---

## 5 · Submission path

> Owned by [S11.12](../playbook/S11-12.md) (script, storyboard, truth audit) and [S11.13](../playbook/S11-13.md) (film, submit).

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
