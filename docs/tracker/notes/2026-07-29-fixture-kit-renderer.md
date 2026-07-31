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

## Second pass, same day — UI craft (labels, dock, findings)

- **Room labels**: SCNText replaced with `RoomLabelSprite` — a pre-rendered capsule chip
  (warm paper surface, room-accent dot, rounded SF semibold) on an SCNPlane billboard.
  Same node contract (`label:<id>`, billboard holder, no depth read/write, labels band).
- **HouseScreen dock**: grouped into quiet sentence-case sections — View (explode +
  floors + spotlight), Escape routes (profiles, room, tour), Route check (findings).
  `dockHeader(_:)` is the one header style. Fixed-height dock contract untouched.
- **Findings**: raw red caption rows replaced with `RouteFindingCard`
  (`Screens/RouteFindingViews.swift`): severity icon well + titled kind + room chip +
  the engine's VERBATIM detail. Severity tiers reuse the scene's badge colors
  (`warningBadge` / `warningBadgeSevere`) so dock and 3D agree; titles only NAME the
  machine `kind` — no client-side safety judgments. Count badge on the header;
  `RouteAllClearRow` when the engine flagged nothing for the current view.
- Verified: full escape_planTests suite green; simulator pass over stacked view,
  finding cards (2× blocked_opening + no_secondary_egress), and the all-clear +
  route-drawn state for Master Bedroom.

## Third pass, same day — glass controls, scene card, fullscreen

- **Scene is a card**: 26 pt continuous corners, soft shadow, inset from the screen edges.
- **View controls float on the model** (`floatingSceneControls`): floor chips + spotlight
  left, fullscreen right, in Liquid Glass. Removed from the dock, which now opens on
  Explode → Escape routes → Route check. This is the "dead top space" the design brief
  called out — the model's sky is now the control surface.
- **`Screens/GlassControls.swift`**: one `#available(iOS 26)` fork for the whole app —
  `glassPill` / `glassPanel` / `glassGroup` (GlassEffectContainer) with `.regularMaterial`
  + rim-stroke fallback below 26. `GlassChipButtonStyle` presses to 0.96 on a critically
  damped spring, suppressed under Reduce Motion.
- **Fullscreen** (`isImmersive`): hides dock + nav bar + tab bar + status bar, squares the
  card to full-bleed, floats the explode slider in glass at the bottom so it isn't lost
  with the dock. Spring 0.42/1.0, cross-fade under Reduce Motion. Disabled while touring
  (a frame change would fight the tour camera).

### Surprise worth recording

Tried `SCNCamera.projectionDirection = .horizontal` so the house's width would always fit
regardless of viewport aspect. **Wrong fix** — on the full-screen 1:2.2 viewport that implies
a ~90° vertical FOV: the model shrank and the wide-angle distortion visibly skewed it.
Reverted to `.automatic`; the mild horizontal crop on entering fullscreen is better, and
pinch resolves it. Don't re-try this without also solving the distance/FOV together.

### Contract note

The "nothing overlays the scene" half of the fixed-dock comment is now deliberately relaxed:
view controls DO float over the scene, but as a fixed-height strip pinned to the card's top
edge, so they never resize it. The no-mid-gesture-resize half still holds — the only frame
change is the immersive toggle, which is user-initiated from a button, never mid-drag.
