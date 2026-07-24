# Revamp B1–B3 + C1–C2 — objects, obstacle routing, LLM house builder

- **Who:** P2 (Claude session, lane/editor worktree)
- **Date(s):** 2026-07-23 (same session as revamp A1–A3; five commits, one per phase)
- **Status when I stopped:** the ENTIRE approved revamp (spec:
  `~/.claude/plans/i-want-you-to-tender-flask.md`) is implemented and green.

## What happened

- **B1 — schema v1.1**: `floor.objects[]` box primitives (no room_id — geometric
  containment) + `source: ai_plan`; three-way lockstep + SchemaMigrator 1.0→1.1 + planted
  `bungalow-blocked.json`. Own commit per the schema PR rule.
- **B2 — objects in the app**: prisms in the renderer (RenderOrder band 5), full editor
  vocabulary (add/drag/rotate/resize/category/delete), rotated-rect hit-testing,
  HouseScreen tool + inspector.
- **B3 — obstacle-aware routing**: per-room 0.1 m grids + deterministic integer A* +
  LOS smoothing; blocked doorway ⇒ edge omitted ⇒ Dijkstra re-plans + `blocked_opening`
  finding; `path` waypoints splice into routes. Object-free rooms byte-identical to pre-B3
  (zero golden churn, asserted). Sample: `docs/route-samples/bungalow-blocked.json`.
- **C1 — builder backend**: pure action layer mirroring the editor vocabulary (pydantic as
  shared semantic gate, adjacency-derived interior/EXTERIOR), hand-rolled tool loop
  (cap 40, NO routing tools, structural ai_plan stamping), `POST /build`.
- **C2 — plan import + review gate**: BuildFromPlanView (text/photo/PDF→PNG client-side),
  ai_plan always needs review, `hasAIDraftContent` blocks `/routes` until
  `.confirmAIDraft` — structural, un-bypassable.

## Verification (all green at close)

backend 227 pass (+ live builder golden gated on the API key), editorcore 186, full iOS
unit+UI suite, corpus valid, manual-build recording driver passes against a live local
backend on the merged HouseScreen.

## Decisions / surprises

All in `docs/decisions.md` (six dated entries for 2026-07-23). Highlights: grid-over-navmesh
per ROOM; start-vs-goal landing radii (what makes blocked-doorway detection work);
builder's structural provenance stamping; intake scope-lock relaxed to LiDAR + reviewed AI
draft.

## Questions for teammates

- @P1/@P3: device-acceptance on the unified HouseScreen + the new object/plan-import flows.
- Live builder golden needs `ANTHROPIC_API_KEY` (same blocker as every live suite).

## Next steps

Device pass; then consider surfacing `blocked_opening` findings in the score/analyze
layers (S3.2 agent could reference them — not wired, deliberately out of this scope).
