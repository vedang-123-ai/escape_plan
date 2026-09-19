# Escape Plan — Congressional App Challenge 2026

iOS home-safety **readiness and prevention** app. It builds a structured 3D model of a home — a full 3D
editor, accelerated by an Apple RoomPlan LiDAR scan — and a deterministic Python engine computes routes,
shelters, hazard findings, a readiness score and a checklist for **fire, earthquake and severe weather
(tornado)**, drawn as animated paths on a SceneKit dollhouse. A server-side Claude layer explains, chats
and audits, grounded in a curated, cited FEMA/NFPA/Red Cross/USFA corpus.

**The AI never computes a route and never invents safety guidance.** That separation is the answer to a
judge asking "isn't this an AI wrapper?" — defend it in every design decision.

**It is not a tool for firefighters to use mid-fire** (a working firefighter told us so). It is a prevention
and readiness app with an opt-in "share with your fire department" snapshot. Never claim otherwise.

**Deadline: submit by Oct 24, 2026.** End-to-end demo path working by Oct 5.

## Where things live

| Question | Read |
| --- | --- |
| What is blocked, unverified or not done? | **[`docs/tracker/BLOCKERS.md`](docs/tracker/BLOCKERS.md)** — start here |
| What are we building and why? | [`docs/playbook/01-product-spec.md`](docs/playbook/01-product-spec.md) (spec v3, scope lock) |
| What is my next session, and on which branch? | [`docs/playbook/README.md`](docs/playbook/README.md) — the S11 arc, 13 sessions, three lanes |
| Long-tail backlog | [`docs/tracker/TODO.md`](docs/tracker/TODO.md) |
| Why is it this way? | `docs/decisions.md` (running log of deviations) |
| Adding a dependency | `docs/tools-used.md` (required for CAC originality) |

**The rule: anything not done, blocked, or unverified goes into `BLOCKERS.md` in the session you discover it**
— not a note, not a commit message, not your head. Remove a line only when you personally verified it; "the
code exists" is not verification. This repo has a history of the tracker contradicting itself and of decision
entries that did not match the filesystem. Do not route around the mechanism.

## Read these when — and only when — you are in that territory

Nothing below auto-loads.

| Working on | Read first |
| --- | --- |
| `schema/`, `backend/app/models.py`, `escape_plan/Models/` | `.claude/rules/paths/schema.md` |
| `backend/corpus/`, or any user-facing safety string | `.claude/rules/paths/corpus.md` |
| The AI layer, prompts, `/explain` `/chat` `/analyze` `/build` | `.claude/rules/vendors/anthropic.md` |
| Python / the backend | `.claude/rules/languages/python.md`, `backend/CLAUDE.md` |
| Swift / the iOS app | `.claude/rules/languages/swift.md`, `escape_plan/CLAUDE.md` |
| `docs/tracker/`, `docs/decisions.md`, `docs/tools-used.md` | `.claude/rules/paths/docs.md` |
| `tools/editorcore/` or any file it symlinks | `.claude/rules/paths/editorcore.md` |

## Branching — three people work in parallel

- One branch per playbook session: `s11-N-slug`, cut from `origin/main` (`git fetch origin && git switch -c
  s11-N-slug origin/main`), or a worktree (`git worktree add ../ep-s11-N -b s11-N-slug origin/main`).
- **Never commit to `main`.** Merge finished work with `git merge --no-ff` after the session's gate is green,
  then push. There is no human sign-off and no PR gate; never tag a reviewer or park a branch awaiting one.
- Touch only the session's OWNED FILES (listed in its playbook file). Anything else goes in `BLOCKERS.md`.
- Never rewrite shared history: no force-push, no rebase of anything already pushed.
- Run `git fetch origin` before starting and `git merge origin/main` before merging. Local `main` once fell
  164 commits behind `origin/main` while a teammate's arc landed there; check divergence, not just `git status`.
- `docs/decisions.md` and `docs/tracker/activity-log.md` merge with `merge=union` (`.gitattributes`); append
  inside your own section of `BLOCKERS.md`/`TODO.md`.

## The one law: the HomeModel schema

`schema/homemodel.schema.json` (currently `schema_version` 2.1) is the contract. The converter produces it,
the editor mutates it, the engine consumes it, the agent inspects it, the renderer draws it. Changing it needs
a `schema_version` bump and a clean `schema-contract-guardian` run — **review is agent-run, no human
sign-off.** Invariants:

- Room footprints are 2D polygons per floor; 3D is extruded — **never store meshes.**
- Openings reference wall segments parametrically (`edge_index` + `t0/t1`); never by absolute coordinates.
- `EXTERIOR` is a reserved pseudo-room id; `room_ids: [room, "EXTERIOR"]` marks an exit.
- Scan-derived items carry `source` + `confidence`; low-confidence items are flagged, **never silently dropped.**
- JSON Schema, pydantic and Swift Codable stay in lockstep; a schema change is incomplete until all three agree
  and the Swift round-trip test passes.

## Traps that have already cost this project real sessions

- **The Anthropic account may be out of credits** (check `BLOCKERS.md`). Then `/explain`, `/analyze`, `/chat`
  and `/build` return **502 by design** — billing, not code. Only touch `backend/app/ai/` in session S11.4.
- **SourceKit and VS Code cannot index this project** and report errors that do not exist. Trust `xcodebuild`
  and `scripts/typecheck-ios.sh`; ignore editor diagnostics.
- **A red iOS run is ~1-in-3 environmental flake.** Re-run once before believing it. True counts come from
  `xcrun xcresulttool get test-results summary --path <bundle>`, never the console tail.
- **Never re-enable `allowsCameraControl`**, and keep `CameraRigModel` pure (no SceneKit, no UIKit): it is
  symlinked into a Foundation-only package, as are `Auth/`, `Sync/` and `SemanticMatcher.swift`.
- **Never introduce a new colour.** `escape_plan/Screens/Theme.swift` is the semantic scale. Route orange is for
  lit routes and exits only; advisory chrome uses dark amber.
- **No keys or tokens in source.** `ANTHROPIC_API_KEY` is a server-side env var; a pre-commit hook blocks
  Anthropic key material. `escape_plan/BackendConfig.local.json` is gitignored.
- **Don't trust a clean merge.** A textually clean merge of `origin/main` once combined a flipped rotation with
  tests written for the original. Run the gate after every merge.

## Scope lock (restated 2026-09-18; full text in the product spec §4)

Fire + earthquake + severe weather (tornado); iOS only; LiDAR scan plus editor primary, with the text/photo
builder as a draft-only accessibility fallback; accounts and cloud sync **optional and soft-gated**, never
required and absent from the pitch; **no custom or trained ML**; no fourth peril, no Android. Fire is fully
code-quantified; earthquake and tornado are FEMA/NOAA-grounded readiness modules and must be labeled honestly.
Object hazards come from RoomPlan objects plus guided manual tagging — transient clutter is never claimed as
detected. Any change to this lock is a dated entry in `docs/decisions.md`.

## Conventions

- **Python** 3.11+, fully typed, pydantic v2, pytest. Routing and conversion are pure functions — no I/O, no
  globals, deterministic — so the engine and the agent tools share one implementation. FastAPI endpoints are
  thin wrappers.
- **Swift** SwiftUI, iOS 17+, Codable structs mirroring the schema exactly. All model mutations go through the
  reducer-style `HomeModelStore` (undo/redo and autosave depend on it). Local JSON via FileManager is the default
  store. SceneKit for 3D.
- **Grounding**: every safety claim carries an inline `[cite: source-id]` resolving against
  `backend/corpus/sources.json`, validated server-side. No source, it doesn't ship.
- **Commits** small. Vet with the relevant quality agent, run `/verify`, judge it yourself, then merge.

## Validation

`/verify` runs the whole gate. Individually:

```bash
python3 backend/corpus/validate.py                              # corpus
backend/.venv/bin/python -m pytest backend/tests/ -m "not live" # backend (create the venv: BLOCKERS §4)
swift test --package-path tools/editorcore                      # EditorCore — fast, pure Foundation
scripts/typecheck-ios.sh                                        # all iOS targets, NO simulator needed
xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build-merge CODE_SIGNING_ALLOWED=NO         # add -only-testing:escape_planTests to iterate
python3 scripts/demo-preflight.py                               # before any device build or filming
```

With no simulator, `scripts/typecheck-ios.sh` is the strongest check you have. It resolves every type, member
and conformance, but does not build, link or run anything: never report it as a passing test suite.

## Ending a session that changed a file

A Stop hook writes `docs/tracker/activity-log.md`. It cannot interpret, so you must also **update your section
of `BLOCKERS.md`** (and `TODO.md` if the backlog moved), write a note in `docs/tracker/notes/` (copy
`_TEMPLATE.md`), and log any deviation in `docs/decisions.md` plus any new dependency in `docs/tools-used.md`.
No note, no DONE.

## Commands and agents

`/session S11.<n>` · `/handoff` · `/verify` · `/verify-docs` · `/tracker` · `/lanes` · `/validate-corpus`

`session-auditor` (acceptance evidence) · `doc-auditor` (doc drift) · `schema-contract-guardian` (schema ↔
pydantic ↔ Swift) · `grounding-auditor` (citations, AI never routes) · `swift-scenekit-reviewer` ·
`lane-integrator` · `pitch-truth-auditor` (every pitch claim vs the shipped build)

**Repo note:** the Xcode project lives at the repo root (`escape_plan/`, `escape_plan.xcodeproj`), not under
`ios/`. See `docs/decisions.md`.
