# Everything still to do

_Last verified: 2026-07-23 on `lane/editor` (../ep-editor worktree) — revamp A1 session:
editorcore 158 pass, iOS **unit** suite green (UI tests not re-run — no editor-path change);
full gate before that was the Lane A editor-completion session._

This is the single source of truth for open work. It replaces the old `board.md` +
`checklist.md`, which had drifted into contradicting each other.

**Rules**

- Only things **not yet done** live here. Finished work is in git and in `notes/`.
- Check a box only after you verified it yourself. "The code exists" is not verification.
- Every line names the concrete next action. If you can't name one, it isn't ready to be here.
- The `(S3.2)` tag links back to `docs/playbook/S3-2.md` for the original spec.

**Verified green as of the stamp above** — if you change code, re-run `/verify`:

| Suite | Count | Command |
|---|---|---|
| Backend pytest | 196 pass, 11 live-deselected | `python3 -m pytest backend/tests/ -m "not live"` |
| EditorCore (SwiftPM) | 146 pass | `swift test --package-path tools/editorcore` |
| iOS (unit + UI) | 266 pass, 3 skipped (env-gated recording drivers) | `xcodebuild test -scheme escape_plan …` |
| Corpus | 11 sources, 6 files | `python3 backend/corpus/validate.py` |

---

## 3D revamp (approved 2026-07-23 — spec/plan: `~/.claude/plans/i-want-you-to-tender-flask.md`)

One free-camera translucent dollhouse = viewer + editor; objects block routes; agentic LLM
house builder behind forced review. Order A → B → C. A1 (camera rig, unified read-only view,
RenderOrder ledger, tour fix) landed 2026-07-23 — see `notes/2026-07-23-revamp-a1-camera-rig.md`.

- [ ] A1 follow-up: device-acceptance pass on gesture feel (orbit sensitivity, pinch anchor)
      before A3 deletes the old camera stack.
- [ ] A3: merge PlanScreen+EditorScreen into `HouseScreen`; delete `EditorSceneController`,
      `DollhouseSceneView`, old screens; full gate + device acceptance.
      (A2 landed 2026-07-23 — arbitrated editing in the unified view, driver passing live;
      see `notes/2026-07-23-revamp-a2-unified-editing.md`.)
- [ ] B1: schema v1.1 — `floor.objects` (box primitives, no room_id) + `source: ai_plan`;
      three-way lockstep + SchemaMigrator + planted-obstacle fixtures. Own PR.
- [ ] B2: objects rendered (RenderOrder band 5) + editable (EditActions, rotated-rect
      hit-testing, inspector).
- [ ] B3: within-room pathfinding — 0.1 m occupancy grid + clearance transform +
      deterministic A* in `backend/app/routing/`; blocked opening ⇒ edge omitted ⇒ room-level
      re-plan + `blocked_opening` finding; golden updates in their own commit.
- [ ] C1: `backend/app/builder/actions.py` + `ai/builder.py` agent loop (no routing tools,
      everything `source=ai_plan`) + `POST /build` with hard validation.
- [ ] C2: iOS plan-import (text + floor-plan image, PDF rasterized client-side) + forced
      review gate (`needsReview` from any `ai_plan` source; routes disabled until confirmed).

## Blocked on a real API key

Nothing here is a code problem. `ANTHROPIC_API_KEY` is unset both locally and on Render, so
every AI endpoint returns a clean 502 today (verified 2026-07-22 — the failure is graceful,
not a crash).

- [ ] Set `ANTHROPIC_API_KEY` in the Render dashboard so the deployed backend's AI endpoints
      work at all. Until this happens `/explain`, `/analyze`, and `/chat` 502 in production. (S1.6)
- [ ] Run the live grounded-explanation suite and hand-review the snapshots it writes:
      `cd backend && ANTHROPIC_API_KEY=… python3 -m pytest tests/test_ai_live.py -m live -v`,
      then review + commit `tests/golden/`. (S3.1)
- [ ] Run the live agent suite the same way (`tests/test_agent_live.py`), hand-review
      `tests/golden/agent_*.json`. Confirms the apartment single-exit finding and the
      `w_kids` undersized-window path come back cited and evidence-linked. (S3.2)
- [ ] Confirm p95 `/explain` latency < 6s with prompt caching on (caching is implemented and
      cache hits are logged; the number gets recorded into the golden snapshots). (S3.1)
- [ ] Chat: ask a smoke-detector question, confirm a cited, house-specific answer. (S3.3)
- [ ] Chat: ask an out-of-corpus question, confirm graceful deferral rather than invented
      advice. (S3.3)
- [ ] Profiles: confirm the explanation text actually reflects the selected profile
      (route switching itself is already verified — this is only the `/explain` prose). (S3.4)

## Needs real LiDAR hardware

The simulator has no LiDAR, so none of this can be closed from a dev machine. The scan entry
point and the `/convert` upload path were wired 2026-07-22 and are reachable in the app; what
is unverified is the round-trip against a real scan.

- [ ] Scan a real 2–3 room space; confirm the raw JSON export has walls/doors/windows. (S1.4)
- [ ] Scan the same space twice in a row without crashing. (S1.4)
- [ ] Commit one clean and one messy real export to `schema/fixtures/scans/`. Everything in
      the converter section below is waiting on this. (S1.4)
- [ ] Real scan → `/convert` → valid HomeModel that renders, with ≥1 exterior door and ≥1
      window mapped. Currently only proven on synthetic fixtures. (S1.5)
- [ ] Messy real scan → valid model with low-confidence flags and no crash. (S1.5)
- [ ] Confirm conversion is idempotent on a real export. (S1.5)
- [ ] Promote the assumed-format risks in `backend/app/convert/README.md` into
      `decisions.md` once a real export shows which assumptions held. (S1.5)
- [ ] Fix a misplaced door on a **real converted scan** in under 2 min, and confirm flagged
      items appear. The equivalent was observed on the twostory fixture; the real-scan half
      is open. (S2.2)
- [ ] Full golden path on one real home without touching Xcode. (S4.1)

## Needs a physical device (no LiDAR required)

- [ ] All three fixtures render legibly at 60fps on-device. Observed working on simulator;
      the frame-rate claim needs real hardware. (S1.3)
- [ ] Two-story exploded view and floor toggling on-device. (S1.3)
- [ ] Build the bungalow shape by hand on-device in under 5 min from an empty model, and
      confirm drags feel smooth. (S2.1)
- [ ] Confirm no gesture can produce an invalid model. (S2.1)
- [ ] Kill and relaunch the app: everything persists, two saved homes coexist. (S2.4)
- [ ] Confirm chat conversation survives background/foreground. (S3.3)
- [ ] Kill the backend mid-flow and confirm the app degrades gracefully. Every failure state
      exists in code and is unit-tested; this is the live pass. (S4.1)
- [ ] Complete a drill for two different profiles (twostory, Grandpa + Maya). The entry point
      is now wired — Home tab → swipe a home → "Drill". (S4.2)
- [ ] Confirm practiced-state persists and moves the preparedness score across a relaunch. (S4.2)

## iOS — real code gaps

_The four 2026-07-22 editor bugs (HomeModelPersisting unconformed, stale toolbar after
tap-selection, second-tap redo, "unwired" bridge) are fixed and verified on `lane/editor` —
see `notes/2026-07-23-lane-a-editor-completion.md`. Stairs on a hand-built two-story home
verified in the recorded manual-build run. New follow-ups discovered in that session:_

- [ ] `setOpeningWidth` exists in the reducer with tests but has **no UI entry point** — add a
      width control (stepper/slider) to the opening inspector in `EditorScreen`. (Lane A)
- [ ] The Editor *tab*'s standalone `EditorScreen()` has no `HomeLibrary`, so the
      delete-under-editor seam only protects the HomeScreen→Editor push path. Cross-tab
      delete while the Editor tab holds the same home is still unguarded — share one library
      instance (or an app-level environment object) if that matters. (Lane A)
- [ ] Selecting an opening or stairs draws no marker in the 3D view
      (`EditorSceneController.highlightCenter` returns nil for both — deferred since S2.2).
      The inspector bar makes the selection legible; a visible marker needs Lane B's renderer
      touch. (S2.2/Lane B)
- [ ] The deployed Render URL is not the app's default — `APIClient.developmentDefaultBaseURL`
      is `http://localhost:8000` and there is no prefilled bearer token, so a fresh install
      talks to nothing until someone types both into Settings. Decide whether the shipped
      default should be the Render URL. (S1.6)

## Backend

- [ ] Agent findings have no stable id, so `checklist.py` keys done-state positionally
      (`agent_finding.<index>`). A re-analysis that reorders findings mis-keys saved
      checkmarks. Non-scoring, so the blast radius is a stale checkmark, not a wrong score. (S3.2/S3.5)
- [ ] `app.ai.agent.Finding` and `app.scoring.findings.Finding` are field-identical
      duplicates, kept separate on purpose (scoring must not import the Anthropic SDK). They
      have to be changed in lockstep by hand — no test currently fails if they drift apart.
      Consider a test that asserts the two field sets match. (S3.2/S3.5)
- [ ] Phone-on-cellular timing against the deployed backend was never measured natively.
      Warm curl from a dev machine was ~0.27–0.39s, well under the 2s bar. (S1.6)

## Demo & submission

- [ ] Table-read the script aloud, confirm under 3:15. On paper it's 436 words ≈ 2:54 at
      150 wpm, but the box means an actual read-aloud. (S5.1)
- [ ] Tech-accuracy pass: verify every claim in `docs/demo/script-v1.md` against the shipped
      build. The script's truth-ledger appendix is a self-audit, not an independent check. (S5.1)
- [ ] Golden path succeeds on 3/3 homes, zero crashes on the demo path. (S4.3)
- [ ] Polish pass: side-by-side before/after that everyone prefers. (S4.4)
- [ ] Film + edit; three non-team viewers name the wow moment unprompted. (S5.2)
- [ ] Submit, save the confirmation screenshot in the repo, finish `tools-used.md`, and write
      the app description + "what we learned" answers. (S5.3)

## Process & repo hygiene

- [ ] **Acceptance evidence is untracked.** `artifacts/` is gitignored wholesale
      (`git ls-files artifacts` returns 0), so the ~45 MB of screenshots and recordings cited
      as the S2.2/S2.3/S3.4/S3.5 handoffs exists only on one machine. Either commit a small
      curated subset or stop citing untracked paths as evidence.
- [ ] `docs/demo/broll/s41-golden-path-simulator.mp4` (19 MB) is committed to git history.
      Removing it needs a history rewrite. At minimum, gitignore future broll.
- [ ] Corpus sign-off: someone other than the author should actually read
      `docs/corpus-summary.md` and confirm it's sufficient for the AI layer, or reopen it if
      thin. It was marked done without an independent read. (S0.4)
- [ ] `escape_plan/CLAUDE.md` is copied into the shipped `.app` bundle as a resource by the
      `PBXFileSystemSynchronizedRootGroup`. Gitignored so it never reaches git, but it will
      ship in a release build. Exclude it from Copy Resources.
- [ ] Residual `P1`/`P2`/`P3` prose mentions remain in ~20 archived docs (playbook narrative,
      demo storyboards, `decisions.md` history). The mechanical lane labels are gone; these
      are sentences that need rewriting by hand, and `docs/tracker/notes/` is deliberately
      left untouched as a dated archive.
