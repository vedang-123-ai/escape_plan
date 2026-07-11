# Conventions

- **Python**: 3.11+, fully typed, pydantic v2 models, pytest. Routing code is pure functions
  (no I/O) so the engine and the agent tools share one implementation.
- **Swift**: SwiftUI, iOS 17+ target, Codable structs mirroring the schema exactly (round-trip
  test required). SceneKit for 3D (RealityKit acceptable if documented in decisions.md).
- **Secrets**: `ANTHROPIC_API_KEY` server-side env var only — never in the app, never in git
  (a pre-commit hook scans staged diffs). Backend endpoints sit behind a shared bearer token.
- **PRs**: small; anything touching `schema/` goes through PR review.
- **Citations**: corpus content uses inline `[cite: source-id]` tags resolving against
  `backend/corpus/sources.json` (see rules/paths/corpus.md).
- **Scope locks** (do not relitigate): fire only, iOS only, LiDAR scan only, no user accounts.
  Out of scope on purpose: furniture detection, camera-only capture, Android, multi-user sync,
  other disasters.
