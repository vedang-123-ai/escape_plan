# Conventions

- **Python**: 3.11+, fully typed, pydantic v2 models, pytest. Routing code is pure functions
  (no I/O) so the engine and the agent tools share one implementation.
- **Swift**: SwiftUI, iOS 17+ target, Codable structs mirroring the schema exactly (round-trip
  test required). SceneKit for 3D (RealityKit acceptable if documented in decisions.md).
- **Secrets**: `ANTHROPIC_API_KEY` server-side env var only — never in the app, never in git
  (a pre-commit hook scans staged diffs). Backend endpoints sit behind a shared bearer token.
- **Review**: small commits, and review is **agent-run, not human**. Vet a branch with the
  relevant quality agents (`schema-contract-guardian` for `schema/`, `swift-scenekit-reviewer`
  for `escape_plan/`), run the green gate, judge it yourself, then merge to `main`. Do not tag a
  human reviewer or leave a PR open awaiting sign-off.
- **Citations**: corpus content uses inline `[cite: source-id]` tags resolving against
  `backend/corpus/sources.json` (see rules/paths/corpus.md).
- **Scope locks** (do not relitigate): fire, earthquake and severe weather (tornado); iOS only;
  LiDAR scan only; no user accounts. Out of scope on purpose: furniture detection, camera-only
  capture, Android, multi-user sync, disasters beyond those three.
  Multi-peril was approved 2026-09-05 with the S6 readiness arc — it was fire-only before that.
