# 2026-07-24 — "Does it work and does it look good?" + obstruction advice

**Session type:** not a playbook session — a state assessment Anish asked for, plus the work
it turned up. **Branch:** `main`.

## What was asked

Three things: what's left, how close is it, and "merge everything and finish everything."
Mid-session Anish redirected: *"I want to first understand if the app even works and looks
good."* That reframed the priority from closing TODO lines to getting eyes on the product.

## Merge status: nothing to merge

All three lanes (backend live-AI, editor revamp, S4.4 polish) were already merged to `main`
before this session — `git branch --all` shows only `main` and `origin/main`. The stray
`../ep-editor` worktree sits on `f21f17c`, an already-merged commit. The "merge everything"
half of the ask was already done.

## Does it work? Yes — gate green before any change

| Suite | Result |
|---|---|
| EditorCore (SwiftPM) | 186 pass |
| Backend pytest (`not live`) | 238 pass, 12 live-deselected |
| Corpus | valid — 11 sources, 6 files |
| iOS unit + UI | TEST SUCCEEDED, 0 failures (6 env-gated drivers skipped) |

## Does it look good? Mixed — and the answer needed the simulator, not the tests

Ran the S4.4 screenshot driver against a local backend (`TEST_RUNNER_S44_*` env vars must be
exported into xcodebuild's OWN environment; passing them as build settings silently skips the
driver — cost a wasted run, worth remembering).

**Strong:** onboarding, the preparedness-score breakdown, and the assistant's offline banner.
The score screen would hold up in front of a judge unchanged.

**Weak, now fixed:** the House tab — the centerpiece — read as unfinished. Cream 3D viewport
fighting black chrome, tiny labels, ~⅓ of the screen dead dock.

**Four findings, three fixed:**

1. *No reproducible demo data.* The library held 14 identical "New Home" documents from
   builder runs; nothing ever created the three named fixtures. **Fixed** —
   `FixtureSeeder.seedStarterHomes` at app launch. Proof it mattered: the driver skipped 4
   steps before (incl. the profile-switch money shot), 2 after.
2. *House tab visuals.* **Fixed** — dark stage backdrop + gradient, plate-backed legible
   labels, dock 240→200 pt (kept fixed-height; the existing comment gives a real reason —
   a mid-gesture resize would shift the world under the user's finger).
3. *Stale copy.* The assistant's error banner advertised a "Plan tab" that revamp A3 deleted.
   **Fixed** in the banner, onboarding, and the test that asserted the old string.
4. *The API key is not persisted anywhere* — not `~/.zshrc`, no `.env`. Last session's key
   lived only in that shell. **Not fixed** (it's Anish's secret to place); it is why the AI
   half is dark locally.

## Open bug found and NOT fixed — routes don't render

The single most important visual in the app does not appear. Evidence gathered:

- The backend returns real geometry: Kids' Bedroom → 8 waypoints, 14.2 m, no findings.
- `routePlan` is non-nil in the app — the route controls (room picker + Tour) only render
  inside `if let routePlan`, and they are on screen.
- `attach(_:)` wires `onRebuild` → `applyOverlay()`, and `fetchRoutes` calls `applyOverlay()`
  after assigning, so the obvious races are already handled.
- Route materials are x-ray (`readsFromDepthBuffer = false`, renderingOrder 55 > walls 10),
  so occlusion by walls is ruled out.

Not yet checked: whether `RouteOverlay.show` is returning issues (e.g. `floorRuns` dropping
runs whose `floor_id` isn't in `knownFloorIDs`) and drawing nothing. **That is the next
thing to look at** — `overlayIssues` is populated but I did not confirm where it surfaces.
This deserves systematic-debugging, not another guess.

## Obstruction advice (the feature Anish asked for)

He asked for more than wiring `blocked_opening` through: the app should tell you *which
objects to move* and where hazards are. Built `app/routing/obstructions.py`:

- **Counterfactual attribution, not proximity** — an object is a culprit only when removing
  it restores the leg. A sofa near a door is never blamed for a doorway a wardrobe blocks.
- **Measured move distance** — bisection on the clearance the leg actually tolerates, so the
  advice is "move the wardrobe about 0.85 m", a number the engine derived and can defend.
- **Two severities, one mechanism** — the same probe at code clearance vs code + 0.15 m
  separates "can't get through" from "tight squeeze".
- **Honest silence** — when removing every object still leaves the doorway unreachable, the
  obstruction is geometry and nothing is blamed.
- Verified against the planted `bungalow-blocked` fixture: names `o_wardrobe_blocking`,
  0.0 m passable vs 0.813 m required, 0.85 m move.

Wired into `RouteFinding.detail` + new `object_ids` (additive; Swift `decodeIfPresent`), and
into the /score checklist — which also **fixed a real id collision**: two blocked doorways in
one room previously collapsed onto one checkbox and were titled "has no usable way out".

10 new tests. Backend 238 → **248 pass**.

## Gate after the changes

EditorCore 186 pass · backend 248 pass · iOS unit TEST SUCCEEDED · corpus valid.
The full iOS UI suite was green earlier in the session; it was not re-run after the last
Swift edits (`RouteFinding` decode + the render-band test widening) — **re-run `/verify`
before trusting the UI half.**

## Next

1. **Debug why routes don't render.** Highest priority — it's the product.
2. Re-run the screenshot driver and look at the House tab again now that fixtures seed.
3. Persist `ANTHROPIC_API_KEY`, and set it in the Render dashboard.
4. Remaining machine-closable iOS gaps (untouched): `setOpeningWidth` UI, shared
   `HomeLibrary`, selection markers, launch screen, agent-finding `id` threading.
