# Full-app test sweep — where we actually are

- **Who:** P1
- **Date(s):** 2026-08-04
- **Status when I stopped:** Whole gate re-run and green (corpus, backend 264, EditorCore 186,
  iOS 320). Two defects found and fixed. **One hard blocker outstanding and it is not code:
  the Anthropic account is out of credits, so every AI feature is dead.**

## What happened

Ran everything end to end rather than trusting the stamp. The stamp was honest — every suite
matched what `TODO.md` claimed.

| Suite | Result |
|---|---|
| Corpus | 11 sources, 6 files, thresholds consistent ✓ |
| Backend pytest | 258 → **264** pass, 13 live-deselected (6 new this session) |
| EditorCore (SwiftPM) | 186 pass ✓ |
| iOS (unit + UI) | **320** pass (315 unit + UI), 8 skipped ✓ |
| `/routes` × 3 fixtures | 16/16 rooms got a primary route ✓ |
| `/convert` × 2 synthetic scans | valid HomeModel, exterior openings mapped ✓ |
| `/score` × 3 fixtures | all render; screenshot captured ✓ |

Also exercised the live API once: `/explain` on the bungalow returned 200 in **26.0s** with
sensible grounded output ("the Bathroom's window is too small and too high to count as a real
second exit"). That re-confirms the p95 < 6s criterion is still unmet at ~26s, matching the
2026-07-23 measurement of 26.3s. Then the account ran dry mid-session.

### Fixed 1 — Anthropic API errors surfaced as bare 500s

`/explain`, `/analyze` and `/chat` all returned `500 Internal Server Error` once credits ran
out. The missing-key path was already clean (502 with a readable reason), so the gap was only
in the unguarded `client.messages.create` calls. One app-level
`@app.exception_handler(anthropic.APIError)` now maps them to **502** (operator must act) or
**503** (retryable), with the API's own sentence as `detail`. Verified against the real dry
account: all three now return 502 with *"The AI service rejected the request: Your credit
balance is too low…"*. 6 tests. See decisions.md.

### Fixed 2 — ScoreScreenshotUITests could never pass

It asserted `navigationBars["Score"]`, but `ScoreScreen` sets
`.navigationTitle(breakdown?.home_name ?? "Score")` — "Score" is the *loading* title. The
assertion failed on exactly the runs that worked. Now waits for the "How it's scored" header.
**TEST SUCCEEDED**, and the long-open "nobody has watched Score render" item is closed:
`docs/evidence/score-screen-2026-08-04/`.

## Decisions / surprises

- **The account being out of credits is the single biggest risk to the submission.** Nothing in
  the AI half of the app works right now, including the never-run live agent golden
  (`agent_bungalow_blocked`). This is not a code problem and no amount of testing clears it.
- **The iOS test runner is ~1-in-3 flaky, and it is environmental.** Three identical back-to-back
  full runs went pass / **fail (10 failures)** / pass. Every failure was
  `Simulator device failed to launch cac.Escape-Plan … Busy ("Application failed preflight
  checks")` — it kills both test targets at once, so a red run says nothing about the code.
  **Never trust a single `/verify` run; re-run before believing a failure.** Disk is at 93%
  (31 GB free) — better than the 99% that blocked the screenshot before, still tight, and the
  most likely lever.
- **Console output undercounts the iOS suite.** `xcodebuild` prints `Executed 16 tests` because
  the unit target runs under Swift Testing, which doesn't emit the old `Test Suite` lines. The
  result bundle shows the real number: **320 passed**. I briefly mis-read this as "the 315 unit
  tests never run" — they do. Read the `.xcresult`, not the console tail:
  `xcrun xcresulttool get test-results summary --path <bundle>`.
- **The P1 scoring flaw is now visible in a committed screenshot**: "No open safety findings —
  20/20" on a home that has never been analysed. Worth looking at while deciding that P1; it's
  more persuasive as a picture than as a paragraph.
- `backend/.venv` does not exist on this machine. System `python3` is 3.13.5 with pydantic
  2.13.3 and runs everything fine. `TODO.md`'s heads-up about 3.9 is machine-specific — kept,
  but corrected.

## Questions for teammates

- **@Anish — top up the Anthropic account.** Until then: no `/explain`, no `/analyze`, no
  `/chat`, no live goldens, and no filming the AI half of the demo.
- @Anish — the P1 (never-analysed home scores 20/20 for safety) is still undecided and now has
  a screenshot. Worth 15 minutes before the demo script gets locked, since the score is on
  camera.

## Next steps

1. Add Anthropic credits, then immediately run the live suites — including the never-executed
   `test_blocked_bungalow_agent_names_the_wardrobe` golden, which has been waiting on this.
2. Free disk and re-run the iOS gate a few times to see whether the ~1/3 launch flake clears.
   If it persists it will bite during recording.
3. Decide the P1.
