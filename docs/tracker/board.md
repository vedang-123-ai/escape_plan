# Board — where we are right now

_Last updated: 2026-07-10 (by P3/Claude). Update this whenever a session flips status._

**Schedule check:** Phase 0 target is Jul 20 — only S0.3 remains in Phase 0, and P1's lane is
already two sessions into Phase 1. **We are ahead of schedule.** Immovable milestone:
end-to-end demo path working by **Oct 5**; submit by **Oct 24**.

## ✅ DONE

| Session | What landed |
|---|---|
| S0.1 | Repo, CLAUDE.md, playbook, .claude/ control center |
| S0.4 | Grounding corpus + sources.json + egress_thresholds.json + validate.py ⚠️ P1 review still advised (see decisions.md) |
| S0.2 | HomeModel schema v1 + pydantic mirror + 3 fixtures + invalid/ fixtures + validate CLI |
| S1.1 | Navigation graph builder + egress checker (docs/graphs/*.png) |
| S1.2 | Routing engine: primary/secondary/bottlenecks/constraints (docs/route-samples/) |

## ▶️ CAN START NOW

| Who | Session | Notes |
|---|---|---|
| **P2** | **S0.3 — iOS scaffold + model layer** | Just unblocked by S0.2. Read docs/schema-summary.md first. Stock Core Data template gets replaced wholesale; decide root vs ios/ location (decisions.md). |
| **P3 (Claude)** | **S1.6 — Backend scaffold + deploy** | Just unblocked by S1.2. Deploy step needs a human to create the Render/Railway account + set ANTHROPIC_API_KEY. |
| **P1** | Review pass | Read backend/app/ + docs/schema-summary.md + docs/corpus-summary.md — CAC requires the team to understand every line. Optional: record the S1.2 CLI demo gif. |

## ⏸ BLOCKED (waiting on the above)

- **P2 lane:** S1.3 renderer ← S0.3 · S1.4 RoomPlan capture ← S0.3 (+ LiDAR device) · then S2.1 → S2.2
- **P1 lane:** S1.5 scan converter ← S1.4 · S3.1 explanations ← S1.6 · then S3.2
- **P3 lane:** S2.4 persistence ← S2.1 · S3.3 chat ← S3.1 · S3.4 profiles ← S2.3 · S3.5 score ← S3.2
- **All hands:** S4.x ← S4.1 ← (S1.5 + S2.3 + S3.1) · S5.x last

## 🔑 Critical path to the Oct 5 demo milestone

S0.3 → S1.3/S1.4 (P2) is now the longest pole. Backend (P1/P3) can run ahead:
S1.6 → S3.1 → S3.2 need nothing from iOS.

Cut order if we slip (never cut scan → editor → 3D routes → profile switch):
1. S4.2 drill · 2. S3.3 chat · 3. S3.5 score · 4. camera tour · 5. simplified agent
