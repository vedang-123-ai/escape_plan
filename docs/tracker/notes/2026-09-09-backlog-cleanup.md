# Backlog cleanup — close every agent-doable "Known defect"

- **Who:** Codex (interrupted mid-session, out of context) → finished by Claude (Sonnet 5)
- **Date(s):** 2026-09-09
- **Status when I stopped:** All of `BLOCKERS.md` §3 that a coding agent can close is closed or
  honestly re-scoped. The device-pass checklist (§2) and ship blockers (§1) are untouched, as
  instructed — they need the owner's iPhone and account.

## What happened
- Fixed the tracker's own duplicate-`## 3` heading bug: the device-pass checklist (was mislabeled
  "Simulator-gated blocks") is now a subsection of §2 "Device blocks," and Known
  defects/Flake-and-process/Submission-path renumbered to §3/§4/§5.
- Verified, rather than re-fixed, two items that were already resolved by earlier sessions:
  bookcase/water_heater mitigation coverage (S7.4/S7.5) and the v1.1-self-description line (S7.1).
  Both got a proving test instead of a second edit.
- Fixed for real, each with a new test on the previously-untested path: `/build`'s null
  serialization, `FloorObject.size_m`'s unbounded array, `tornado.py`'s mixed-key-space
  double-count risk, the weak tornado shelter assertion, the onboarding sandbox-pollution bug,
  onboarding's every-run demo-home duplication, and three corpus/grounding mis-citations (FEMA
  over-claim, a dead FEMA URL, ShakeOut step imprecision — all three re-verified live, not
  trusted from the interrupted pass).
- Deleted the dead `routing/perils/objective.py` stub after confirming nothing imports it.
- Retuned `RouteRedrawAfterEditUITests`'s pixel predicate to the current route blue and verified
  the math by direct calculation, then ran it live for what looks like the first time ever — which
  surfaced a second, separate, pre-existing bug (see Decisions/surprises) that the live run still
  can't get past. Recorded as a new, distinct `BLOCKERS.md` line rather than folded into the
  "fixed" one.

## Verification (this session, on this machine)
- `python3 -m pytest backend/tests/ -m "not live" -q` → **385** passed, 13 deselected (up from
  382 — the three new backend tests).
- `python3 backend/corpus/validate.py` → 23 sources, 9 corpus files, 2 threshold files, exit 0
  (unchanged).
- `swift test --package-path tools/editorcore` → **275** passed (up from 273 — the two new
  `FloorObject.size_m` Codable tests).
- `xcodebuild test` full suite, single uncontended run, `.build-merge`, `xcresulttool` summary:
  **615 passed, 0 failed, 8 skipped, 620 total** (up from 608/0/8/616 — the four new Swift unit
  tests; the three new backend tests aren't in this count).
- `TEST_RUNNER_ROUTE_REDRAW=1 xcodebuild test -only-testing:...RouteRedrawAfterEditUITests`
  against a local backend (`BACKEND_BEARER_TOKEN=dev-local-token`, `uvicorn` on :8000): **failed**
  at "House screen never finished loading" — before the pixel assertion this pass fixed is ever
  reached. Root-caused, not left as a mystery: see Decisions/surprises.
- FEMA safe-rooms URL: `curl` gets a `403` from Akamai bot-protection; fetched via `WebFetch`
  instead and confirmed the page contains the exact near-absolute-protection/FEMA-criteria
  language the corpus now cites it for.
- ShakeOut step1 URL: `curl` gets a real `200` and the body contains "Bookcase", "Water Heater",
  "Secure" — matches the corrected citation.

## Decisions / surprises
- See `docs/decisions.md`, "2026-09-09: Backlog cleanup — close every agent-doable 'Known
  defect'" for the full list, including the `OnboardingState.seedError` double-purposing left
  as a minor polish item rather than reopened as a defect.
- **An independent reviewer caught two things this pass got wrong before it was committed** —
  worth naming, since that's the whole point of running one:
  1. The first `shakeout-guidance` fix repointed the source to `/step1/` (correct for the
     furniture-securing citations) but the same id is *also* cited five times elsewhere in
     `earthquake-preparedness.md` for Drop/Cover/Hold-On content — the repoint silently broke
     those. `validate.py` only checks that a cite id resolves, not that its content matches the
     claim, so nothing caught it automatically. Fixed by splitting into two source ids
     (`shakeout-guidance` for step 1, new `shakeout-guidance-dcho` for step 5), both verified
     live. Corpus now has 24 sources, not 23.
  2. The `tornado.py` `exterior_edges` fix was described as closing a "live trap for scan-derived
     homes," but `Opening._check`'s validation (room_ids must include the wall_segment's host,
     never `EXTERIOR_ID`) makes the branch it touched unreachable for any validated `HomeModel` —
     scan-derived homes included. The code change is harmless and simpler either way; the
     BLOCKERS.md characterization was corrected rather than left standing.
- The RouteRedraw live-run failure is a genuinely new find: the test's own launch arguments
  (`-onboarding.completed YES`) skip the only code path that seeds a demo home, so a fresh
  simulator install has nothing for House screen to show. This has apparently never been caught
  because the test has (per the line it's replacing) never actually been run — it's been
  permanently skipped since the 2026-08-05 colour pass made its old orange predicate obsolete.
- FEMA's site blocks non-browser `curl` requests with a `403` even though the URL is live and
  correct — confirmed by fetching through a tool that renders like a browser instead. Filed as a
  reminder alongside S7.2's "HTTP 200 isn't content proof" lesson: for some government sites,
  `curl` doesn't even get that far.

## Questions for teammates
None.

## Next steps
- Fix the RouteRedraw test's bootstrap gap (seed a home some other way before it skips
  onboarding), then re-run live and confirm the pixel assertions themselves pass — new line in
  `BLOCKERS.md` §3.
- Everything else remaining in `BLOCKERS.md` is either §1 (owner-only: billing, bearer token) or
  §2 (needs the physical iPhone), or an item this pass deliberately left alone (elevation-blind
  routing, thin fixture seeding, the 19 stranded contract tests, `RouteFinding`'s missing
  `citation` field) — none of it is agent-closeable right now.
