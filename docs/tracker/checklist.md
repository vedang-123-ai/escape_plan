# Master checklist — S0.1 → S5.3

Rules: check an acceptance box only after you verified it yourself. A session is DONE only when
**all** acceptance boxes AND all three end-of-session boxes (📋 decisions.md · 🔧 tools-used.md ·
📦 handoff) are checked. Read `docs/playbook/S<x>-<y>.md` before starting any session.

Phase targets: P0 → Jul 20 · P1 → Aug 17 · P2 → Sep 7 · P3 → Sep 28 · P4 → Oct 12 · P5 → submit by Oct 24.
**Demo path end-to-end by Oct 5 (immovable).**

---

## Phase 0 — Foundations

### S0.1 — Repo, conventions, playbook install — **DONE 2026-07-10** (P1/P3)
- [x] Repo cloned by all 3
- [x] Claude Code correctly summarizes the project from CLAUDE.md
- [x] 📋 decisions.md · [x] 🔧 tools-used.md · [x] 📦 handoff (repo + "how we work" in CLAUDE.md)

### S0.2 — HomeModel schema v1 + fixtures — **DONE 2026-07-10** (P1 via P3)
- [x] All fixtures validate (bungalow, apartment, twostory — `cd backend && python3 -m app.validate ../schema/fixtures/*.json`)
- [x] Broken fixture fails with a clear message (3 files in `schema/fixtures/invalid/`)
- [x] Schema doc-comments explain every field
- [x] 📋 decisions.md · [x] 🔧 tools-used.md · [x] 📦 handoff (`docs/schema-summary.md`)

### S0.3 — iOS app scaffold + model layer — **READY** (P2) ← unblocked by S0.2
- [ ] App builds and runs on a real device
- [ ] Fixture decodes and displays room names per floor
- [ ] Decode → encode → semantic-compare round-trip test passes
- [ ] 📋 decisions.md (incl. Core Data vs JSON docs; root vs `ios/` location) · [ ] 🔧 tools-used.md · [ ] 📦 handoff (screenshot + schema-friction note to P1)

### S0.4 — Fire-safety grounding corpus — **DONE 2026-07-10** (P3)
- [x] Every claim traceable to a named source (`python3 backend/corpus/validate.py`)
- [x] Thresholds file validates (imperial↔metric 1% tolerance)
- [~] P1 sign-off "sufficient for S3.1" — recorded done at P3's direction; **P1: please actually read `docs/corpus-summary.md` and reopen if thin**
- [x] 📋 decisions.md · [x] 🔧 tools-used.md · [x] 📦 handoff (`docs/corpus-summary.md`)

## Phase 1 — Core engines

### S1.1 — Navigation graph builder — **DONE 2026-07-10** (P1 via P3)
- [x] Fixture graphs match hand-drawn expectations (13 tests, `docs/graphs/*.png`)
- [x] Non-egress windows excluded as exits (flagged in `excluded_exits`, not dropped)
- [x] Pure functions, no I/O
- [x] 📋 decisions.md · [x] 🔧 tools-used.md · [x] 📦 handoff (module + debug renderings)

### S1.2 — Routing engine — **DONE 2026-07-10** (P1 via P3)
- [x] Hand-verified routes on all fixtures incl. apartment bottleneck + two-story stairs
- [x] Deterministic (same input → same output; tested)
- [x] ≥15 unit tests (19 in `backend/tests/test_routing.py`)
- [x] Constraints demonstrably change routes on twostory.json (avoid_stairs → window; +avoid_windows → no_viable_route)
- [x] 📋 decisions.md · [x] 🔧 tools-used.md · [x] 📦 handoff (`docs/route-samples/*.routeplan.json`; CLI gif optional — P1 can record `python3 -m app.routing plan ../schema/fixtures/twostory.json --pretty`)

### S1.3 — 3D dollhouse renderer — **BLOCKED (needs S0.3)** (P2)
- [ ] All three fixtures render correctly and legibly on-device at 60fps
- [ ] Two-story exploded view works
- [ ] Toggling a floor works
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff (30-sec recording per fixture — demo b-roll)

### S1.4 — RoomPlan capture module — **BLOCKED (needs S0.3 + LiDAR device)** (P2)
- [ ] Real 2–3 room scan exports raw JSON with walls/doors/windows present
- [ ] Second full scan of same space completes without crashing
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff (clean + messy exports → `schema/fixtures/scans/`)

### S1.5 — Scan converter (RoomPlan → HomeModel) — **PREP DONE 2026-07-13, awaiting S1.4 real exports** (P1, P3 support)
- [~] Clean scan → valid HomeModel, renders in S1.3, ≥1 exterior door + ≥1 window mapped — **synthetic half done** (`backend/app/convert/`, ground-truth tests on 3 synthetic fixtures; S1.3 render check + real-export validation pending)
- [~] Messy scan → valid model with low-confidence flags, no crash — passes on the synthetic messy fixture; re-verify on S1.4's real messy export
- [~] Conversion idempotent — tested (synthetic); re-verify on real exports
- [ ] 📋 (known failure modes — assumed-format risks listed in `backend/app/convert/README.md`, promote to decisions.md after S1.4 diff) · [ ] 🔧 · [ ] 📦 handoff (USDZ vs render side-by-side)

### S1.6 — Backend scaffold + deploy — **DEPLOYED 2026-07-16, cellular check DEFERRED (team decision)** (P1 via P3)
- [~] Phone on cellular gets twostory.json routes from deployed backend in <2s — **deploy DONE 2026-07-16**: live at `https://escape-plan-backend.onrender.com`. Verified via curl from a dev machine (not phone/cellular): `/health` 200 OK ~0.39s warm, `/routes` on `twostory.json` 200 OK ~0.27s warm — both well under 2s. **Native phone-on-cellular timing DEFERRED BY TEAM DECISION** (no REST client available on the test phone; nothing else is currently blocked on this number) — will be exercised naturally when P2 wires `APIClient.swift` to this URL. Local API fully tested (13 tests incl. /convert, `backend/tests/test_api.py`)
- [x] Secrets not in git (verified: `git grep` for key material clean; token/key are env-only, service fails closed without token). `ANTHROPIC_API_KEY` left unset on Render (blank accepted by the Blueprint form — not required to boot); `BACKEND_BEARER_TOKEN` auto-generated by Render, revealed in dashboard only, never committed
- [x] 📋 · [x] 🔧 (FastAPI, uvicorn, httpx, anthropic, Render) · [~] 📦 handoff (curl examples in backend/README.md ✓; base URL known — `https://escape-plan-backend.onrender.com`; bearer token to be pasted into the team password note by hand, not committed)

## Phase 2 — The 3D editor

### S2.1 — Editor core: rooms, walls, vertices — **BLOCKED (needs S1.3)** (P2)
- [ ] Build bungalow shape by hand on-device in <5 min from empty model
- [ ] Drags feel smooth
- [ ] No gesture yields an invalid model (validate on mutation, reject with haptic)
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff ("built from scratch in 4 min" recording)

### S2.2 — Editor: openings, stairs, undo — **BLOCKED (needs S2.1)** (P2)
- [ ] Fix a misplaced door + confirm flagged items on a real converted scan in <2 min
- [ ] Add working stairs between floors of a hand-built 2-story
- [ ] Undo/redo consistent across 20 mixed operations
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff (updated recording; schema pressure → P1)

### S2.3 — Route visualization on the 3D model — **BLOCKED (needs S1.3 + S1.6)** (P2)
- [ ] Upstairs bedroom → primary animates down stairs and out front door; secondary shows window path
- [ ] Tour mode runs smoothly
- [ ] Warning badge on room lacking secondary egress (apartment/kids' room fixtures are built for this)
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff (recording)

### S2.4 — Persistence & documents — **BLOCKED (needs S2.1)** (P3)
- [ ] Kill + relaunch → everything persists
- [ ] Two saved homes coexist
- [ ] Export validates against the schema
- [ ] 📋 (test checklist) · [ ] 🔧 · [ ] 📦 merged

## Phase 3 — The AI layer

### S3.1 — Grounded explanations + recommendations — **CODE DONE 2026-07-13, live verification BLOCKED-ON-HUMAN** (P1 via P3)
- [~] Valid, cited JSON on all fixtures — enforced by code (schema-enforced tool-use + server-side citation validation w/ retry) and asserted by the 5 golden live tests; **needs one human run: `cd backend && ANTHROPIC_API_KEY=... python3 -m pytest tests/test_ai_live.py -m live -v` (key wasn't in P3's shell env), then review+commit `tests/golden/`**
- [x] Citation validator rejects a fabricated source (in tests — `test_validator_rejects_fabricated_source`, plus full retry-then-502 path)
- [~] p95 latency <6s with prompt caching — caching implemented (cache_control on corpus block, hits logged); latency recorded into golden snapshots on the live run above
- [x] 📋 · [x] 🔧 · [~] 📦 handoff (prompt files committed in `backend/app/ai/grounded.py` ✓; 3 sample outputs = golden snapshots, produced by the live run; red-team deferral test included)

### S3.2 — Agentic home analysis — **CODE DONE 2026-07-16, live verification BLOCKED-ON-KEY** (P3, parallel worktree)
- [~] apartment.json → flags single-point-of-failure exit with evidence — engine flags `d_entry` (confirmed directly); agent correctly cites it in the scripted test (`test_agent_flags_apartment_single_exit_with_evidence`), but no live model has run it yet
- [~] twostory.json → flags bedroom lacking secondary egress — **the engine's own `no_secondary_egress` RouteFinding does NOT trip for `r_bed_kids`** (its secondary route legitimately exits through a different downstairs door); the room's window (`w_kids`) does fail egress on its own, and the agent's `check_egress` tool catches this (`test_agent_flags_kids_room_undersized_window_via_check_egress`) — see `docs/decisions.md` 2026-07-16 for the full explanation before assuming the literal playbook wording holds
- [x] Zero findings without evidence links — enforced server-side in `_validate_findings()`, not just requested of the model (4 tests incl. bad-evidence and bad-citation drops)
- [~] runs <60s — trivially true for the scripted tests (milliseconds); real latency unverified without a live model call
- [x] 📋 decisions.md · [x] 🔧 tools-used.md (no new deps — reuses `anthropic`, already listed) · [x] 📦 handoff (`docs/agent-trace-example/README.md` + `apartment-analysis.json`)

**Remaining for full DONE:** a real ANTHROPIC_API_KEY, a `test_agent_live.py` (doesn't exist yet — mirror `test_ai_live.py`'s marker pattern), one live run, hand-review.

### S3.3 — Chat assistant — **BLOCKED (needs S3.1)** (P3 backend, P2 UI) — cut candidate #2
- [ ] Smoke-detector question → cited, house-specific answer
- [ ] Out-of-corpus question → graceful deferral
- [ ] Conversation survives background/foreground
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff (5 screenshot Q&As)

### S3.4 — Family profiles end-to-end — **BLOCKED (needs S2.3)** (P3 + P2/P1)
- [ ] Grandpa vs Maya switch changes rendered route or raises no-viable-route flag (engine side already proven in tests)
- [ ] Explanation text reflects the profile
- [ ] Deterministic profile→constraints mappings documented
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff (live-switch recording — demo material)

### S3.5 — Preparedness score + checklist — **BLOCKED (needs S3.1 + S3.2)** (P3) — cut candidate #3
- [ ] Score reproducible by hand from documented weights
- [ ] Completing an item updates the score
- [ ] Breakdown screen legible
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff (weights in docs/)

## Phase 4 — Integration & product

### S4.1 — Golden path end-to-end — **BLOCKED (needs S1.5 + S2.3 + S3.1)** (P2 lead, all)
- [ ] One person, one real home, full loop without touching Xcode
- [ ] Injected failures (kill backend mid-flow) degrade gracefully
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff (full-loop recording — demo skeleton)

### S4.2 — Drill / practice mode — **BLOCKED (needs S4.1)** (P3 + P2) — **cut candidate #1**
- [ ] Complete a drill for two different profiles
- [ ] Practiced-state persists and moves the score
- [ ] 📋 · [ ] 🔧 · [ ] 📦

### S4.3 — Real-home testing + bug bash — **BLOCKED (needs S4.1)** (all)
- [ ] Golden path succeeds on 3/3 homes (editor-assisted fine)
- [ ] Zero crashes on the demo path
- [ ] 📋 (shared failure sheet) · [ ] 🔧 · [ ] 📦

### S4.4 — Polish pass — **BLOCKED (needs S4.3)** (P2)
- [ ] Side-by-side before/after
- [ ] Team unanimously prefers after
- [ ] 📋 · [ ] 🔧 · [ ] 📦

## Phase 5 — Demo video & submission

### S5.1 — Script + storyboard — **BLOCKED (needs S4.1)** (P3 lead, P1 accuracy pass)
- [ ] Table-read under 3:15
- [ ] Every claim true of the shipped build
- [ ] 📋 · [ ] 🔧 · [ ] 📦 (storyboard mapped to session recordings)

### S5.2 — Film + edit — **BLOCKED (needs S5.1)** (all)
- [ ] Three non-team viewers get it and name the wow moment unprompted
- [ ] 📋 · [ ] 🔧 · [ ] 📦 handoff (unlisted YouTube upload, CAC specs)

### S5.3 — Submission package — **BLOCKED (needs S5.2)** (P1 accountable, all)
- [ ] Submitted ≥48h before the Oct 26 deadline (target Oct 24)
- [ ] Confirmation screenshot saved in repo
- [ ] tools-used.md complete (CAC originality requirement)
- [ ] App description + "what we learned" answers written
- [ ] 📋 · [ ] 🔧 · [ ] 📦
