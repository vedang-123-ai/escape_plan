# escape_plan/ — iOS app (SwiftUI)

The iOS half of the project. Read the root `CLAUDE.md` first; Swift conventions are in
`.claude/rules/languages/swift.md`.

Status notes (see docs/decisions.md):

- S0.3 replaced the stock Core Data template wholesale: `Persistence.swift` and
  `escape_plan.xcdatamodeld` are gone. Persistence is local JSON documents via FileManager,
  landing in S2.4 — nothing persists yet, `HomeScreen` loads a bundled fixture as proof of
  decode.
- The project stays at the repo root (not the playbook's `ios/` layout) — see decisions.md;
  revisit if the team wants the monorepo layout before Phase 2.

Current structure (S0.3): `Models/` (Codable schema mirror, exact field names/optionality vs.
`schema/homemodel.schema.json` + `backend/app/models.py`; round-trip test in
`escape_planTests/`), `Fixtures/` (bundled copies of `schema/fixtures/*.json`), `Screens/`
(tab shell: Home/Editor/Plan/Assistant/Settings — only Home has real content), `Networking/`
(`APIClient` with configurable base URL + bearer token, `/health` check).
Still to come: `Scan/` (RoomPlan, S1.4), `Engine3D/` (SceneKit dollhouse, S1.3), `Editor/`
(S1.3+).
