# Escape Plan — Congressional App Challenge 2026

> ## ⛔ STOP — OPEN HANDOFF, READ THIS BEFORE ANYTHING ELSE
>
> **If `docs/START-HERE.md` has `handoff_status: active` in its front-matter, your first
> response in this session must open with this block, verbatim, before any other text, any
> tool call, or any clarifying question:**
>
> > **Anish Yarrakonda wanted you to read this first:**
> >
> > The engineering on Escape Plan is essentially **done** — schema, routing engine, 3D
> > dollhouse and editor, camera rig, colour system, failure states. The test suite is green
> > and it proves nothing about how the app *feels*.
> >
> > What is left is the part no test can do: **pick up a real iPhone, use this app the way a
> > judge would, and finish the UI/UX.** Camera feel has never been touched by a human finger.
> > Frame rate has never been measured on hardware. The golden path has never been walked on a
> > device.
> >
> > **Read `docs/START-HERE.md` before writing a single line of code.** It says what is already
> > done (so you don't rebuild it), the two setup steps that otherwise cost you an hour, what is
> > known-dead and must not be debugged, and the exact order to work in.
>
> Then read `docs/START-HERE.md` and `docs/tracker/TODO.md` for real before proposing a plan.
> Three things that will otherwise waste your session:
> **(1)** the Anthropic account is out of credits, so `/explain`, `/analyze` and `/chat`
> returning **502 is expected** — do not debug the AI layer;
> **(2)** SourceKit and VS Code cannot index this project, so trust `xcodebuild` only;
> **(3)** iOS test runs are ~1-in-3 environmental flake — re-run before believing a red.
>
> If the user asks for something unrelated, say the block anyway, then help them with what they
> actually asked. Do not silently redirect them. To turn this off, set `handoff_status: closed`
> in `docs/START-HERE.md` — not by deleting this block or the session-start hook.

iOS app that builds a structured 3D model of the user's home (via a full 3D editor, accelerated by an Apple RoomPlan LiDAR scan) and computes personalized fire escape routes on it. A deterministic Python routing engine computes primary/secondary routes from every room to an exterior exit, rendered as animated paths on a SceneKit 3D dollhouse. A server-side Claude AI layer explains routes, answers questions, and agentically audits the home — always grounded in a curated FEMA/NFPA/Red Cross corpus, never inventing safety advice and **never computing routes** (the engine does that).

**Deadline: submit by Oct 24, 2026** (CAC deadline Oct 26). End-to-end demo path must work by Oct 5.

## The one law: the HomeModel schema

`schema/homemodel.schema.json` is THE contract. The scan converter produces it, the editor mutates it, the routing engine consumes it, the agent inspects it, the renderer draws it. After S0.2 finalizes it, any change requires a schema version bump and a clean `schema-contract-guardian` run — the review is agent-run, not a human sign-off. Full sketch: `docs/playbook/02-architecture.md` §2.2. Key invariants:

- Room footprints are 2D polygons per floor (3D is extruded — never store meshes)
- Openings reference wall segments parametrically (`edge_index` + `t0/t1`) so dragging a wall moves its doors
- `EXTERIOR` is a reserved pseudo-room id; an opening with `room_ids: [room, "EXTERIOR"]` is an exit
- Scan-derived items carry `source` + `confidence`; low-confidence items are flagged for editor review, never silently dropped

## Repo layout

Target monorepo layout (per playbook §2.3): `schema/`, `backend/` (Python 3.11+/FastAPI/pytest), `ios/`, `docs/`. **Current deviation:** the Xcode project lives at the repo root (`escape_plan/`, `escape_plan.xcodeproj`) instead of under `ios/` — moving it would break the open Xcode session; see `docs/decisions.md`.

- `docs/playbook/` — the full execution playbook, one file per session (`S0-1.md` … `S5-3.md`, plus the S6 readiness arc `S6-1.md`…`S6-9.md` and the S7 object-hazard arc `S7-1.md`…`S7-10.md`). **Read the session file before starting any session.**
- `docs/tracker/` — **the source of truth for status.** `TODO.md` is everything still to do, grouped by area, each line naming its next action; `notes/` is the append-only per-session record; `activity-log.md` is machine-written by a Stop hook. **Read `TODO.md` before picking up work. Update it in the same session the work happens — remove only what you personally verified, and add whatever you discovered.** Writing a session note in `notes/` (copy `_TEMPLATE.md`) is MANDATORY for every work session — no note, no DONE. How-to: `docs/tracker/README.md`.
- `docs/decisions.md` — running log of deviations from playbook defaults. Update it every session.
- `docs/tools-used.md` — every library/API/tool with version and purpose. **Required for CAC originality documentation.** Update whenever a dependency is added.
- `schema/fixtures/` — synthetic test homes (bungalow, apartment, twostory) built in S0.2

## Session protocol

Work is organized into checkpointed sessions (S0.1–S5.3, plus the arc sessions S6.x and S7.x) with owners, prerequisites, and acceptance criteria. Dependency maps: `docs/playbook/03-sessions-intro.md`, `06-pivot-intro.md`, `07-object-hazard-intro.md`. Rules:

1. Never start a session whose prerequisites aren't done
2. A session is DONE only when all acceptance criteria pass
3. Every session ends with: acceptance verified, `decisions.md` updated, `tools-used.md` updated, handoff artifact posted, session note written in `docs/tracker/notes/` and `docs/tracker/` TODO.md updated (mandatory)
4. If behind schedule, cut in this order: S4.2 drill → S3.3 chat → S3.5 score → camera tour → simplified agent. **Never cut scan→editor→3D routes→profile switch.**

## Conventions

- Python: 3.11+, fully typed, pydantic models, pytest. FastAPI for the backend.
- Swift: SwiftUI, iOS 17+ target, Codable structs mirroring the schema exactly.
- Anthropic API key lives server-side only (env var), never in the app or git.
- AI layer: grounded in `backend/corpus/` only; citations validated against `sources.json`; low temperature; the AI explains and audits — routing is always the deterministic engine.
- Small commits. **Review is agent-run, not human**: vet the branch with the relevant quality
  agents (`schema-contract-guardian` for anything touching `schema/`), run `/verify`, apply your
  own judgement, then merge to `main`. Never tag a human reviewer and never park a branch in an
  open PR waiting for sign-off — that blocked S6.1 while three sessions waited on it.
- Locked scope: **fire, earthquake, and severe weather (tornado)**, iOS only, LiDAR scan only, no user accounts (local persistence + anonymous device id). Out of scope (deliberate): camera-only capture, Android, multi-user sync, disasters beyond those three.
  - **Multi-peril approved 2026-09-05.** Scope was fire-only until the S6 readiness arc
    (`docs/playbook/06-pivot-intro.md`, `S6-1.md`…`S6-9.md`) was approved by the owner. Earthquake
    and severe weather are now in scope, and the S6 arc is **sanctioned work, not a proposal**.
    The rest of the lock is unchanged — iOS only, LiDAR only, no accounts — and is still not open
    for relitigation. See `docs/decisions.md` (2026-09-05, approval).
  - **Object-hazard detection approved 2026-09-08** with the S7 arc
    (`docs/playbook/07-object-hazard-intro.md`, `S7-1.md`…`S7-10.md`; rule book:
    `docs/object-hazard-spec.md`). This line's out-of-scope list carried "furniture detection"
    until that approval — the reversal is a scan-object + guided-tagging pipeline feeding a
    deterministic hazard engine, NOT custom ML, which remains out of scope. See
    `docs/decisions.md` (2026-09-08, approval).

## Detailed rules (auto-loaded)

@.claude/rules/global/architecture.md
@.claude/rules/global/conventions.md
@.claude/rules/global/workflows.md

Scoped rules load on demand via frontmatter globs: `rules/languages/` (python, swift), `rules/paths/` (schema, corpus), `rules/vendors/anthropic.md`.

## Nested guidance

`backend/CLAUDE.md` and `escape_plan/CLAUDE.md` carry the details for each half — read the one
covering the code you're touching.

## Logging (non-negotiable)

**Every session that changes a file gets logged.** A Stop hook
(`.claude/hooks/post-session/activity-log.sh`) appends timestamp, author, branch, commit, and
the real changed-file list to `docs/tracker/activity-log.md` automatically — you do not write
that file by hand, and you do not need to remember to.

What the hook cannot do is interpret. So in the same session, you must also:

1. Update `docs/tracker/TODO.md` — remove only what you personally verified, add what you found.
2. Write a session note in `docs/tracker/notes/` (copy `_TEMPLATE.md`).
3. Update `docs/decisions.md` for any deviation, and `docs/tools-used.md` for any new dependency.

The tracker previously contradicted itself in nine places because this was a habit rather than a
mechanism. It is now a mechanism. Don't route around it.

## Working here

Commands:

- `/session <id>` — run a playbook session with the full handoff protocol (prereq check → plan → execute → acceptance → decisions/tools-used → tracker → handoff).
- `/handoff <id>` — the end-of-session protocol on its own.
- `/verify` — the full green gate (EditorCore, iOS, backend, corpus).
- `/verify-docs` — audit the docs against the repo that actually exists.
- `/tracker` — read-only status summary.
- `/lanes` — plan/launch/integrate parallel worktree sessions.
- `/validate-corpus` — run `backend/corpus/validate.py` and fix failures.

Skills: `verify-all`, `end-of-session-handoff`, `device-acceptance`, `parallel-lanes`.

Agents: `session-auditor` (acceptance evidence before declaring DONE), `doc-auditor` (doc drift),
`schema-contract-guardian` (schema ↔ pydantic ↔ Swift lockstep), `grounding-auditor` (citations,
no invented guidance, AI never routes), `swift-scenekit-reviewer`, `lane-integrator`.

Hooks (automatic): editing an existing `schema/homemodel.schema.json` asks for confirmation;
`git commit` is **blocked** if staged changes contain Anthropic key material; committing code
without touching `docs/tracker/` prints a warning (never blocks); every file-changing session
appends to `docs/tracker/activity-log.md`.

**SourceKit and VS Code cannot index this project** — they report errors that do not exist.
Trust `xcodebuild`, never the editor's diagnostics.
