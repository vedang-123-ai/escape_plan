# Revamp A3 — HouseScreen consolidation

- **Who:** P2 (Claude session, lane/editor worktree)
- **Date(s):** 2026-07-23
- **Status when I stopped:** A3 done — Project A (unified free-camera viewer+editor) complete.
  Full gate green; manual-build driver passes live on the merged screen. B1 (schema v1.1) next.

## What happened

- `Screens/HouseScreen.swift` merges EditorScreen + PlanScreen: editing session, inspector,
  toolbar, floor chips + spotlight, explode slider, route overlay/picker/tour — one screen.
  Edits invalidate the plan and re-fetch `/routes` (0.9 s debounce). Tab shell: Home / House /
  Assistant / Settings.
- Deleted: `EditorScreen`, `PlanScreen`, `EditorSceneController`, `DollhouseSceneView`.
  `DrillScreen` → `UnifiedSceneView`. UI-test drivers updated (no Plan tab; routes assert in
  place).
- Two real interaction bugs found by the recording driver, fixed for fingers too:
  1. Pan-recognition slop (~10 pt, not covered by `translation` at `.began`) made drag
     arbitration hit the wrong room's vertex → `InitialPointPanGestureRecognizer` captures
     the true touch-down point.
  2. Chrome resizing the scene view mid-drag shifted the world under the finger (vertex drags
     landed ~1.7 m off) → chrome lives in a fixed-height scrollable dock; the scene frame
     never changes.
- Verification: editorcore 168, full iOS unit+UI suite, backend 196 + corpus — all green.
  `TEST_RUNNER_MANUAL_BUILD=1` driver run passes against local uvicorn.

## Decisions / surprises

- All promoted to `docs/decisions.md` (2026-07-23 A3 entry): fixed-height-dock layout law,
  slop-proof pan subclass, overlay-in-class-box (no @State writes from `updateUIView`),
  accessibilityValue debugging pattern.

## Questions for teammates

- @P1/@P3: device-acceptance pass on the whole unified experience is still owed (gesture
  feel, dock height on small screens, tour). Simulator behavior is verified; feel is not.

## Next steps

B1 per the saved plan: schema v1.1 (`floor.objects` box primitives + `source: ai_plan`),
three-way lockstep, SchemaMigrator 1.0→1.1, planted-obstacle fixtures. Own PR.
