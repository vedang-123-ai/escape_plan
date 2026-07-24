# Integration — lane/backend × lane/editor × lane/polish

- **Who:** integration session (Claude, ep-editor worktree)
- **Date(s):** 2026-07-23
- **Status when I stopped:** all three lanes merged onto `integrate/2026-07-23`; full gate run post-merge (see TODO.md stamp).

## What happened

Merged the three parallel lanes into one branch, in the skill-prescribed order
(zero-shared-file lane first, widest surface last):

1. `lane/backend` (Lane C: live-AI unlock, stable finding ids, goldens) — fast-forward
   except docs; decisions.md table rows kept from both sides.
2. `lane/polish` (S4.4 Lane B: route legibility, Render-URL default, copy pass, app icon,
   screenshot/backend-down UI-test drivers, evidence sets) — docs conflicts only.
3. `lane/editor` (revamp A1–A3/B1–B3/C1–C2: unified HouseScreen, schema v1.1 objects,
   grid pathfinding, LLM builder + review gate; plus Lane A editor-bug completion) — the
   real conflict surface.

### Conflict resolutions (kept BOTH sides everywhere)

- **`DollhousePalette`** — polish's hotter route colors win (editor's were the untouched
  base values); editor's new `object(category:)` tints kept.
- **`DollhouseScene.makeWall`** — editor's `RenderOrder.walls` constant + polish's
  `castsShadow = false`.
- **`RouteOverlay`** — polish's per-style route `renderingOrder` (primary 55 over
  secondary 50; device-verified against the x-ray rework) kept over editor's flat
  `RenderOrder.routes`; polish's exit-glow order 52 + shadow-off kept; tour finish now does
  polish's label un-hiding AND editor's orbit-rig camera hand-back (`tourRestoreNode`,
  never `allowsCameraControl`).
- **`PlanScreen.swift` (modify/delete)** — deleted, as the editor lane intended
  (HouseScreen replaced it). Polish's S4.4 changes to it were **ported into HouseScreen**:
  friendlier copy (planning/offline/401/generic-error/overlay-issue strings),
  `plan.route.picker` / `plan.tour.button` accessibility ids, `Haptics.tick()` on a live
  plan, `Haptics.begin()` on tour start.
- **`S44ScreenshotUITests`** — retargeted from the dead "Plan"/"Editor" tabs to "House",
  and `"Exploded view"` → the unified screen's `"Explode"` label. (Both drivers stay
  env-gated; they never run in the normal suite.)
- **docs** — decisions.md: all 2026-07-23 rows from all three lanes kept. TODO.md: merged
  stamp + suite table; dropped the four editor bugs Lane A verified fixed and the stale
  "Render URL isn't the default" item (closed by S4.4); kept everything else from both
  sides. tools-used.md auto-merged (Observation, PDFKit+PhotosUI — both Apple SDK).
- Closed the stale `TODO(integration)` in `escape_plan/Capture/README.md` (`onFinished`
  has been wired in HomeScreen since the capture-wiring session).

### Gate (post-merge)

- Corpus: valid, 11 sources / 6 files.
- Backend: **238 passed, 12 live-deselected** (207 + 227 pre-merge counts were additive).
- EditorCore SwiftPM: **186 passed**.
- iOS unit+UI on iPhone 17 Pro simulator: see TODO.md stamp (run at integration time).

## Decisions / surprises

- The two lanes' route rendering-order schemes (editor's `RenderOrder` ledger vs polish's
  per-style 50–56 band) coexist; polish's values sit inside the ledger's routes band
  (above walls 10/glow 20, below labels 100). If someone consolidates, fold the per-style
  values into `RenderOrder` — don't flatten primary/secondary to one value, the tour
  overlap needs primary on top.
- Editor's decisions rows mention `EditorScreen`; it no longer exists (HouseScreen). Left
  as-is — the log is a dated archive.

## Questions for teammates

- None blocking. Device-only acceptance boxes in TODO.md remain **unchecked** on purpose.

## Next steps

- Fast-forward `main` to `integrate/2026-07-23` (done in this session if the iOS suite
  came back green — check git log).
- Re-run the S44 screenshot drivers when someone wants fresh evidence of the unified
  HouseScreen (the committed s44-after set predates the House tab).
