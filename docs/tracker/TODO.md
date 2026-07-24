# Everything still to do

_Last verified: 2026-07-23 @ lane/backend f39d9f6 — backend + corpus re-verified live (real
ANTHROPIC_API_KEY, all live suites run and green); EditorCore/iOS counts below are from the
2026-07-22 pass and untouched by this lane._

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
| Backend pytest | 207 pass, 11 live-deselected | `python3 -m pytest backend/tests/ -m "not live"` |
| Backend live suites | 6 + 2 + chat smoke, all pass | `python3 -m pytest backend/tests/ -m "" ` (needs key; latency bounds can flake on API variance) |
| EditorCore (SwiftPM) | 128 pass | `swift test --package-path tools/editorcore` |
| iOS (unit + UI) | 242 pass, 1 skipped | `xcodebuild test -scheme escape_plan …` |
| Corpus | 11 sources, 6 files | `python3 backend/corpus/validate.py` |

---

## Blocked on a real API key

2026-07-23 (Lane C): a real key was used locally — the entire live battery below was run and
hand-reviewed; goldens are committed in `backend/tests/golden/`. What remains here is only
what a dev machine cannot close.

- [ ] Set `ANTHROPIC_API_KEY` in the Render dashboard so the deployed backend's AI endpoints
      work at all. Until this happens `/explain`, `/analyze`, and `/chat` 502 in production.
      Exact steps: dashboard → `escape-plan-backend` service → Environment → add
      `ANTHROPIC_API_KEY` → save (auto-redeploys). Then verify: `/health` 200, one
      token-authed `/explain` on a fixture returns 200 with resolving citations. (S1.6)
- [ ] **p95 `/explain` < 6s is UNMET and needs a team decision** — measured 2026-07-23 on
      claude-sonnet-5, cache hits confirmed on every request: warm mean 26.3s, p95 30.2s
      (haiku-4-5 comparison ~18.5s). Output-bound (~2k output tokens/whole-home explanation),
      so caching can't fix it. Options: terser output, per-room explain calls, streaming UX,
      faster model, or revise the target. See decisions.md 2026-07-23. (S3.1)
- [ ] One transient garbled-generation glitch observed (95s run, corrupted prose that still
      passed citation validation). Decide whether /explain needs a server-side coherence
      retry or the app tolerates the rare bad response. (S3.1)

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

- [ ] **`HomeModelPersisting` is declared but nothing conforms to it** and
      `HomeLibrary.editor` is never assigned. Consequence: deleting a home that is open in
      the editor does not close it or clear its undo history. Fix: conform `HomeModelStore`
      and set `HomeLibrary.editor` when the editor opens. (S2.1/S2.4)
- [ ] **Editor toolbar doesn't refresh after a tap-selection**, so "Add Stairs" stays
      disabled until some other action bumps the revision and forces a re-render. Known
      workaround only; see the 2026-07-22 device-acceptance entry in `decisions.md`. (S2.2)
- [ ] **Redo occasionally needs a second tap** right after an undo — same stale-render
      suspicion as above. Not blocking, but it will look bad on camera. (S2.2)
- [ ] `SceneKitEditorBridge` gesture recognizers are still unwired (`TODO(integration)` in
      the file's header block). (S2.1)
- [ ] Add stairs between floors of a **hand-built** two-story home. Observed only on the
      seeded fixture. (S2.2)
- [ ] Custom launch screen (branded color/image instead of the generated blank): needs a
      pbxproj edit (storyboard ref or physical Info.plist), deliberately deferred to the
      integration window while Lane A holds the project file — decisions.md 2026-07-23. (S4.4)
- [ ] Real-device check of the S4.4 renderer work: 60fps on all three fixtures on a physical
      phone, and haptics feel (simulator can't verify either). (S4.4)
- [ ] Drop the real shared bearer token into `escape_plan/BackendConfig.local.json`
      (`{"bearer_token": "..."}`, gitignored) on the build machine before any demo/device
      build — without it a fresh install reaches the Render URL but gets 401s until the
      token is typed in Settings. Mechanism + decision: decisions.md 2026-07-23. (S4.4)

## Backend

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
