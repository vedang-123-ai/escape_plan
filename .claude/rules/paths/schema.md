---
description: HomeModel schema contract rules
globs: ["schema/**"]
alwaysApply: false
---

# Schema rules (schema/)

`homemodel.schema.json` is the project's one law. It gets finalized in S0.2; after that:

- Any change requires a `schema_version` bump and team sign-off, via PR. A PreToolUse hook
  will ask for explicit confirmation before edits to the existing file.
- Keep JSON Schema (draft 2020-12), `backend/app/models.py` pydantic models, and the Swift
  Codable structs in lockstep — a schema change is incomplete until all three agree and the
  Swift round-trip test still passes.
- Validation invariants live in pydantic, not just the schema: polygons non-self-intersecting
  and CCW, openings reference existing rooms/edges, stairs reference existing floors/rooms,
  ids unique.
- `fixtures/` are the project-wide test bed (`bungalow.json`, `apartment.json`,
  `twostory.json`, plus `scans/` for raw RoomPlan exports). Keep them realistic; seed them
  with plantable safety issues on purpose (single-exit apartment, too-small egress window) —
  S3.2's agent tests assert those are found.
