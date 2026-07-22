# Integration — five parallel lanes (S2.2, S2.3, S3.3, S3.4, S3.5)

- **Who:** P3
- **Date(s):** 2026-07-22
- **Status when I stopped:** all five lanes integrated, every automated suite green, S3.4's
  cross-lane TODO closed. Nothing verified by eye on a screen — that's the whole remaining list.

## What happened

Five sessions ran in parallel and were *meant* to run in separate git worktrees. They didn't —
`git worktree list` shows one entry and `.git/worktrees` doesn't exist. All five wrote into the
same working tree on `main`. So there was no merge to perform: the "merge" was already done,
implicitly and unsupervised, by five agents editing shared files in sequence.

That made the job verification, not integration. What I checked and found:

- **Shared-file collisions survived intact.** `EditAction.swift` was the big risk (S2.2 adds
  `dragOpening`/`addStairs`/`deleteStairs`, S3.4 adds `addProfile`/`updateProfile`/`deleteProfile`,
  and `undoLabel`/`isContinuousDrag` are exhaustive switches). Both lanes' cases *and* all their
  switch arms are present. Same for `HomeScreen.swift`, where S3.5 explicitly noticed S3.4's
  concurrent edit and merged the two context menus by hand instead of clobbering it.
- **No compile-level collision between the three new `APIClient` extensions.** S2.3, S3.3, and
  S3.5 each added a sibling extension file; none declares a colliding helper.
- **Two false alarms of my own, recorded so nobody re-raises them.** I initially reported
  `ScoreScreen`/`ProfilesScreen` as orphaned dead code — wrong, they're reached via
  `navigationDestination` in `HomeScreen.swift:46,49`; my grep pattern was too literal. And S3.4
  reported a build break at `EditorSceneController.swift:152` (missing `Selection.stairs`); S2.2
  had already fixed it by the time I looked.
- **One real, genuinely pre-existing bug fixed.** `testBundledFixturesMatchSchemaFixtures` has
  been failing since the 2026-07-16 model-layer unification, which deleted
  `escape_plan/Resources/Fixtures/` (fixtures moved to `escape_plan/Fixtures/`) without updating
  the test. Two separate lanes reported it as "pre-existing, unrelated, not mine" and moved on,
  which is exactly how a red suite becomes background noise. Repointed the path — all three
  fixtures are byte-identical, so the drift guard passes and is doing its job again.
- **Closed the one deliberate cross-lane gap.** S3.4 deferred "live route re-fetch on profile
  switch" because S2.3 wasn't in yet, and left a `TODO(integration)`. S2.3 had already left the
  matching `profileID:` parameter on `fetchRoutes`. Wiring: a "Who" segmented picker in
  `PlanScreen.routeControls` that re-fetches on change and jumps to the selected profile's
  bedroom.

## Verification

All green, on this machine, today:

- `swift test --package-path tools/editorcore` — 115/115
- `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — full
  `escape_planTests` + UI tests, **no failures** (first time the suite has been clean)
- `python3 -m pytest backend/tests/ -m "not live"` — 195 passed, 9 deselected
- `python3 backend/corpus/validate.py` — 11 sources, 6 files, thresholds consistent

## Decisions / surprises

- The worktree isolation everyone assumed was in place was never there. Five agents mutating one
  tree happened to work — `EditAction.swift` came out correct — but that was luck plus careful
  agents, not a guarantee. If this pattern gets repeated, actually create the worktrees.
- A real iOS 26.5 simulator runtime is installed (three lanes independently rediscovered this).
  Every "no simulator, so acceptance is code-done-only" deferral from S1.3/S1.4/S2.1/S2.4 is now
  worth revisiting — see the S2.2 decisions.md row.
- Both changes I made are in decisions.md.

## Questions for teammates

- @P1 — S3.3 found `/chat` returns a plain-text **500**, not 502, when `ANTHROPIC_API_KEY` is
  unset: `api_chat.post_chat` catches `ChatGroundingError` but not the base `GroundingError` that
  `/explain` handles. Worth a one-line fix before the live key session.
- @P2 — everything below is yours; none of it needs code.

## Next steps

Nothing left is a coding task. In one simulator session someone can clear most of it:

1. **S3.4 acceptance (now unblocked):** open a home → Profiles → add "Grandpa"
   (mobility_limited) and "Maya" (child) → Plan tab → switch the "Who" picker and watch the 3D
   route change. That's the demo money shot and the S3.4 handoff recording.
2. **S2.2's three criteria:** drag an opening along a wall, place stairs between floors, undo/redo
   a drag. Code + unit tests are done; nobody has touched the screen.
3. **S2.3:** eyes-on pulse/tour smoothness, plus the acceptance recording (twostory upstairs
   bedroom → both routes; apartment → warning badges).
4. **S3.5:** "breakdown screen legible" — the only unticked S3.5 box.
5. **S3.3:** blocked on `ANTHROPIC_API_KEY` on Render, not on a device.

Every device-only acceptance box across all five lanes is deliberately still unchecked.
