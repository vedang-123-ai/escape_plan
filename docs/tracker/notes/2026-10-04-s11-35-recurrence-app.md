# S11.35 — The app remembers when a recurring task was done

- **Who:** Anish (agent-run)
- **Date(s):** 2026-10-04
- **Status when I stopped:** done and merged. One owner check left: tick the drill task by hand in Tasks and look at the label.

## What happened
- Step 0: `/health` showed commit 9877802, a descendant of the S11.34 merge 23e44ce, so the live server takes timestamps.
- Checklist values are now a Bool or a completion date (`ChecklistMark`, `Models/ScoreModels.swift`). A completed recurring
  item goes to `/score` as an ISO-8601 UTC string with whole seconds; everything else is `true`/`false`.
- `ChecklistStateStore` keeps both in one UserDefaults dictionary. The migration test was written first: a Bool-only store
  written the old way loads every value and re-saves as the same Bools. One bad value now costs only itself.
- `ChecklistItem` decodes `recurrence_days` and `completed_at` if present (old score caches still load).
- `ReadinessStore.isDone` follows the server's `done` for recurring items; a fresh tick shows at once until the answer lands.
  `toggleDone` stores the time for a recurring item. The S11.23 race tests pass unchanged.
- The monthly alarm test now ticks in place (it went to House, which can never tick it). Rows show
  "Done 3 months ago · due in 3 months" (owner's wording).
- Manual check against the live server, done by writing the stored date with `simctl spawn ... defaults write` (no code edit):
  a "now" drill date came back done with that `completed_at`; 200 days back came back not done.

## Decisions / surprises
- Owner answers (live, 2026-10-04): make the alarm test tickable (yes); the label wording (the recommended one); a lapsed monthly
  alarm test keeps lowering the score.
- No tap tool was available, so the drill row itself was never seen on screen (BLOCKERS, S11.35 findings).
- Reviewers: swift-scenekit-reviewer (no blockers). Fixed: the label now agrees with the row while a tick is pending;
  an offline tick survives a same-home reload; overdue reads "due again now", not "due within a day"; VoiceOver gets a comma,
  not "·". Declined moving the label code to `Readiness/` (new file, pbxproj). ecc:silent-failure-hunter (no blockers):
  added a log when `completed_at` does not parse; wrong phone clock and old-cache-offline tick logged in BLOCKERS.
- Mutation checks, each restored from a scratchpad backup: 12 breaks (store ignores Dates, store ignores Bools, fractional
  seconds on the wire, `completed_at` required, label ignores `done`, local tick beats the server, tick stores a flag not a
  date, alarm test sent to House, override never cleared, override cleared on same-home reload, overdue clamp removed, label
  ignores the row's state). Every one turned its named test red.
- Swift files added: none.

## Questions for teammates
- None.

## Next steps
- Owner: Tasks tab, tap the drill task, "We practiced it for real", close. Expect "Done today · due in 6 months".
