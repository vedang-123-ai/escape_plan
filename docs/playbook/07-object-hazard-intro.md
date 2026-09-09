# PART VII — OBJECT HAZARD DETECTION (S7.x)

**Status: APPROVED 2026-09-08 by the owner. Not started.**
Scoped 2026-09-08 against the merged post-S6 tree (`388cf37`, all three cheap suites green).
The scope locks in `CLAUDE.md`, `.claude/rules/global/conventions.md` and
`playbook/01-product-spec.md` were updated in lockstep — "furniture detection" left the
out-of-scope list the day this arc was approved. The rule book for the whole arc is
**`docs/object-hazard-spec.md`**; read it before any S7 session, and treat it as authoritative
when a session file and the spec disagree.

## What changes, and why

The app models the home's *structure* and reasons about it deterministically. Its contents —
the wardrobe beside the bed, the heater beside the sofa, the dresser under the egress window —
are invisible, except where the v1.1 object layer already catches furniture standing in a
doorway. Yet objects are where the injuries are: falling objects are the most common cause of
earthquake injury (already cited in our corpus), and heating equipment and blocked exits are
staple fire findings.

The unlock is embarrassing in the best way: **RoomPlan already detects household objects with
3D boxes, and we throw them away.** The device writes them to `apple-raw.json`; the wire
format and `/convert` drop them. Most of "object detection" is therefore plumbing plus
judgment, not ML — which is exactly the architecture story this project tells: sensors and a
deterministic engine measure, the AI only explains.

The arc turns the app from **a structure-aware escape planner** into **a contents-aware home
safety system**:

1. Schema 2.1 lets an object be high up (`elevation_m`), wall-mounted (`mounted`), and of a
   hazard-relevant category (`bookcase`, `tv`, `water_heater`, `heat_source`). (S7.1)
2. The corpus gains real, named sources for heating/electrical fire hazards — the one hazard
   family we currently cannot cite at all. (S7.2)
3. The scan pipeline carries RoomPlan objects into the HomeModel, flagged for review when
   low-confidence, never silently dropped. (S7.3)
4. A deterministic rules engine measures every object against cited thresholds: topple arcs
   vs. beds, overhead loads over sleepers, heater clearances, blocked egress windows,
   unstrapped water heaters. Every finding carries a number, a threshold, a citation, and an
   action. (S7.4)
5. Findings surface through the existing checklist/score/agent plumbing with near-zero
   contract change — no new checklist category, no new finding kind. (S7.5)
6. The editor gains the "hazard hunt": a guided, skippable, zero-network flow to tag what no
   scan can see, plus the secured toggle the schema has been carrying UI-less since 2.0. (S7.6)
7. The 3D view shows the hazard (advisory emphasis, camera focus from a finding), verified on
   a device. (S7.7)
8. Stretch: exit-path re-check by partial re-scan diff (S7.8); optional Vision photo-assist
   suggestions (S7.9, S7.10).

## Decisions locked at scoping time (2026-09-08)

These were interrogated and confirmed by the owner. **Do not relitigate them inside a session.**

| Decision | Ruling |
|---|---|
| Detection mechanism | **RoomPlan scan objects + guided manual tagging.** Custom ML rejected for this cycle — accuracy failures in a safety app are worse than absence. |
| Vision photo-assist | **In the arc, optional, at the tail** (S7.9/S7.10), on-device Apple classifiers only, suggestions the user must confirm — never auto-added. |
| Transient clutter (backpacks etc.) | **Never claimed as detected.** Recurring checklist items + hazard hunt + (stretch) S7.8 re-scan diff. The spec's honesty section is binding. |
| Finding contract | **A number, a threshold, a citation, an action — on every finding.** "There is a sofa" outputs are banned. |
| Contract breadth | **Schema 2.1 is the only contract change.** No new ItemCategory (reuse `mitigation`), no new FindingKind (R4 reuses `blocked_opening`/`narrows_route`). |
| Who computes | **The deterministic engine measures; the AI explains via `check_object_hazards` and never estimates a distance or severity itself.** Same law as everywhere else. |
| Corpus gating | **No source, no rule.** S7.2 blocks S7.4. Engineering constants are labeled as ours and live in `object_hazard_thresholds.json`, not in code. |
| Geometry's role | **Prioritizes, never excuses.** An unsecured wardrobe far from everything still gets the generic secure-it item. |
| Cut order if behind | **S7.10 → S7.9 → S7.8 → S7.7's visual-emphasis half. Never cut S7.1–S7.5.** |

## What already exists — extend it, do not rebuild it

Reading this table is the difference between a 4-hour session and a 12-hour one. Verified on
the merged tree (`388cf37`), 2026-09-08.

| You will think you need to build | It already exists |
|---|---|
| An object model | `FloorObject` (schema v1.1): category, footprint, `height_m`, rotation, `source`/`confidence`, and `secured` — which has exactly one reader (`checklist.mitigation_items`) and no UI. You are adding three fields and four enum values, not a model. |
| An obstruction detector | `backend/app/routing/obstructions.py` — grid-reachability probe, counterfactual culprit attribution ("removing WHICH object restores the path"), measured `suggested_move_m`, thresholds from `egress_thresholds.json`. R4 widens its probe to egress windows; do not write a second engine. |
| A "furniture in the way" agent tool | `check_obstructions` in `backend/app/ai/agent.py`, with prompt rules that forbid the model estimating distances. `check_object_hazards` is a sibling, built the same way. |
| A "secure your furniture" checklist item | `mitigation_items` in `scoring/checklist.py` — tenure-aware (renter straps vs. wall studs), cited, id `mitigation.secure.<obj.id>`. S7.5 *supersedes* it per-object with specific hazards, never duplicates it. |
| Object editing UI | Reducer actions `addObject`/`dragObject`/`rotateObject`/`resizeObject`/`setObjectCategory` in `escape_plan/Editor/Core/EditAction.swift` + `HomeModelStore.swift`, inspector in `HouseScreen.swift`, per-category renderer in `Renderer/Fixtures/FurnitureFixture.swift`. Missing: `setObjectSecured`, elevation controls, size/height controls. |
| iOS decode work for new categories/kinds | Already done by the S6 merges: `ChecklistCategory` has all 11 backend values, `FindingKind` has all 6. Keep it that way — schema 2.1's new `ObjectCategory` cases are the only Swift enum change, and `FurnitureFixture`'s exhaustive switch must gain arms in the same session (S7.1) or the app stops compiling. |
| Earthquake object logic | `perils/earthquake.py` cover search (tables only) and `perils/tornado.py` are S6.3's and stay untouched. **The name `hazard.py` is taken** by fire-origin simulation (`routing/hazard.py`) and **`check_obstructions` is taken** — the new module is `routing/object_hazards.py`, the new tool `check_object_hazards`. |
| Scan-object capture | The device already writes RoomPlan objects to `apple-raw.json` (`Export/ScanStore.swift`); `RawScanExport` (formatVersion 2) and `/convert`'s `RPRoom` simply omit them. S7.3 is plumbing, not capture work. |

## Dependency map

```
S7.1 ─► { S7.3, S7.6 }               S7.2 (independent start)
S7.1 + S7.2 ─► S7.4 ─► S7.5
S7.4 + S7.5 + S7.6 ─► S7.7
S7.3 + S7.4 ─► S7.8 (stretch)        S7.6 ─► S7.9 ─► S7.10 (optional)
```

In words, byte-consistent with every session file's `Prereqs:` line: S7.1 and S7.2 can start
immediately and in parallel. S7.3 needs S7.1 only. S7.4 needs both S7.1 and S7.2. S7.5 needs
S7.4. S7.6 needs S7.1 only. S7.7 needs S7.4 + S7.5 + S7.6. S7.8 needs S7.3 + S7.4. S7.9 needs
S7.6; S7.10 needs S7.9.

## How to use the prompts

Each `S7-<n>.md` contains one paste-ready, self-contained prompt for a fresh session — written
long-horizon, because the executing session will not have this scoping conversation in its
context. Rules that apply to every one of them:

- Read `CLAUDE.md`, this file, and `docs/object-hazard-spec.md` before writing anything. The
  spec is the rule book; sessions implement it.
- The AI never invents safety guidance and never computes a route, a distance, or a severity.
  The engine measures; the corpus speaks; the AI explains.
- The schema is the contract. Only S7.1 may bump it, and a schema change is incomplete until
  JSON Schema, pydantic, and Swift agree and the round-trip test passes.
- Trust `xcodebuild`, never the editor — SourceKit/VS Code cannot index this project. A red
  iOS run is ~1-in-3 environmental flake; re-run before believing it. Do not launch the iOS
  simulator without the owner's go-ahead (this machine struggles with it) — the cheap gates
  are EditorCore, backend pytest, and corpus validation.
- The Anthropic account may still be dry: 502 from `/explain`, `/analyze`, `/chat` is billing,
  not code. AI-touching sessions ship deterministic tests; live goldens wait for credits.
- Close-out is mandatory and four-part: update `docs/tracker/TODO.md`, write a session note in
  `docs/tracker/notes/` (copy `_TEMPLATE.md`), log deviations in `docs/decisions.md`, and
  record any new dependency in `docs/tools-used.md`. A session without a handoff and a tracker
  note didn't happen.
