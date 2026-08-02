# Routes survive a committed edit — 2026-08-02

Backs the claim that the 2026-07-30 merge did not reintroduce the 2026-07-24 blocker
("escape routes do not render"). Captured on the iPhone 17 Pro simulator against a local
backend, seeded `Two-Story House` fixture, by
`escape_planUITests/RouteRedrawAfterEditUITests`.

| File | What it shows |
|---|---|
| `before-edit.png` | Routes drawn on the merged build: orange primaries across both floors, green exit glows, fixture-kit doors/windows. Route check: "No issues flagged for this view". |
| `after-edit.png` | The same screen after **Add Object** commits — the edit path that clears the overlay, rebuilds the dollhouse, and fires `onRebuild`. Routes are **back and rerouted** around the new object. |

Why the pair matters: the bug's signature was never "the screen is broken," it was *"the route
controls appear but no route draws."* Both screenshots show the controls. Only the pixels in
the 3D view distinguish a working build from the regressed one, which is why the test asserts
on route-colored pixel count rather than on control existence.

**Unplanned bonus.** The object the test adds to force a commit landed in front of a doorway,
so `after-edit.png` also shows the obstruction layer working end to end in the UI: two red `!`
markers in the scene, a `Route check 3` badge, and the measured advice ("…there is no path to
that doorway at all. Moving it…") produced by `backend/app/routing/obstructions.py`. That was
not what the test was written to prove, but it is the first captured evidence of the
obstruction attribution reaching a user-visible surface.
