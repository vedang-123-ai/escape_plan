# What Escape Plan does when it's finished

_Written 2026-08-05. The feature-by-feature answer to "what can this app actually do", with
honest status per capability._

There was no single file with this view. The pieces existed and still do — read them for depth:

| For | Read |
|---|---|
| The locked product decisions and the pitch | [`playbook/01-product-spec.md`](playbook/01-product-spec.md) |
| The S11 session plan, lanes, dependency map and branch protocol | [`playbook/README.md`](playbook/README.md) + `playbook/S11-*.md` |
| The contract every part agrees on | [`../schema/homemodel.schema.json`](../schema/homemodel.schema.json), summarized in [`schema-summary.md`](schema-summary.md) |
| What is still open, and why | [`tracker/TODO.md`](tracker/TODO.md) — the source of truth for status |
| Why anything was built the way it was | [`decisions.md`](decisions.md) |

This file is the layer those don't cover: capabilities, in user terms, in one list.

**Status key** — `SHIPPED` works and is verified · `BUILT` code complete, acceptance not yet
closed · `BLOCKED` finished but unusable right now for a stated reason · `OPEN` not started.

---

## 1. Build a model of your home

The 3D home engine is the product, not a means to it. Judges should come away understanding
that the editor is the engine and the scan is an on-ramp — "raw scans are messy, so we built a
real editor" is the originality story.

| Capability | Status |
|---|---|
| Scan a home with LiDAR (Apple RoomPlan), multi-room continuous capture, guided instructions, retry | `BUILT` — never run on real hardware |
| Convert a scan into a structured home: room polygons, parametric door/window placement, room adjacency, confidence carried through | `BUILT` — proven on synthetic fixtures only |
| Low-confidence scan items flagged for review rather than silently dropped | `BUILT` |
| Build a home from scratch: add floors, rooms, doors, windows, stairs | `SHIPPED` |
| Direct manipulation: drag walls, vertices and joints; rooms reshape live | `SHIPPED` |
| Openings attach parametrically to wall segments — moving a wall carries its doors | `SHIPPED` |
| Multi-floor homes joined by stairs | `SHIPPED` |
| Undo / redo across every edit | `SHIPPED` |
| Local persistence, multiple saved homes, no account required | `SHIPPED` |

The scan is deliberately treated as a draft: it gets you ~80% there, and the editor corrects
the rest. That framing is in the demo script on purpose.

## 2. See and fix it in 3D

| Capability | Status |
|---|---|
| 3D dollhouse of your actual home — white architectural-model look, soft key light, ambient occlusion, sliced wall tops | `SHIPPED` (rebuilt 2026-08-05) |
| Floor stacking: the active floor solid, the others ghosted; tap a ghosted floor to activate it | `SHIPPED` |
| Orbit, pinch-to-zoom anchored under your fingers, bounded pan, inertia, double-tap, recenter | `SHIPPED` — feel unverified on a real phone |
| Edit directly on the 3D model, not on a separate 2D plan | `SHIPPED` |
| Camera tour that flies the model, including down the stairs | `SHIPPED` |
| Room labels, selection highlighting, warning badges in-scene | `SHIPPED` |
| Selection marker for openings and stairs (rooms already have one) | `OPEN` |

## 3. Escape routes

This is the money shot, and it is **deterministic** — a graph routing engine, not a model call.
That separation is the answer to "isn't this an AI wrapper?"

| Capability | Status |
|---|---|
| Primary and secondary escape route from **every** room to an exterior exit | `SHIPPED` |
| Routes animate along the actual 3D geometry, across floors and down stairs | `SHIPPED` |
| Routes render as the only color in an otherwise monochrome model, so the eye goes where it must | `SHIPPED` |
| Bottleneck detection — the single doors whose loss disconnects rooms | `SHIPPED` |
| Rooms with no viable route, or no second way out, called out explicitly | `SHIPPED` |
| Egress qualification against real code thresholds (window size, sill height) | `SHIPPED` |
| Per-person route colors and family-member figures placed in the model | `OPEN` — designed, deliberately deferred |

## 4. Family profiles

| Capability | Status |
|---|---|
| Household members with real constraints: child, elderly, mobility-limited, pets | `SHIPPED` |
| Switching profile **visibly changes the routes** — a wheelchair user is not routed down stairs or out a window | `SHIPPED` |
| Advice and checklist adapt to the profile too | `SHIPPED` |

The profile switch visibly re-routing the house is the second-best moment in the demo after the
routes themselves, because it proves the routing is real.

## 5. The AI layer — explains and audits, never routes

Grounded exclusively in a curated FEMA / NFPA / Red Cross corpus. Every safety claim carries a
citation validated server-side against `sources.json`; uncited claims are rejected. The AI has
no path to computing a route.

| Capability | Status |
|---|---|
| Plain-language explanation of your routes, with citations | `BLOCKED` — built, Anthropic account out of credit |
| Agentic home inspection: walks your model with real tools and surfaces risks (a bedroom with no second egress, a single-point-of-failure exit, a window too small to climb out of) | `BLOCKED` — same |
| Findings link to the actual tool-call evidence that produced them | `BLOCKED` — same |
| Chat assistant that answers fire-safety questions with awareness of *your* home | `BLOCKED` — same |
| Honest deferral on anything outside the corpus; "call 911 first" on emergencies | `BLOCKED` — same |

Every one of these is code-complete and was working on 2026-07-23. The account balance is the
only thing between here and a live demo. The deterministic half is entirely unaffected, which
is the architecture behaving as designed.

## 6. Preparedness score and checklist

| Capability | Status |
|---|---|
| Weighted, **explainable** preparedness score — every component visible, no black box | `SHIPPED` |
| Actionable checklist generated from your home's real findings | `SHIPPED` |
| Recommendations cite the corpus | `BLOCKED` (AI half) |

## 7. Practice

| Capability | Status |
|---|---|
| Fire drill: start a fire in a chosen room, watch everyone's way out (0.25×–2×) with a "Who does what" card per person (House fire simulation; replaced the step-by-step drill in trim 2, 2026-10-03) | `BUILT` (needs the server) |

First on the cut list if the schedule slips. It is currently ahead of that.

## 8. Product surface

| Capability | Status |
|---|---|
| Onboarding with sample homes so the app is not empty on first launch | `SHIPPED` |
| Home list, plan view, score, assistant, settings | `SHIPPED` |
| Backend deployed and token-authenticated | `SHIPPED` |
| Design pass across app chrome (accent, typography, per-screen signature moment, live 3D thumbnails) | `OPEN` — in progress |
| App icon in the White Model language | `OPEN` — in progress |
| Custom launch screen | `OPEN` |
| Distinguish "retry may work" from "an operator must act" when the backend fails | `OPEN` — backend already distinguishes them; the app renders both the same |

---

## Where this actually stands

Nearly everything is built. What is left divides into three piles, and only one of them is
engineering:

1. **One billing action.** Top up Anthropic → section 5 goes from `BLOCKED` to live.
2. **One device trip.** A LiDAR phone and a real room closes every `BUILT` in section 1, plus
   on-device verification of sections 2 and 3. Procedure: [`tracker/field-test-lidar.md`](tracker/field-test-lidar.md).
3. **The design pass.** Section 8, plus the per-person route layer in section 3.

## Milestones

From the playbook calendar. The immovable one is in bold.

| Phase | Target | What it means | State |
|---|---|---|---|
| 0 — Foundations | Jul 20 | Schema, fixtures, app scaffold, grounding corpus | Done |
| 1 — Core engines | Aug 17 | Routing, renderer, scan capture + converter, backend deployed | Code done; scan unverified |
| 2 — Editor | Sep 7 | Rooms/walls/vertices, openings/stairs/undo, routes on the 3D model, persistence | Done |
| 3 — Intelligence | Sep 28 | Explanations, agentic analysis, chat, profiles, score | Code done; blocked on credit |
| **Demo path end-to-end** | **Oct 5** | **Scan → editor → 3D routes → profile switch, working together** | **Simulator-verified; real-device half open** |
| 4 — Integration | Oct 12 | Golden path, drill mode, real-home testing, polish | Polish in progress |
| 5 — Submission | Oct 13–24 | Script, film, edit, submit | Script + storyboard drafted |
| **Submit** | **Oct 24** | CAC deadline is Oct 26 — the 48h buffer is deliberate | — |

If the schedule slips, the cut order is fixed and non-negotiable: drill mode → chat → score →
camera tour → simplified agent. **Scan → editor → 3D routes → profile switch is never cut.**
