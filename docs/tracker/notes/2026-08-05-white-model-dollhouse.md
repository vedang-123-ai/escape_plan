# Revamp — "White Model" dollhouse renderer overhaul

- **Who:** P1
- **Date(s):** 2026-08-05
- **Status when I stopped:** DONE for the renderer core. Full gate green (192 editorcore, 323 iOS,
  264 backend, corpus valid) and verified on the simulator. People layer and app-chrome pass
  deliberately not started.

## What happened

Implemented the approved design handoff from Claude Design project
`344e3e53-37d2-4471-831c-aa50067e9d55` — `DOLLHOUSE-REDESIGN-SPEC.md` (the brief) plus
`swift-implementation-notes.md` (the tuned values the three.js prototype converged on). Ported the
prototype's look and controls onto the existing SceneKit stack.

Landed:

- `DollhousePalette` rewritten to the White Model palette. One white family for every wall, door,
  window, stair, slab and furniture piece; the only color in scene is route orange + exit green.
  Deleted `accent(for:)`, `object(category:)`, `opening(kind:isExit:)`, `openingFrame`, `wallCap`,
  the clay `exteriorWall`, both wall opacities, `roomAccentStrength` and the four stair blends.
- Fixtures: walls opaque and shadow-casting with a 12 mm pure-white cut cap; white door leaves and
  frames; near-invisible 8% glass; white stairs; 0.14 m slabs; new `FurnitureFixture` (parametric
  white minis per category) and `ExitMarkerFixture` (green pad + chevrons on the plate).
- Lighting rebuilt: warm key at azimuth 315°/elevation 50° with a shadowless twin to dial shadow
  strength to 0.55, cool fill at 120°/25°, generous ambient, 2048 shadow map, and **SSAO on the
  camera** — that last line is most of what makes a one-material model read as solid.
- Orthographic camera by default, 35° long lens, scale-matched so a projection toggle wouldn't jump.
- Ghost-floor stacking replaces the exploded view AND the spotlight toggle. Tap a ghosted floor in
  3D or use the chips — both go through one path.
- Routes: 0.065/0.04 radii, same-hue dashed secondary (the blue one is retired), two-pass
  occlusion, cylinder shading, off-active-floor dimming.
- Camera: 12°–80° pitch, extent-relative zoom limits, bounded pan with rubber band + spring,
  turntable axis lock, inertia on release, recenter chip, double-tap zoom.
- Accent → deep safety green `#0E8A3E`; selection ring replaces the yellow sphere.
- New `jagged.json` fixture (3 misaligned levels) as the stacking acceptance model.

## Decisions / surprises

All promoted to `docs/decisions.md` under "2026-08-05 — White Model dollhouse overhaul". The two
worth repeating here because they cost real debugging time:

1. **The spec's framing distance was wrong for the new lens.** 1.35 × extent came from the old 50°
   FOV; at 35° the house rendered cropped on all four sides. Correct factor is ~2.2 ×. If you
   change the FOV again, re-derive it — `CameraRigModel.openingDistanceFactor` documents the math.
2. **`orthographicScale` is a half-HEIGHT.** On a portrait phone the visible WIDTH is
   `scale × aspect`, so the house loses both sides. The rig now corrects for aspect. This is
   invisible on a square-ish preview and obvious on a real device — check ortho framing on a phone,
   never on a Mac window.

Also surprising: **the builder opened focused on the top floor while the chips read from the
store**, so the render and the chips disagreed on first paint. Focus is now seeded from
`store.activeFloorId` in `attach`. Any future "which floor is active" source must go through
`HouseScreen.focusFloor(_:)` — it is deliberately the only path.

Prototype shortcut NOT ported: the three.js build fakes AO with baked gradient strips and radial
sprites. SceneKit has real SSAO, so that hack is gone. If AO ever looks wrong, it's the camera's
`screenSpaceAmbientOcclusion*` properties, not geometry.

## Questions for teammates

- @P2 The "server didn't accept the access token" banner shows on the House tab against the
  deployed backend. Unrelated to this change (config, not renderer) but it is on the demo path.
- @P3 Room label chips are legible but small at 0.22 m. Spec's number; flag it if it reads too
  faint on a real device rather than the simulator.

## Next steps

Whoever resumes: run the device-acceptance pass on real hardware against the `jagged` fixture —
activate the basement and confirm the two floors above ghost, all three slab outlines stay legible
and there is no z-fighting. That is the one acceptance criterion I verified only in the simulator.
