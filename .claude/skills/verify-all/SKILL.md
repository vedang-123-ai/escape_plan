---
name: verify-all
description: Run the full green gate for the whole repo — EditorCore SwiftPM tests, the iOS app test suite on the simulator, backend pytest, and corpus validation. Use before declaring work done, after a merge/integration, or whenever the user asks to "verify", "run the tests", "check it's green", or "run the gate".
---

# verify-all

The project has four independently-runnable test surfaces. Run all four and report each verbatim.
A real iOS 26.5 simulator runtime IS installed on this machine (iPhone 17 / 17 Pro / Air, etc.) —
`xcodebuild test` works here; do not repeat the old "no simulator" assumption.

Run these from the repo root, in this order (fast → slow):

```bash
# 1. Editor core — pure Foundation, macOS, seconds. Catches non-exhaustive switches.
swift test --package-path tools/editorcore

# 2. Backend — Python, ~2s. Exclude live tests (they need ANTHROPIC_API_KEY).
python3 -m pytest backend/tests/ -m "not live" -q

# 3. Corpus — stdlib only, instant.
python3 backend/corpus/validate.py

# 4. iOS app + unit tests on the simulator — slowest (several minutes).
xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build-merge CODE_SIGNING_ALLOWED=NO
```

Notes:
- To iterate on one iOS target only, add `-only-testing:escape_planTests` (skips the slow UI
  tests). Run the full command (UI tests included) at least once before declaring done.
- `.build-merge/` is gitignored derived data — leave it.
- If a Swift build error mentions a missing enum arm, a lane added an `EditAction`/`Selection`
  case without updating every switch — that's the fix, not a test change.
- SourceKit/VS Code cannot index this project and shows phantom "cannot find type" errors; ignore
  the editor's diagnostics and trust `xcodebuild`.
- `-m "not live"` skips tests needing the Anthropic key. Only run the `live` suite when the key is
  actually set.

Report: a PASS/FAIL line per surface with the summary line from each (e.g. "195 passed"), and if
anything fails, the specific failing test and its assertion. Never weaken a test to make it pass.
