# S11.15 — The drill shows the engine's findings verbatim (AUD-025)

- **Who:** Anish (with Claude Code)
- **Date(s):** 2026-09-30
- **Branch:** `s11-15-drill-verbatim`
- **Status when I stopped:** AUD-025 fixed and verified (tests, typecheck, simulator); auditors run; merged.

## What happened

- Re-confirmed on `origin/main` `7f2c97e`: `grep -rn "nearby sturdy building" escape_plan` hit
  `DrillScreen.start`, which appended "Leave immediately and seek shelter in a nearby sturdy building.
  [cite: redcross-tornado]" to the engine's `no_viable_safe_room` finding.
- New pure builder `escape_plan/Editor/Core/DrillNotice.swift` (EditorCore, so `swift test` reaches it). A notice is
  `text` + `citations`. `DrillNotice(finding:)` is the engine's `detail` verbatim with its `citation` id carried
  separately. `start(room:profileName:peril:)` returns `.walk(Route)` or `.notice(DrillNotice)`: tornado safe-room
  finding first, then the primary route, then "No primary route for X." plus the engine finding that explains it
  (`no_viable_route`, then `blocked_opening`, then the first). The three fixed status notices are static members.
- `DrillScreen.swift`: `routesNotice` is now `DrillNotice?`; the notice assignments use the builder and `start` switches
  on its outcome; the banner renders `text` plus `DrillCitationChips` (the drill's existing way of showing source ids)
  and VoiceOver reads "<text> Source: <id>." Nothing else in the file changed.
- Tests: `escape_planTests/EditorCore/DrillNoticeTests.swift`, 10 tests, engine sentences copied from `engine.py`.
  Tornado no-interior-room gives exactly the engine's sentence and `["redcross-tornado"]`; the tornado finding wins
  even with a primary route; no citation gives no chips; the no-primary branch is "No primary route for X. <engine
  detail>" and prefers `no_viable_route` over an earlier earthquake no-cover finding, then `blocked_opening`; walkable
  rooms give `.walk`; and three
  sweeps over every notice: what remains after removing engine text is one of five status lines, no `[cite:`, no
  "Leave immediately".

## Evidence (2026-09-30, run by me)

- `grep -rn "nearby sturdy building" escape_plan` → nothing (exit 1).
- `swift test --package-path tools/editorcore` → **645 tests, 0 failures** (10 new).
- `xcodebuild test … -only-testing:escape_planTests/{DrillSessionTests,DrillInstructionsTests,DrillPracticedStateTests,DrillNoticeTests}`
  → xcresulttool on `.build-s1115/drill3.xcresult` (final commit `e7b6bf9`): **19 total, 19 passed, 0 failed,
  0 skipped** (iPhone 17 Pro sim, iOS 26.5, unsigned; bundle not committed).
- `bash scripts/typecheck-ios.sh` → ok on all four targets.
- **Simulator, by hand:** built the home as a copy of `schema/fixtures/twostory.json` with `stairs: []`
  (home_id `S11-15-NO-STAIRS`), so nothing upstairs can reach a ground-floor room. Ran a local backend from this
  branch on port 8015, pointed the sim app at it, opened Practice drill → Severe Weather → Maya. The banner showed
  only: "No interior room could be reached from here. If you are in a mobile or manufactured home, go now to a nearby
  sturdy building or community shelter." with one `redcross-tornado` chip. No client sentence, no raw tag.
  Done twice: on `29713b9` and again on the final build `e7b6bf9`, same screen.
  Afterwards the test home, the sim's base-URL and token overrides, and the port-8015 backend were removed.

## Mission 2 — every string DrillScreen shows, classified

Engine text: the routes notice (now `DrillNotice`), `noCoverFinding` passed into `DrillSession`.
DrillInstructions text (cite-checked by `DrillInstructionsTests`): step cards via `DrillCitedText(card.body)`,
`DrillInstructions.drillTimerGoal`.
Non-safety UI/status copy: "AR requires iOS 17"; "Add family members in Profiles first…"; "What are you practicing?";
peril pills; "Who is practicing?"; "The drill walks that person's primary route…"; "Where does the fire start?
(optional)" and its explainer; "Working out the modeled walk…"; "Modeled from a fire starting in X."; "The drill itself
doesn't need this…"; "Practice log"; "Step n of m"; "Walk it in AR" and its hint; timer labels; "Next";
"Modeled with the fire starting in X."; "Pick where the fire starts before a drill…"; "Plan practiced — your
preparedness score updates…"; "Mark plan as practiced"; "Getting the escape route ready…"; the two `logError`
strings; the "Couldn't load home" empty state; the four `DrillNotice` status lines; `BackendFailureBanner` and
`OfflineCapabilityNote` (shared, not drill-authored); also "No family profiles yet", "No drills recorded", "· stopped", "Start the fire in X" and the accessibility hints ("Opens the camera…", "Closes without setting a fire origin."). None gives safety advice.

## Auditors

- grounding-auditor: **GROUNDED**, no client-written safety text; corpus valid (36 sources). Its two outside-the-diff
  findings (engine/checklist wording) are in BLOCKERS. Its `findings.first` point was fixed (reason preference).
- swift-scenekit-reviewer: **PASS**. Acted on: walk-or-notice outcome instead of an unreachable-by-construction
  `guard`, real engine text in tests, "Source/Sources" wording. Behaviour note it raised: non-tornado notices now also
  show the engine's citation as a chip (no new text).

## Decisions / surprises

- **The playbook's `-only-testing:escape_planTests/DrillModeTests` runs zero tests.** The file holds three classes
  (`DrillSessionTests`, `DrillInstructionsTests`, `DrillPracticedStateTests`); XCTest selects by class, and an unknown
  class matches nothing yet reports TEST SUCCEEDED. Use the class names.
- **"Never a raw [cite: …]" holds for notices only.** `DrillCitedText` deliberately shows DrillInstructions copy with
  its inline `[cite: id]` tags *and* the chips (visible on the drill screen today). Changing that is outside S11.15's
  owned files; logged in BLOCKERS as a question.
- **The engine's text still reads wrongly for a site-built house** (mission 4, not fixed in Swift): its
  no-interior-room sentence offers nothing for a site-built home, and `/score`'s checklist item "Identify a nearby
  sturdy building for tornado shelter" ("No room in your home qualifies as a safe room") fired for this two-story
  house on the Home screen. Logged in BLOCKERS for the backend/corpus owner.
- Environment: `tools/editorcore/.build` still had the old repo path (S11.8's finding); I deleted it and the package
  went green. `backend/.venv/bin/uvicorn` has a stale shebang from the repo move; `.venv/bin/python -m uvicorn` works.

## Questions for teammates

- Backend/corpus owner: should `no_viable_safe_room` and `safe_room.nearby_shelter` say something for a site-built
  house (lowest floor, interior room), and should the checklist item fire only when no room anywhere qualifies?
- S11.10 owner: keep inline `[cite: id]` tags in drill cards, or strip them and keep only the chips like the notices?

## Next steps

- Backend/corpus owner: decide the site-built wording of `no_viable_safe_room` and `safe_room.nearby_shelter`
  (BLOCKERS, S11.15 findings).
- S11.12 truth pass: the drill no longer writes tornado advice.
