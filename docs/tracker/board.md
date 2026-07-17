# Board — where we are right now

_Last updated: 2026-07-16 (by P3/Claude, merge terminal — seven parallel lanes + S0.3 + S1.6 deploy all merged to main). Update this whenever a session flips status._

**Schedule check:** enormous day — S0.3 landed, the backend is deployed and code-complete
through Phase 3, and big chunks of Phase 1–2 iOS code merged. **We are far ahead of schedule.**
What's left is mostly device/human verification, not code. Immovable milestone: end-to-end
demo path working by **Oct 5**; submit by **Oct 24**.

## 📱 P2 — READ THIS FIRST

**S0.3 (iOS scaffold) landed on `main` 2026-07-16** — stock Core Data template is gone,
replaced with the real `Models/`/`Screens/`/`Networking/` layer. Your one human step:

1. `git pull`, open `escape_plan.xcodeproj`, build+run on your real iPhone (click-by-click
   steps in `docs/tracker/notes/2026-07-16-s0-3-ios-scaffold.md`).
2. Confirm the **Home** tab shows "Two-Story House" with rooms per floor, then flip S0.3 to
   DONE here + check the device box in `checklist.md`.
3. Note: S1.3 renderer / S2.1 editor / S1.4 capture / S2.4 persistence code ALSO merged today
   (see below) — after the device run, the next P2 jobs are the device acceptance checks in
   the table below, not building those modules from scratch.
4. ⚠️ Model-layer unification is in progress on the merge terminal: the S2.1 lane's stub
   `Models/Generated/HomeModel.swift` is being retired in favor of S0.3's `Models/` — read
   the decisions.md 2026-07-16 rows before renaming any model fields.

## ✅ DONE

| Session | What landed |
|---|---|
| S0.1 | Repo, CLAUDE.md, playbook, .claude/ control center |
| S0.4 | Grounding corpus + sources.json + egress_thresholds.json + validate.py ⚠️ P1 review still advised |
| S0.2 | HomeModel schema v1 + pydantic mirror + 3 fixtures + invalid/ fixtures + validate CLI |
| S1.1 | Navigation graph builder + egress checker (docs/graphs/*.png) |
| S1.2 | Routing engine: primary/secondary/bottlenecks/constraints (docs/route-samples/) |
| S1.6 | **DEPLOYED** — live at `https://escape-plan-backend.onrender.com`; `/health` + `/routes` verified 200 OK ~0.3–0.4s. Cellular timing check deferred by team decision (see decisions.md). `ANTHROPIC_API_KEY` not yet set on Render (AI endpoints 502 until then). Bearer token: Render dashboard → Environment. |

## 🟡 CODE DONE — human/device/key steps remain (all lanes audited 2026-07-16)

| Session | What landed | Remaining step |
|---|---|---|
| S0.3 iOS scaffold | `Models/` Codable mirror + round-trip test PASSED (simulator on teammate's machine), tab shell, APIClient | **P2: build+run on real iPhone (box above)** |
| S3.1 grounded explanations | `/explain`, citation validation w/ reject-retry, golden + red-team live tests | **P1: live `-m live` run with key, review `tests/golden/`** |
| S3.2 agentic analysis | `/analyze` 6-tool loop, 22 scripted-client tests, trace example | **Key + write `test_agent_live.py` + live run/review** |
| S3.3 chat backend (prep) | `/chat` stateless multi-turn on the S3.1 grounding layer | **Live smoke tests once key exists; iOS chat UI separate** |
| S1.3 renderer | SceneKit dollhouse (`Renderer/`), 3 fixtures decode+build, 18 tests compiled (no simulator runtime to run them) | **Simulator/device: run `scripts/s13-acceptance.sh`, 60fps check, 3 recordings (b-roll)** |
| S1.4 RoomPlan capture | `Capture/` + raw JSON/USDZ exporter matching converter contract; synthetic round-trip PASSES | **LiDAR device: real 2–3 room scan, commit device-{clean,messy} fixtures (gates S1.5 calibration), verify UIFileSharingEnabled on device** |
| S2.1 editor core | `HomeModelStore` reducer + validation-on-mutation, drag/snap/hit-test; 89 tests RUN green (SwiftPM) | **On-device bungalow hand-build <5 min + recording; wire `EditorSceneAdapter` seam to the renderer** |
| S2.4 persistence | Document store + migration stub; 17 tests run green; export schema-validated. ⚠️ landed directly on main | **On-device kill/relaunch check** |
| S3.4 profiles (backend half) | Tag→constraint mappings (docs/profile-constraint-mappings.md), `/routes profile_id`, Grandpa-vs-Maya proven on twostory | **iOS half: profile CRUD UI + live 3D re-fetch (needs S2.3)** |
| S3.5 score (backend half) | `/score` + pure engine, weights doc hand-reproducible, 34 tests | **iOS score screen (P2); optional live golden for AI recommendations** |

## ▶️ CAN START NOW

| Who | Session | Notes |
|---|---|---|
| **anyone** | **S2.2 — openings/stairs/undo** | S2.1 merged; store hooks (`onCommit`, `replaceModel`) prepared for it. |
| **P2** | Device acceptance sweep | One device session clears S0.3 + S1.3 + S2.1 + S2.4 checks. |
| **P1** | Key session | Set `ANTHROPIC_API_KEY` on Render + locally, run all `-m live` suites → clears S3.1/S3.2/S3.3. |
| **P1** | Review pass | backend/app/ grew a lot today; CAC requires the team to understand every line. |

## ⏸ BLOCKED

- S2.3 route viz ← S1.3 device check (backend is live already) · S1.5 calibration ← S1.4 device fixtures
- S4.1 golden path ← S1.5 + S2.3 + S3.1 · S4.x after S4.1 · S5.1 draft v0 EXISTS (docs/demo/), final pass ← S4.1

## 🔑 Critical path to the Oct 5 demo milestone

P2's device sessions (S0.3 run → S1.3/S2.1 acceptance → S2.3) are the longest pole.
Backend is deployed and code-complete; one API-key session closes the whole AI column.

Cut order if we slip (never cut scan → editor → 3D routes → profile switch):
1. S4.2 drill · 2. S3.3 chat · 3. S3.5 score · 4. camera tour · 5. simplified agent
