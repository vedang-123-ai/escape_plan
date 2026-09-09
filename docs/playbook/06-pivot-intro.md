# PART VI — THE READINESS PIVOT (S6.x)

**Status: APPROVED 2026-09-05; all nine sessions' CODE LANDED on `main` as of the 2026-09-08
merge** (S6.1–S6.3 on 2026-09-05 with the 2026-09-06 review fixes; S6.4–S6.9 via the Wave-2 /
S6.7–S6.9 commits merged 2026-09-08). Reconciliation basis: code verified present + the three
cheap suites green on the merged tree — device/simulator acceptance was NOT re-walked, and the
open S6.1–S6.3 review items in `docs/tracker/TODO.md` remain open. Scoped 2026-09-05, approved
the same day; the scope locks in `CLAUDE.md` and `.claude/rules/global/conventions.md` were
updated to match at approval time.

## What changes, and why

The app's pitch was "we compute your fire escape routes." The honest critique that produced this
pivot: for an able-bodied adult in their own house, the route is *obvious*, the owner knows their
home better than a scan does, and a shortest-path-to-the-door engine is not, by itself, a reason
for the app to exist.

What survives that critique is already in the repo and badly marketed. `docs/profile-constraint-mappings.md`
documents a `mobility_limited` profile whose upstairs bedroom yields `no_viable_route` — the engine
saying *there is no way out for this person*, which is exactly the thing a resident does **not**
already know. That finding, not the animated path, is the product.

So the arc below turns the app from **a route viewer** into **a readiness system**:

1. An AI-narrated household interview on first launch, which produces structured facts.
2. A deterministic rule table turns those facts into a single, unified, hazard-tagged checklist.
3. The checklist becomes the Home tab — completing it *is* the app.
4. Fire is joined by **earthquake** and **severe weather (tornado)**, each with a genuinely
   different routing objective, not re-skinned copy.
5. A composite readiness score, exportable — the insurance story.
6. An opt-in, anonymous, manually-shared responder snapshot — the pre-incident-intelligence story.

## Decisions locked at scoping time (2026-09-05)

These were interrogated and confirmed by the owner. **Do not relitigate them inside a session.**

| Decision | Ruling |
|---|---|
| Hazard breadth | Fire + earthquake + tornado/severe weather, all with **real** logic. |
| Checklist generation | **Deterministic rule table.** The AI interviews; it never composes the checklist. |
| Hazard applicability | All hazards always on. No geography gating, no risk-API dependency. |
| Model authority | HomeModel stays the source of truth; a time-based nudge prompts periodic rescans. |
| Checklist shape | One unified list, items tagged by hazard. Not three parallel lists. |
| Navigation | The checklist **replaces the Home tab**. |
| Accounts / sync | Unchanged: local-only, anonymous. Sharing is a one-way manual export, never sync. |
| Safe room | **Engine-computed** from geometry. No manual override. Same trust model as fire exits. |
| Score | One composite number, per-hazard breakdown underneath. |
| Interview format | Fixed branching wizard, conversationally narrated. Not free chat. |
| Interview data | Members + ages, per-person mobility/sensory needs, rent-vs-own, existing equipment. |
| Skip / edit | Every question skippable (skip = unconstrained default); profile editable later. |
| Insurance + responder | **Designed and demoable, not integrated.** No insurer, no department, no endpoint. |

## What already exists — extend it, do not rebuild it

Reading this table is the difference between a 4-hour session and a 12-hour one.

| You will think you need to build | It already exists |
|---|---|
| A checklist generator | `backend/app/scoring/checklist.py` — deterministic, categories, stable ids, `ChecklistState` (id→done) persisted on the home document |
| Checklist UI with toggles | `ScoreScreen.swift` renders it today, backed by `ChecklistStateStore`, re-POSTing `/score` |
| An onboarding flow | `escape_plan/Onboarding/OnboardingFlowView.swift` (S4.1) — seeds a demo home, gated on `@AppStorage("onboarding.completed")` |
| A score | `backend/app/scoring/score.py` + `docs/preparedness-score-weights.md` — pure, reproducible by hand |
| Per-person routing constraints | `backend/app/routing/profiles.py` + `docs/profile-constraint-mappings.md` |
| Fire-origin simulation | `backend/app/routing/hazard.py` — **the name `hazard` is taken**; multi-peril work must use `peril` naming to avoid a collision |

## Dependency map

```
S6.1 (schema 2.0) ─┬─► S6.3 (peril engine) ─┬─► S6.6, S6.7, S6.8, S6.9
                   ├─► S6.4 (rule table) ───┴─► S6.6, S6.7
                   └─► S6.5 (interview) ──────► S6.6
S6.2 (corpus) ─────┴─► S6.3, S6.4
```

S6.1 and S6.2 are the only two that can start immediately. S6.2 is independent of everything.

## How to use the prompts

Each `S6-<n>.md` contains **one paste-ready, self-contained prompt** for a fresh session. They are
written long-horizon on purpose: each carries its own context, its own non-negotiables, its own
acceptance bar, and its own close-out, because the session running it will not have this
conversation in context.

Rules that apply to every one of them:

- **Read `CLAUDE.md` and this file before starting.** The prompt assumes both.
- **The AI never invents safety guidance and never computes a route.** Every new safety claim needs
  a real, cited corpus source. No source → it does not ship.
- **`schema/homemodel.schema.json` is the contract.** Only S6.1 may change it, and it bumps the
  version. Every other session treats it as frozen.
- **Trust `xcodebuild`, never the editor.** SourceKit and VS Code cannot index this project.
- **A red iOS run is ~1-in-3 environmental flake.** Re-run before believing it.
- **The Anthropic account is out of credits.** `/explain`, `/analyze`, `/chat` returning 502 is
  expected and is a billing problem. Never debug the AI layer over it.
- **Close out properly or the session did not happen:** update `docs/tracker/TODO.md`, write a note
  in `docs/tracker/notes/` (copy `_TEMPLATE.md`), log deviations in `docs/decisions.md`, add any new
  dependency to `docs/tools-used.md`.
