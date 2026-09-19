# 2026-09-14 · Merge `origin/main` (S9.1) into the local S7.7 line

**Type:** integration, not a playbook session. No feature work.

## What happened

`main` had diverged 8 local / 1 remote. Merged `origin/main`'s `0103a74`
("Semantic Relocalization Engine and UI Enhancements") into the local hazard-hunt
line as `33ef233`.

**One conflict: `docs/tracker/activity-log.md`.** Both sides only appended — the
first 1522 lines were byte-identical to the merge base. Resolved as the
chronological union of the two tails: 2 entries from `origin/main`, 11 local,
13 total, sorted by timestamp, no entry dropped and none duplicated. Verified by
comparing headings against both sides (132 = 130 local + 2 incoming).

**The code merged without overlapping.** The two sides touched disjoint files —
the only shared paths were `decisions.md` and the activity log, both docs. The
local line was Swift under `Editor/Core` + `HazardHuntView`; the incoming line
was `Drill/SemanticMatcher`, `DiffReviewSheet`, `HomeScreen`. So the clean Swift
merge is real, not a lucky text merge.

`backend/app/scoring/diff.py` was deleted by the incoming commit; checked for
dangling imports across `backend/` — none.

## Verified green post-merge

- backend **394** passed, 13 live-deselected — `cd backend && .venv/bin/python -m pytest tests/ -m "not live"`
- EditorCore **295** passed — `swift test --package-path tools/editorcore`
- corpus valid — 24 sources, 9 files, 2 threshold files

## NOT verified

iOS was not run (owner's standing restriction on this machine). That matters more
than usual here: the incoming commit adds ~400 lines of Swift that has never been
compiled, and its two new test files may not be wired into the `.xcodeproj` target.
Logged in `BLOCKERS.md` §4.

## Corrections made

1. **`BLOCKERS.md` said no interpreter on this machine has `pytest`. That was wrong.**
   The venv is at `backend/.venv` (3.13.9 / pytest 9.1.1); the 2026-09-10 check had
   been run from the repo root, where `.venv` does not exist. Backend work was never
   actually unverifiable here. Cleared with evidence.
2. **`decisions.md` table was split** by a blank line the S9.1 entry left behind —
   every row below it stopped rendering as a table. Removed.

## Left deliberately

15 `patch_*.py` authoring scripts that landed in the repo root with `0103a74`.
Deleting another author's committed files is not a merge resolution; logged in
`BLOCKERS.md` §4 for the author to confirm.

## Not pushed

The merge is committed locally (`main` ahead 11). Pushing was not requested.
