---
gate_status: open
gate_owner: Anish / Yuki
---

# FIRST PRIORITY — do this before anything else

**Someone with a working iOS simulator must compile and test the app, and record a real
count.** Do this before starting a new session, before S8.2, before any feature work.

Nothing below is a request to write code. It is a request to find out whether the code
that already exists works.

## Why this is first

Four bodies of Swift have landed since the last recorded green iOS run (**615 passed,
2026-09-09**), and none of them has a verified result:

| Landed since | What | Test evidence |
| --- | --- | --- |
| S7.7 | `HazardHuntView` rewrite | none |
| S7.8 | `DiffReviewSheet` + re-scan wiring | none |
| S9.1 / S9.2 | `SemanticMatcher`, `DrillRelocalizationController`, `DrillRelocalizationView` | a note claims `xcodebuild test` passed — **no count, no result bundle** |
| S9.3 | `ARDrillView` (223 lines) | **no test claim at all** |

All seven new files pass `swiftc -parse`, which is syntax only and proves nothing about
whether they compile. The machine this was last worked on **cannot run the simulator**,
so it could not be checked there.

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
3. Only then start new work. The S7.7 **device pass** (`BLOCKERS.md` §2) is the largest
   remaining body of work and gates filming; it has never been started.

## To clear this gate

Change `gate_status:` above to `closed`. That is the intended way — deleting this file
or the hook that surfaces it is not. Leave the body in place as the record of why it
existed.
