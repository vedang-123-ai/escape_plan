# Everything still to do

_Last verified: 2026-08-04 on `main` (full-app test sweep) — **every suite re-run this session
and green**: backend **264** not-live (13 live-deselected), EditorCore **186**, iOS **320**
(315 unit + UI, 8 skipped), corpus valid. Endpoints exercised by hand too: `/routes` on all
three fixtures (16/16 rooms routed), `/convert` on two synthetic scans, `/score` on all three.
See `notes/2026-08-04-full-app-test-sweep.md`._

_**AI is entirely down — the Anthropic account is out of credits.** One `/explain` succeeded
this session (200, 26.0s, good grounded output) and the balance ran out mid-sweep. `/explain`,
`/analyze`, `/chat` and every `-m live` suite are blocked on a top-up, not on code. Read the
first blocker section below before planning any AI work or filming._

_**Do not trust a single iOS run.** Three identical back-to-back full runs went pass / fail
(10 failures) / pass. Every failure was `Simulator device failed to launch … Busy
("Application failed preflight checks")` — environmental, kills both test targets, says nothing
about the code. Also: `xcodebuild`'s console prints `Executed 16 tests` because the unit target
runs under Swift Testing; the real count is in the result bundle
(`xcrun xcresulttool get test-results summary --path <bundle>` → 320)._

_Prior stamp, 2026-08-02 on `main` (check_obstructions agent tool) — backend 258 not-live pass,
corpus valid. EditorCore and iOS were not re-run that session._

_Prior stamp, 2026-07-24 on `main` (route-fix + live-AI session) — backend 248 not-live + 12
live pass, editorcore 186, corpus valid, iOS FULL suite (unit + UI) TEST SUCCEEDED. Escape
routes confirmed rendering on the simulator after the stale-@State fix. (The 2026-07-30 merge
moved backend to 252 without refreshing this table.)_

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
| Backend pytest | 264 pass, 13 live-deselected (2026-08-04) | `python3 -m pytest backend/tests/ -m "not live"` |
| Backend live suites | 12 pass (2026-07-24); the 13th (`agent_bungalow_blocked`) has never run. **Blocked on credits as of 2026-08-04, not just on a key** | `set -a; . ./.env; set +a; python3 -m pytest backend/tests/ -m "live"` (latency bounds can flake on API variance) |
| EditorCore (SwiftPM) | 186 pass (2026-08-04) | `swift test --package-path tools/editorcore` |
| iOS (unit + UI) | 320 pass, 8 skipped (2026-08-04) — **~1-in-3 launch flake, re-run before believing a red** | `xcodebuild test -scheme escape_plan …` |
| Corpus | 11 sources, 6 files (2026-08-04) | `python3 backend/corpus/validate.py` |

**Heads-up on `python3`:** on at least one machine the system `python3` is 3.9 and cannot
import pydantic; that machine needs its own venv. On this one (2026-08-04) system `python3` is
3.13.5 with pydantic 2.13.3 and runs everything — and **`backend/.venv` does not exist**, so
the old "use `backend/.venv/bin/python`" instruction fails outright. Check before assuming.

---

## ~~BLOCKER — escape routes do not render~~ FIXED 2026-07-24

Root cause: `HouseScreen`'s `onRebuild` closure read `@State routePlan` from a stale captured
View snapshot (always nil), and `updateUIView` rebuilds the scene empty on every render, so
routes were wiped as fast as they were drawn. Fixed by caching draw inputs + view state in the
`RouteOverlayHolder` class and redrawing from it in `onRebuild`. The explode slider had the
same latent bug (snapped to 0 on rebuild); after the 2026-07-30 merge that half is carried by
the UI branch's separate `SceneViewStateHolder`, and both boxes now coexist. **Confirmed rendering**
on the simulator (orange primary + blue secondary, all 7 primaries in "Everyone", exit glows).
Details: decisions.md 2026-07-24 (later) + `notes/2026-07-24-look-and-feel-*.md`.

**Re-confirmed on the merged build 2026-08-02** — the open "nobody has looked at the merge on a
simulator" item is now closed. Routes draw, and they survive a committed edit (the exact thing
the fix protects). Evidence: `docs/evidence/route-redraw-2026-08-02/`; regression guard:
`escape_planUITests/RouteRedrawAfterEditUITests` (env-gated, needs a local backend).

## 3D revamp (approved 2026-07-23 — spec/plan: `~/.claude/plans/i-want-you-to-tender-flask.md`)

**ALL SIX PHASES LANDED 2026-07-23** (A1–A3 unified free-camera HouseScreen; B1–B3 schema
v1.1 objects + obstacle-aware grid routing; C1–C2 LLM house builder + forced review gate).
Notes: `notes/2026-07-23-revamp-a1-camera-rig.md`, `-a2-unified-editing.md`,
`-a3-housescreen.md`, `-b-c-objects-routing-builder.md`. Remaining follow-ups:

- [ ] Device-acceptance pass on the whole revamp: unified HouseScreen gesture feel (orbit
      sensitivity, pinch anchor, dock height on small screens), object editing, plan-import
      flow + review gate, tour. Simulator + recording-driver verified; real-device feel and
      real-photo floor plans are the open items.
- [ ] Fixture-kit renderer (landed 2026-07-29, `notes/2026-07-29-fixture-kit-renderer.md`):
      include in the device-acceptance pass above — node count is ~3-4× the old builder and
      the editor rebuilds per commit; profile one edit-drag session on hardware. Next
      actions if custom assets land: register via `FixtureCatalog.shared.door =
      AssetFixture(named:)` at startup, then eyeball joins on all three schema fixtures.
- [x] ~~Live builder golden~~ — run 2026-07-24 with the key in `.env`; PASSES after removing
      the deprecated `temperature` param from `builder.py` (the model 400s on it). See
      decisions.md 2026-07-24 (later). (The 2026-07-29 branch still listed this as blocked on
      the key — it was closed on the other branch before the merge.)
- [x] ~~Surface `blocked_opening` in /score~~ — done 2026-07-24, and went further per Anish:
      `app/routing/obstructions.py` names WHICH object blocks (counterfactual attribution)
      and how far to move it (measured), surfaced in `RouteFinding.detail` + `object_ids`
      and as a `usfa-escape-plans`-cited checklist item. 10 tests.
- [x] ~~Give the S3.2 **agent** a `check_obstructions` tool~~ — done 2026-08-02. Optional
      `room_id` filter, returns the engine's fields verbatim including its `detail`
      sentence; prompt rule 1 now forbids estimating a move distance, rule 4 maps
      `blocks_opening`/`narrows_route` to severities. 6 deterministic tests (backend 248 →
      258). See decisions.md 2026-08-02. **The live case is unrun** — next item.
- [ ] Review the golden for `test_blocked_bungalow_agent_names_the_wardrobe`
      (`backend/tests/test_agent_live.py`, `-m live`). It has never executed: there is no
      `ANTHROPIC_API_KEY` on every machine — the `.env` in the stamp above is gitignored and
      machine-local, so a fresh clone does not inherit it. On the first machine with the key,
      run the live agent suite; the golden writes itself and `pytest.skip`s for review, then
      commit `backend/tests/golden/agent_bungalow_blocked.json`. (S3.2)

## BLOCKER — the Anthropic account is out of credits (found 2026-08-04)

Every AI feature is dead. `/explain`, `/analyze` and `/chat` fail with
`Your credit balance is too low to access the Anthropic API`. One `/explain` succeeded earlier
in the same session (200 in 26.0s, good grounded output), so this happened just now — the key
in `.env` is valid, the balance is not. The deterministic half (`/routes`, `/score`,
`/convert`) is completely unaffected, which is the architecture working as designed.

- [ ] **Top up the Anthropic account.** Blocks: the AI half of the demo, the never-executed
      `agent_bungalow_blocked` live golden, all 13 `-m live` tests, and any filming that shows
      the assistant. Nothing else on this list is closer to the critical path.
- [x] ~~AI API errors surfaced as a bare `500 Internal Server Error`~~ — fixed 2026-08-04.
      Each AI module only guarded the *missing-key* case; the `client.messages.create` calls
      were unguarded, so a dry account / rate limit / outage escaped as a 500 with nothing the
      app could show. One app-level `@app.exception_handler(anthropic.APIError)` now returns
      **502** (operator must act: no credit, bad key) or **503** (retryable: rate limit,
      overload, network), with the API's own sentence as `detail`. Verified against the real
      dry account. 6 tests (backend 258 → 264). See decisions.md 2026-08-04.
- [ ] Decide what the **app** shows for the new 502 vs 503. The backend now distinguishes
      "retry may work" from "an operator must act", but Swift's `APIClientError` only carries
      `unexpectedResponse(statusCode:)` — so both still render as one generic failure. Cheapest
      version: map 503 → banner with a Retry button, 502 → "AI features are unavailable right
      now" with no retry. (S1.6/S4.4)

## Blocked on a real API key

2026-07-23 (Lane C): a real key was used locally — the entire live battery below was run and
hand-reviewed; goldens are committed in `backend/tests/golden/`. What remains here is only
what a dev machine cannot close.

- [x] ~~Key not persisted anywhere locally~~ — Anish placed it in repo-root `.env`
      (gitignored) on 2026-07-24; live suites and local AI now work. (Deployed Render backend
      still needs its own dashboard env var — next item.)
- [ ] Set `ANTHROPIC_API_KEY` in the Render dashboard so the deployed backend's AI endpoints
      work at all. Until this happens `/explain`, `/analyze`, and `/chat` 502 in production.
      Exact steps: dashboard → `escape-plan-backend` service → Environment → add
      `ANTHROPIC_API_KEY` → save (auto-redeploys). Then verify: `/health` 200, one
      token-authed `/explain` on a fixture returns 200 with resolving citations. (S1.6)
- [ ] **p95 `/explain` < 6s is UNMET — DEFERRED 2026-07-24**, not resolved. Anish's call: the
      submission is an edited video, so a slow call can be cut around; revisit only if the
      app is ever judged live. The criterion stays formally unmet. Original measurement — measured 2026-07-23 on
      claude-sonnet-5, cache hits confirmed on every request: warm mean 26.3s, p95 30.2s
      (haiku-4-5 comparison ~18.5s). Output-bound (~2k output tokens/whole-home explanation),
      so caching can't fix it. Options: terser output, per-room explain calls, streaming UX,
      faster model, or revise the target. See decisions.md 2026-07-23. (S3.1)
- [x] ~~Garbled-generation glitch: decide retry vs tolerate~~ — Anish chose **tolerate +
      document**, 2026-07-24. See decisions.md. No code; revisit only if it recurs more often.

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

_2026-07-24: three closed. The three demo homes now seed on first launch
(`FixtureSeeder.seedStarterHomes`) — nothing created them before, which is why the screenshot
driver silently skipped the profile-switch shot. The House tab got its visual pass (dark
stage backdrop, plate-backed legible labels, dock 240→200 pt). The stale "Plan tab" copy in
the assistant banner + onboarding is now "House tab"._

_The four 2026-07-22 editor bugs (HomeModelPersisting unconformed, stale toolbar after
tap-selection, second-tap redo, "unwired" bridge) are fixed and verified on `lane/editor` —
see `notes/2026-07-23-lane-a-editor-completion.md`. Stairs on a hand-built two-story home
verified in the recorded manual-build run. The old "Render URL is not the app's default"
item is closed by S4.4 Lane B: `APIClient` now defaults to the deployed Render URL._

- [ ] `setOpeningWidth` exists in the reducer with tests but has **no UI entry point** — add a
      width control (stepper/slider) to the opening inspector in `HouseScreen` (EditorScreen
      was merged into it in revamp A3). (Lane A)
- [ ] The House *tab*'s standalone `HouseScreen()` has no `HomeLibrary`, so the
      delete-under-editor seam only protects the HomeScreen→Editor push path. Cross-tab
      delete while the House tab holds the same home is still unguarded — share one library
      instance (or an app-level environment object) if that matters. (Lane A)
- [ ] Selecting an opening or stairs draws no marker in the 3D view
      (`UnifiedSceneController.highlightCenter` returns nil for both — deferred since S2.2).
      The inspector bar makes the selection legible; a visible marker needs Lane B's renderer
      touch. (S2.2/Lane B)
- [ ] Custom launch screen (branded color/image instead of the generated blank): needs a
      pbxproj edit (storyboard ref or physical Info.plist), deliberately deferred to the
      integration window while Lane A holds the project file — decisions.md 2026-07-23. (S4.4)
- [ ] Real-device check of the S4.4 renderer work: 60fps on all three fixtures on a physical
      phone, and haptics feel (simulator can't verify either). (S4.4)
- [ ] Drop the real shared bearer token into `escape_plan/BackendConfig.local.json`
      (`{"bearer_token": "..."}`, gitignored) on the build machine before any demo/device
      build — without it a fresh install reaches the Render URL but gets 401s until the
      token is typed in Settings. Mechanism + decision: decisions.md 2026-07-23. (S4.4)

## Client/server contract (added 2026-08-02)

- [x] ~~Score screen dead on apartment + twostory~~ — fixed 2026-08-02. Backend emitted
      `category: "egress"` (R310 work, 2026-07-27); Swift's `ChecklistCategory` had no case,
      and a throwing enum failed the whole `ScoreBreakdown`. Also fixed the whitelist behind
      it (`ScoreScreen.categoryOrder`) that would have made the fix look successful while
      still rendering nothing. Verified by 315 unit tests (a decode test using the real
      `egress` category + a whitelist-exhaustiveness test), and by curl against the backend
      confirming which categories each fixture emits. **Not yet seen on screen** — next item.
- [x] ~~Screenshot the fixed Score screen~~ — **done 2026-08-04, TEST SUCCEEDED.** Evidence:
      `docs/evidence/score-screen-2026-08-04/` (twostory, 75/100, all five components
      rendered, no decode-failure state). Disk was a real factor in the earlier attempts, but
      the test *also* asserted `navigationBars["Score"]` while `ScoreScreen` sets
      `.navigationTitle(breakdown?.home_name ?? "Score")` — "Score" is the **loading** title,
      so the assertion failed on exactly the runs that worked, and would have failed forever.
      Now waits on the "How it's scored" header. See decisions.md 2026-08-04. (S3.5)
- [x] ~~Enum tolerance sweep~~ — done 2026-08-02, all ten enums checked. `FindingKind`,
      `WaypointKind`, `Severity` made tolerant; the six schema enums left strict on purpose
      (they round-trip user data — see decisions.md). iOS unit suite 309 → 315.
- [ ] **Surface `narrows_route` as a RouteFinding** — `obstructions.py` computes it and
      nothing shows it. Now safe to wire up: `FindingKind` degrades gracefully instead of
      killing the plan, and `RouteFindingViews` has an `.unknown` style. Would have broken
      routes outright before today. (S2.3/revamp)
- [ ] Consider a contract test that diffs the backend's `Literal`/enum values against the
      Swift cases automatically. Today's sweep was by hand and found the gap six days late;
      nothing stops the next one. Cheapest version: a pytest that imports the enums, greps
      the Swift sources, and asserts the value sets match.

## Backend

- [ ] **DECISION NEEDED (P1): a home that has never been analysed scores full marks for
      safety.** `/score` defaults `findings=[]`, so the 20-point "No open safety findings"
      component pays out in full when `/analyze` has simply never run — bungalow and twostory
      both read 75/100 on a home nobody has audited. "We didn't look" and "we looked and it's
      clean" produce the same number, which is a safety claim the app hasn't earned. Fix
      would be to distinguish absent from empty (e.g. `findings: Optional[...] = None` →
      component reported as *not assessed*, its 20 pts subtracted from a new `max_possible`
      so the UI renders "55 / 80"). **Not done unilaterally: it changes `ScoreBreakdown`, the
      `ScoreScreen`/`ScoreModels` Swift contract, and every worked example in the weights
      doc.** Mitigated in part 2026-07-27 — undersized bedroom egress windows are now caught
      deterministically without `/analyze` (see `egress.window.*` items). **Now visible in a
      committed screenshot** (`docs/evidence/score-screen-2026-08-04/`): the twostory home
      reads "No open safety findings — 20/20" having never been analysed. Worth deciding
      before the demo script locks, since the score is on camera. (S3.5)
- [ ] Phone-on-cellular timing against the deployed backend was never measured natively.
      Warm curl from a dev machine was ~0.27–0.39s, well under the 2s bar. (S1.6)
- [ ] TODO(integration): `/analyze` findings now carry a stable server-stamped `id`
      (2026-07-23); Swift's `AgentFinding` ignores it and `ChecklistStateStore` still sees
      positional `agent_finding.<index>` keys via the fallback. Thread the `id` through the
      Swift decode (add to CodingKeys) and key checkmarks on `agent_finding.<id>` — old
      positional checkmarks are deliberately orphaned (see decisions.md 2026-07-23). (S3.2/S3.5)

## Demo & submission

- [ ] Table-read the script aloud, confirm under 3:15. On paper it's 436 words ≈ 2:54 at
      150 wpm, but the box means an actual read-aloud. (S5.1)
- [ ] Tech-accuracy pass: verify every claim in `docs/demo/script-v1.md` against the shipped
      build. The script's truth-ledger appendix is a self-audit, not an independent check. (S5.1)
- [ ] Golden path on a **real device** — the simulator half is done (2026-07-23, Lane B):
      onboarding loop green live against the local backend, routes rendered on 3/3 fixtures,
      plan/chat/score/drill walked with backend up AND pointed at a dead port (graceful
      banners, zero crashes; `S44BackendDownUITests` + `docs/evidence/s44-after/offline-*`).
      Remaining: same pass on a phone. (S4.3)
- [ ] Polish pass: the before/after artifact is built and committed
      (`docs/evidence/s44-before-after.md` + `s44-before/` + `s44-after/`, 2026-07-23) —
      remaining: the team actually looks at it and prefers the after. (S4.4)
- [ ] Film + edit; three non-team viewers name the wow moment unprompted. (S5.2)
- [ ] Submit, save the confirmation screenshot in the repo, finish `tools-used.md`, and write
      the app description + "what we learned" answers. (S5.3)

## Process & repo hygiene

- [ ] **iOS test runs are ~1-in-3 flaky at launch (found 2026-08-04).** Three identical
      back-to-back full runs: pass / fail (10 failures) / pass. Every failure was
      `Simulator device failed to launch cac.Escape-Plan … Busy ("Application failed preflight
      checks")` — it takes down both test targets, so a red run says nothing about the code.
      Disk is the most likely lever (93% used, 31 GB free; the previous blocker was 99%).
      Next action: free disk, run the gate 5× in a row, and record the pass rate here. If it
      persists it will bite during filming. Until then, **re-run before believing a red**.
- [ ] Console output undercounts the iOS suite — `xcodebuild` prints `Executed 16 tests`
      because the unit target runs under Swift Testing, which doesn't emit the old
      `Test Suite` lines. The true count (320) is only in the result bundle. Anything that
      parses the console tail for a pass count is wrong. Next action: when someone touches
      the `/verify` skill, have it read
      `xcrun xcresulttool get test-results summary --path <bundle>` instead.

- [ ] Backfill curated evidence for the S2.2/S2.3/S3.4/S3.5 handoffs (their ~45 MB of
      screenshots/recordings still live only in one machine's gitignored `artifacts/`).
      The convention + home for it now exists: `docs/evidence/` (see its README; S4.4's
      before/after sets are the first committed example). (process)
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
