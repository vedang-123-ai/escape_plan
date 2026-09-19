---
name: verify-all
description: Run the full green gate for the whole repo — EditorCore SwiftPM tests, backend pytest, corpus validation, the iOS type-check, and (only where a simulator exists) the iOS app suite read from its result bundle. Use before declaring work done, after a merge/integration, or whenever the user asks to "verify", "run the tests", "check it's green", or "run the gate".
---

# verify-all

Five surfaces. Four of them run anywhere; the fifth needs a simulator that **the owner's machine
does not have**. Run everything you can, and report what you could not run as *not run* — never
as passing.

## Use the right interpreter

`python3` on this machine is **3.9**, has no `pytest`, and has **no usable TLS trust store** —
it fails `demo-preflight.py` with `CERTIFICATE_VERIFY_FAILED` on every HTTPS call, which reads
as "the backend is down". The repo venv is at **`backend/.venv`** (3.13.9). Use it for
everything except `validate.py`, which is deliberately stdlib-only so it can run before the
backend env exists.

## 1–4: the surfaces that always run

```bash
# 1. EditorCore — pure Foundation, macOS, ~8s. Auth, Sync, the editor core, SemanticMatcher.
swift test --package-path tools/editorcore

# 2. Backend — ~30s. `-m "not live"` skips the tests needing ANTHROPIC_API_KEY.
backend/.venv/bin/python -m pytest backend/tests/ -m "not live" -q

# 3. Corpus — stdlib only, instant.
backend/.venv/bin/python backend/corpus/validate.py

# 4. iOS type-check — all three targets, both configurations, NO simulator needed, ~3 min.
scripts/typecheck-ios.sh
```

**On (4):** it resolves every type, member and conformance across app, unit tests and UI tests.
It is far more than `swiftc -parse`. It is **not a build** (no SIL, no IRGen, no linking, no
resource compilation) and **not a test run**. Report it as a type-check, never as a passing
suite — see `docs/tracker/BLOCKERS.md` §0.

## 5: the iOS suite — only where a simulator exists

The owner's machine cannot run this. If `xcrun simctl list devices available` shows no usable
runtime, say so and stop; do not report the last known count as though it were this run's.

```bash
xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build-merge CODE_SIGNING_ALLOWED=NO
```

### Read the count from the RESULT BUNDLE, never the console

The console prints `Executed 16 tests` because the unit target runs under Swift Testing, which
`xcodebuild` does not tally into that line. The true count comes only from:

```bash
BUNDLE=$(ls -td .build-merge/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool get test-results summary --path "$BUNDLE"
```

Quote the bundle path alongside the numbers. A count with no bundle behind it is not evidence —
`docs/tracker/BLOCKERS.md` §3 carries an unresolved entry that exists precisely because someone
reported "verified with `xcodebuild test` successfully" with no count and no bundle.

**A red run is ~1-in-3 environmental flake.** Two faces: `Simulator device failed to launch …
Busy ("Application failed preflight checks")`, and a tab-bar button going stale mid-tap. Re-run
once before believing a red; grepping only for the launch string misses the second face.

## Reporting

One PASS / FAIL / **NOT RUN** line per surface, each with its own summary line. If something
fails, show the failing test and its assertion. **Never weaken a test to make it pass**, and
never report a surface you did not execute.

For reference, the last recorded numbers are in `BLOCKERS.md`'s header stamp — use them to spot
a regression, not as a substitute for running anything.

## Notes

- `-only-testing:escape_planTests` skips the slow UI tests while iterating. Run the full command
  at least once before declaring done.
- `.build-merge/` is gitignored derived data — leave it.
- A Swift build error about a missing enum arm means a lane added an `EditAction`/`Selection`
  case without updating every switch. That is the fix, not a test change.
- SourceKit and VS Code cannot index this project and report phantom "cannot find type" errors.
  Trust `xcodebuild` and `scripts/typecheck-ios.sh`; ignore the editor.
