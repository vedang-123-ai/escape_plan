# escape_plan/ — iOS app (SwiftUI)

The iOS half of the project. Read the root `CLAUDE.md` first; Swift conventions are in
`.claude/rules/languages/swift.md`.

Status notes (see docs/decisions.md):

- This is still the stock Xcode "App with Core Data" template — S0.3 (owner P2) is expected
  to replace `Persistence.swift`/`ContentView.swift` wholesale. Playbook default persistence
  is local JSON via FileManager, not Core Data.
- The project lives at the repo root instead of the playbook's `ios/` layout because moving
  it would break the open Xcode session. P2 decides at S0.3 whether to relocate; update the
  root CLAUDE.md and decisions.md if it moves.

Target structure once S0.3 lands (playbook §2.3): `Models/` (Codable schema mirror +
round-trip test), `Scan/` (RoomPlan), `Engine3D/` (SceneKit dollhouse), `Editor/`,
`Screens/`, `Networking/` (APIClient with configurable base URL + bearer token).
