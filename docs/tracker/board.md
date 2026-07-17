# Board — where we are right now

_Last updated: 2026-07-16 (by P3/Claude, parallel worktree session). Update this whenever a session flips status._

**Schedule check:** Phase 0 target is Jul 20 — only S0.3 remains in Phase 0; the backend lane
is into Phase 3. **We are well ahead of schedule.** Immovable milestone:
end-to-end demo path working by **Oct 5**; submit by **Oct 24**.

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

## ▶️ CAN START NOW

| Who | Session | Notes |
|---|---|---|
| **P2** | **S0.3 — iOS scaffold + model layer** | Unblocked by S0.2. Read docs/schema-summary.md first. Stock Core Data template gets replaced wholesale; decide root vs ios/ location (decisions.md). |
| **P1** | S3.1 human step (table above) | S1.6 deploy is done (cellular check deferred, doesn't block DONE-flip criteria that matter right now); S3.1 live-verification still needs a real `ANTHROPIC_API_KEY`. |
| **P1** | Review pass | Read backend/app/ + docs/schema-summary.md + docs/corpus-summary.md — CAC requires the team to understand every line. |

## ⏸ BLOCKED (waiting on the above)

- **P2 lane:** S1.3 renderer ← S0.3 · S1.4 RoomPlan capture ← S0.3 (+ LiDAR device) · then S2.1 → S2.2
- **P1 lane:** S1.5 scan converter ← S1.4 — **prep done 2026-07-13, awaiting S1.4 real exports**: device-independent half landed (`backend/app/convert/` pure module + 3 synthetic RoomPlan fixtures + 18 tests). Remaining: diff real exports against `backend/app/convert/README.md` assumptions, calibrate, S1.3 render check, USDZ side-by-side handoff. `/convert` endpoint wiring belongs to the S1.6 lane.
- **P3 lane:** S2.4 persistence ← S2.1 · S3.3 chat ← S3.1 human step · S3.4 profiles ← S2.3 · S3.5 score ← S3.2
- **All hands:** S4.x ← S4.1 ← (S1.5 + S2.3 + S3.1) · S5.x last

## 🔑 Critical path to the Oct 5 demo milestone

S0.3 → S1.3/S1.4 (P2) is the longest pole. The backend lane is deep into Phase 3:
S3.2 needed nothing from iOS and its code landed 2026-07-16 (prep, pending a live API key).

Cut order if we slip (never cut scan → editor → 3D routes → profile switch):
1. S4.2 drill · 2. S3.3 chat · 3. S3.5 score · 4. camera tour · 5. simplified agent
