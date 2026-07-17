# Board — where we are right now

_Last updated: 2026-07-16 (by P3/Claude, S0.3 merge). Update this whenever a session flips status._

**Schedule check:** Phase 0 is effectively clear — S0.3 code landed on `main`, one human step
(device run) left. The backend lane is into Phase 3. **We are well ahead of schedule.**
Immovable milestone: end-to-end demo path working by **Oct 5**; submit by **Oct 24**.

## 📱 P2 — READ THIS FIRST

**S0.3 (iOS scaffold) landed on `main` 2026-07-16 — your stock Core Data template is gone,
replaced with the real `Models/`/`Screens/`/`Networking/` layer.** Before starting S1.3
(3D renderer, unblocked by this), you need to do the one thing a Claude Code session can't do
for you:

1. `git pull` on `main` to get the new project files.
2. Open `escape_plan.xcodeproj`, plug in your iPhone, and build+run on the real device
   (full click-by-click steps in `docs/tracker/notes/2026-07-16-s0-3-ios-scaffold.md` — Xcode
   account/signing setup, trusting the developer cert on-device, the whole flow).
3. Confirm the **Home** tab shows "Two-Story House" with rooms listed under Ground Floor /
   Upstairs.
4. Once confirmed, flip S0.3 to **DONE** in this file and in `docs/tracker/checklist.md`
   (check the "runs on a real device" box) — that's what unblocks S1.3/S1.4 for real.
5. Also worth 5 minutes: read the `Models/` field-naming note in `docs/decisions.md`
   (2026-07-16, S0.3 rows) before building the SceneKit renderer on top of it — easy to
   rename now, expensive after wall/opening rendering code depends on it. And the
   `escape_plan/Fixtures/*.json` drift-risk note (they're copies of `schema/fixtures/`, not
   synced automatically).

## ✅ DONE

| Session | What landed |
|---|---|
| S0.1 | Repo, CLAUDE.md, playbook, .claude/ control center |
| S0.4 | Grounding corpus + sources.json + egress_thresholds.json + validate.py ⚠️ P1 review still advised (see decisions.md) |
| S0.2 | HomeModel schema v1 + pydantic mirror + 3 fixtures + invalid/ fixtures + validate CLI |
| S1.1 | Navigation graph builder + egress checker (docs/graphs/*.png) |
| S1.2 | Routing engine: primary/secondary/bottlenecks/constraints (docs/route-samples/) |

## 🟡 CODE DONE — one human step from DONE

| Session | What landed | The human step |
|---|---|---|
| S1.6 backend scaffold | **DEPLOYED 2026-07-16** — live at `https://escape-plan-backend.onrender.com` (Render blueprint). FastAPI `/health` + `/routes` + `/convert`, bearer auth (fails closed), curl examples + API tests. `/health` and `/routes` (twostory.json) verified via curl: 200 OK, ~0.3-0.4s — well under the 2s bar. `ANTHROPIC_API_KEY` left unset (not required to boot; `/explain` will 502 until a real key is added). | **Remaining: phone-on-cellular <2s check — DEFERRED BY TEAM DECISION 2026-07-16** (no REST client on the test phone; nothing else is blocked on this number — will happen naturally when P2 wires `APIClient.swift` to the live URL post-S1.3). Bearer token: reveal in Render dashboard → Environment → `BACKEND_BEARER_TOKEN`, paste into the team password note (not committed to git). See `docs/decisions.md` (2026-07-16). |
| S3.1 grounded explanations | `/explain` + `app/ai/grounded.py`: cached corpus prompt, structured output, server-side citation validation w/ reject-retry, golden + red-team live tests | **P1: `cd backend && ANTHROPIC_API_KEY=... python3 -m pytest tests/test_ai_live.py -m live -v`, hand-review `tests/golden/`, commit, paste 3 samples for team review** |
| S3.2 agentic home analysis | `/analyze` + `app/ai/agent.py`: 6-tool inspection loop over the S1.2 engine + S1.1 egress checker, evidence/citation validated server-side, 22 tests, rendered example trace in `docs/agent-trace-example/` | **No ANTHROPIC_API_KEY was available — all tests use a scripted client, no live model run yet.** Needs: (1) a key, (2) a `test_agent_live.py` written mirroring `test_ai_live.py`'s pattern (doesn't exist yet), (3) that run + hand-review, before this flips DONE. Also: read the twostory.json note in `docs/decisions.md` (2026-07-16) — the kids' room planted issue surfaces via the agent's `check_egress` tool, not the engine's own RoutePlan finding. |
| **S0.3 iOS scaffold** | **Core Data template replaced wholesale** — `Models/` (Codable mirror of the HomeModel schema), `Screens/` tab shell (Home/Editor/Plan/Assistant/Settings), `Networking/APIClient.swift`. Fixture decodes and displays room names per floor ✅. Round-trip test (decode→encode→decode, all 3 fixtures) passes ✅ (`xcodebuild ... -only-testing:escape_planTests` → `** TEST SUCCEEDED **`). Full build succeeds on Simulator (iPhone 17, iOS 26.5) ✅ | **P2: build + run on your real iPhone via Xcode** — see the box at the top of this file. This is the only box left; S1.3/S1.4 are unblocked below already since the code itself is done and tested. |

## ▶️ CAN START NOW

| Who | Session | Notes |
|---|---|---|
| **P2** | **S1.3 — 3D dollhouse renderer** | S0.3 code is done and tested (see table above) — unblocked. Do your device-run check first (5 min), then start here. |
| **P2** | **S1.4 — RoomPlan capture module** | Same unblock as S1.3; also needs a LiDAR-equipped device. |
| **P1** | S3.1 human step (table above) | S1.6 deploy is done (cellular check deferred, doesn't block DONE-flip criteria that matter right now); S3.1 live-verification still needs a real `ANTHROPIC_API_KEY`. |
| **P1** | Review pass | Read backend/app/ + docs/schema-summary.md + docs/corpus-summary.md — CAC requires the team to understand every line. |

## ⏸ BLOCKED (waiting on the above)

- **P2 lane:** S1.3/S1.4 unblocked (see CAN START NOW) — then S2.1 → S2.2
- **P1 lane:** S1.5 scan converter ← S1.4 — **prep done 2026-07-13, awaiting S1.4 real exports**: device-independent half landed (`backend/app/convert/` pure module + 3 synthetic RoomPlan fixtures + 18 tests). Remaining: diff real exports against `backend/app/convert/README.md` assumptions, calibrate, S1.3 render check, USDZ side-by-side handoff. `/convert` endpoint wiring belongs to the S1.6 lane.
- **P3 lane:** S2.4 persistence ← S2.1 · S3.3 chat ← S3.1 human step · S3.4 profiles ← S2.3 · S3.5 score ← S3.2
- **All hands:** S4.x ← S4.1 ← (S1.5 + S2.3 + S3.1) · S5.x last

## 🔑 Critical path to the Oct 5 demo milestone

S1.3/S1.4 (P2) is now the longest pole — S0.3's code is done, only the device-run check is
left. The backend lane is deep into Phase 3: S3.2 needed nothing from iOS and its code landed
2026-07-16 (prep, pending a live API key).

Cut order if we slip (never cut scan → editor → 3D routes → profile switch):
1. S4.2 drill · 2. S3.3 chat · 3. S3.5 score · 4. camera tour · 5. simplified agent
