# Product spec v3 (the S11 reframe)

Status: APPROVED 2026-09-18. Supersedes the fire-only spec, the S6 pivot charter and the S7/S8 charters
(all recoverable at tag `archive/playbook-v1`). Rationale and history: `docs/decisions.md`.

## 1. What the app is

A **home-safety readiness and prevention app** for iOS. A family scans or builds a structured 3D model
of its home (Apple RoomPlan LiDAR accelerates it; a real editor finishes it). A **deterministic engine**
computes escape routes, shelter choices and hazard findings on that model for **fire, earthquake and
severe weather (tornado)**, and turns them into a readiness score, a checklist and animated routes on a
SceneKit dollhouse. A server-side **Claude layer explains and chats**, grounded in a curated,
cited FEMA / NFPA / Red Cross / USFA corpus.

**The AI never computes a route and never invents safety guidance.** That separation is the answer to
"isn't this an AI wrapper?" Defend it in every decision.

## 2. What we learned from a working firefighter (long-serving; not named, details withheld until he agrees)

| He said | So we do |
|---|---|
| ~75-80% of his department's calls are medical, ~10% are fires; fires start anywhere (kitchens, candles, garage lithium batteries) | Prevention across the whole house, not just routes. The hazard engine and prevention tips are the product, not a side feature |
| In a working fire he cannot see his hand; he moves by touch, wall-tracing and hearing, and would not trust a stored layout after a remodel | **Not an operational tool for firefighters.** Never pitch it as one |
| "Might be marketable on a fire prevention / public education front": the department shares a QR code, the family scans the house, gets escape routes, and can opt in to share with the department | Reposition as prevention and readiness. Promote the **Responder Snapshot** to an opt-in "Share with your fire department" feature |
| The department already runs a manual **Clutter Survey Program** after medical calls; self-reporting clutter to the department is unrealistic (exigent-circumstance law, privacy, stigma) | Our hazard engine is the self-service version. Sharing is informational and opt-in, never something a department is expected to act on |
| Remodels make stored layouts stale | Show **scan age** everywhere a model is shown or shared; prompt a re-scan |
| Public fire-safety literacy is low; he wants basics taught (meeting spot, close doors behind you, call 911, do not fight a large fire, do not grab valuables) | A cited in-app prevention layer (S11.1 content, S11.5 UI) |

## 3. Keep / cut / improve

| Verdict | Feature | Why |
|---|---|---|
| **Keep** | Scan -> HomeModel -> deterministic routing and scoring -> grounded explainer | The identity of the app, and the part the firefighter reacted to |
| **Keep** | Object-hazard engine (S7): RoomPlan objects plus guided manual tagging, no ML | Matches the department's own clutter program; rules carry a number, a threshold, a citation and an action |
| **Keep** | `/evacuate` fire-spread simulation (Dijkstra on the nav graph, every occupant re-routed) | Non-trivial, fully deterministic, needs no AI credits to impress |
| **Keep** | Grounded AI architecture (corpus derived from `sources.json`, citation validation with retry) | The design is right even while the account is unfunded |
| **Keep, demote** | Optional accounts and cloud sync (S8, on `main`) | Owner-approved 2026-09-14, verified live, soft-gated ("Continue without an account"). Absent from the pitch; the app must work fully signed-out. `archive/s8-cloud-sync` marks the pre-demotion state |
| **Keep, de-risk** | AR Drill and semantic relocalization (S9) | Strong demo moment but device-only and unverified. Needs a flat-screen fallback; nothing else may depend on it |
| **Keep, own it** | Text/photo builder (`/build`) | An accessibility fallback for phones without LiDAR. Draft-only, mandatory editor review, never presented as scan parity |
| **Improve** | Earthquake and tornado depth | 6 fire corpus docs vs 1 and 1, and no codified numeric thresholds for the last two. Deepen with real sources; label the tiers honestly |
| **Improve** | Responder Snapshot | Becomes the headline opt-in sharing feature (S11.6) |
| **Improve** | Home tab | Reframed around readiness and prevention (S11.5) |
| **Cut** | Any claim that firefighters navigate with the app; self-reported clutter feeding a department database; Vision photo-assist (S7.9 was a NO-GO); anything needing custom ML | Not credible, not legal, or not built on evidence |

## 4. Scope lock (restated 2026-09-18)

- **Perils:** fire + earthquake + severe weather (tornado). No fourth peril.
- **Honest tiering:** fire is **fully code-quantified** (egress windows, timing, hazard thresholds).
  Earthquake and tornado are **FEMA/NOAA-grounded readiness modules**; where no codified number exists we
  say so and never manufacture one. The pitch must not imply three equally quantified pillars.
- **Platform:** iOS only (LiDAR and RoomPlan are Apple-only). Minimum iOS 17.0.
- **Capture:** LiDAR scan plus editor is primary. The text/photo builder is a draft-only fallback.
- **Accounts:** optional, soft-gated, never required for any feature. Local JSON stays the default store.
- **Out:** camera-only capture as a first-class path, Android, a fourth peril, custom or trained ML models.
- **Object hazards:** RoomPlan scan objects plus guided manual tagging feeding a deterministic engine.
  Transient clutter (bags, cords) is never claimed as detected.

## 5. The HomeModel schema is still the one law

`schema/homemodel.schema.json` (currently `schema_version` 2.1) is the contract between converter, editor,
engine, agent and renderer. The S11 arc is not expected to change it. If a session needs to, it stops,
logs the need in `docs/tracker/BLOCKERS.md`, and follows `.claude/rules/paths/schema.md`.

## 6. Pitch skeleton

1. **Civic problem:** most families have never drawn a home escape plan, and fires start in ordinary places.
2. **Wow:** scan your house, see it as a dollhouse, watch personalised routes light up across floors.
3. **Technical originality:** a custom 3D editor, a deterministic router and fire-spread simulator, a rules
   engine for hazards with citations, and an AI that explains and audits but never routes.
4. **Real-world validation:** a working firefighter told us what it is good for and what it is not. We
   changed the product because of it. Say that plainly.
5. **Honest demo:** show the scan getting most of the way, then the editor fixing the rest. Do not stage or
   hide errors.
