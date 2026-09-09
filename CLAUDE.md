# Escape Plan — Congressional App Challenge 2026

iOS app that builds a structured 3D model of a home — a full 3D editor, accelerated by an Apple
RoomPlan LiDAR scan — and computes personalized readiness on it for **fire, earthquake and severe
weather**. A deterministic Python engine computes routes and shelters and renders them as animated
paths on a SceneKit dollhouse. A server-side Claude layer explains, chats and audits, grounded in a
curated FEMA/NFPA/Red Cross corpus.

**The AI never computes a route and never invents safety guidance.** That separation is the answer
to a judge asking "isn't this an AI wrapper?" — defend it in every design decision.

**Deadline: submit by Oct 24, 2026.** End-to-end demo path working by Oct 5.

## Status lives in two files — read, don't guess

| File | Holds |
| --- | --- |
| **[`docs/tracker/BLOCKERS.md`](docs/tracker/BLOCKERS.md)** | **Start here.** Everything blocking or unverified, ranked by critical path. |
| [`docs/tracker/TODO.md`](docs/tracker/TODO.md) | The long-tail backlog. |

**The rule: anything not done, blocked, or unverified goes into `BLOCKERS.md` in the session you
discover it** — not in a note, not in a commit message, not in your head. Remove a line only when
you personally verified it; "the code exists" is not verification. This repo has a documented
history of the tracker contradicting itself in nine places, because status was a habit instead of
a mechanism. Don't route around the mechanism.

## Read these when — and only when — you're in that territory

Nothing below auto-loads. Open the one that matches what you're touching.

| Working on | Read first |
| --- | --- |
| Anything under `schema/`, `backend/app/models.py`, `escape_plan/Models/` | `.claude/rules/paths/schema.md` |
| `backend/corpus/`, or any user-facing safety string | `.claude/rules/paths/corpus.md` |
| The AI layer, prompts, `/explain` `/chat` `/analyze` | `.claude/rules/vendors/anthropic.md` |
| Python / the backend | `.claude/rules/languages/python.md`, `backend/CLAUDE.md` |
| Swift / the iOS app | `.claude/rules/languages/swift.md`, `escape_plan/CLAUDE.md` |
| Running a playbook session S0.1–S7.10 | `docs/playbook/S<x>-<y>.md`, then `docs/decisions.md` |
| Why something is the way it is | `docs/decisions.md` (running log of deviations) |
| Adding a dependency | `docs/tools-used.md` — required for CAC originality |

## The one law: the HomeModel schema

`schema/homemodel.schema.json` is the contract. The converter produces it, the editor mutates it,
the engine consumes it, the agent inspects it, the renderer draws it. Changing it needs a
`schema_version` bump and a clean `schema-contract-guardian` run — **review is agent-run, there is
no human sign-off and no PR gate.** Invariants:

- Room footprints are 2D polygons per floor; 3D is extruded — **never store meshes.**
- Openings reference wall segments parametrically (`edge_index` + `t0/t1`), so dragging a wall
  moves its doors. Never position openings by absolute coordinates.
- `EXTERIOR` is a reserved pseudo-room id; `room_ids: [room, "EXTERIOR"]` marks an exit.
- Scan-derived items carry `source` + `confidence`; low-confidence items are flagged for editor
  review, **never silently dropped.**
- JSON Schema, pydantic and Swift Codable stay in lockstep. A schema change is incomplete until
  all three agree and the Swift round-trip test passes.

## Traps that have already cost this project real sessions

- **The Anthropic account is out of credits.** `/explain`, `/analyze` and `/chat` returning **502
  is expected.** It is billing, not code. If you find yourself reading `backend/app/ai/`, stop.
- **SourceKit and VS Code cannot index this project.** They report errors that do not exist.
  Trust `xcodebuild` only; ignore the editor's diagnostics completely.
- **A red iOS run is ~1-in-3 environmental flake.** Re-run once before believing it. True counts
  come from `xcrun xcresulttool get test-results summary --path <bundle>`, never the console tail
  (which prints `Executed 16 tests` because the unit target runs under Swift Testing).
- **Never re-enable `allowsCameraControl`**, and keep `CameraRigModel` pure — no SceneKit, no
  UIKit. It is symlinked into a Foundation-only SwiftPM package and will fail to build otherwise.
- **Never introduce a new colour.** `escape_plan/Screens/Theme.swift` is the semantic scale.
  Route orange is reserved for lit routes and exits; advisory chrome uses dark amber.
- **No keys or tokens in source.** `ANTHROPIC_API_KEY` is a server-side env var; a pre-commit hook
  blocks Anthropic key material. `escape_plan/BackendConfig.local.json` is gitignored.

## Conventions

- **Python** 3.11+, fully typed, pydantic v2, pytest. Routing and conversion are pure functions —
  no I/O, no globals, deterministic — so the engine and the agent tools share one implementation.
  FastAPI endpoints are thin wrappers.
- **Swift** SwiftUI, iOS 17+, Codable structs mirroring the schema exactly. All model mutations go
  through the reducer-style `HomeModelStore` (undo/redo and autosave depend on it). Persistence is
  local JSON via FileManager. SceneKit for 3D.
- **Grounding** every safety claim carries an inline `[cite: source-id]` resolving against
  `backend/corpus/sources.json`, validated server-side. No source → it doesn't ship.
- **Commits** small. Vet a branch with the relevant quality agent, run `/verify`, judge it
  yourself, merge to `main`. Never tag a human reviewer or park a branch awaiting sign-off — that
  blocked S6.1 while three sessions waited.
- **Scope lock, not open for relitigation:** fire + earthquake + severe weather (tornado); iOS
  only; LiDAR scan only; no user accounts. Deliberately out: camera-only capture, Android,
  multi-user sync, any fourth peril, **custom/trained ML models**.
  - Multi-peril was approved 2026-09-05 with the S6 arc; **object-hazard detection was approved
    2026-09-08 with the S7 arc** (`docs/playbook/07-object-hazard-intro.md`, `S7-1.md`…`S7-10.md`;
    rule book `docs/object-hazard-spec.md`). "Furniture detection" was on this out-list until that
    approval — the sanctioned form is RoomPlan scan objects + guided manual tagging feeding a
    deterministic hazard engine, never custom ML. See `docs/decisions.md`.

## Validation

`/verify` runs the whole gate. Individually:

```bash
python3 backend/corpus/validate.py                        # corpus
python3 -m pytest backend/tests/ -m "not live"            # backend (drop -m only with a key)
swift test --package-path tools/editorcore                # EditorCore — fast, pure Foundation
xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build-merge CODE_SIGNING_ALLOWED=NO   # add -only-testing:escape_planTests to iterate
python3 scripts/demo-preflight.py                         # before any device build or filming
```

## Ending a session that changed a file

A Stop hook writes `docs/tracker/activity-log.md` for you. What it cannot do is interpret, so you
must also: **update `BLOCKERS.md`** (and `TODO.md` if the backlog moved), write a note in
`docs/tracker/notes/` (copy `_TEMPLATE.md`), and log any deviation in `docs/decisions.md` plus any
new dependency in `docs/tools-used.md`. No note, no DONE.

## Commands and agents

`/session <id>` · `/handoff <id>` · `/verify` · `/verify-docs` · `/tracker` · `/lanes` ·
`/validate-corpus`

`session-auditor` (acceptance evidence) · `doc-auditor` (doc drift) · `schema-contract-guardian`
(schema ↔ pydantic ↔ Swift) · `grounding-auditor` (citations, AI never routes) ·
`swift-scenekit-reviewer` · `lane-integrator`

**Repo note:** the Xcode project lives at the repo root (`escape_plan/`, `escape_plan.xcodeproj`)
rather than under `ios/` as the playbook specifies — moving it would break the open Xcode session.
See `docs/decisions.md`.
