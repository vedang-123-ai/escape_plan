# 2026-07-22 — Repo assessment, entry-point wiring, doc consolidation

Not a playbook session. A cleanup pass: assess where the project actually is by running it,
then make the documentation tell the truth and make it structurally harder to stop telling it.

## What the assessment found

Ran the backend locally and the app on a simulator rather than reading docs about them.

**The code is in much better shape than the docs claimed. The docs were the problem.**

Two finished modules were unreachable from the app:

- `escape_plan/Capture/` — the RoomPlan LiDAR scan, ~960 LOC, complete and tested. Referenced
  by zero app code. `HomeScreen`'s empty state advertised "or capture one with a LiDAR scan"
  with no way to start one. This is the scope-locked headline feature.
- `escape_plan/DrillMode/` — ~530 LOC, same situation.

Both carried `TODO(integration)` headers waiting on a session that had already landed.

The gap was bigger than "add a button" for Capture: there was **no `/convert` client in Swift
at all**. `ScanFlowView` handed back a `ScanArtifacts` with a `rawJSON` URL and nothing
consumed it.

Also found: no shared Xcode scheme (`xcshareddata/` absent), so `xcodebuild -scheme escape_plan`
only worked on one machine.

## Observed state (measured, not claimed)

| Suite | Result |
|---|---|
| Backend pytest | 196 passed, 11 live-deselected |
| EditorCore | 128 passed |
| iOS unit + UI | 242 passed, 1 skipped (`GoldenPathRecordingUITests`, skipped by design) |
| Corpus | valid — 11 sources, 6 files |

This settles three contradictions that existed inside the old tracker: EditorCore was claimed
as both 115 and 128 (it's 128), backend as 195/196/197 (196), iOS as 231/238 (238 unit + 4 UI).

Endpoints verified live: `/routes` returns 7 rooms with primary and secondary plans on
twostory, `/score` 200. `/chat` and `/analyze` return a clean 502 with
`"ANTHROPIC_API_KEY is not configured on the server"` — the degradation is graceful, not a crash.

## What changed

**Wiring**

- New `escape_plan/Networking/APIClient+Convert.swift`. Carries the scan blob as `JSONValue`
  rather than a typed struct on purpose — the raw export format is the converter's contract, and
  a Swift copy of it would be a second thing to drift.
- `HomeScreen`: toolbar Scan button, "Scan a Home" in the empty state, `ScanFlowView` in a
  `fullScreenCover`, and the scan → `/convert` → save → open-editor path with per-status error
  messages (422 = "scan couldn't be turned into a floor plan, try again", 401/403 = token).
- `HomeScreen`: Drill via leading swipe and context menu → `DrillScreen(homeID:)`.
- New `escape_planUITests/EntryPointUITests.swift` — 3 tests, all passing, asserting the Scan
  button exists, that tapping it presents the capture flow, and that the empty state offers the
  action. These exist so the regression can't recur silently: nothing could have caught the
  original bug, because nothing referenced the code.
- Shared scheme at `escape_plan.xcodeproj/xcshareddata/xcschemes/escape_plan.xcscheme`.

**Docs**

- `docs/plan.md` deleted — 40,429 bytes against `cat docs/playbook/*.md` = 40,599. It was the
  same document pre-split, orphaned since 2026-07-10, linked from nowhere.
- `board.md` + `checklist.md` → one `docs/tracker/TODO.md`: only open work, grouped by area,
  each line naming its next action, no owner lanes, no deadline.
- `README.md` rewritten (was 11 lines, untouched since day one, never mentioned the tracker).
- `CLAUDE.md`: team-lane section removed, full command/skill/agent inventory (it listed 2 of 6
  commands and 1 of 5 agents), new mandatory logging section.
- P1/P2/P3 lane labels stripped from 39 live files (387 lines). **`docs/tracker/notes/` was
  deliberately left alone** — it's a dated append-only archive, and rewriting it retroactively
  would falsify the record rather than clean it. ~20 files still have prose mentions needing a
  hand rewrite; that's logged in `TODO.md`.

**Anti-staleness (four stacked mechanisms)**

1. Stop hook → `docs/tracker/activity-log.md`, machine-written, only on file-changing turns.
2. `/verify-docs` + `doc-auditor` agent — would have caught every contradiction listed above.
3. Freshness stamps (`_Last verified: date @ sha_`) on live docs.
4. Pre-commit **warn** (not block) when code changes without the tracker.

**`.claude/` fixes** — the highest-value one: `rules/vendors/anthropic.md` had
`globs: [..., "backend/app/api/**"]` and that directory does not exist. The Anthropic grounding
rules were silently never loading when editing the actual endpoint code. Also rewrote the three
index READMEs (`skills/` said "None yet" with four skills present), fixed the stale Core Data
claim in `rules/languages/swift.md`, added `.mcp.json`.

## Corrections to my own plan, made mid-session

Two things I had listed as "stale TODOs to delete" turned out to be real open work. Checking
before deleting was worth it:

- `HomeModelPersisting` — I assumed S2.1 had wired it. Nothing conforms to it and
  `HomeLibrary.editor` is never assigned, so deleting a home open in the editor doesn't close
  it. Comment rewritten to say so; now tracked.
- `scoring/findings.py` vs `ai/agent.py` `Finding` — the TODO said "delete this and re-export
  theirs on merge". S3.2 merged, but `agent.py` imports `anthropic` at module level, so doing
  that would drag the SDK into the deterministic scoring path. The duplication is correct;
  the comment now explains why, and the lockstep risk is tracked.

## Deleted

`docs/plan.md`, `docs/tracker/board.md`, `docs/tracker/checklist.md`, `docs/demo/script-v0.md`,
`docs/demo/storyboard-v0.md` (both banner-marked SUPERSEDED),
`escape_plan/Renderer/DollhouseDemoView.swift` and `escape_plan/Persistence/HomeListView.swift`
(both unreferenced, superseded by `PlanScreen` / `HomeScreen`), `artifacts/s13/` (empty), and
all derived-data and cache directories. No dangling references remain.

## Still open, flagged not fixed

- `artifacts/` is gitignored, so ~45 MB of acceptance evidence cited as the S2.2/S2.3/S3.4/S3.5
  handoffs exists only on one machine — `git ls-files artifacts` returns 0.
- `docs/demo/broll/s41-golden-path-simulator.mp4` (19 MB) is in git history; removing it needs
  a rewrite, which I didn't do unprompted.
- `escape_plan/CLAUDE.md` ships inside the `.app` bundle as a resource via the
  `PBXFileSystemSynchronizedRootGroup`.

## Limits of this pass

The real scan round-trip is **not** verified and cannot be from a dev machine — RoomPlan needs
LiDAR hardware. What's proven is that the entry point exists, presents, and degrades honestly on
a device without LiDAR. The `/convert` upload path itself is only exercised against synthetic
fixtures via the backend suite. That box stays open in `TODO.md`.
