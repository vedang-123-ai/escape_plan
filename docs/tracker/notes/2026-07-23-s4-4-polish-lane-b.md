# S4.4 — polish pass + demo-path hardening (Lane B, worktree `ep-polish`)

- **Who:** Lane B (Claude session, branch `lane/polish`)
- **Date(s):** 2026-07-23
- **Status when I stopped:** committed as `8b8bf40` on `lane/polish` (NOT merged — Lane B
  merges last). iOS suite 244 passed / 0 failed / 4 gated-skips (the gated drivers + golden
  path, which was separately run live and passed). Before/after evidence committed.

## What happened

- **Before/after evidence pipeline built first.** New `escape_planUITests/S44ScreenshotUITests`
  walks every screen unattended (onboarding, home, plan ×3 fixtures, room routes, mid-tour,
  profile switch, editor, chat, settings, score, profiles, drill) and writes PNGs to the host
  dir in `S44_OUT` (gate: `TEST_RUNNER_S44_SHOTS=1`). Ran it against the untouched app →
  `docs/evidence/s44-before/`. The same driver produces `s44-after/`, so framing is identical.
  Fixture seeding = copying the three fixture JSONs into the app container's
  `Documents/Homes/<home_id>.homeplan.json` (the store's on-disk format IS the fixture JSON).
- **Renderer overhaul** (`Renderer/` only): warm palette (`DollhousePalette` rework), exterior
  vs interior walls (occurrence-count in `DollhouseGeometry.walls` — edge owned by one room =
  exterior shell, deeper clay + more body; shared = interior, airy), room accents strengthened,
  warm key light with soft deferred shadows + cool fill. **Routes now render x-ray**
  (`readsFromDepthBuffer = false`, renderingOrder above walls) — the before-shots proved the
  old tubes were alpha-dimmed to invisibility behind 4–6 stacked translucent wall surfaces.
  Primary tube 0.06→0.10 radius, lift 0.22→0.30, pulsing start marker on single-room view,
  exit glow x-ray too. Camera tour: easeInEaseOut, 65° lens, gaze aimed down at the path, and
  room labels hidden during the tour (a billboarded label filled the whole frame at eye level).
- **App-wide design pass:** generated app icon (light/dark/tinted, `scripts/make_app_icon.swift`),
  ember AccentColor (light/dark variants) re-tints every control, score screen got an animated
  progress ring, chat messages animate in, `Haptics` helper wired at meaningful moments (routes
  landed, tour/drill start, drill step, checklist tick, drill practiced = success, chat failure
  = warning). Empty states rewritten with actions (Home, Plan, Assistant, Score).
- **Copy pass:** every user-facing "backend"/"bearer token"/jargon string replaced with plain
  warm language ("server", "access token", "check your connection and try again"). No
  client-side safety guidance added anywhere — engine findings and corpus-cited drill cards
  still render verbatim.
- **Shipped backend default:** `APIClient` defaults to the deployed Render URL; token comes
  from gitignored bundled `BackendConfig.local.json` if present; Settings gained a connection
  status light, friendlier form, and a DEBUG-only deployed/local server switcher. Decision +
  mechanism in `docs/decisions.md` (2026-07-23 rows).
- **Hardening:** new `S44BackendDownUITests` (gate `TEST_RUNNER_S44_DOWN=1`) drives
  plan/chat/score/drill against a dead port and asserts graceful states, no crash.
  `docs/evidence/README.md` + tracker README now define the curated-evidence convention.

## Decisions / surprises

- All four 2026-07-23 decisions.md rows are this lane's (Render default via bundled token file,
  x-ray routes, launch screen deferred, generated icon).
- Surprise: the S13-era `-fixture` launch args are gone from the app — screenshot seeding had
  to go through the container filesystem instead.
- Surprise: XCUITest env vars must be `env TEST_RUNNER_…` on xcodebuild's environment, not
  build-settings-style `KEY=VALUE` args (those silently become build settings).
- Surprise: after sending a chat message the keyboard covers the tab bar and every subsequent
  tab tap silently lands on the keyboard — the driver relaunches the app between chat and the
  swipe-action section. Worth knowing for any future UI test that types.

## Questions for teammates

- @P1: `BackendConfig.local.json` needs the real bearer token dropped in before any demo/device
  build (file shape: `{"bearer_token": "..."}` at `escape_plan/`). Not committed, gitignored.
- Real-device fps + haptics feel remain device-only items (tracked in TODO.md).

## Next steps

- Integration: Lane B merges LAST (widest surface). After merge, re-run
  `S44ScreenshotUITests` on iPhone 17 to confirm no editor-lane interaction.
- Launch screen (deferred): needs pbxproj edit during the integration window.
