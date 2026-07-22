# Storyboard — **DRAFT v0**

> **SUPERSEDED 2026-07-22 by `storyboard-v1.md`** — the b-roll path contract lives there now.

Companion to `script-v0.md`. Same status: early draft, written 2026-07-16, nothing locked.

This maps each beat to the footage it needs and says plainly whether that footage **exists
today** or is a **shot to capture**. Almost everything visual is a shot to capture, because the
iOS app hasn't been scaffolded yet (S0.3 is still READY, not DONE — see `docs/tracker/board.md`).

**The point of this file:** every session from here to S4.1 produces a handoff artifact, and most
of those artifacts are screen-recordable moments. If each session records 30 seconds of its own
work *as it lands*, October is an edit, not a shoot. The shot list below is the ask.

---

## What footage already exists

| Asset | Where | Usable for |
|---|---|---|
| Nav-graph renderings (bungalow, apartment, twostory) | `docs/graphs/*.png` | Beat 4 cutaway, Beat 7 "we wrote the engine" |
| Route plan JSON, 3 fixtures + 1 mobility-limited | `docs/route-samples/*.json` | Beat 4 / Beat 5 cutaway (terminal or pretty-printed) |
| Routing CLI (`python3 -m app.routing plan …`) | `backend/app/routing/` | Beat 7 — a live terminal run is honest and fast |
| `/routes` + `/explain` API responses | `backend/` | Beat 5 cutaway |

That's the whole inventory. Everything else is a shot list.

---

## Beat-by-beat

### Beat 1 — Hook (~0:22)

- **A-roll:** none. Title card / black.
- **Shots to capture:** a dark hallway, a smoke alarm, a house at night. Can be stock or shot on
  a phone. Nothing app-related.
- **On screen:** the two statistics with their source attributions visible (Red Cross). Per
  `.claude/rules/paths/corpus.md`, if it's not in `backend/corpus/`, it doesn't go on screen.
- **Exists:** no. **Blocked on:** nothing — this beat is shootable today.

### Beat 2 — The honest scan (~0:30)

- **A-roll:** a real person walking a real home holding a phone; screen recording of the RoomPlan
  capture UI building the room in real time.
- **Shot to capture — owner P2, from S1.4.** `[PENDING: S1.4]`
  - Screen recording of a full capture session on a LiDAR device (this is the one shot that
    cannot be faked or reshot late — it needs the device *and* the home).
  - The reveal of the raw converted model with flagged low-confidence items visibly marked.
    `[PENDING: S1.5 + S1.3]`
- **Ask of S1.4's handoff:** whatever capture you record for the handoff, record it clean and
  landscape once. That take is probably the demo take.

### Beat 3 — The editor (~0:28)

- **A-roll:** hands on the phone: drag a wall (doors follow it), place the missed window, connect
  the stairs.
- **Shot to capture — owner P2, from S2.1/S2.2.** `[PENDING: S2.1]` `[PENDING: S2.2]`
  - The wall-drag with openings following is *the* shot — it's the visual proof of the
    parametric-opening invariant. Frame it so both the wall and its door are on screen.
  - A flagged item going from flagged → fixed.
- **Exists:** no.

### Beat 4 — The money shot (~0:28, the longest single visual)

- **A-roll:** the SceneKit dollhouse, routes animating out of every room, camera tour descending
  the stairs and out the front door.
- **Shot to capture — owner P2, from S1.3 (+ S2.3).** `[PENDING: S1.3]`
  - Slow orbit of the dollhouse with primary routes drawn.
  - Secondary route appearing in a second color through a *different* exit — the script says
    "different exit" out loud, so the shot has to show it.
  - Camera tour. `[PENDING: camera tour]` — 4th in the cut order; if cut, hold the orbit longer.
- **Exists today (fallback + cutaway):** `docs/graphs/*.png` and `docs/route-samples/`. If S1.3
  slips catastrophically, a rendered 2D path over the floorplan plus real JSON is an honest, ugly
  fallback. Say so on camera rather than mocking up a fake 3D shot.

### Beat 5 — Inspector + profile switch (~0:36)

- **A-roll:** the findings list populating; tap a finding, the room highlights; switch profile,
  routes visibly redraw.
- **Shots to capture:**
  - Agent findings appearing in-app — owner P1/P3, from S3.2. `[PENDING: S3.2]`
  - Profile switch redrawing routes — owner P3, from S3.4. `[PENDING: S3.4]` `[PENDING: S2.3]`
    The redraw must be one continuous take. A cut here reads as a cheat.
- **Exists today (cutaway):** `docs/route-samples/twostory.routeplan.json` vs
  `twostory.mobility-limited.routeplan.json` — the same home, two profiles, different routes,
  already committed. Diffing these side by side is a real cutaway we could cut *today*.
- **Ask of S3.2's handoff:** record the agent's tool-call trace scrolling. It's the strongest
  visual answer to "isn't this an AI wrapper?" — you can see it inspecting the model.

### Beat 6 — Montage (~0:20, fast cuts, 3–4 shots)

- **Shots to capture:** score screen with its explanation open (`[PENDING: S3.5]`), checklist with
  a house-specific item (`[PENDING: S4.x]`), drill running with a timer and a kid actually moving
  (`[PENDING: S4.2]`).
- **Note:** all three are on the cut list. Shoot this beat last, from whatever survived. The drill
  shot needs a family and daylight — it's the only beat with a scheduling dependency outside the
  team.

### Beat 7 — Learnings + next (~0:23)

- **A-roll:** the three of us, on camera, in one frame. Then a last dollhouse shot to close.
- **Cutaway while VO says "we wrote the routing engine":** a live terminal run of
  `python3 -m app.routing plan ../schema/fixtures/twostory.json --pretty`, or a scroll through
  `backend/app/routing/engine.py`. **Exists today.** Real code beats a slide.
- **Exists:** the cutaway yes; the team shot no.

---

## Shot list — the ask, by owner

| # | Shot | Owner | Comes from | Status |
|---|---|---|---|---|
| 1 | Night house / smoke alarm B-roll | anyone | — | Shootable today |
| 2 | RoomPlan capture, full session, clean take | P2 | S1.4 | `[PENDING: S1.4]` — needs device + home |
| 3 | Flagged low-confidence items on the raw model | P2 | S1.5 + S1.3 | `[PENDING]` |
| 4 | Wall drag, doors following | P2 | S2.1 | `[PENDING]` |
| 5 | Flagged → fixed | P2 | S2.2 | `[PENDING]` |
| 6 | Dollhouse orbit, primary routes animating | P2 | S1.3 | `[PENDING]` — the money shot |
| 7 | Secondary route via a different exit | P2 | S1.3 | `[PENDING]` |
| 8 | Camera tour down the stairs | P2 | S1.3 | `[PENDING]` — cuttable |
| 9 | Agent findings populating + tool-call trace | P1/P3 | S3.2 | `[PENDING]` |
| 10 | Profile switch, one continuous take | P3 | S3.4 | `[PENDING]` |
| 11 | Score / checklist / drill | P3 | S3.5, S4.x, S4.2 | `[PENDING]` — all cuttable |
| 12 | Team on camera | all | S5.x | Shootable once we're all together |
| 13 | Terminal run of the routing CLI | P1/P3 | S1.2 | **Exists / recordable today** |

**Standing request for every session from here to S4.1:** when your handoff artifact is a working
UI, screen-record it once, cleanly, landscape, no notifications, and drop it in `docs/demo/broll/`
(directory doesn't exist yet — first person to record it creates it). Cost: two minutes. Savings
in October: enormous.

---

## Open questions

1. Where does b-roll live? `docs/demo/broll/` in git will bloat the repo fast. A shared drive with
   an index file committed here is probably the right call — decide before shot 2 lands.
2. Landscape or portrait? Portrait is honest for a phone app; CAC judges watch on laptops. Pick
   once, before S1.4 records anything.
3. Is a screen recording enough for beats 2–5, or do we need over-the-shoulder shots of a person
   holding the phone? Over-the-shoulder is warmer and matches the script's tone.
