---
gate_status: open
gate_owner: Anish / Yuki
---

# FIRST PRIORITY — do this before anything else

**Someone with a working iOS simulator must compile and test the app, and record a real
count.** Do this before starting a new session and before any feature work. (This line used to
say "before S8.2" — S8.1 through S8.4 have all landed since, so read it as "before the next
thing", not as a specific session.)

Nothing below is a request to write code. It is a request to find out whether the code
that already exists works.

## Why this is first

**Six** bodies of Swift have landed since the last recorded green iOS run (**615 passed,
2026-09-09**), and none of them has a verified result:

| Landed since | What | Test evidence |
| --- | --- | --- |
| S7.7 | `HazardHuntView` rewrite | none |
| S7.8 | `DiffReviewSheet` + re-scan wiring | none |
| S9.1 / S9.2 | `SemanticMatcher`, `DrillRelocalizationController`, `DrillRelocalizationView` | a note claims `xcodebuild test` passed — **no count, no result bundle** |
| S9.3 | `ARDrillView` (223 lines) | **no test claim at all** |
| S8.3 (2026-09-15) | `Screens/Auth/` — `AuthGateView`, `LoginView`, `SignupView`, `AuthSheetView`, `RootView` | the logic under them IS tested (84 tests in `tools/editorcore`), the **screens have never been rendered**, and `KeychainTokenStoreTests` has **never executed on any platform** |
| S8.4 (2026-09-16) | `Screens/SyncStatusBadge.swift`, `Persistence/HomeDocumentSyncRepository.swift` | the sync core IS tested (69 tests in `tools/editorcore`), but the **badge has never been rendered** and `HomeDocumentSyncRepositoryTests` has **never executed** |

Everything above now `swiftc -typecheck`s clean — all four targets, against iOS 17.0, via
`scripts/typecheck-ios.sh` (2026-09-16). That resolves every type, member and conformance, so
"do these files even compile?" is answered for the type system. It is **not** a build (no SIL,
no IRGen, no linking, no resource compilation) and **not** a test run, and the machine this was
last worked on still **cannot run the simulator**.

## The command

```bash
xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build-merge CODE_SIGNING_ALLOWED=NO
```

**Read the count from the result bundle, never the console.** The console prints
`Executed 16 tests` because the unit target runs under Swift Testing:

```bash
xcrun xcresulttool get test-results summary --path <bundle>.xcresult
```

A red run is ~1-in-3 environmental flake — re-run once before believing it.

## Then, in order

1. Record the real count in `BLOCKERS.md`'s header stamp, replacing the stale 2026-09-09
   line. If it is red, put the failures in `BLOCKERS.md` §3 — do not fix and move on
   silently.
2. **Fix the two defects already found by review** (`BLOCKERS.md` §3, both found
   2026-09-14, neither seen on a device):
   - `ARDrillView.swift:68` pins every AR waypoint to `1.0` height with no floor term, so
     a `twostory.json` route draws both levels at one height.
   - `SemanticMatcher` scores a room with no doors as a perfect `0`, so it outranks
     correctly-matched rooms and can push the right room out of the candidate list.
3. **Confirm the two never-executed test classes actually pass**, and say so with a count.
   Both are written, both run the same contracts their in-memory counterparts already pass, and
   neither has ever been executed anywhere:
   - `escape_planTests/KeychainTokenStoreTests.swift` (S8.3) — until it runs, "the token
     persists across app restarts" is argued, not verified.
   - `escape_planTests/HomeDocumentSyncRepositoryTests.swift` (S8.4) — the ping-pong guard.
     `HomeDocumentStore.save(model:)` stamps `meta.modified` with the current time; if the
     sync repository does not pass `now:` a pulled home looks newer than the server's copy and
     two devices trade it forever. The EditorCore suite cannot reach this — its in-memory
     repository stores models verbatim and so cannot reproduce the stamping at all.
4. **Walk the two S8 flows by hand while you have the simulator**, and record what you saw in
   `BLOCKERS.md` §2: register → sign out → sign in → relaunch (S8.3), then sign in → sync →
   edit a home → sync, watching the badge (S8.4).
5. Only then start new work. The S7.7 **device pass** (`BLOCKERS.md` §2) is the largest
   remaining body of work and gates filming; it has never been started.

## Who can do this — confirmed 2026-09-16

**Not the repo owner (P3).** Their machine cannot run the simulator; this was re-confirmed
2026-09-16 when they were asked directly ("cant run it rn so leave it as a task for the
others"). So this gate is genuinely blocked on **Anish / Yuki**, not merely unassigned, and it
will not clear itself by another backend-side session going well.

Everything that CAN be checked without a simulator has now been: the whole app type-checks
clean against the iOS 26.5 SDK in both configurations and at the new iOS 17.0 floor, the
Foundation-only layers carry 388 executing tests, and the auth wire contract has been verified
against the deployed backend. What remains genuinely needs a device or a simulator.

## To clear this gate

Change `gate_status:` above to `closed`. That is the intended way — deleting this file
or the hook that surfaces it is not. Leave the body in place as the record of why it
existed.
