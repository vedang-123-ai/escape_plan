# Board — where we are right now

_Last updated: 2026-07-16 (by P3/Claude, merge terminal — all seven parallel lanes audited and merged to main). Update this whenever a session flips status._

**Schedule check:** the backend lane is essentially through Phase 3 (code); huge chunks of
Phase 1–2 iOS code landed today ahead of schedule. **The critical gap is now S0.3** — it was
assigned to a parallel terminal but never landed, and several merged modules carry stub model
layers waiting for it. Immovable milestone: end-to-end demo path working by **Oct 5**; submit
by **Oct 24**.

## ✅ DONE

| Session | What landed |
|---|---|
| S0.1 | Repo, CLAUDE.md, playbook, .claude/ control center |
| S0.4 | Grounding corpus + sources.json + egress_thresholds.json + validate.py ⚠️ P1 review still advised (see decisions.md) |
| S0.2 | HomeModel schema v1 + pydantic mirror + 3 fixtures + invalid/ fixtures + validate CLI |
| S1.1 | Navigation graph builder + egress checker (docs/graphs/*.png) |
| S1.2 | Routing engine: primary/secondary/bottlenecks/constraints (docs/route-samples/) |

## 🟡 CODE DONE — human/device steps remain (all audited by session-auditor 2026-07-16)

| Session | What landed | The human step |
|---|---|---|
| S1.6 backend scaffold | FastAPI `/health` `/routes` `/convert` (+ now `/explain` `/analyze` `/chat` `/score`), bearer auth, `render.yaml` | **P1: Render deploy (backend/README.md § Deploy), post URL+token, verify from phone** |
| S3.1 grounded explanations | `/explain` + citation validation w/ reject-retry, golden + red-team live tests | **P1: run `-m live` tests with a key, hand-review `tests/golden/`, paste 3 samples** |
| S3.2 agentic analysis | `/analyze` 6-tool loop, evidence/citation validation, 22 scripted-client tests, trace example | **Needs key + a `test_agent_live.py` + live run/review** |
| S3.3 chat backend (prep) | `/chat` stateless multi-turn on the S3.1 grounding layer, cached summary block | **Live smoke tests (`test_chat_live.py -m live`) once key exists; iOS chat UI separate** |
| S1.3 renderer | SceneKit dollhouse (`escape_plan/Renderer/`), all 3 fixtures decode+build, 18 tests **compiled, never executed** (no simulator runtime) | **Run `scripts/s13-acceptance.sh` once a simulator runtime exists; on-device 60fps check; 3 recordings (b-roll)** |
| S1.4 RoomPlan capture | `escape_plan/Capture/` + raw JSON/USDZ exporter matching the converter contract; round-trip harness PASSES on synthetic | **Scan a real 2–3 room space on a LiDAR device; commit device-{clean,messy} fixtures to schema/fixtures/scans/ (gates S1.5 calibration); verify UIFileSharingEnabled lands in a device build** |
| S2.1 editor core | `HomeModelStore` reducer + validation-on-mutation, drag/snap/hit-test logic; **89 tests RUN green** (SwiftPM harness) | **On-device: build bungalow by hand <5 min + recording (after S0.3 + renderer wiring)** |
| S2.4 persistence | `escape_plan/Persistence/` document store, migration stub, export **validated against schema** (17 tests run green). ⚠️ landed directly on main, not via branch | **On-device kill/relaunch check once the app shell exists** |
| S3.4 profiles (backend half) | Tag→constraint mapping (docs/profile-constraint-mappings.md), `/routes` profile_id, Grandpa-vs-Maya proven on twostory | **iOS half: profile CRUD UI + live 3D re-fetch (needs S2.3)** |
| S3.5 score (backend half) | `/score` + pure scoring engine, weights doc hand-reproducible (docs/preparedness-score-weights.md), 34 tests | **iOS score screen + animation (P2); optional live golden for AI recommendations** |

## ▶️ CAN START NOW

| Who | Session | Notes |
|---|---|---|
| **P2** | **S0.3 — iOS scaffold + model layer** ⚠️ **CRITICAL PATH** | Was assigned to a parallel terminal 2026-07-16 but never landed. `escape_plan/Models/Generated/HomeModel.swift` is the S2.1 lane's stub schema mirror standing in for it — S0.3 replaces it wholesale (round-trip tests are the swap gate). |
| **anyone** | **S2.2 — openings/stairs/undo** | S2.1 merged; store hooks (`onCommit`, `replaceModel`) already prepared. |
| **P1** | Human steps column above | Render deploy + one live-key test session clears four sessions at once. |
| **P1** | Review pass | CAC requires the team to understand every line — backend/app/ grew a lot today. |

## ⏸ BLOCKED

- S2.3 route viz ← S1.6 deploy + S1.3 device check · S1.5 calibration ← S1.4 device fixtures
- S4.1 golden path ← S1.5 + S2.3 + S3.1 · S4.x after S4.1 · S5.1 draft v0 EXISTS (docs/demo/), final pass ← S4.1

## 🔑 Critical path to the Oct 5 demo milestone

S0.3 → renderer/editor integration → S2.3 is the longest pole now; everything backend is
code-complete and waiting on one Render deploy + one API-key test session.

Cut order if we slip (never cut scan → editor → 3D routes → profile switch):
1. S4.2 drill · 2. S3.3 chat · 3. S3.5 score · 4. camera tour · 5. simplified agent
