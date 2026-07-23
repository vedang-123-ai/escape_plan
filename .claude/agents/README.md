# agents/

Delegatable, read-only review jobs. Each has a narrow remit so its findings are trustworthy.

| Agent | Remit |
|---|---|
| `quality/session-auditor` | Evidence-based audit of a session's acceptance criteria before declaring it DONE |
| `quality/doc-auditor` | Documentation drift: stale claims, cross-file contradictions, dead path/glob references |
| `quality/schema-contract-guardian` | The one law — JSON Schema, pydantic, and Swift Codable staying in lockstep |
| `quality/grounding-auditor` | The AI layer's non-negotiables: every claim cited, citations resolve, AI never routes |
| `quality/swift-scenekit-reviewer` | Swift / SwiftUI / SceneKit changes under `escape_plan/` |
| `quality/lane-integrator` | Verifying parallel-lane work coexists, then running the full gate |

`_TEMPLATE.md` is the scaffold — copy it, don't invoke it.

Add an agent only when a recurring, delegatable job emerges that benefits from a fresh context.
