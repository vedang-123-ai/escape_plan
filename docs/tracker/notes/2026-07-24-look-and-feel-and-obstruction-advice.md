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

## The route-rendering bug — FOUND AND FIXED (2026-07-24, later)

The single most important visual in the app was silently dead. Resolved by instrumentation,
not guessing (three theories above were all wrong — backend geometry, x-ray materials, and
overlay logic were all fine; the strengthened `testOverlayParentsRoutesPerFloorAndClearsCompletely`
proved `show()` creates ≥7 tube nodes).

**Root cause (confirmed via `NSLog` + `log stream` during a UI-test run):**
- `applyOverlay drew rooms=7 issues=[] sameScene=true` — routes ARE drawn into the live scene.
- **No `onCommit` / `invalidateRoutes` ever fired** — nothing legitimately cleared them.
- Interleaved `applyOverlay early-return … plan=false` — the `onRebuild` closure set in
  `attach` captures the **View struct**, and reading `@State routePlan` from inside that
  closure returns a STALE snapshot (perpetually nil). `EditorSceneView.updateUIView` rebuilds
  the scene to a fresh EMPTY one on every SwiftUI render (line 102), and the stale-self
  `onRebuild` redraw saw `routePlan == nil` and drew nothing — so every rebuild wiped the
  routes a fresh-context draw had just added. The screenshot always caught the empty scene.
  That is exactly why the overlay unit test (calls `show()` directly) passed while the app
  showed nothing.

**Fix:** cache the draw inputs (plan, selectedRoomID, model) AND the view state (explode,
spotlight) in the stable `RouteOverlayHolder` class. `onRebuild` now redraws from the holder,
never from captured @State. Fresh-context callers (`fetchRoutes` completion, the room/profile
pickers, the explode/spotlight controls) sync the holder then apply. `invalidateRoutes` clears
`holder.plan` so a post-edit rebuild doesn't redraw stale routes.

**Twin bug fixed at the same time:** `applyViewState` (explode/spotlight) had the identical
stale-@State-in-`onRebuild` flaw — the explode slider would snap back to 0 on any rebuild.
Routed through the holder too.

**Confirmed visually:** re-ran the screenshot driver — orange primary + blue secondary routes
now render, all 7 primaries in "Everyone", green exit-glows, on the new dark stage. Live chat
also confirmed working now that the key is in `.env` (spinner + a 200 from Anthropic in the
backend log).

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

## Live AI unlocked

Key now lives in repo-root `.env` (Anish added it). Ran the live backend suite
(`-m live`, key sourced): **11 passed, 1 fixed**. The one failure was real — the house
builder (`app/ai/builder.py`) still sent `temperature`, which the current model rejects with
`400 "temperature is deprecated for this model"`; `agent.py`/`grounded.py`/`chat/service.py`
already carry that lesson. Dropped the param; builder live golden passes.

## Gate after all changes

EditorCore 186 · backend 248 (not-live) · backend live 12 pass · corpus valid ·
iOS full suite (unit + UI) re-run at the end.

## Next

1. Persist `ANTHROPIC_API_KEY` for the Render deploy (in `.env` locally now; still needs the
   Render dashboard env var so the DEPLOYED backend's AI endpoints stop 502ing).
2. Remaining machine-closable iOS gaps (untouched): `setOpeningWidth` UI, shared
   `HomeLibrary`, selection markers, launch screen, agent-finding `id` threading.
3. Give the S3.2 agent a `check_obstructions` tool so the AI phrases the "move the wardrobe"
   advice conversationally (deterministic layer is built + tested; only wiring left).
