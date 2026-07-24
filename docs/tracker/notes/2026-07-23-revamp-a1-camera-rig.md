# Revamp A1 — unified free-camera view (camera rig + read-only parity)

- **Who:** P2 (Claude session, lane/editor worktree)
- **Date(s):** 2026-07-23
- **Status when I stopped:** A1 done and green; A2 (editing in the unified view) not started.

## What happened

Kicked off the approved 3D revamp (full grilled spec + phased plan:
`~/.claude/plans/i-want-you-to-tender-flask.md`, decision summary in `docs/decisions.md`).
A1 shipped:

- `Editor/Core/CameraRigModel.swift` — pure orbit/truck/zoom-toward-anchor math, 12 new
  editorcore tests (zoom-anchor invariant, pitch/distance clamps, basis orthonormality).
- `Renderer/OrbitCameraRig.swift` — SCNNode binding; anchor via hitTest → floor-plane
  unproject fallback; rig node persists across scene rebuilds.
- `Renderer/UnifiedSceneView.swift` — replaces `DollhouseSceneView` in `PlanScreen`:
  1-finger orbit, 2-finger truck, pinch-to-point zoom (pinch + truck recognize together).
- `Renderer/RenderOrder.swift` ledger + band-assertion test in `DollhouseRendererTests`.
- `DollhouseScene.setFloorFade`, route tubes → `RenderOrder.routes`, tour restores
  `pointOfView` via `restoreTo:` instead of `allowsCameraControl`.

Verification: editorcore 158 pass (incl. 12 new), iOS unit suite `** TEST SUCCEEDED **`
(incl. new render-order test). UI tests not re-run this session (no editor-path changes yet).

## Decisions / surprises

- See `docs/decisions.md` 2026-07-23 entry (rig replaces allowsCameraControl; RenderOrder
  ledger; tour teardown change).
- `RouteOverlay.startTour` signature changed (`restoreTo:` param, defaulted) — PlanScreen is
  the only caller.

## Questions for teammates

- @P1/@P3: gesture *feel* (orbit sensitivity π/view-height, pinch anchoring) needs a
  device-acceptance pass before A3 deletes the old stack.

## Next steps

A2 per the saved plan: pure `GestureArbiter` (hit + selection → camera/edit), extend
`EditorSceneAdapter` with `worldPoint(from:onPlaneY:)` + perspective `metersPerPoint()`,
new `UnifiedSceneController` conformer, wall-drag edge-normal projection, migrate the
UI-test tap driver.
