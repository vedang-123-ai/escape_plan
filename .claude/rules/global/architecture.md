# Architecture baseline

Two halves, one contract:

- **iOS app (SwiftUI)** — RoomPlan scan capture, SceneKit 3D dollhouse renderer + editor,
  product UI (plan, profiles, checklist, chat, drill). Local persistence only (JSON documents,
  anonymous device id). Currently at repo root (`escape_plan/`, `escape_plan.xcodeproj`);
  target location is `ios/` — see docs/decisions.md before moving anything.
- **Backend (Python 3.11+ / FastAPI)** — `/convert` (RoomPlan → HomeModel), `/routes`
  (deterministic graph routing), `/analyze` (agentic inspector), `/explain`, `/chat`, `/score`.
  Anthropic API key lives here, env-var only.

## The contract

`schema/homemodel.schema.json` is the single source of truth (finalized in S0.2; after that,
changes need a schema_version bump + team sign-off — a hook enforces confirmation). Invariants:

- Room footprints are 2D polygons per floor; 3D is extruded — never store meshes.
- Openings reference wall segments parametrically (`edge_index` + `t0/t1`).
- `EXTERIOR` is a reserved pseudo-room id; `room_ids: [room, "EXTERIOR"]` marks an exit.
- Scan-derived items carry `source` + `confidence`; low-confidence items are flagged for
  editor review, never silently dropped.

## Division of labor (defend this in every design decision)

Routing is ALWAYS the deterministic Python engine. The AI layer explains, chats, and audits —
grounded exclusively in `backend/corpus/` with citations validated against `sources.json`.
The AI never computes routes and never invents safety guidance.

Full architecture: `docs/playbook/02-architecture.md`.
