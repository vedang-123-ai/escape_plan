# Escape Plan — Congressional App Challenge 2026

iOS app that builds a structured 3D model of the user's home (via a full 3D editor, accelerated by an Apple RoomPlan LiDAR scan) and computes personalized fire escape routes on it. A deterministic Python routing engine computes primary/secondary routes from every room to an exterior exit, rendered as animated paths on a SceneKit 3D dollhouse. A server-side Claude AI layer explains routes, answers questions, and agentically audits the home — always grounded in a curated FEMA/NFPA/Red Cross corpus, never inventing safety advice and **never computing routes** (the engine does that).

**Deadline: submit by Oct 24, 2026** (CAC deadline Oct 26). End-to-end demo path must work by Oct 5.

## The one law: the HomeModel schema

`schema/homemodel.schema.json` is THE contract. The scan converter produces it, the editor mutates it, the routing engine consumes it, the agent inspects it, the renderer draws it. After S0.2 finalizes it, any change requires a schema version bump and team sign-off. Full sketch: `docs/playbook/02-architecture.md` §2.2. Key invariants:

- Room footprints are 2D polygons per floor (3D is extruded — never store meshes)
- Openings reference wall segments parametrically (`edge_index` + `t0/t1`) so dragging a wall moves its doors
- `EXTERIOR` is a reserved pseudo-room id; an opening with `room_ids: [room, "EXTERIOR"]` is an exit
- Scan-derived items carry `source` + `confidence`; low-confidence items are flagged for editor review, never silently dropped

## Team & roles

- **P1** (human): backend, ML, routing engine, agentic AI, scan converter
- **P2** (human): iOS/SwiftUI, SceneKit 3D renderer + editor, RoomPlan capture
- **P3** (**Claude Code — that's you**): grounding corpus (S0.4), backend scaffold + deploy (S1.6), persistence (S2.4), chat assistant backend (S3.3), family profiles (S3.4), preparedness score (S3.5), drill mode (S4.2), demo script (S5.1), plus S1.5 support and testing throughout

## Repo layout

Target monorepo layout (per playbook §2.3): `schema/`, `backend/` (Python 3.11+/FastAPI/pytest), `ios/`, `docs/`. **Current deviation:** the Xcode project lives at the repo root (`escape_plan/`, `escape_plan.xcodeproj`) instead of under `ios/` — moving it would break the open Xcode session; see `docs/decisions.md`.

- `docs/playbook/` — the full execution playbook, one file per session (`S0-1.md` … `S5-3.md`). **Read the session file before starting any session.**
- `docs/tracker/` — team progress tracker: `board.md` (DONE / READY / BLOCKED right now), `checklist.md` (per-session acceptance checkboxes), `notes/` (session notes). **Check `board.md` before picking work; update it when a session flips status. Writing a session note in `notes/` (copy `_TEMPLATE.md`) is MANDATORY for every work session — no note, no DONE.** How-to: `docs/tracker/README.md`.
- `docs/decisions.md` — running log of deviations from playbook defaults. Update it every session.
- `docs/tools-used.md` — every library/API/tool with version and purpose. **Required for CAC originality documentation.** Update whenever a dependency is added.
- `schema/fixtures/` — synthetic test homes (bungalow, apartment, twostory) built in S0.2

## Session protocol

Work is organized into checkpointed sessions (S0.1–S5.3) with owners, prerequisites, and acceptance criteria. Dependency map in `docs/playbook/03-sessions-intro.md`. Rules:

1. Never start a session whose prerequisites aren't done
2. A session is DONE only when all acceptance criteria pass
3. Every session ends with: acceptance verified, `decisions.md` updated, `tools-used.md` updated, handoff artifact posted, session note written in `docs/tracker/notes/` and `docs/tracker/` board/checklist updated (mandatory)
4. If behind schedule, cut in this order: S4.2 drill → S3.3 chat → S3.5 score → camera tour → simplified agent. **Never cut scan→editor→3D routes→profile switch.**

## Conventions

- Python: 3.11+, fully typed, pydantic models, pytest. FastAPI for the backend.
- Swift: SwiftUI, iOS 17+ target, Codable structs mirroring the schema exactly.
- Anthropic API key lives server-side only (env var), never in the app or git.
- AI layer: grounded in `backend/corpus/` only; citations validated against `sources.json`; low temperature; the AI explains and audits — routing is always the deterministic engine.
- Small PRs; anything touching `schema/` goes through PR review.
- Locked scope: fire only, iOS only, LiDAR scan only, no user accounts (local persistence + anonymous device id). Out of scope (deliberate): furniture detection, camera-only capture, Android, multi-user sync, other disasters.

## Detailed rules (auto-loaded)

@.claude/rules/global/architecture.md
@.claude/rules/global/conventions.md
@.claude/rules/global/workflows.md

Scoped rules load on demand via frontmatter globs: `rules/languages/` (python, swift), `rules/paths/` (schema, corpus), `rules/vendors/anthropic.md`.

## Working here

- `/session <id>` — run a playbook session with the full handoff protocol (prereq check → plan → execute → acceptance → decisions/tools-used → handoff).
- `/validate-corpus` — run `backend/corpus/validate.py` and fix failures.
- `session-auditor` agent — evidence-based audit before declaring any session DONE; end-of-session checklist in `.claude/workflows/runbooks/end-of-session.md`.
- Hooks (auto): editing an existing `schema/homemodel.schema.json` requires explicit confirmation; `git commit` is blocked if staged changes contain Anthropic key material.
