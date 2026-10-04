# S11.48 — The home library lists cheaply, and launch seeding failures are visible

- **Who:** P3 (Lane D)
- **Date(s):** 2026-10-04
- **Status when I stopped:** done and merged; gate green (see BLOCKERS "S11.48 findings")

## What happened
- Mission 0: timed `list()` with 50 copies of `jagged.json` (14 KB each) in a scratch directory on the iPhone 17 Pro simulator. **Before: 215, 223, 217, 224, 219, 222, 213 ms.** Anish chose to fix it.
- **After (same 50 homes, same test shape): cold listing 8.3, 7.5, 7.6, 7.6, 10.5, 8.0, 8.6 ms; refresh after one autosave 1.1 to 1.2 ms** (one file re-read each time).
- Cause was building every home's full JSON tree just to read a name and two counts. Fix: `SummaryProbe` light decode + `summaries(reusing:)` cache keyed on file change time and size, held by `HomeLibrary`.
- Seeding: `escape_planApp` logs the failure and shows one alert once (`StarterSeedingNotice`).
- Tests (PersistenceTests): light decode equals the old full decode for every file in `schema/fixtures` and for nine odd shapes; only the changed file is re-read; deletes cannot resurrect; library shows save/delete/duplicate at once; cache key needs both change time and size; unreadable file is retried; notice shown once and only recorded on dismissal.
- **Mutation checks** (each broke the named tests, then restored with `git diff` clean): reuse disabled; room count wrong; size ignored; change time ignored; unreadable file cached; notice flag set too early. A first version of my own library test was flaky (same-second timestamps tied); fixed by giving the copy a later timestamp and a deterministic tie-break.
- Reviewer found three should-fix items; all done.

## Decisions / surprises
- No background thread, on purpose: see decisions.md (4 rows, 2026-10-04). The big win was the decode, not the thread.
- Sort ties now break by id.
- The alert is typechecked, not seen on screen.

## Questions for teammates
- None.

## Next steps
- If a screenshot of the seeding alert is wanted, force the failure in a Debug build once.
