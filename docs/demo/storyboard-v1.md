# Storyboard — **v1**

Companion to `script-v1.md` (supersedes `storyboard-v0.md`). Updated 2026-07-22.

Since v0 the situation inverted: in July the app didn't exist, so everything was a shot list.
Now S1.3/S2.1/S2.2/S2.3/S3.2–S3.5 are code-complete and integrated — **every shot below is
recordable from the current build**; what's missing is captures, not features. A b-roll lane
(Worktree 4) is capturing fresh recordings concurrently against this file.

## The b-roll contract — canonical artifact paths

**This section is the contract.** The b-roll lane (and any device session) delivers into these
exact paths under `docs/demo/broll/` (create the directory with the first file — v0's standing
request, now binding). If a take can't match its path, rename here first, not ad hoc.

| Canonical path | Beat | Shot | Source session |
|---|---|---|---|
| `docs/demo/broll/s14-roomplan-capture.mov` | 2 | Full RoomPlan capture, clean take (the unfakeable shot — needs LiDAR device + home) | S1.4 |
| `docs/demo/broll/s15-flagged-items.mov` | 2 | Raw converted model with low-confidence items visibly flagged | S1.5 + S1.3 |
| `docs/demo/broll/s22-editor-walldrag.mov` | 3 | Wall drag with doors/windows following (*the* shot — frame wall + its door together) | S2.1/S2.2 |
| `docs/demo/broll/s22-flagged-to-fixed.mov` | 3 | A flagged item going flagged → fixed; add stairs | S2.2 |
| `docs/demo/broll/s23-routes-dollhouse.mov` | 4 | Slow dollhouse orbit, primary pulse-tube routes animating, dashed secondary via a *different* exit | S2.3 |
| `docs/demo/broll/s23-camera-tour.mov` | 4 | Camera tour down the stairs and out the door (**cuttable** — 4th in cut order) | S2.3 |
| `docs/demo/broll/s32-agent-findings.mov` | 5 | Findings populating in-app + the tool-call trace scrolling (strongest "not a wrapper" visual) | S3.2 (needs live key) |
| `docs/demo/broll/s34-profile-switch.mov` | 5 | PlanScreen "Who" picker: switch to Grandpa (mobility_limited), routes re-fetch and redraw — **one continuous take**, a cut reads as a cheat | S3.4 |
| `docs/demo/broll/s35-score-checklist.mov` | 6 | Score screen with component breakdown open; toggle a checklist item, score re-animates | S3.5 |
| `docs/demo/broll/s42-drill.mov` | 6 | Timed drill run (**[PENDING: S4.2]** — session not started; don't wait on this) | S4.2 |
| `docs/demo/broll/s12-routing-cli.mov` | 7 | Terminal: `python3 -m app.routing plan ../schema/fixtures/twostory.json --pretty` — **recordable today** | S1.2 |
| `docs/demo/broll/team-oncamera.mov` | 7 | The three of us in one frame (shootable whenever we're together) | S5.x |
| `docs/demo/broll/night-house.mov` | 1 | Dark hallway / smoke alarm / house at night — phone footage fine, no app dependency | — |

**Capture standards (every take):** landscape, clean screen-record (no notifications, no
debug overlays), one uninterrupted take per shot, real fixture data (`twostory` is the demo
home — it carries the seeded too-small kids' window). For any shot hitting the live backend:
warm-up ping first (Render free tier cold-starts) and make sure `ANTHROPIC_API_KEY` is set —
the Render deploy doesn't have it as of 2026-07-22, so AI shots run against a keyed local
backend until that lands.

**Storage:** committed `.mov` files will bloat the repo — still the open question from v0.
Until P1 decides, keep takes ≤30s and ≤50 MB each, or park large takes on the shared drive
and commit `docs/demo/broll/INDEX.md` mapping canonical path → drive link. Either way the
*names* above stay the contract.

---

## Beat-by-beat

### Beat 1 — Hook (~0:22)
- **A-roll:** title card / `night-house.mov`. On screen: the two statistics with visible Red
  Cross source attribution (if it's not in `backend/corpus/`, it doesn't go on screen).
- **Exists:** shootable today, no dependencies.

### Beat 2 — The honest scan (~0:30)
- **A-roll:** person walking the home phone-in-hand; `s14-roomplan-capture.mov` building rooms
  in real time; cut to `s15-flagged-items.mov` for "it also gets things wrong."
- **Status:** the only beat still blocked on hardware — S1.4 needs a real LiDAR device and a
  home. Everything else in the video can be captured before this shot exists.

### Beat 3 — The editor (~0:28)
- **A-roll:** `s22-editor-walldrag.mov` (doors following the wall is the visual proof of the
  parametric-opening invariant), then `s22-flagged-to-fixed.mov`.
- **Status:** feature shipped (S2.1/S2.2 green); awaiting capture only. Keep on-camera edits
  to normal drags — edge-case placements have no geometric containment checks (decisions.md
  S2.2) and can look nonsensical.

### Beat 4 — The money shot (~0:28, longest single visual)
- **A-roll:** `s23-routes-dollhouse.mov` — orbit, primary pulse tube animating from the
  bedroom, dashed secondary appearing through a *different* exit (the script says "different
  exit" out loud; the shot must show it — pick the twostory bedroom, both routes on screen).
  Optionally `s23-camera-tour.mov`; if the tour is cut, hold the orbit longer.
- **Fallback that exists today:** `docs/graphs/*.png` + `docs/route-samples/*.json`. Honest
  and ugly; only if capture catastrophically fails. Never mock up a fake 3D shot.

### Beat 5 — Inspector + profile switch (~0:36)
- **A-roll:** `s32-agent-findings.mov` (findings populate; tap the kids'-room finding, room
  highlights; let the tool-call trace scroll), then `s34-profile-switch.mov` (one continuous
  take: pick Grandpa, watch routes redraw and jump to his bedroom).
- **Accuracy rails (from script-v1 Beat 5):** the finding on camera is the **too-small
  window** (agent `check_egress`), not "no second way out"; the profile switched on camera is
  **mobility_limited** (or elderly) — never the child profile, which changes zero routes.
- **Cutaway that exists today:** side-by-side diff of `twostory.routeplan.json` vs
  `twostory.mobility-limited.routeplan.json` — same home, two profiles, different routes.

### Beat 6 — Montage (~0:20, fast cuts)
- **A-roll:** `s35-score-checklist.mov` (breakdown open → toggle → count-up re-animation),
  then `s42-drill.mov` **only if S4.2 ships**. Film the score after an `/analyze` run or crop
  the findings row (reads full marks until wired — script-v1 caveat).
- **Note:** still the most-cuttable beat. Shoot last, from whatever survived.

### Beat 7 — Learnings + next (~0:22)
- **A-roll:** `team-oncamera.mov`, closing on a last dollhouse shot.
- **Cutaway while VO says "we wrote the routing engine":** `s12-routing-cli.mov` or a scroll
  through `backend/app/routing/engine.py`. **Recordable today.** Real code beats a slide.

---

## What exists in-repo today (fallbacks / cutaways)

| Asset | Where | Usable for |
|---|---|---|
| Nav-graph renderings (3 fixtures) | `docs/graphs/*.png` | Beat 4 fallback, Beat 7 cutaway |
| Route plans, 3 fixtures + mobility-limited | `docs/route-samples/*.json` | Beat 4/5 cutaways, profile diff |
| Routing CLI live run | `backend/app/routing/` | Beat 7 — honest and fast |
| `/routes` + `/explain` API responses | deployed backend | Beat 5 cutaway (warm-up ping; `/explain` needs key) |

No `.mov`/`.mp4` exists in the repo yet — the table above plus the b-roll contract is the
complete footage plan.

## Open questions (carried from v0)

1. **B-roll storage** — git vs shared drive + committed `INDEX.md`. Decide before
   `s14-roomplan-capture.mov` lands (flagged to P1; interim rule above).
2. **Landscape vs portrait** — standard above says landscape (CAC judges watch on laptops);
   revisit only before S1.4 records, then it's locked.
3. **Screen-recording vs over-the-shoulder** for beats 2–5 — over-the-shoulder is warmer and
   matches the script's tone; needs a second person at capture time.
