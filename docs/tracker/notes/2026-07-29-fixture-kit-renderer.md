# UI revamp — parametric fixture kit for the dollhouse renderer

- **Who:** Yuki (with Claude Code)
- **Date(s):** 2026-07-29
- **Status when I stopped:** fixture kit live on all screens; unit tests green (21 renderer
  tests, full escape_planTests suite); visually verified on the demo home in the simulator
  (stacked, exploded, routes + exit glow, tour untouched).

## What happened

Replaced the single-color-box rendering of walls/doors/windows/stairs/slabs with a
**parametric fixture layer** (`escape_plan/Renderer/Fixtures/`):

- `FixtureKit.swift` — specs (`WallFixtureSpec`, `OpeningFixtureSpec`, `StairFixtureSpec`,
  `SlabFixtureSpec`), builder protocols, the swappable `FixtureCatalog`, and an
  `AssetFixture` adapter that bounding-box-fits a bundled `.usdz`/`.scn` onto any spec —
  the plug-in point for hand-modeled replacements. Local-frame contract documented in the
  file header.
- Walls (`StyledWallFixture`) now carve REAL holes for their openings (box composition:
  piers + sill/header strips, merged/clamped cutouts) and carry a darker "cut line" cap rim.
  Cutouts ride on `DollhouseGeometry.WallSpec` and are computed against the deduped wall,
  from the same clamped numbers the opening fixture gets — seamless joins by construction.
- Doors: jamb frame + leaf ajar (~19°) + handles; exits keep the palette green.
- Windows: frame + protruding sill + cross mullions + translucent glass (new
  `RenderOrder.glass` band).
- Stairs: treads with nosing, closed risers, sloped stringers, handrail + posts
  (count derived from rise at ~0.185 m riser). Still the honest straight-flight proxy.
- Slabs: per-face materials (accent top, darker cut edge) + a chamfered base plate under
  the house that catches the key-light shadow.
- All fixture tones are DERIVED from the existing `DollhousePalette` colors — same palette,
  one place to restyle.

`DollhouseSceneBuilder` now only places/names what the catalog builds. Node-name contract
("room:", "opening:", "stairs:") unchanged; `RouteOverlay` exit glow now sizes from the
opening container's bounding box instead of casting to `SCNBox`.

## Decisions / surprises

- **Found + fixed a pre-existing bug**: explode slider and spotlight fade silently did
  nothing on HouseScreen. `onRebuild` (captured once at attach) read @State through a stale
  struct copy — every editor rebuild reset explode/fade to defaults. Verified pre-existing
  by stashing the renderer change and reproducing on main. Fix: `SceneViewStateHolder`
  reference box (same pattern as `RouteOverlayHolder`); `applyViewState` reads only the box.
  Console-log instrumented via `simctl launch --console-pty` to catch it.
- Two new RenderOrder bands: `fixtures = 6` (opaque detail, before the translucent shell),
  `glass = 12` (after walls). Band test updated to include them.
- `FixtureCatalog.shared` is `nonisolated(unsafe)` mutable — swap at app startup only.

## Questions for teammates

- Want the ajar-door angle / handrail sides (single vs both) exposed as FixtureStyle knobs?
- basePlate margin is 1.1 m — taste check on the biggest scanned home.

## Next steps

- If custom `.usdz` door/window models land, register them via
  `FixtureCatalog.shared.door = AssetFixture(named: "…")` at startup and check joins on the
  three schema fixtures.
- Consider a device run — fixture node count is ~3-4× the old builder (still trivially
  small, but the editor rebuilds per commit; worth one profile pass on hardware).
