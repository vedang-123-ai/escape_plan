# Decisions log

| 2026-10-04 | S11.39 Path B: AI inspector dormanted | **Kept `APIClient+Analyze.swift` and `AnalyzeModels.swift` dormant instead of deleting them.** They have had no callers since `dac8673`, but `escape_planTests/OnboardingTests.swift` still depends on decoding `AnalysisResult`. Kept them with a comment clarifying they are uncalled, as instructed for Path B. `ReadinessStore`'s `agent_finding` also stays dormant. |
Running log of deviations from playbook defaults, and why. Newest first.

| Date | Session | Decision | Why |
|------|---------|----------|-----|
| 2026-10-23 | presubmit-fixes | **The assistant calls live `/chat` again. The Oct 18 pre-written conversation is only a fallback, for Anish's House only, on a 502/503/504 or a dropped connection, and shown under a "Sample conversation" label.** Corrects `f9b1c9b`, which answered every question in every home from the script as if live. | Owner chose "live AI, labelled fallback" on 2026-10-23. The demo keeps a working assistant with no credit, and nothing pre-written is passed off as a live AI answer. |
| 2026-10-23 | presubmit-fixes | **`/score` passes `ObjectHazardThresholds`, so the S7 hazard rules finally reach the app.** Two-Story caps at 40, Anish's House at 40. | The endpoint never passed them (no commit ever did); only direct `compute_score` tests saw `hazard.*` items. Owner chose to fix it, accepting the score change. |
| 2026-10-23 | presubmit-fixes | **`HouseScreen(embedsNavigationStack: false)` when pushed from Home.** | A02-01/02: two nested stacks hid the back button on "Build it myself". |
| 2026-10-11 | scan-quality-fixes | **Furniture lower than a window's sill (+0.10 m) never blocks that window; a scanned object's shortfall within 0.05 m per side is not reported; a shared door is probed at the probing room's own wall.** | Owner's device scan reported a bed under a bedroom window as a "blocked doorway" needing a 0.05 m move. You climb over a bed to use the window, and 0.05 m is RoomPlan noise. Hand-placed objects are still judged exactly. |
| 2026-10-11 | scan-quality-fixes | **Scanned rooms are fitted together: one floor axis, jogs under 0.25 m removed, facing walls within 0.35 m stitched to their midline.** Local snaps, no solver; a room the pass would break keeps its polygon. | Owner: rooms did not fit together and edges were jagged. Asked for something basic and low-latency, today. |
| 2026-10-11 | scan-quality-fixes | **Route finding title "Blocked doorway" renamed "Blocked way out".** | The same card covers egress windows. |
| 2026-10-11 | audit-review (owner review of agent lanes) | **New overlapping openings are rejected again; homes that already contain an overlap still open.** `HomeModelStore.dispatch` refuses an action only when it introduces a warning the model did not already have, matched by kind and entity id. | The backend lane made overlaps a non-blocking warning so legacy homes open, but that also let a user draw a door on top of a door. This keeps the legacy fix without allowing new overlaps. |
| 2026-10-11 | audit-review | **Kept the bundled bearer token in Release; rejected the build lane's BackendConfig exclusion.** | Release ignores the Settings override, so excluding the bundled config would have shipped an app that cannot reach the server. |
| 2026-10-11 | audit-review | **Deferred the carbon-monoxide checklist item and tip.** | Corpus rule: no source verified, no ship. The garage presatisfaction check read a non-existent field and the iOS tips copy was out of sync. |
| 2026-10-05 | S11.57 (`s11-57-defect-fixes`), owner (Anish) | **Scope-lock wording: the app draws fire evacuation routes only (S53-3).** House sends no `peril` and `/routes` defaults to fire, so it gets fire routes only; the readiness score and Tasks cover fire, earthquake and severe weather (tornado) as guidance-based readiness content; the backend engine can compute earthquake and tornado plans (shelters) but the app does not show them. Corrected `CLAUDE.md` (opening and scope lock), `docs/playbook/01-product-spec.md` §1 and §4, `docs/demo/script-v2.md` (Beat 3 says "fire escape route"), `docs/demo/claims-ledger-v2.md`, `backend/README.md`. No backend capability or test removed; no safety guidance reworded. | The S11.53 walk found no screen that shows a non-fire plan, while `CLAUDE.md` said routes and shelters for all three perils are drawn. The owner chose to correct the claim rather than build a peril picker before the deadline. |
| 2026-10-05 | S11.57 | **`alarm.test_monthly` is a one-time tick (implements the owner's 2026-10-05 decision).** Backend: no `recurrence_days`; `true` or ANY string counts as done (`FORMERLY_RECURRING_IDS`, exempt from the timestamp 422), so an old phone's stored date never errors and never lapses. App: a cached score's 30-day recurrence is dropped on decode, a stored date loads as `true`, the row shows no "due" line and still ticks in place. Recurring items left: `practice.drill_recent`, `rescan.home`. Title, detail and citation unchanged. | Owner's product choice (row below). Any-string rather than parse-or-422 because the only strings ever sent for this id are dates from S11.35 builds, and a 422 would fail the whole score. |
| 2026-10-05 | S11.57 | **A fresh install seeds Bungalow, Apartment 4B and Two-Story House (not Jagged Stack) and opens on Two-Story House; the active home is remembered in UserDefaults (`readiness.activeHomeID`).** Fallback order everywhere (launch, delete, onboarding's household target): remembered, else Two-Story, else first. Existing installs keep any Jagged Stack they already have. `ReadinessStore` and `OnboardingState` take the memory as an optional parameter (nil in tests), like S11.50's `HomeLibrary`. | S53-1, S53-2. Jagged stays a bundled fixture: renderer and export tests use it. Onboarding wrote the household to `list().first`, which would no longer be the home on screen. |
| 2026-10-05 | S11.57 | **One deliberate default-size change: House's dock switch segments are 44 pt tall (were a fixed 40).** Everything else in S53-4 changes only at the accessibility sizes, with the old view tree kept verbatim below them where it mattered (score card, status pill). | 40 pt was under the 44 pt target floor in `CLAUDE.md`; swift-scenekit-reviewer flagged it as an undeclared default change. |
| 2026-10-05 | S11.57 | **DEBUG-only `UITEST_CANNED_SCORE` launch environment caches a /score answer for every home at launch, tagged by `home_name`; a later launch without it removes those entries.** | The new XXXL layout UI test needs a score card and a checklist with no server; it follows the `-TEST_SEED_DEMO_HOME` precedent and is compiled out of Release. |
| 2026-10-05 | audit follow-up (`audit-s11-29-score-deadline`) | **`/score?include_recommendations=true` degrades to its deterministic breakdown when the AI recommendations hit their deadline, instead of returning 504.** The 502 for an unfunded key is kept. | The breakdown is already computed when the AI call runs, and the AI items are explicitly non-scoring, so a 504 discarded finished work because its garnish was slow — on the endpoint the demo path leans on hardest. This is the project's central claim applied to its own code: the deterministic half never depends on the AI half, so `/score` must be the last thing to break. A missing key stays a 502 because that is an operator problem to surface; a timeout is transient. Confirmed live on `f3cd237` with a probe test (504) before fixing. |
| 2026-10-05 | process | **S11.29 and S11.33 were each built twice in parallel on 2026-10-03; the duplicates were discarded in favour of the merged versions.** Only one finding from the duplicate work was kept (the `/score` row above). | The playbook README is the only claim-staking mechanism and is written at session END, so two people choosing "the next unblocked session" independently pick the same one and discover it at push time. The merged implementations were better where it counted — the merged S11.33's tests need no UIKit and therefore RUN without a simulator, which is precisely what left the duplicate's 17 tests unexecuted. Recorded as a process decision, not a code one: the next parallel batch needs a claim convention (a CLAIMED column written at START, or pushing the empty branch as the lock) or it will happen again with three sessions left. |
| 2026-10-05 | S11.50 (`s11-50-code-defects`) | **A chat message over 8,000 characters is stopped on the phone before sending (Send off, a plain line, draft kept), never cut.** | The server's per-message 422 is a validation list, so the user saw a vague "couldn't use what we sent". Cutting would answer half a question (the S11.26 rule). |
| 2026-10-05 | S11.50 | **A 502 is the server's own only when its body is `{"detail": "<text>"}`; any other 502, and a 200 body that is not JSON at all, is a new kind `.responseCutOff` ("cut off on the way", Retry).** | Every deliberate 502 in `backend/app` is FastAPI's `{detail: str}`; a proxy's is not. A cut body was told to update the app. A wrong shape inside valid JSON is still "Update the app". |
| 2026-10-05 | S11.50 | **`HomeLibrary` has no default conversation store; `ContentView` passes the real one.** | The default made every test reach the real `Documents/Assistant`. A defaulted-nil parameter keeps the many test call sites unchanged. |
| 2026-10-05 | S11.50 | **A tick on an item an old cached score did not mark as recurring keeps its time in memory; when an answer says it recurs, the tick is stored as that date and re-sent once.** Not persisted. | The server counts a bare `true` on a recurring item as done forever, so such a tick never lapsed. Memory-only keeps the store shape unchanged; losing it on quit falls back to the old behaviour. |
| 2026-10-05 | S11.50 | **Phone clock far off: detect, do not correct.** When the server echoes a just-ticked date and still says not done, Tasks says the iPhone's date and time look wrong and how to fix it. Rejected: stamping ticks with the server's HTTP `Date` header. | The server stays the one clock and nothing is rewritten silently; a cached or proxy `Date` header could stamp a wrong time with no one noticing. The echo proves the server read our date. |
| 2026-10-05 | S11.55 (`s11-55-judge-access`), owner decisions (Anish) | **Four owner decisions recorded. (1) Owner's product choice: a lapsed alarm test does NOT lower the readiness score, and the item becomes a one-time tick with no date tracking (his view: people test alarms about once a year).** Note the corpus says "Test every alarm monthly" [cite: usfa-smoke-alarms] (`backend/corpus/smoke-alarms-usfa.md`); the session that makes the change must keep that cited monthly guidance in the item's title and text and change only the scoring and date tracking. This reverses the 2026-10-04 answer to S11.34 ("keeps lowering"); the code change is a later session's, not done here (BLOCKERS S11.55). **(2) The per-member contribution statement is deferred; the owner decides later. (3) The GitHub repo will be made public;** how judges get the running app is recommended in `docs/submission/judge-access.md` (video + live demo on the team iPhone + build-from-source; TestFlight only if a parent pays $99 by about Oct 12), still the owner's call. **(4) Team eligibility is done.** Also for the public repo: added an all-rights-reserved `LICENSE` (not an open-source licence), and removed the firefighter's city and years of service from `01-product-spec.md` §2 and from the 2026-09-18 row below (wording only, meaning unchanged), plus a teammate's local username from one session note. History still holds them. | Owner answers given 2026-10-05. CAC rules §3 say "No other party should have any rights or interest in the app", so an open-source licence before judging is a risk; all rights reserved is the default anyway and the team can relicense after judging. The firefighter has not agreed to be identified. |
| 2026-10-05 | S11.54 (`s11-54-tidy`) | **Collapsed the `.build-*` ignore lines into one `.build-*` rule, added `scripts/clean.sh`, and told sessions to put logs under `.build/logs/`. Did NOT move `audit/`, `demo-homes/` or `artifacts/`, and did NOT change the `.build-merge` derived-data path in CLAUDE.md, the skills or `gate.yml`.** | Root clutter was local only (nothing tracked). Moving tracked folders or the CI derived-data path risks broken references for no demo benefit; owner can decide later. |
| 2026-10-05 | S11.52 (`s11-52-engine-stress`) | **Fixed bugs outside routing/scoring: `app/schema_migrator.py` (non-string `schema_version` was a 500), and an app-wide `RequestValidationError` handler in `main.py` (NaN/Infinity in a body was a 500). `RoutingConstraints` floats now reject NaN/Infinity. Opening-wider-than-wall and diff id collisions left in BLOCKERS.** | Each was a 500 or a schema-invalid response on input a client can send; the fixes return the 422 the contract already implied and change no valid response (engine outputs hashed identical before/after). The two left open need a schema or endpoint-contract change. |
| 2026-10-05 | S11.51 (`s11-51-submission-paperwork`) | **S11.51 drafted the submission paperwork that `S11-13.md` lists as its own (`docs/submission/**`, `docs/tools-used.md`); there is no `S11-51.md` playbook file.** S11.13 reviews and pastes these drafts rather than rewriting them. Requirements come from the official 2026 CAC Rules PDF read 2026-10-05: video 1 to 3 minutes (max 3:00, not the 3:15 in older notes), YouTube or Vimeo public, the six rulebook questions, deadline 12:00 pm EDT Oct 26. `tools-used.md` was rebuilt from the lock file, package metadata and the app's `import` lines; corrected PDFKit (not used; `CGPDFDocument` is), Actions v4/v5 (now v7) and the cut Hazard Hunt row. The drafts leave out the firefighter "really cool" line until his permission is recorded. | Assigned by the orchestrator as agent B of 4 so the paperwork is ready before filming. The repo's figures were wrong or missing on the rules, and the AI disclosure had to be complete (rules §3). |
| 2026-10-04 | S11.12 (`s11-12-pitch-v2`) | **AI chat requires a funded account to film.** If Anthropic credits are missing, Beat 5 will be cut rather than faked. | The rules prohibit faking AI features for the pitch video. |
| 2026-10-04 | S11.35 (`s11-35-recurrence-app`) | **Store shape: one UserDefaults dictionary holding a Bool or a Date per item (`ChecklistMark`), not an enum with custom Codable and not two dictionaries.** | A property list stores both types natively, so a pre-S11.35 Bool-only store needs no migration step and re-saves byte-identical; the old `as? [String: Bool]` cast that dropped everything is gone. |
| 2026-10-04 | S11.35 | **`isDone` follows the server's `done` for recurring items, with a short-lived override for a tick the user just made (cleared when a `/score` answer lands or the home changes).** | One clock (the server). Without the override a tick shows nothing until the answer arrives, which can be ~50 s on a cold server. A fresh tick is always "done now", so the override can never disagree with the clock. |
| 2026-10-04 | S11.35 | **Touched `TaskDestination` (ReadinessStore.swift) and `TaskRow` (TaskComponents.swift): a smoke-alarm item with `recurrence_days` ticks in place; rows show the due label.** Owner chose both, live. | `alarm.test_monthly` went to House, which cannot tick it, so it could never get a date. Server-driven (`recurrence_days`), not an id list. |
| 2026-10-04 | S11.35 | **Declined a reviewer's request to move the label code out of `Models/` into `Readiness/`; dropped the playbook's DrillScreen/markPracticed and "Home's Last practiced" items.** | Moving needs a new file and a `project.pbxproj` edit while another iOS agent works; `Models/` stays Foundation-only. The drill screen, `markPracticed` and "Last practiced" were deleted by demo trim 2; the drill is ticked by hand through `toggleDone`. |
| 2026-10-04 | S11.46 (`s11-46-ci-gating`) | **Nightly `ios-tests` runs only when `main` gained a commit in the last 24 h** (a Linux `nightly-gate` job checks HEAD's commit time), and the nightly run skips `backend` and `ios-typecheck`. Push and PR runs are unchanged. | The repo is private (owned by `vedang-123-ai`), so a macOS minute costs about 10x a Linux one ($0.062 vs $0.006 per minute, GitHub billing docs, read 2026-10-04). A full suite run is ~10 to 20 macOS minutes (9 min 10 s in run 37232672098), about 100 to 200 of the 2,000 (Free) or 3,000 (Pro) included minutes, every night. Skipping nights when `main` has not moved costs nothing in coverage, because that commit was already tested. The push jobs already ran on the same commit, so re-running them nightly would only spend minutes. |
| 2026-10-04 | S11.46 | **`render.yaml` sets `autoDeployTrigger: checksPass`** (confirmed with WebFetch in Render's blueprint spec, render.com/docs/blueprint-spec, 2026-10-04: values `commit`, `checksPass`, `off`; it replaces the deprecated `autoDeploy`). Whether the live service follows the blueprint is unconfirmed, so the dashboard check is the owner's (BLOCKERS §1). | Render's deploy docs: a check counts as passing when its conclusion is `success`, `neutral` or `skipped`, and Render does not deploy if any check fails or there are zero checks. `ios-tests` and `nightly-gate` are skipped on push, so they do not block a deploy; `backend` and `ios-typecheck` do. A nightly or manual `ios-tests` on `main` adds a check to `main`'s HEAD, so a red one can hold back a not-yet-deployed commit (recovery: Render's Manual Deploy; BLOCKERS). A deploy now waits for `ios-typecheck` (~3.5 min on macOS). If the Actions quota runs out, CI stops and so do deploys: that coupling is recorded in BLOCKERS. |
| 2026-10-04 | S11.46 | **Actions bumped to v7: `checkout`, `setup-python` and also `upload-artifact`** (all `runs.using: node24`, read from each action's `action.yml` at that tag). `upload-artifact` was not named in the playbook. | Each v7 is the current major (GitHub releases API, 2026-10-04). `upload-artifact@v4` is `node20` too, so leaving it would keep the warning on `ios-tests`. Release notes list no input changes that affect our use (`ci.xcresult` is a directory, so it is still zipped). The install `run:` steps were not touched (S11.47 owns them). |
| 2026-10-04 | S11.45 (`s11-45-conversation-per-home`) | **Trimming keeps the newest unbroken run of turns and never opens on an assistant turn; the final user message is always sent even if it alone breaks a cap.** Characters are counted as Unicode scalars. | A gap in the middle would show the model a conversation that never happened. Dropping the question just asked would answer something else; an oversize question gets the server's 422 sentence instead (S11.37). Python's `len` counts scalars, Swift's `count` counts graphemes, so `count` would under-count emoji and still get 422. |
| 2026-10-04 | S11.45 | **Unreadable files are renamed aside (`<id>.unreadable-<uuid>.json`, `conversation.unmigrated-<uuid>.json`), never overwritten or deleted; a file that cannot be READ blocks saving for that home.** Home id `conversation` is refused as a file name. | The session's rule is "never lose it". A read failure may be temporary, so the file stays where it is and the new thread is not saved over it (both reviewers found the first draft could). `conversation.json` is the old file's name. |
| 2026-10-04 | S11.45 | **`HomeLibrary.swift`: one property (`conversations`) and three lines in `delete`.** The thread deletion runs even when the sync tombstone fails. **`AssistantScreen`: New chat is disabled while a reply is on its way.** | Owned "only to delete a home's conversation"; the property is the store it deletes from. The tombstone ordering was a reviewer finding. The New chat change is in an owned file and stops a late reply opening the next thread. |
| 2026-10-04 | S11.47 (`s11-47-repo-hygiene`) | **Regenerated `requirements.lock` using `python3.12 -m venv` rather than skipping the step when `uv` was missing.** | The playbook stated "If python3.12 or uv is not installed... skip", but since `python3.12` was available and fully capable of generating the lockfile matching `render.yaml`'s pinned version, I proceeded. This avoided leaving the lockfile out of sync. |
| 2026-10-04 | S11.44 (`s11-44-chat-citations`) | **STEP 0 = option (a): a server post-check, one corrective retry, then a fixed honest deferral.** "Safety claim" is defined once in `backend/app/ai/chat/claims.py` (a sentence that tells the reader what to do: an imperative verb opening a clause, or should/must/make sure/recommend phrasing) and the eval graders import it. Exempt: questions, the rule-4 emergency line, referrals, narration of the engine's computed route, app pointers, sign-offs. The uncited retry is a last chance: any failure after it (still uncited, fabricated id, out of time, API error, 911 line dropped) returns the deferral, never a 502 or 504. Total calls stay at 3 (S11.27's `BUDGET_COST_SINGLE_CALL`). | (b) structured output is stronger but would change the chat feel and needs a live model to tune. (a) keeps the `{reply, citations}` contract the iOS app decodes. The last-chance rule came from the grounding-auditor: without it, an emergency reply that used to ship with the 911 line could become an error after the retry. The deferral reuses only CHAT_RULES wording (rule 4 and rule 2); no new advice. |
| 2026-10-04 | S11.44 | **Edited the chat prompt (CHAT_RULES, owned file):** rule 3 now says route facts from the engine need no tag and advice does; the house-specific example now carries `[cite: nfpa-escape-planning]` ("practice ... twice a year", corpus `escape-planning-nfpa.md:28`). The eval cap in `test_evals.py` went from 12-15 to 12-17 cases for the two new AUD-030 cases. | The old example was an uncited imperative, teaching the exact shape the server now rejects (grounding-auditor). Live effect is unmeasured until S11.49. |
| 2026-10-04 | S11.37 (`s11-37-honest-failures`) | **Touched files outside OWNED FILES, all small:** `backend/app/ai/client.py` (`CHAT_DEADLINE_S` 50 to 110), `backend/tests/test_ai_deadlines.py` (phone chat 120, plus a test that reads the Swift constant), a one-line cancellation guard in `AssistantScreen`, `HomeScreen`, `HouseScreen` (x2), `BuildFromPlanView`, `ReadinessStore` (now calls `BackendFailure.isCancellation` instead of its own copy), and one case in `ConversationStoreTests` | Raising the phone's chat wait without the server deadline would have cut chat off at 50 s for nothing (S11.29 asked for exactly this pairing). The guards: without them the new silent `.cancelled` kind is stored by five screens as a failure, producing a warning haptic, a lone "Dismiss" and a "Try loading routes again" line under an invisible banner (both reviewers found it). The old `ConversationStoreTests` case pinned the discarded 422 detail that mission item 5 exists to fix. |
| 2026-10-04 | S11.37 | **Copy and kinds:** timeout says "didn't answer in time. It may be waking up" (not a flat "is waking up"); 504 is its own kind; a decode failure is non-retryable and says "Update the app"; a chat 422 shows the server's sentence only if it is a plain string of at most 300 characters | The phone cannot know the server is asleep, only that it did not answer, so the wording hedges (a reviewer's point). A 504 means the server answered, so it is not the offline or waking-up case. A pydantic 422 list does not decode to a string and falls back to the generic line, so a family never sees a validation dump. |
| 2026-10-04 | S11.37 | **Kept the other endpoint timeouts:** /build 180 s, /analyze 90 s, /routes /evacuate /score /convert 90 s | After a 51 s cold start the deterministic endpoints answer in milliseconds, so 90 s leaves about 39 s. The AI endpoints already sit 10 s above their server deadlines (S11.29). Only chat was too short. |
| 2026-10-04 | S11.31 (`s11-31-backend-hygiene`) | **Skipped the Mongo index retry and `/health/db` index readiness (AUD-042); `/convert` 422 only for `ConversionError`, so a post-parse pydantic failure is a 500; class-scoped fixtures replaced by function-scoped ones.** | S11.30 was dropped and cloud sync is off. The reviewer showed a post-parse failure is a converter bug, not client input. Classmethod fixtures depend on the pytest version. |
| 2026-10-04 | S11.34 (`s11-34-recurrence-server`) | **STEP 0: a legacy bare `true` on a recurring item (`practice.drill_recent`, `rescan.home`, `alarm.test_monthly`) means "done at an unknown time" and stays done until a timestamp replaces it (option a).** `_is_done` used to return False for it once a clock existed; the docstring and the branch now say otherwise. | Deploy order: the backend ships before the iOS app can send timestamps (S11.35). With option (b), every existing user's drill and rescan tasks would flip to not-done on deploy with no way to complete them into a fresh state. The cost is that an old `true` never goes stale until S11.35 writes a timestamp, which is today's behaviour, not a regression. |
| 2026-10-04 | S11.34 | **`alarm.test_monthly` gets `recurrence_days=30`, from the corpus line "Test every alarm monthly" (`usfa-smoke-alarms`, `smoke-alarms-usfa.md:24`). It stays `scoring: true`, so a lapsed monthly test lowers the smoke-alarm score. Weights are unchanged.** `alarm.replace_10y` gets no recurrence. | 30 days is our reading of "monthly" (the source gives no day count). The drill and rescan are non-punitive by an earlier decision; this item was documented as scoring and nothing asked to change that, but the effect is real and is a product call for the owner (BLOCKERS). `replace_10y` runs from each alarm's manufacture date, not from the last tick, so a completion-based interval would be wrong; no source, no recurrence. |
| 2026-10-04 | S11.34 | **`ChecklistItem` gained `completed_at` (UTC, nullable) next to `recurrence_days`; `ScoreRequest` rejects an unparseable timestamp with 422 at the request boundary; a timestamp with no offset is read as UTC.** Not in the playbook's text beyond "if cheap". | The app needs the time the server used to show "due again" without re-deriving it, and a malformed value must not be silently scored as not-done. `checklist.py` and `main.py` share one `parse_completion_time`. The response field is additive; Swift Codable ignores it until S11.35 reads it. |
| 2026-10-04 | S11.29 (`s11-29-ai-deadlines`) | **Server-side deadlines: /build 170 s, /analyze 80 s, /chat 50 s, /explain 60 s (also covers /score recommendations). One model call may start only with at least 20 s left; one attempt gets half the time left; SDK `max_retries=1`.** | Each is 10 s under the phone's timeout (180, 90, 60 for chat TODAY, 90 for /score). Half-the-remaining per attempt plus the 20 s start floor keeps attempt + one retry inside the budget. Numbers live in `backend/app/ai/client.py`. A sync endpoint cannot be cancelled when the phone disconnects, so a wall-clock deadline was chosen over disconnect polling (not simple, not done). |
| 2026-10-04 | S11.29 | **Chat deadline is 50 s, not the playbook's "<= 110 s".** | The playbook assumed S11.37 had raised the iOS chat timeout to 120 s or more. It has not (still 60 s, `APIClient+Chat.swift`). A deadline above 60 s would never fire before the phone gave up. S11.37 must raise `CHAT_DEADLINE_S` with the iOS timeout. |
| 2026-10-04 | S11.29 | **On deadline `/analyze` returns the existing truncated, empty result (200); `/build`, `/chat`, `/explain` return 504 with `{detail}`.** Request and response contracts are otherwise unchanged. | The agent has no findings until it submits, so "partial findings" is an honest empty result like the iteration cap. The builder must never return a half-built home, so it raises. 504 is a new status for AI endpoints (previously 502/503); the iOS error handling is not owned here and treats any non-2xx as an error. |
| 2026-10-04 | S11.29 | **Did NOT thread `response.usage` into `DailyAICallBudget` (S11.27 asked for it).** Left in BLOCKERS. | `backend/app/rate_limit.py` is outside S11.29's owned files, and `test_ai_budget.py` pins the budget constants in lockstep with the loop caps. The call count already bounds spend. |
| 2026-10-04 | S11.29 | **Builder image block marked `cache_control: ephemeral`, unverified.** Iteration caps unchanged (builder 40, agent 15, citation retries 2, submit retries 2). | The image sits in the first turn and is re-sent every iteration; marking it lets later iterations read the prefix from cache. A stub cannot prove cache reads, so the claim is owed to S11.49 live; the cache usage is logged. |
| 2026-10-04 | S11.48 (`s11-48-library-listing`) | **The library listing was not moved off the main thread. It was made cheap instead: a light decode of five fields plus a per-file cache (change time + size) so a refresh re-reads only changed files. `refresh()` stays synchronous, and so does launch.** | Measured first (50 fixture-size homes, simulator): 215 ms before, 8 ms cold and 1.2 ms per autosave after. Callers read `library.homes` on the next line (new-home flow, "Your homes"), so an async refresh would have needed a generation counter and would show stale rows; with these numbers it buys nothing. Anish un-deferred it and asked for the fix; the goal (no freeze) is met. |
| 2026-10-04 | S11.48 | **`list()` sort ties (equal `meta.modified`) now break by id.** Everything else about `list()` is unchanged. | The cache keeps entries in a dictionary, so tied homes would otherwise swap places between refreshes. The old order for ties was whatever the directory returned. |
| 2026-10-04 | S11.48 | **A file that cannot be read is retried every refresh; a file whose contents are rejected (not a HomeModel, `home_id` mismatch) is cached until its change time or size moves.** | Review finding: caching a transient read failure would hide a home until restart. `HomeLibrary`'s old promise "no cache, cannot disagree with disk" is now "cache keyed on the file's change time and size". |
| 2026-10-04 | S11.48 | **Seeding failure notice lives in `escape_planApp` (an alert, once, marked shown on dismissal), not in the ContentView banner.** | ContentView is not owned by S11.48 and its banner means "Storage unavailable" (and gates onboarding). `HomeLibrary.loadError` is only shown inside the Manage homes sheet. A failed seed does not spend the seeding flag, so a separate notice flag stops it nagging every launch. |
| 2026-10-04 | S11.42 (`s11-42-server-settings`) | **Token precedence: launch argument > saved override (only if `APIClient.bearerTokenOverridden` is set) > bundled token. A stored token with no flag is ignored (migration). `bearerToken` is a plain property; only `overrideBearerToken(_:)` persists.** | AUD-009: any "Save changes" used to persist the token forever, so a rotated bundled token (AUD-001) would never reach installs that ever tapped Save. Empty token field = clear the override. |
| 2026-10-04 | S11.42 | **Release ignores every override: stored URL, stored token and launch arguments (`honorOverrides`, default `APIClient.isDebugBuild`). A stored URL must pass `validatedBaseURL` (https + host; http only for localhost/127.0.0.1) or the deployed URL is used. `currentBaseURL` (used by `escape_planApp.swift` for Auth/Sync) follows the same rule, so all three clients agree.** | Owner answer (S11.14): no token change before submission, hide Advanced in Release. Without it a Release install with a stale saved address had no way to see or fix it. Found by ecc:security-reviewer and swift-scenekit-reviewer. |
| 2026-10-04 | S11.42 | **A stored URL needs no override flag (only the token does); Settings Advanced, its footnote and the Developer section are `#if DEBUG`; Reset to default is in the Developer section.** | Unit suites seed `APIClient.baseURL` directly and rely on it being honoured; the AUD-009 problem is the token. Reset sits in DEBUG because that is the only place an override can be made. |
| 2026-10-04 | S11.41 (`s11-41-home-id-validation`) | **Home id rule: ASCII `[A-Za-z0-9_-]{1,64}` (`escape_plan/Sync/HomeID.swift`), not "UUID or fixture id" (the BLOCKERS suggestion).** | Every id in use today must pass or a saved home stops loading: UPPER-case UUIDs from `blankHome`/`newHome`, `TEST-DEMO-HOME-1234`, the non-UUID fixture `…-empty-123`, `preserved-<uuid>-N` and many test ids are not UUIDs. The rule still excludes `/` and `.`, so no path separators and no `.`/`..` segments. This is a client-side storage constraint only: the schema's `format: uuid` and pydantic's `home_id: str` are unchanged (no schema change, no version bump). |
| 2026-10-04 | S11.41 | **`list()` lists by file name and skips (logs, keeps on disk) a file whose name is not a valid id or whose embedded `home_id` differs from it, comparing case-insensitively. No repair.** | `load` opens by file name, so listing by name means every row opens. Repairing would rewrite the embedded id, changing the home's identity for sync and possibly colliding with another file's home. Case is ignored because the simulator's volume is case-insensitive, so a pull of `ABC…` over `abc…` could keep the old name (security-review finding). |
| 2026-10-04 | S11.41 | **`HomeDocumentStore.url(for:)` stays non-throwing and internal; it percent-escapes an invalid id. Every store operation uses a private validating `checkedURL(for:)`. `InvalidHomeID` lives in `HomeID.swift`, not `PersistenceError`.** | An unowned test (`HomeLibraryEditorSeamTests`) calls `url(for:)`; escaping means even that path stays one file inside the directory. `PersistenceError.swift` is not owned by S11.41. |
| 2026-10-04 | S11.41 | **Deleted about 14 GB of stale gitignored DerivedData folders (`.build-*` with `Build/` or `ModuleCache.noindex/`, except `.build-merge`) at the start of the session.** | The disk had 1.9 GB free, under the 2 GB line where a simulator run died on 2026-10-03. They are regenerable build caches; logs and `.xcresult` bundles were kept. |
| 2026-10-03 | S11.40 (`s11-40-release-files`) | **`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are removed from the Release build only; Debug keeps both. The stores stay in Documents: no move to Application Support.** | With file sharing off, Documents is not visible in the Files app or Finder, which closes AUD-008. A move to Application Support needs a migration of every home, chat and cache file, a risk with no user benefit before the deadline. It becomes necessary only if file sharing ever has to stay on in Release (e.g. a user-facing "export scans" feature): then everything except deliberately shared files must move out of Documents first. Homes, chats and scans are still in device and iCloud backups; that is not what AUD-008 asked about. |
| 2026-10-03 | S11.40 | **Raw scans: deleted once the converted home is saved; not deleted when the user dismisses a failed conversion; at launch, scan directories more than 7 days old (by the `yyyyMMdd-HHmmss` stamp in the name) are swept. Debug keeps raw scans by default (UserDefaults `debug.keepRawScans`, absent = keep); Release always deletes.** The playbook's "after a re-check completes" half is not done: the re-check flow was cut 2026-10-02 (S11.24 dropped), so import is the only path. | A failed conversion's raw scan is the only copy of that walk-through, so Dismiss leaves it for Retry or a later look, and the sweep collects it after a week. The name stamp was picked over the file creation date because it is set once by our own code and is testable with a known-answer date. Debug keeps scans so the Finder fixture workflow (`escape_plan/Capture/README.md`) still works with an Xcode build; there is no Settings toggle because `SettingsScreen.swift` is not owned here. |
| 2026-10-03 | S11.40 | **Owned-files exception: one line in `escape_plan/escape_planApp.swift` (`ScanStore.sweepStaleScansInBackground()` in `init`).** Precedent: S11.23, S11.33. | The launch sweep needs a launch call site and neither `escape_planApp.swift` nor `RootView.swift` is owned. The work runs in a detached utility-priority task, off the main thread; all logic stays in `Capture/Export/ScanCleanup.swift`. |
| 2026-10-03 | S11.40 | **`ScanStore` is `nonisolated` (and gained `rootOverride` for tests); `writeRawJSON` is `@MainActor`.** | The sweep runs off the main actor, but the app target defaults to MainActor isolation. `writeRawJSON` calls `RawScanExport.encoded()`, which is MainActor under that default; its only caller is already on the main actor. Found by swift-scenekit-reviewer with `-default-isolation MainActor`, which `scripts/typecheck-ios.sh` does not pass (BLOCKERS, S11.33). |
| 2026-10-03 | S11.33 (`s11-33-photo-jpeg`) | **Every Import Plan image is capped at a 1568 px long edge, including the PDF page, which used to render at up to 3000 px (~150 dpi).** | 1568 px is Anthropic's recommended maximum; the API downscales anything larger, so the extra pixels only cost upload time and tokens and could never reach the model. |
| 2026-10-03 | S11.33 | **`APIClient.build` takes a `PreparedImage` (bytes + media type made together by `ImagePreparation`) instead of `imageData` + `imageMediaType`; `BuildRequest.image_media_type` is optional and omitted with no image.** | Removing the defaults alone still let a caller pair any bytes with any label. With one type, the only way to attach an image is through the encoder that knows what it wrote. The server's pydantic default only applies when there is no image. |
| 2026-10-03 | S11.33 | **Owned-files exception: `escape_plan/Auth/AccountPrivacy.swift` copy changed** ("a photo is sent as it is, including any location" → "re-saved as a smaller JPEG, without the location or date"). | The S11.16 BLOCKERS line handed this to whoever fixes AUD-024, and leaving it would make the privacy screen overstate what leaves the phone. Backed by `testLocationMetadataIsNotSent` (mutation-checked). |
| 2026-10-03 | S11.33 | **A PDF renders from its crop box, not its media box, and off the main actor; the view shows "Preparing your floor plan…" and disables Build until a picked image is ready.** Beyond the playbook's "image preparation only". | From the swift-scenekit-reviewer: the crop box is what a viewer shows, and without the wait a user who had typed a description could tap Build mid-decode and send a text-only build without knowing. |
| 2026-10-03 | Audit of S11.36 (`audit-s11-36-38-fixes`) | **The route cache is stamped and looked up with `RoutePlanCache.fingerprint(of:)`: `HomeFingerprint` of the model with `meta` blanked, not `HomeFingerprint.of(home)`.** Corrects the S11.36 row (which was appended at the very bottom of this file instead of the top). `HomeFingerprint.of` itself is unchanged; sync still uses it. | `meta` is dates and the address; the engine routes on none of them. `meta.modified` is stamped by the editor on every edit and again by `HomeDocumentStore.save` with its own clock in whole seconds, so House's model and the same home on disk never fingerprinted alike: the printed plan could not find the routes House had just cached. Any real edit (rooms, openings, stairs, profiles) still changes the fingerprint and is still a miss. |
| 2026-10-03 | Audit of S11.38 | **Settings' one-time "turn it on" gate stays removed, against S11.38's RULES line ("keep two ConsentSheet presentations"); `ConsentSheet.isEnablingOnly` is deleted.** Per-share consent is unchanged. Settings explains itself when there is no home or only a draft, and the privacy footnote S11.38 dropped is restored. | The playbook's chosen option (a) reuses `ShareWithFireDepartmentCard`, which never had that gate: Tasks already offered Share without it, so the gate protected nothing and kept a second code path, the thing AUD-027 asked to remove. Every actual share still shows the consent sheet first. |
| 2026-10-03 | S11.23 (`s11-23-score-race`) | **Owned-files exception: `escape_plan/Persistence/ScoreCache.swift` gains `remove(homeID:)` (3 lines), and `ReadinessStore.clearScoreForDraft` deletes the draft-era cache with it.** | The S11.17 hand-off in BLOCKERS asked for exactly this one-line exception and named S11.23 as the owner. Without it a score cached for an AI-guessed floor plan by a pre-fix build stays on disk until the first successful `/score`, readable by the plan export. |
| 2026-10-03 | S11.23 | **`ReadinessStore.breakdown` is computed from a home-tagged pair and returns nil for any home but the active one; `switchActiveHome` (used by `select` and `ensureActiveHome`) also clears the previous home's failure notice; `replaceActiveHome` ignores a model for another home; `startScoreFetch` sends nothing while the id and model disagree (between `ensureActiveHome` and the next `load`).** The playbook asked only for the after-await check and one cancellable task. | Same root cause (R6: a result not tagged with what it was for), cheap, in the owned file. The tag makes "A's score under B's name" impossible by construction rather than by every caller cancelling correctly. The extra guards came from the review. |
| 2026-10-03 | S11.23 | **`toggleDone` ignores an item that is not on the active home's on-screen checklist, but cannot tell apart ids every home shares (`practice.meeting_point` etc.).** Passing the row's home id needs view changes in HomeScreen/TasksScreen, outside this session's owned files; logged in BLOCKERS (S11.23 findings). | Mission 4 asked for it; the store-only part is what fits the owned files. Hard to reach in practice (a sheet covers the home switcher). |
| 2026-10-03 | S11.23 | **Playbook file kept, not deleted**, and the README row marked like S11.22's. | The rule says shipped session files are deleted, but S11.15 to S11.22 all kept theirs in this generation; matching the neighbours over a mixed state. |
| 2026-10-03 | Demo trim 2 (`trim-2-drill-playback`) | **The drill is House's fire simulation ("Reuse House"), not a rewritten drill screen.** "Run a fire drill" (Home's card, and the `practice.drill_recent` task) calls `AppRouter.openFireDrill`, which opens the House tab with the dock on "Fire simulation" (`HouseScreen(startsOnFireSimulation:)`). The old `DrillMode/` (practice drill, practice log, reminders), the AR walk (`Drill/`, `SemanticMatcher`, its EditorCore symlink, `WallGrouping`), `DrillNotice`, `DrillLogStore`, `PracticeReminderScheduler` and `Renderer/UnifiedSceneView.swift` (only the drill used it) are deleted with their tests. **Corrects the 2026-10-02 plan's Step 2**, which rewrote `DrillScreen` around a read-only `EditorSceneView`. | Anish, 2026-10-02: "the current scene kit view is perfect. I don't want to make any scene kit changes." House already has the fire ignite flow, transport, scrubber and findings; a second 3D host would duplicate it and need renderer changes (tap-to-highlight a person), so that idea was dropped too. |
| 2026-10-03 | Demo trim 2 | **House's fire dock gains "Who does what": one card per person with their start room, the rooms they pass, the exit, the time they are outside, and a warning when the engine flagged them overtaken.** The rooms come from `EvacuationJourneyNarrator` (Editor/Core, pure), which puts each of the server's `OccupantTrack.steps` points in a room with the editor's point-in-polygon test, folds repeats and skips points in no room. It never searches, smooths or re-times a path. A note says when nobody is added (the engine then puts one stand-in per room). Speeds are 0.25×, 0.5×, 0.75×, 1×, 1.25×, 1.5×, 2×. | The owner's ask. It is narration of the engine's route, the same rule as `RouteNarration`: the AI and the client never compute a route. The no-people note replaces the old drill's empty state, which was AUD-020's way to Household. |
| 2026-10-03 | Demo trim 2 | **`practice.drill_recent` is ticked by hand, like the other manual items; its detail sheet's main button ("Run a drill") opens the fire simulation and a second button, "We practiced it for real", marks it done.** Nothing ticks it automatically. | Decided for the owner. The practice log and "Mark plan as practiced" that used to tick it are gone, and watching a simulation is not the family practising, so an auto-tick would overclaim. It is `scoring=False`: no score change either way. |
| 2026-10-03 | Demo trim 2 | **`OfflineCapabilityNote` no longer promises "the practice drill and its log" offline; "the fire drill simulation" is listed as needing the server.** Demo script beat 6 drops "timed" ("a fire drill you can watch… who goes where"). | `/evacuate` is server-side; the old drill was the offline one. There is no timer any more, so "timed" would be false. |
| 2026-10-03 | S11.27 (review fix) | **The budget's unit is one Anthropic `messages.create`, not one HTTP request: `BUDGET_COST_BUILD` 40, `BUDGET_COST_ANALYZE` 17, `BUDGET_COST_SINGLE_CALL` 3.** The loop routes charge their remainder inside the handler, after validation, not in the guard. Costs are mirrored from the loops rather than imported, with a lockstep test. **Corrects the row below that described a flat per-call budget.** | `/build` loops up to `MAX_ITERATIONS = 40` model calls and `/analyze` up to 15 + 2 retries, and neither uses prompt caching, so a flat count made the stated 300/day ceiling really ~12,000 model calls — the docstring's "every call site has its own `max_tokens`" was true per call and false per request. Charged in the handler because the guard runs before body validation (measured: a malformed `/build` already charges), so putting 40 there would let eight junk requests switch the AI off for the day. Mirrored rather than imported to keep `rate_limit` free of any `app.ai` dependency; the lockstep test is what stops a raised cap silently multiplying the bill. |
| 2026-10-03 | S11.27 (review fix) | **The budget is charged AFTER the concurrency gate, not before it.** | It is the only check in the stack that consumes something, so a request turned away by a free check must not already have been billed. With the budget third, a burst bouncing off a full semaphore spent the day's allowance at zero credit cost — letting the service switch its own AI off for nothing. |
| 2026-10-03 | S11.27 | **Owned-files exception: `backend/tests/conftest.py`** — the existing autouse `_ai_cost_guard_relaxed` fixture now also calls `rate_limit.budget.reset()`. | That fixture exists precisely to keep AI-guard state out of unrelated tests, and this session adds a third piece of it. Unlike the bucket and the semaphore the budget ACCUMULATES, so without the reset the suite spends its own allowance partway through and every later test 429s — a failure that cannot be reproduced in isolation. Same category as the two resets already there, so it belongs in that fixture rather than in a new one. |
| 2026-10-03 | S11.27 (`s11-27-ai-spend`) | **The shared bearer token is PUBLIC by design, and is written down as such.** It ships in plain JSON inside every app build, so anyone with the app or its IPA has it. It identifies the *app*, not the caller: it keeps the service from being an open relay for anonymous internet traffic, and it is not, and cannot be, what bounds spend. **No effort will be made to hide it in the bundle.** | Obfuscating a secret that must be present on the device buys nothing against anyone willing to run `strings` on an IPA, and pretending otherwise is how the real control never gets built. Stating the premise is what forces the spend ceiling to be server-side. The honest version is also the one we can defend to a judge. |
| 2026-10-03 | S11.27 | **A global daily AI budget is the spend ceiling: `AI_DAILY_CALL_BUDGET` (default 1000 **model calls**, raised from 300 once the unit was corrected) per UTC day, server-wide, 429 when spent, remaining/spent reported on `/health`.** It counts **calls, not tokens**, and is charged **on entry, not on success**. In memory, so a restart resets it. | A ceiling that counts every call regardless of who makes it is the only one a holder of the public token cannot reset — the per-client bucket, however it is keyed, is per-client. Calls not tokens because debiting real `response.usage` needs every AI module to report it back and `app/ai/` is outside this session's owned files (BLOCKERS line; S11.29 goes there next); every call site already has its own `max_tokens`, so a call count does bound spend. On entry because a call that reached Anthropic and then failed has usually already cost credit, and refunding failures would let a loop of failing calls run unbounded — the exact shape of the incident that drained the account. In memory rather than Mongo because persisting spend control in a database the demo trim is switching off would make the control depend on a feature being removed. |
| 2026-10-03 | S11.27 | **The rate-limit key is no longer caller-supplied.** `client_key` prefers `CF-Connecting-IP`, else counts in from the **right** of `X-Forwarded-For` by `AI_TRUSTED_PROXY_HOPS` (default 1), else the socket peer. Both are configurable; `AI_TRUSTED_PROXY_HOPS=0` is the local no-proxy setting. | The old key was the **first** XFF hop, which the caller writes, so a script got a fresh bucket per request by varying a header — the limiter bounded nobody. Confirmed from Render's documentation 2026-10-03: "All inbound traffic to Render web services passes through Cloudflare's global network before reaching your application", proxies **append** to XFF (so the trustworthy entries are on the right), and Render's own FastAPI guidance calls trusting the client-settable value "a critical vulnerability, allowing bad actors to spoof their IP address". Made configurable so no vendor detail is load-bearing. |
| 2026-10-03 | S11.27 | **`/score?include_recommendations=true` is guarded imperatively, inside the handler, rather than by route dependencies — and the flag is kept, not removed.** | AUD-006: it was the one AI call site outside the cost guard. It cannot take `AI_GUARDS` as route dependencies, because `/score` is deterministic and the demo path leans on it — budgeting the whole route would throttle the thing that still works when the AI is down, which is the separation the project is built on. A per-request flag cannot be a route-level dependency, so the same enforcement functions run in the flagged branch; one implementation, not two, since two is how this drifted. The flag is kept rather than deleted because two backend tests exercise it and cutting a feature is the owner's call, which they are actively making elsewhere in the demo trim. |
| 2026-10-03 | S11.27 | **Recorded, deliberately NOT built: per-install tokens with App Attest are the real fix for AUD-003.** Each install would attest to Apple, the server would issue a per-install credential, and spend could then be attributed and revoked per device instead of bounded in aggregate. | It does not fit before Oct 24: it needs an Apple Developer entitlement, a server-side attestation verifier, a credential store, a rotation path, and an offline story for a device that cannot reach Apple — and it would touch the iOS networking layer during the demo trim. The daily budget is the mitigation that fits the calendar; it caps the damage rather than preventing the abuse. Written down so the gap is a known limitation rather than an oversight a judge finds. |
| 2026-10-03 | S11.27 | **`require_token` and `AI_GUARDS` moved to `backend/app/deps.py`**, imported by `main.py` and `api_chat.py`, which import nothing from each other. | AUD-043: it was duplicated because importing it from `main` into the router closed an import cycle. Two copies of an auth check is two places to get it wrong, and this session added a guard to the stack — `api_chat` would otherwise have had to be edited separately and correctly to get the budget, which is exactly the kind of omission that produced AUD-006. |
| 2026-10-03 | S11.26 (`s11-26-request-limits`) | **Body limits are 8 MiB by default and 16 MiB for `/build`, derived from the S11.25 geometry bounds rather than chosen.** The maximum bounds-valid home measures 1,649,482 bytes compact / 1,780,354 pretty; its `route_plan` 273,048 and its `profiles` 10,340, so the combined `/chat` worst case is 2,063,742 and the default carries 4.06x headroom. `/build` is larger because it must hold a 10 MB base64 image. Caps: `description` 20,000 chars, `image_b64` 10,000,000, chat 40 messages / 8,000 per message / 100,000 total. All violations are 413 or 422, never silent truncation. | The limit's job is to refuse before parsing, so it has to clear the largest body the server is obliged to accept — and `HomeModel` already defines that ceiling. The headroom is deliberate: this ships before the client-side trimming (S11.45) and transcoding (S11.33), so a limit tight against today's measurement would reject real requests in the gap. Truncating a chat history server-side would make the model answer about a conversation the user did not send — authoritative-sounding and about the wrong house, which is worse on a safety app than an error the client can show. |
| 2026-10-03 | S11.26 | **Anthropic's per-image maximum is taken as 10 MB base64-encoded, not the audit's "~5 MB", and the media-type allow-list is exactly jpeg/png/gif/webp.** Confirmed against the official vision documentation on 2026-10-03. | The audit stated "~5 MB" from memory; that is the Amazon Bedrock and Google Cloud limit. We call the Claude API directly, where it is 10 MB. Capping at 5 MB would have rejected photos the API accepts. HEIC's absence from the accepted set is the root of AUD-024. |
| 2026-10-03 | S11.26 | **`_declared_length` refuses to trust `Content-Length` whenever chunked framing is present, two Content-Length headers disagree, or the value is negative or unparseable** — such a request is counted instead. | A declared length short-circuits the counting path, so a lying declaration defeats the limit rather than under-counting it: measured, `Content-Length: 10` plus a chunked body delivered 12,582,912 bytes through the 8,388,608 cap. **This corrects my own first write-up of the fix, which said h11 rejects that header pair and that the reach needed a permissive proxy.** It does not: on the installed h11 0.16.0 (with `httptools` absent, so uvicorn uses h11) `normalize_and_validate` accepts the pair and keeps both headers, and `_body_framing` returns chunked at its "T-E beats C-L" step before reading Content-Length. It was directly exploitable. A size limit that holds only because another layer is strict is not a limit. |
| 2026-10-03 | S11.26 | **The `/build` media-type allow-list is documented as fixing only AUD-024's server half.** It refuses a *correctly labelled* unsupported type; it does not stop real HEIC bytes arriving labelled `image/png`, because `APIClient+Build.swift` hardcodes that value at both defaults and `BuildFromPlanView` omits the argument. | The first version of the docstring claimed a HEIC payload "is now refused here", which a future session reading that line alone would have taken as the symptom being fixed. It is not: the mislabel is a client bug, S11.33 owns it, and the user still sees "AI unavailable" until then. |
| 2026-10-03 | S11.26 | **ACCEPTANCE's `ecc:security-reviewer` was substituted with the `security-review` skill**, which reported no findings at confidence >= 8 on the final tip. The `grounding-auditor` half ran as specified and returned GROUNDED. | That agent does not exist in this install — already logged under "S11.25 findings" in BLOCKERS with an owner action. Recorded here so no one later reads a clean `ecc:` run into this session. |
| 2026-10-02 | Demo trim 1 (`trim-1-demo-cuts`) | **Anish cut five features from the demo app after reviewing `docs/demo/feature-inventory.md`: Hazard Hunt, the re-scan review, the AR drill walk, the practice log + reminders, and accounts + cloud sync. This branch does three of them.** Hazard Hunt and the re-scan review are deleted (views, `HazardHuntPlan`, the diff request types and client call, `HomeIntent.recheckRoom`, the "Re-check a room" button). Accounts + sync are **switched off, code kept**: no gate, no sync badge, no sign-in or delete-account in Settings, no sync triggers; `RootView` signs out a stored login once. The "what leaves this iPhone" disclosure moved to its own Privacy section in Settings. AR and the practice log go with the drill rewrite (trim 2). Supersedes the scope lock's "accounts optional and soft-gated" and "guided manual tagging". | The owner's call, to keep the demo to one story (scan → edit → routes per person → fire simulation → score/checklist → printable plan). Deleting the small features is cheap and contained; deleting accounts would take ~270 app and ~160 backend tests three weeks before the deadline, so it is switched off instead and can be deleted later. Score impact: none (every Hazard Hunt checklist item is `scoring=False`, the object inspector sets the same flags, and items can be ticked). |
| 2026-10-02 | Demo trim 1 | **The Privacy paragraph opens "Your homes are saved on this iPhone." and never mentions accounts** (it said "saved only on this iPhone; there are no accounts"). `AccountPrivacyTests` now asserts the word "account" is absent. | Anish, reviewing the wording: saying account data isn't saved "looks bad in the demo", and accounts and databases are irrelevant to the app. Every other sentence of the S11.16 paragraph is unchanged. |
| 2026-10-02 | Demo trim 1 | **House's error banners fade after 8 s and have a close button** (opt-in `autoHides`), except when the fix is in Settings (a missing or wrong token), for an offline or saved-routes notice, or while VoiceOver is running; House's dock keeps a "Try loading routes again" button. Every other banner stays up as before. **Only `practice.drill_recent` opens the drill**; `practice.meeting_point` and `rescan.home` tick off in place. | Anish: "they should disappear after some time." Opt-in because the trim-1 review found that on Home, Tasks, Score, the scan import, the Assistant and Import Plan the banner holds the only Retry; hiding it left a blank card. The offline notice is what says the routes on screen are saved, not live. The Settings case is the only on-screen explanation of why nothing works; a VoiceOver user may not have reached the banner. The drill does neither the meeting point nor a re-scan, so sending those there was wrong. |
| 2026-10-02 | Demo trim 1 | **Sessions dropped:** S11.24 (re-check a room), S11.28 (sign-in throttling), S11.30 (cloud homes CAS), S11.32 (sync CAS), S11.43 (session length). S11.31 skips its Mongo index retry; S11.40's prereq on S11.24 is lifted. | Each existed only for a cut feature. The backend `/auth`, `/homes` and `/diff_obstructions` routes are still deployed; turning them off is logged on BLOCKERS. |
| 2026-10-02 | S11.22 (`s11-22-sync-conflict-copies`) | **`SyncState` gains `preservedCopies` (original `home_id` → the "(this device)" copy's id + the fingerprint of the copied version) WITHOUT a version bump: `currentVersion` stays 3, the field is decoded with `decodeIfPresent`.** A sync copies each local version at most once; a recorded copy no longer on disk (deleted by the user) counts as discarded and is neither remade nor brought back. `SyncManager` asks `SyncHomeRepository.checkCanWritePulledHome` before copying, so a home open in House is never copied (AUD-015). | `FileSyncStateStore.load` accepts only `version == currentVersion`, so a bump would make every phone discard its sidecar: tombstones forgotten (deleted homes come back), ownership forgotten, a full re-sync. An optional field is read by a v3 file and ignored by older builds. Checking before copying removes the pile-up at its source; the record covers the one remaining path (a disk error after the check). |
| 2026-10-02 | S11.22 | **A running sync keeps tombstones written while it runs.** It snapshots the sidecar's tombstones before reading the library, adopts any written since (before each action and in `persist`), skips the action for such a home, and gives an ownerless mid-run tombstone this run's own claim (token subject only). `homeWasDeletedLocally` throws `DeletionNotRemembered` instead of `try?`. S11.21's "Your homes are syncing. Try again…" stopgap is removed. | Supersedes the S11.21 stopgap row above. Same shape as the `forgottenAccountID` guard (2026-09-24). Snapshotting before the library read, the owner fill and the by-value skip each came from a reproduced swift-scenekit-reviewer finding. |
| 2026-10-02 | S11.22 | **Owned-files exceptions:** `Persistence/HomeLibrary.swift` (`try` on the deletion observer, so a failed tombstone lands in `loadError` while `delete` returns true; doc line) and `Screens/HomeScreen.swift` (`ManageHomesSheet`: stopgap removed, and `loadError` shown after a successful delete). | Nuance 2 named both as the session's to take, with a dated row; showing the message is one token on the line the stopgap removal already changed, and leaving it would make the new error unreachable on screen. |
| 2026-10-02 | S11.21 (`s11-21-home-delete`) | **AUD-021: delete and duplicate live in a "Your homes" list (Home → home switcher → "Manage homes…", the first item in the menu), chosen by Anish in the simulator over a context menu on the switcher's rows; the confirmation uses the short wording Anish chose: title `Delete “<name>”?`, body "It's removed from this iPhone. You can't undo this.", "…from this iPhone and from your account…", or "…from this iPhone now, and from the account it's backed up to the next time that account signs in here…".** Which body is shown is `Sync/HomeDeletionReach.swift`, read from the home's owner in `SyncState.homeOwners` against the signed-in token's subject: the same rule `SyncManager` uses to send `DELETE /homes/{id}` (2026-09-24), so the promise and the sync cannot disagree. "Manage homes…" is first because the end of the menu is off screen with ~16 homes (a UI test could not reach it). | The playbook asked for two placements to be shown and the wording to be Anish's call; nuance 6 required the wording to be truthful about the cloud, and "signed in or not" is not the rule (a home owned by a signed-out account is deleted from that account later). |
| 2026-10-02 | S11.21 | **Duplicate copies the home and its household (profiles live in the home file), and NOT its checklist ticks, drill log or meeting point:** those are keyed by home id in their own stores, so the copy starts with none. The copy is named "<name> copy", gets a new id, is unclaimed by any account, and is never labelled Demo. **The "Demo" tag** marks the four fixed-id starter homes (`HomeFixture.allCases`: bungalow, apartment, twostory, jagged), read from the fixtures, not the name. | A copy is usually "the same house, a variation": the household is the same people, but ticks and drills describe what was done in the original, and copying a meeting point would silently claim the copy has one. Fixed ids are what make a home a starter (seeded once, `fixtures.starterHomesSeeded.v1`); a user's rename must not hide it. |
| 2026-10-02 | S11.21 | **A brand-new home is not written when House opens it; its first committed edit creates the file.** `HouseScreen.loadIfNeeded` no longer autosaves when `loaded == nil` (`HouseEditorSessionController` already treats "no file, no fingerprint" as current). With an empty library, `HouseTab` (`ContentView.swift`) keeps the editor's identity when that first save makes the home appear, and makes it the active home. | Writing on open is how blank "New Home"s piled up (AUD-021) and each one uploaded on the next sync. The `HouseTab` change stops the first save from rebuilding the editor and losing that edit's undo (swift-scenekit-reviewer; a temporary UI test failed without it and passed with it). |
| 2026-10-02 | S11.21 | **While a sync is running, "Your homes" refuses Delete** ("Your homes are syncing. Try again when the sync finishes."). Stopgap: `SyncManager.sync()` writes its start-of-sync snapshot of the sidecar back after every action, so a tombstone written mid-sync is lost and the deleted home comes back (ecc:security-reviewer). The real fix (merge tombstones written since the snapshot) belongs to S11.22, which owns `SyncManager`/`SyncState`; BLOCKERS @S11.22. | A delete is otherwise a promise the app breaks ("removed from your account", then the home reappears). Blocking for the length of a sync is cheap and lives in S11.21's own file. |
| 2026-10-02 | S11.21 | **Owned-files exceptions, each logged:** comment-only fixes in `Persistence/HomeDocumentSyncRepository.swift` and `Sync/SyncState.swift` (AUD-039; nuance 1), plus `deletionReach(of:signedInUserID:)` added to `HomeDocumentSyncRepository` (read-only); a new `Sync/HomeDeletionReach.swift` (pure Foundation, compiled into tools/editorcore); `ContentView.swift` beyond comments (`HouseTab` identity, above); `escape_planUITests/ProfilesEntryUITests.swift` (`buildBlankHome` makes one edit, nuance 2); `Screens/Theme.swift` + `escape_planTests/ThemeContrastTests.swift` (new `Theme.destructiveFill` #C93A3A for the Delete swipe action's white label, 5.06:1, asserted). | Each was needed for the session's own acceptance or a reviewer finding it caused; none changes behaviour outside delete/duplicate/blank home. Theme.swift is the only place a colour may be defined, and `Theme.warning` carries white at only ~3.5:1. |
| 2026-10-02 | S11.20 (`s11-20-profiles-reachable`) | **AUD-020: the persistent entry is a "Household" row on Home, under the drill and 3D-house cards, chosen by Anish in the simulator over the same row at the top of Tasks' "Family plan" (both were built and shown; Tasks' was removed). The screen's title changed from "Profiles" to "Household" to match. The drill's empty state opens it as a sheet and reloads the drill on dismiss. On leaving after a change, ProfilesScreen calls `ReadinessStore.replaceActiveHome(saved, api:)` rather than the playbook nuance's `load(api:)`; ReadinessStore itself is unchanged.** | Home is seen on every launch, beside the drill that needs people; Tasks' row sat below every task. `load` does not cancel a /score already in flight, so on a slow cold start the old household's score could land last (swift-scenekit-reviewer; the AUD-014 race); `replaceActiveHome` goes through the cancellable `rescore`. The sheet keeps the drill screen in place (its `load()` runs once per push). House needs no wiring: S11.19 reloads it on appear, verified in the simulator. |
| 2026-10-01 | S11.19 (`s11-19-house-reload`) | **AUD-013: the minimal design, not the structural one. House's session keeps the `HomeFingerprint` of its file as last read or written (`Editor/Core/HouseEditorSessionController.swift`, Foundation-only); every appear re-arms `library.editor` and sync's `openHomeID`, then reloads a changed file; every autosave checks first and reloads instead of overwriting; a deleted file closes the session and is never re-created. Trade-off accepted: a reload clears the undo history, and an edit made while the file changed underneath is dropped in favour of the newer file; the one-line notice says both. Owned-files exception: deleted `HomeLibrary`'s unused `convenience init() throws` (one line, outside "editor registration API").** | Every writer found (onboarding, re-scan add, sync pulls, Profiles, BuildFromPlan, seeding) writes the file, so a fingerprint check on appear and before each save catches all of them; none needs House's live store. One `HomeModelStore` per home owned by `HomeLibrary` would touch every writer's session and is not needed yet. Undo snapshots describe the old document, and undoing into one would write it back over the newer file. The fingerprint is taken over what landed on disk, because `HomeDocumentStore.save` stamps `meta.modified`. The init was the last route back to a second store (S11.18 BLOCKERS) and had no callers. Tab lifecycle confirmed in the simulator: `onDisappear` fires on every tab switch. |
| 2026-10-01 | S11.18 (`s11-18-one-store`) | **AUD-019: every screen uses the launch store. Owned-files exception: `Onboarding/OnboardingFlowView.swift` (no session owns it) gained `init(documentStore:onFinished:)`, and `OnboardingState.init(documentStore:)` lost its default, so nothing can build onboarding without the library's store. Settings, BuildFromPlan and Drill read the `HomeLibrary` environment object; onboarding gets the store passed explicitly; HouseScreen's unused `init()` was deleted rather than injected. Review fix: `onboarding.completed` is not set while on the temporary fallback store.** | ContentView attaches the onboarding `.fullScreenCover` outside its `.environmentObject(library)`, so the cover cannot read the library from the environment, and `OnboardingState` is built inside OnboardingFlowView's `@State`: the store can only arrive through that view's init. Every other presenter sits inside the TabView subtree (audited by swift-scenekit-reviewer). With one store, onboarding on the fallback now succeeds against the temp directory; spending the flag there would lose the interview for good, the same reason launch skips starter seeding on fallback. |
| 2026-10-01 | S11.17 (`s11-17-draft-review`) | **AUD-023: an unreviewed AI draft is never scored, and the review state is a full card ("Review your draft" / "Review in House"), chosen by Anish in the simulator over a one-line row. HomeScreen was changed beyond "build completion only": Home swaps score / Up next / quick actions for the card and its subtitle says "AI draft, not reviewed yet". The shared `DraftReviewNotice` lives in `TasksScreen.swift`. `ReadinessStore.rescore` now returns its `Task` (`@discardableResult`) so tests await it.** | The mission requires Home to show the review state, which cannot be done from the build completion alone; hiding the drill card is also how the drill is kept off a draft without touching DrillMode/. A new file was not in OWNED FILES, so the shared view went into an owned one. Returning the task replaced a fixed sleep in the test, which the swift-scenekit-reviewer flagged as able to pass falsely. |
| 2026-10-01 | S11.16 (`s11-16-privacy-truth`) | **SUPERSEDES the S11.7 privacy wording (2026-09-24 rows; not edited). The disclosure separates "sent to our server to work things out, not stored" from "saved to your account, only if you sign in", and names Anthropic.** New summary: "Signed out, your homes are saved only on this iPhone, and you never need an account. To work out routes, your score and the fire drill, the app sends the whole home — household names and tags included — to our server, which uses it and does not store it. The assistant sends your messages and your home's room names on to Anthropic's AI service, and Import Plan sends it the picture and description you give it." Five lists: `sentToCompute` (keyed to request fields), `sentToAnthropic`, `uploaded`, `notSynced` (AUD-018), `notUploaded`. The password moved from "never uploads" to the account list as "a one-way hash". The button reads "What leaves this iPhone?" | AUD-050: S11.7 wrote about what an account STORES but phrased the headline about UPLOADING, and every `/score` `/routes` `/evacuate` `/chat` request sends the whole home signed out; Import Plan sends a photo. "Does not store", not "does not keep" or "deleted after N minutes": the code shows no DB write and no body logging for those endpoints, and nothing about the host's platform logs or Anthropic's retention, so the copy claims neither (security-reviewer). The analytics line admits the server records request time and IP (security-reviewer). The pitch-truth-auditor removed the S11.7 address claim (no screen sets `meta.address_optional`; the copy now says the app never asks for an address), added the `pet` tag, and the location line now says a picked Import Plan photo is sent with any location saved in it (original bytes, `BuildFromPlanView`); changing that is a code change, logged in BLOCKERS. Tests pin request fields against real encodes rather than pinning a phrase. Inventory: note `2026-10-01-s11-16-privacy-truth.md` |
| 2026-09-30 | S11.15 (`s11-15-drill-verbatim`) | **AUD-025: drill notices are built by a pure `DrillNotice` in `Editor/Core/` (EditorCore), the engine's citation is shown as the drill's source chips rather than an inline `[cite: …]`, and the "no primary route" notice now shows the engine finding that explains it (`no_viable_route`, then `blocked_opening`) instead of `findings.first`.** The engine's own tornado wording and the drill cards' inline cite tags (`DrillCitedText`) were NOT changed. | The client-written tornado sentence contradicted the engine and corpus for site-built homes; extracting the builder makes the rule testable (`DrillNoticeTests`). Chips match how the drill already shows sources. `findings.first` could put earthquake cover advice where the reason for no route belongs (grounding-auditor). Engine/corpus wording is the backend owner's by rule; `DrillCitedText` is outside S11.15's owned files. Both logged in BLOCKERS. |
| 2026-09-30 | S11.8 (`s11-8-ios-verify`) | **`KeychainTokenStoreTests` `XCTSkip` when, and only when, the Keychain returns `errSecMissingEntitlement` (-34018); the gate run stays unsigned (`CODE_SIGNING_ALLOWED=NO`).** Any other Keychain status still fails. | The addendum offered "sign the gate run or skip with a reason". One ad-hoc-signed run (`CODE_SIGN_IDENTITY=-`) passed 3/3, proving the store works; signing every gate run would change the command every doc, CI job and teammate uses for a 3-test class. Narrowing the skip to that one status keeps a real Keychain bug red. CI should still run the class ad-hoc-signed (BLOCKERS, S11.8 findings → S11.46). |
| 2026-09-30 | S11.8 | **The Settings privacy-disclosure test was fixed by matching the identifier on any element type, not by scrolling** (the addendum's medium-confidence guess). The UI-test interruption monitor declines permission alerts rather than granting them. `CriticalSectionTests` got its own `URLProtocol` stub. | The failing line was the one after the button's `waitForExistence`, which had passed, so the button was found; the `.combine`d list is not exposed as `.other`. Verified by the test passing on three runs with no scroll added. Declining keeps every UI test on the first-run app a new user sees. The stub was a cross-suite race on a shared static (`OfflineIntegrityTests` installs a `-1009` responder), the only new red since S11.14. All test-side; no product source changed. |
| 2026-09-30 | S11.25 follow-up (`s11-25-followup-object-bounds`) | **CORRECTS the S11.25 row below: grid cells are NOT the only cost driver, and the cell bound alone did not close AUD-004.** Objects in ONE room are the worse driver, so `MAX_OBJECTS_PER_FLOOR` drops 500 -> **120**, plus new `MAX_OBJECTS_PER_ROOM = 25` (counted by the same bounding-box overlap test `objects_intersecting` uses) and `MAX_OBJECTS_TOTAL = 200`. The stated budget changes from "under 7 s" to a measured **21.82 s** for the COMBINED worst case (245,000 cells, 200 rooms, 200 objects, every route blocked). Owner chose 25/room over 40/room when asked. | The S11.25 measurement scaled `twostory.json`, which holds objects fixed at 5, so it measured the cell term and missed the object term entirely. When a route is blocked, culprit attribution re-rasterizes the room per object, so cost grows **~O(n^1.7)** in the objects one room holds, almost regardless of its cell count. Measured 2026-09-30 in a 1,225-cell room with objects piled against the only exit, ONE peril: 10 obj 0.27 s, 25 obj 0.90 s, 50 obj 2.79 s, 100 obj 9.03 s, 200 obj 42.67 s, 400 obj 134.17 s — x3.2 for every x2 objects. The old 500-per-floor cap therefore permitted a **~10-minute `/score`** inside every other bound, which is precisely the AUD-004 denial-of-service the cell bound was supposed to have closed; the public bearer token (AUD-003) is the threat model, so it had to hold against an adversarial body, not just a realistic one. 25 per room keeps ~22x headroom over the largest committed fixture (9 objects per floor) and comfortably above RoomPlan's ~5-15 detections per room, so no realistic home is affected. The real fix is to make attribution linear — engine work, out of scope here and logged in BLOCKERS; these bounds are the mitigation, not the cure. |
| 2026-09-30 | S11.25 (STEP 0) | **AUD-004 geometry bounds live in pydantic validators + Swift `EditorValidation` only — option (a). The JSON Schema is NOT changed and `schema_version` stays 2.1.** | `.claude/rules/paths/schema.md` already puts the structural invariants (CCW, non-self-intersection, reference resolution, id uniqueness) in pydantic rather than the JSON Schema, and size is the same kind of rule: it is about what the routing engine can afford to rasterize, not about the shape of the document. Option (b) would have cost a 2.2 bump plus the full lockstep migration (Swift models, `SchemaMigrator`, every fixture copy) to express caps that `maxItems`/`maximum` cannot express anyway — neither of the two bounds that actually matter (bounding-box cells per room and per home) is expressible in JSON Schema at all — they require rasterizing a bounding box at `CELL_M`. **Honest caveat (schema-contract-guardian, 2026-09-30):** the *scalar* caps added here *are* expressible — `le=` is `maximum`, `max_length=` is `maxItems`, and the schema already uses both idioms — so the JSON Schema is now strictly more permissive than pydantic in ways it could have described. That is a deliberate continuation of the existing precedent, not an oversight, and no test asserts schema-valid implies pydantic-valid (the one equivalence test, `test_models.py`'s `household` nullability case, runs the other direction). The owner was not asked to choose (b), so the recommended default stands. |
| 2026-09-30 | S11.25 (STEP 0) | **The bound that matters is grid CELLS, not room area: `MAX_TOTAL_GRID_CELLS = 250_000` (whole home) and `MAX_ROOM_GRID_CELLS = 90_000` (one room), alongside `MAX_COORD_M = 200`, `MAX_ROOM_SPAN_M = 60`, `MAX_ROOM_AREA_M2 = 500`, `MAX_POLYGON_VERTICES = 64`, `MAX_FLOORS = 8`, `MAX_ROOMS = 200`, `MAX_OPENINGS_PER_FLOOR = 400`, `MAX_OBJECTS_PER_FLOOR = 500`, `MAX_SAFETY_POINTS_PER_FLOOR = 100`, `MAX_STAIRS = 50`, `MAX_PROFILES = 50`, `MAX_FLOOR_HEIGHT_M = 20`.** Stated budget: a home at the maximum completes a 3-peril `/score` in **under 7 s on this Mac** (measured 6.11 s at 252,491 cells). | **The audit's proposed `room area <= 2,000 m2` would not have fixed AUD-004.** `build_room_grid` rasterizes a room's *bounding box*, not its area, so a measured 75 m2 diagonal sliver inside +/-200 m coordinates produces 2,250,000 cells — 300x more than its area justifies, ~58 s to rasterize once — and today's pydantic accepts it (reproduced 2026-09-30, `scratchpad/sliver.py`). Cost is linear in bounding-box cells at ~26 us/cell for a 3-peril `/score`: twostory measured 16,000 cells / 0.39 s, 64,000 / 1.54 s, 256,000 / 6.22 s, 576,000 / 14.21 s, 1,600,000 / 42.09 s. 250,000 cells was chosen over the example 5 s budget (~185,000 cells) so that a 5,000 ft2 (460 m2) house still fits with ~4.5x headroom; worst case is ~15-20 s on Render's free instance, well inside the iOS 90 s timeout, versus hours today. Headroom over the largest committed fixture (twostory/jagged): 15x cells, 10x coordinate span, 6x room area, 16x polygon vertices, 25x rooms. Grid optimisation itself is explicitly out of scope for S11.25. |
| 2026-09-29 | S11.14 (owner decision, delegated) | **AUD-022: Path B. The pitch says the AI "explains and chats"; the AI inspector (`/analyze`, `/explain`) is NOT wired into the app before Oct 24.** S11.39 runs Path B (claims re-worded, dead Analyze client handled per AUD-044); S11.12 takes the claims diff into script v2. Re-open only with a new dated row if the Anthropic credits are topped up AND S11.27 + S11.29 are merged before 2026-10-10. | The owner asked Claude to decide ("decide for me"). Credits are not topped up (AUD-002, 2026-09-29), so a wired inspector could not be filmed or verified live; Path A needs S11.27 and S11.29 first (spend controls) and ~4 h vs ~1 h. The anti-"AI wrapper" answer is the deterministic engine, not the inspector, so the pitch loses nothing true. Judges test claims; an unreachable feature in the script is the worse risk. |
| 2026-09-29 | S11.14 (owner decision, delegated) | **AUD-001 follow-up for S11.42: no further change of the shared backend token before submission (unless it leaks), and Settings' "Advanced" section (server URL, token) is hidden in Release builds.** | The owner asked Claude to decide. Every token change so far has left the app and Render out of step (AUD-001), and a persisted token overrides the bundled one on installs (AUD-009), so another change before Oct 24 adds risk for no benefit. A judge or user has no reason to see or edit the server settings; DEBUG builds keep them for the team. |
| 2026-09-29 | S11.14 | **AUD-038: the owner confirms the AI tools used on the project are Claude (Claude Code) and Google Antigravity / Gemini, nothing else.** The four stale worktrees (three Antigravity, `../wt-s6-1`) were removed with the owner's approval; all were clean and their commits already on `origin/main`. | Recorded for S11.12, which owns `docs/tools-used.md` (the Challenge requires every AI tool to be listed). |
| 2026-09-26 | drill fix (`drill-3d-fallback`) | **The 3D walkthrough is the drill again; the S9 AR walk is an opt-in "Walk it in AR" button on the drill card, shown only where `RoomCaptureSession.isSupported`.** S9.2 (`bffb16c`, 2026-09-14) had replaced `start()`'s `DrillSession` construction with the AR full-screen cover, so the step-through, timer record, practice log and time comparison were unreachable, and the Simulator and every non-LiDAR phone got an AR scanner that can never start | The AR path is device-only and unverified (`escape_plan/CLAUDE.md` already called the flat-screen drill "the fallback"); a demo cannot depend on it. `finish(outcome:)` needs a `DrillSession`, so with AR as the only path no drill was ever logged. The AR cover now sits on top of the running 3D session and no longer clears `routePlan` on dismiss. Also rejected from the 2026-09-26 Antigravity "swarm" (uncommitted edits on `main`, reverted, patch kept in the gitignored `artifacts/antigravity-leftovers/`): `/analyze` before every `/score` (an AI agent run per checklist tap), a `.deleteRemote` sync rewrite (server delete already existed, 4 tests red), a unique `(home.home_id, user_id)` index (the sync design allows several server copies of one home; creating it over existing duplicates fails at startup), removing `.preferredColorScheme(.dark)`, a `MetadataPreview` home list, a duplicate CI workflow and an unused `APIClient+Explain.swift`. Kept: `minHeight: 48` on two buttons |
| 2026-09-25 | audit remediation (Part B) | **iOS findings from the 2026-09-25 audit fixed on `audit-ios-fixes`, merged into `ui-revamp-1-foundation` (NOT `main`):** Assistant grounds on `ReadinessStore.activeHome` and follows it; ScoreScreen reads `ReadinessStore` instead of POSTing `/score` itself; one `ScoreBand` (85/60) for Home and Score; `AppRouter.clearHouseRequest()` + `HouseRequest.honoured` so the House tab follows the active home; onboarding interview always runs and writes to the active home; `refreshLastPracticed()` after a drill; local load failures get `BackendFailure.localLoad`; Tasks' no-home state; the deduction row shows "−X points"; 90 s timeouts and one injected `session` in every `APIClient+*.swift`; a fire-and-forget `/health` at launch; one launch `HomeDocumentStore` with a temporary fallback and a banner, no `try!`; `BetaScreen` deleted; VoiceOver announcements and Dynamic Type fixes; `ThemeContrastTests` rewritten; 429 maps to the busy copy | **`ScoreBand` lives in `Readiness/`, not in `ReadinessStore.swift` as the task text suggested,** because `Readiness/` is symlinked into EditorCore: the band test then runs on every CI push, where a test in `Screens/` runs only in the manual simulator job. `ReadinessStore.band(for:)` is the entry point the screens call. **Bands are 85/60**, Home's newer values: `docs/preparedness-score-weights.md` defined no numbers (only that the cap of 40 is "Needs work", which both satisfied), 85 is where the gauge's success flourish already fires, and the three fixture scores (73/70/66) land mid-band under either. The words are Score's ("Well prepared" / "Some gaps to close" / "Needs work"), because the weights doc already names the low band "Needs work". `ChatError` is kept (it carries the 422 detail) but its text now comes from `BackendFailure`, so there is one copy of every failure message |
| 2026-09-25 | Linear revamp (`ui-revamp-1-foundation`) | **The dark-only Linear redesign retires the "never introduce a new colour" rule.** Three guardrails replace it: (1) safety colours stay distinct and colour-blind-safe — cool is routes, warm is hazard, green is exits; (2) accessibility floors — 4.5:1 text, 3:1 components, 44pt targets, Dynamic Type, VoiceOver; (3) `CameraRigModel` purity with `allowsCameraControl` off. The tab bar becomes **Home, Tasks, House, Assistant, Settings**: the checklist gets its own Tasks tab, home switching moves into Home's top bar, and the **Beta tab is removed** (`BetaScreen.swift` deleted in the audit remediation) | The old rule protected a light/dark system palette that no longer exists, and it could not express the actual safety requirement, which is about hue families and contrast, not about the count of colours. Guardrail (1) and (2) are asserted in `ThemeContrastTests` (hue families and per-surface ratios on all four dark surfaces); (3) is unchanged from the old trap list. The audit's "forced dark mode is an accessibility violation" finding is rejected on the strength of those tests. Root `CLAUDE.md` carries the new wording on the revamp branch and reaches `main` when the revamp merges |
| 2026-09-25 | audit remediation (Part A) | **Backend and CI findings from the 2026-09-25 audit fixed on `audit-backend-fixes`, merged to `main`:** `/diff_obstructions` bearer-guarded plus a route-walking guard test; an in-memory AI cost guard (`app/rate_limit.py`: per-IP token bucket + global semaphore, 429 + `Retry-After`) on `/explain` `/analyze` `/build` `/chat`; `.github/workflows/gate.yml`; `backend/requirements.lock` installed by Render; `DuplicateKeyError` by `isinstance` | No new dependency: a single free Render instance is exactly what an in-process bucket fits, and a Redis limiter would add a service to keep alive for a demo. Limits are env-configurable and deliberately NOT pinned in `render.yaml`, whose values would overwrite dashboard tuning on a blueprint sync. CI installs the LOCK (what Render deploys), not `requirements.txt`, and fails when the lock stops satisfying `requirements.txt` — a deviation from the task text, chosen because testing the unpinned file would test something that is never deployed. The test suite relaxes the limits in `conftest.py` so a test that calls a mocked AI route four times does not start failing with 429 |
| 2026-09-25 | audit (rejected) | **Not done: make `/auth/login` accept JSON.** | iOS form-encodes on purpose (`Auth/AuthClient.swift:85`, `Auth/FormURLEncoding.swift`) because `OAuth2PasswordRequestForm` is the standard; both sides are tested. The audit read one side only |
| 2026-09-25 | audit (rejected) | **Not done: parallelise `/score`'s three route plans with `asyncio.gather`.** | The handler is sync and CPU-bound, so under the GIL it would not help. Measured 5–386 ms for all three perils; the real latency is Render's cold start, addressed on iOS by an early `/health` ping and 90 s timeouts |
| 2026-09-25 | audit (rejected) | **Not done: undo forced dark mode as an "accessibility violation".** | A deliberate redesign decision (see the Linear dark-only row). The accessibility floors are tested instead: `ThemeContrastTests` asserts 4.5:1 text and 3:1 components on every surface |
| 2026-09-25 | audit (rejected) | **Not done: rename `severe_weather` to `tornado` (or vice versa) as a "naming bug".** | Deliberate mapping at `backend/app/scoring/checklist.py:390-395`; `PERIL_BASIS` and `basis` share keys. Routing's peril is `tornado`, the checklist's hazard tag is `severe_weather`, and the mapping between them is the tested seam |
| 2026-09-25 | audit (rejected) | **Not done: return a full component list from `/score`.** | `ScoreBreakdown.components` carrying 0 or 1 entry is S6.7's "largest deduction" by design. Only its iOS rendering was wrong (an always-empty "0 / X" bar), and that is fixed |
| 2026-09-25 | audit (rejected) | **Not done: a compound `(_id, user_id)` Mongo index.** | Every lookup hits the unique `_id` index first; `user_id` is a filter on a single document |
| 2026-09-25 | audit (rejected) | **Not done: replace `.iso8601` date decoding "because it fails on fractional seconds".** | It does not on this deployment target; pinned by `SchemaV2ContractTests.testWholeAndFractionalSecondsBothDecode` |
| 2026-09-25 | audit (rejected) | **Not done: password re-entry on `DELETE /auth/me`.** | A destructive-alert confirmation exists; Apple does not require re-authentication for in-app account deletion; the choice is recorded in BLOCKERS (S11.7) |
| 2026-09-25 | audit (rejected) | **Not done: split 401 and 403 in `BackendFailure`.** | The backend never emits 403 (an unowned home is a 404 by design, so ids cannot be probed) |
| 2026-09-25 | audit (rejected) | **Not done, each checked and false:** `/score` refetched on every tab switch; Tasks shows content while loading; jargon in the UI; HazardHunt dead end; score ring NaN; `fake_mongo` upsert semantics; `claude-sonnet-5` being an invalid model id; `s11-0-baseline` unmerged (its merge `5264dcd` is an ancestor of `origin/main`) | Re-verified against the code on 2026-09-25 before any work started. Recorded so a future audit pass does not re-open them without new evidence |
| 2026-09-24 | ui-loading-tips | **Loading screens show rotating prevention tips: a shuffle bag over the `.everyone` tips that shows each once per cycle and front-loads fire (while both kinds remain, the next draw is fire with p = 0.75), so short waits mostly see fire tips.** Shown only on Score, Drill, Export and scan-conversion waits; House is wired by the UI revamp. Tips filter to `.everyone` audience only; tips appear after ~0.8 s (avoiding flash on fast loads); rotation interval is ~7 s | Fire is the app's headline peril, so the majority of tips should reinforce it; earthquake and tornado remain visible but secondary. The 0.8 s delay ensures users see tips during genuinely slow operations (cold-start backend can take 30+ s on Render), not on fast network hits. One-tip-only under VoiceOver (no juggling), swaps without animation under Reduce Motion. Tips are bundled and cited (`prevention_tips.json`, byte-identical with the corpus copy). `LoadingTipRotator` is symlinked into EditorCore so rotation logic is testable on a machine with no simulator. |
| 2026-09-24 | S11.4 follow-up | **An unsupported `ANTHROPIC_MODEL` stops the backend at startup, including the routing engine, rather than turning only the AI endpoints into 502s.** `app/ai/model_support.py` holds the supported set; `config.get_settings` raises on anything else, same as a too-short JWT secret. Chosen over switching `/explain` to `tool_choice=auto` because that would not have been enough: `thinking={"type":"disabled"}` in grounded/chat/agent 400s on the same Fable/Mythos/Opus 5.5 models, and changing THINKING is out of scope until credits allow measuring it | The grounding-auditor pointed out that this cuts against `database.py`'s "never take down the routing engine" and the missing-key -> 502 behaviour. Kept anyway: a misconfigured model is an operator error, not an absent feature (the JWT split), and on Render a deploy that fails to boot leaves the previous one serving, so the bad value never goes live. The alternative, a per-endpoint 502, would only surface on the first real AI call, which on this account may be weeks away |
| 2026-09-24 | S11.4 follow-up | **`check_object_hazards` classifies `threshold_m` by rule (a standard only on `heat_clearance`), not "a standard only when the finding carries a citation"** | That was the wording asked for, but every object-hazard finding carries a citation (`citation: str`, never None): R1, R2 and R5 all cite `shakeout-guidance` while `threshold_m` holds an object height or an engineering constant. A citation-based rule would have told the agent the 1.5 m height was a cited standard, the exact failure being closed |
| 2026-09-24 | S11.4 follow-up | **The `/build` eval cases grade the `BuildResult`, not text, and live in their own `BUILD_CASES` list with scripted tool-call probes** instead of `EvalCase` string probes | `/build` returns home/trace/truncated/issues and drops the builder's prose, so a text grader would score something no user sees. Same discipline otherwise: question, why, a probe that must pass, one that must fail (and must still build a valid home, so it fails on the grader rather than the validator), and the live runner reuses the graders unchanged |
| 2026-09-24 | S11.6 follow-up | **EditorCore bundles `escape_plan/Fixtures` as a package resource, via a symlink and `.process`, so `FixtureLoader` works in `swift test` (`Bundle.module` under `SWIFT_PACKAGE`). This departs from the 2026-07-16 S2.4 rule that Swift tests read `schema/fixtures` off the source tree instead of a bundle copy** | `FixtureLoader` is product code the app ships, and it can only read its own bundle. Tests that call it (the S11.6 snapshot tests) could never run in the package, which is the only test runner guaranteed on every machine. The bundle is the app's own copies, not `schema/fixtures`, so both runners load identical bytes and `schema/fixtures/invalid/` and `scans/` stay out of the bundle. The S2.4 concern was a copy drifting silently. That is now covered twice: the backend's `test_the_apps_bundled_fixtures_match_the_contracts`, and the new `FixtureLoaderTests.testLoaderBytesMatchCanonicalSchemaFixtures`, which compares the loader's bytes against `schema/fixtures` in both runners. The source-tree `Fixtures` helper in `EditorCoreTestSupport` is unchanged and stays the default for tests that don't need the loader |
| 2026-09-24 | S11.1 (follow-up) | **The aftershock drill card was NOT re-pointed to `shakeout-guidance-after`, so `usgs-earthquake` was NOT deleted.** The planned fix was a cite-tag swap; it was stopped because the card says "evacuate only if the building is damaged **or if you are instructed to do so**", and neither ShakeOut Step 6 nor Ready.gov (both re-read live 2026-09-24) nor the corpus carries that condition | A tag swap would have hung a resolving citation on a clause its source does not say — the "fabricated citation that validates" failure the S11.1 HIGH item was opened to remove, which no validator can see. The fix belongs with the copy: change the clause to the source's own condition (damage or an unsafe surrounding area, keeping its "outside a tsunami zone" scope) and set the tag to `shakeout-guidance-after` in one commit, then delete `usgs-earthquake` and its `ORPHAN_SOURCE_EXCEPTIONS` entry together. Owner S11.10 (owns `escape_plan/DrillMode/**`); logged in BLOCKERS §S11.1. The exception's stale owner text was corrected meanwhile |
| 2026-09-24 | S11.7 (review) | **A remote delete is authorised by the TOMBSTONE's owner, never by `SyncAction.Reason.deletedOnThisDevice`.** The `.skip` branch reads `state.deletions[id]?.ownerUserID` and requires it non-nil and equal to `token.subject`; an ownerless tombstone stays the pure skip it was before S11.7. All duplicate server records of the home are deleted, not the first match | Found by `swift-scenekit-reviewer` and reproduced before fixing. `.deletedOnThisDevice` comes from `SyncState.isDeletedLocally`, which **deliberately** also matches a tombstone with no owner — one made before anybody signed in — for whichever account is looking. That is correct for the question it was written to answer ("should I download this?") and catastrophic for the question S11.7 started asking with it ("may I erase this from the cloud?"). The path is built from this repo's own facts: starter homes keep FIXED `home_id`s across installs, so a fresh install where the user deletes the seeded Bungalow **before** signing in produces an ownerless tombstone, and the first sign-in erased their other device's real Bungalow from the account. It also contradicted the invariant `SyncState` documents about itself — "one person's deletion silently editing another person's library" is the exact thing its owner-scoping exists to prevent. **The general lesson:** reusing a predicate for a more destructive decision than it was written for is not a refactor, and the blast radius is measured at the new call site, not the old one |
| 2026-09-24 | S11.7 (review) | **`forgetAccount` sets a `forgottenAccountID` flag that `persist` applies, rather than writing the wiped sidecar once** | `sync()` holds its own `state` across every `await` and persists it after each action, so an account deletion confirmed during a launch sync — up to 90s of one against a cold Render instance — was wiped and then written straight back by the running loop, restoring exactly the dangling ownership claims the wipe exists to remove. Both are `@MainActor`, which prevents mid-statement interleaving and not interleaving at suspension points. Cancelling a running sync mid-flight would be the larger hammer; making the single write path aware of the deletion is cheaper and cannot be forgotten by a future caller. Confirmed to fail without the guard |
| 2026-09-24 | S11.7 | **Deleting an account erases the SERVER side completely and touches nothing on the device.** `DELETE /auth/me` removes every home belonging to the user and then the user record; on iOS, `AuthSession.deleteAccount()` ends the session and clears the Keychain, and `SyncManager.forgetAccount` clears the sidecar — no home document is read, written or removed. `AccountPrivacy.deletionSummary` says exactly this on the screen before the user commits | The homes predate the account and outlive it: this app is local-first, they are fully usable signed out, and the overwhelmingly common case is somebody who used the app offline and later signed up for backup. Erasing their floor plans because they closed a backup account would be the worst failure this layer could have, and it is not what "delete my account" means to anyone. The promise and the behaviour are deliberately the same sentence so neither can drift without the other. `SyncDeletionTests.testForgettingAnAccountNeverTouchesAHomeDocument` pins it |
| 2026-09-24 | S11.7 | **Homes are deleted BEFORE the user record, not after, and account deletion is idempotent rather than transactional** | The other order orphans every home under a user id nothing can authenticate as, so nobody — not even their owner — could ever ask for them to be removed; a leak with no delete path is strictly worse than a retryable partial. Mongo has no cheap cross-collection transaction here, so the two steps are made individually idempotent instead: a failure between them leaves an account whose data is already gone, and asking again finishes the job |
| 2026-09-24 | S11.7 | **`DELETE /homes/{home_id}` was added and wired into sync's tombstone path, closing a real data defect — but only in one direction.** A home deleted on this device now removes the server copy on the next sync. A home deleted on ANOTHER device still does not delete here | Before this the backend had no delete endpoint at all, which is the entire reason `SyncState` carries tombstones: the server served a deleted home forever and the reconciler could only keep refusing to download it, so "I deleted that home" was true on one phone and false in the cloud. The wiring lives in `SyncManager.apply`, not as a new `SyncAction.Operation`: the reconciler's decision is unchanged ("do not download this") and this is the I/O that decision implies, which keeps the plan a pure decision and left all 69 existing sync tests untouched. It is self-limiting — a deleted record stops appearing in `GET /homes`, so nothing retries. The other direction is NOT closed because an absent server record is indistinguishable from a lost one, and the reconciler deliberately re-creates rather than destroying local data on a guess; closing it needs a server-side tombstone and a `schema_version` conversation. In `BLOCKERS.md` |
| 2026-09-24 | S11.7 | **The privacy disclosure lives in `escape_plan/Auth/AccountPrivacy.swift` — Foundation-only, one source for three screens — and its `uploadedHomeKeys` set is pinned by test against a real encode of the fixture homes** | A privacy disclosure is the one piece of user-facing text that goes stale silently and invisibly: the schema gains a field, `POST /homes` uploads it because it uploads the whole document, and the screen keeps describing the old shape. Putting the copy behind the Foundation boundary means it is testable on a machine with no simulator (the same reason `Auth/` is symlinked into EditorCore at all), and asserting the declared key set against `HomeModel.encoder()` means adding a field without describing it fails a test instead of quietly making the screen a lie. Every "not uploaded" line is checkable in the code rather than reassuring — no "we respect your privacy" |
| 2026-09-24 | S11.7 | **"Continue without an account" is promoted from a grey subheadline to a `DSSecondaryButton`, a visual peer of "I already have an account"; and the gate's headline changes from "Keep your plan safe" to "Back up your homes?"** | S8.3's decision (2026-09-15) called the skip a first-class button, but what shipped was a `.subheadline` in `DS.supporting` grey with no chrome under two 56pt buttons — subordinate by every visual measure, so the decision and the pixels disagreed. S11.7's brief says visually equal, and ordering is the right tool for making something the third option, not shrinking it. The headline was the copy check in the same mission item: "Keep your plan safe" over a sign-up screen reads as "without an account your plan is not safe", which is false and is precisely the implication the soft gate must not carry. The gate also became scrollable (`GeometryReader` + `ScrollView` + `minHeight: proxy.height`, which leaves the collapsed layout identical) because the expanded disclosure would otherwise push the skip button off an SE's screen |
| 2026-09-24 | S11.7 | **`DELETE /auth/me` requires only the JWT — no password re-entry — and this is a recorded choice, not an omission** | Apple's in-app deletion requirement does not ask for re-authentication, and a stolen token already reads and overwrites every home in the account, so gating deletion behind the password adds little against the threat that matters. Recorded rather than left implicit because it is a product decision somebody may reasonably want to revisit before submission. Logged in `BLOCKERS.md` alongside the other finding of the session's security pass: the ACCEPTANCE line names an `ecc:security-reviewer` agent that does not exist in this environment, so the `security-review` skill was run instead and found no HIGH or MEDIUM issues |
| 2026-09-23 | S11.6 | **The Responder Snapshot's hazard summary has NO aggregate score or "clutter score" across categories — it is `[{category, ruleID, count, citation}]`, one row per rule the engine actually fired, never rolled into a single number.** `SnapshotHazardSummary` also deliberately excludes `mitigation.secure.*` and per-home `mitigation.<slug>` items (earthquake-prep suggestions) from the count, keeping only `routes.*`/`egress.*`/`hazard.*` — the things the engine found on THIS home | The engine has no defensible weighting across a blocked exit, an unsecured water heater and a too-small egress window — inventing one would be exactly the kind of unsourced claim `.claude/rules/paths/corpus.md` forbids, and the scope lock already forbids claiming transient clutter is detected at all. A summary that folded "recommend securing this wardrobe" in with "found no viable route out of this room" would also blur the one distinction the whole snapshot exists to make honest: findings vs. suggestions |
| 2026-09-23 | S11.6 | **Narrow, logged exception to S11.7's ownership of `escape_plan/Screens/SettingsScreen.swift`: S11.6 edited only its Responder Snapshot section (now "Share with your fire department"), the two `ConsentSheet` presentations, and `generateSnapshot()`.** Account/auth/sync — S11.7's actual subject — untouched | Missions 1 (rename the feature) and 4 (local-only share, revocable) are impossible without this section, and it was already the Responder Snapshot toggle's home before this session. The S11.6 session file authorized this exception explicitly rather than leaving it to be discovered as a file-ownership collision at merge |
| 2026-09-23 | S11.5 | **The re-scan nudge threshold stays 180 days (~6 months), and gains a second, higher-priority trigger: a wall added or removed since the last scan, detected via a locally-persisted wall-edge-count snapshot (`ScanFreshnessStore`, UserDefaults, MeetingPointStore precedent) rather than a schema field.** `ScanFreshness.daysSince` falls back to `meta.modified` when a home has never been scanned at all | 180 days was already the threshold HomeScreen.swift used before this session ("It's been over 6 months since this home was scanned") — this makes that existing judgement call a named, tested constant rather than re-litigating the number. The wall-edit trigger answers the firefighter's specific warning more directly than age alone: a home scanned yesterday but edited today (a new wall) is more stale than a home scanned 90 days ago and untouched since. No schema field was added — `schema/homemodel.schema.json` is frozen outside its own process (`.claude/rules/paths/schema.md`), and wall count is a locally-recorded, best-effort proxy (edge count summed across every room polygon), not app-verified truth, matching the "resident-maintained, not verified" wording every nudge carries |
| 2026-09-23 | S11.5 | **`PreventionTip.cite` stays a single `String`, not a list, even though `BLOCKERS.md:494` notes some tips are composite/under-attributed** | Making `cite` a list would mean editing `backend/corpus/prevention_tips.json` and `backend/corpus/validate.py`, neither of which is an S11.5-owned path (OWNED FILES lists `escape_plan/Resources/prevention_tips.json`, a byte-identical bundled *copy*, not the corpus original). The client renders whatever single id the corpus ships. The composite-tip under-attribution issue is carried forward as a follow-up in this session's BLOCKERS block rather than fixed here |
| 2026-09-23 | S11.4 | **All four AI system prompts re-positioned from "a home fire escape planning app" to a three-peril prevention/readiness framing, with two new standing statements: this is neither a mid-emergency nor a responder tool, and fire is the code-quantified peril.** Every pre-existing safety rule kept verbatim | The prompts were the last place in the codebase still describing the pre-S6 product. `CLAUDE.md` says the prevention framing must be defended "in every design decision" and that the responder claim must never be made — a working firefighter told the team so — yet nothing in the prompts said either, and `search_corpus` advertised "the **fire-safety** grounding corpus", which is a reason for the model not to call it on an earthquake question against a corpus that has covered earthquake and severe weather since S6.2. The honest-tiering sentence was added because S11.2 made that distinction load-bearing in the score (`sub_scores`, the `basis` map) while the layer that talks to the user said nothing about it. **Not making a claim is not the same as refusing it:** a model never told will happily answer "so firefighters can find you" when asked what the app is for, so each prompt disowns the claim positively rather than merely omitting it |
| 2026-09-23 | S11.4 | **The eval set grades our graders, not the model.** 14 cases in `backend/tests/evals/`, each with a hand-written passing probe AND a failing probe, run against a stub client; `test_evals_live.py` scores the same cases with the same graders against the real model when credits exist | The account is out of credits, so an eval that needs a key would have been written, never run, and rotted before anyone saw it work. Grading probes instead means the **graders** are the artifact under test, and they are what carries over on top-up — no rewrite, no new decisions. The failing probe is the load-bearing half: a grader that accepts everything is the normal way an eval decays into decoration, and `test_the_bad_reply_is_caught` fails when that happens. It did, twice, on the first run — `says_call_911_first` counted newlines so a paragraph of door-checking advice ahead of "call 911" passed, and "is my house earthquake-safe?" turned out not to be a corpus deferral at all (the peril is in scope; the structural verdict is not), so collapsing it into `defers_honestly` would have let either behaviour satisfy both cases |
| 2026-09-23 | S11.4 (correction) | **Corrects this session's own eval set: `allowed_measurements` is now DERIVED from the engine, never typed.** Both measuring cases shipped with hand-written numbers and both were wrong | Found by the grounding-auditor, and worse than a typo. `states_no_measurement_outside` grades **live model output** against that set, so the route-timing case — written specifically to catch invented measurements — was **inverted**: it allowed `"8.4 m"` when the engine computes **14.192 m**, so on a funded key a model quoting the engine correctly would have FAILED and one inventing 8.4 m would have PASSED. The obstruction case asserted "check_obstructions computed it" for a 0.35 m move on `twostory.json`, where the engine returns `[]` — the planted obstruction is on `bungalow-blocked.json` at 0.85 m. Fixed structurally rather than by correcting the literals: `EvalCase` now carries its own fixture, measurements are read from the engine, and three tests fail if a literal reappears (verified by restoring `"8.4 m"`). **The lesson is the session's own:** the file whose job is catching numbers nobody measured contained two numbers nobody measured |
| 2026-09-23 | S11.4 | **`MAX_ITERATIONS` is now guarded at its shipped value, and the runaway limit in the guard is deliberately NOT derived from it** | `test_agent_truncates_at_iteration_cap` passes `max_iterations=3`, so it proves the loop can truncate and never touches the number the server runs with — raising `MAX_ITERATIONS` from 15 to 500 left the entire suite green. The cap bounds the <60s latency acceptance and the per-call API cost and `anthropic.md` states it as design, so it deserves a guard. The runaway limit is a fixed 50 because a limit computed from `MAX_ITERATIONS` rises with it and passes at any value — the same self-consistency trap `.claude/rules/paths/editorcore.md` warns about for rotation tests. The citation retry path, by contrast, was already genuinely covered: verified by breaking the loop in `grounded.py` and `chat/service.py` and watching the existing tests go red, and nothing was added |
| 2026-09-23 | S11.4 | **`THINKING = {"type": "disabled"}` was left in place across all four AI modules, and the question logged rather than answered** | Current Anthropic guidance says disabled thinking produces exactly the failure this repo already hit and documented at `agent.py:47` — the model writing a descriptive evidence ref into visible text instead of a structured block, which is the entire reason `MAX_SUBMIT_RETRIES` exists. The documented remedy is adaptive thinking at low effort, which might also hold the p95 budget the setting was chosen for. But the original decision was **measured** (71s across the 15-iteration loop with adaptive; `/explain` p95 over 6s), and the replacement cannot be measured without credits. Changing a latency-motivated setting on the strength of documentation alone, in a session whose whole point is that the layer cannot currently be exercised, would be exactly the kind of unverified change this tracker exists to prevent. Logged in `BLOCKERS.md` with the A/B to run on top-up |
| 2026-09-22 | S11.3 | **S10.2 ("Q&A findings and future-tech decision") was folded into S11.3 rather than run as its own session, and its deliverable `docs/decisions-object-detection-future.md` is written.** S10.2 was never cancelled; it simply has no record outside a playbook file | Recorded because the grounding-auditor could not check the claim: `docs/playbook/S11-3.md` says "the old S10.2 (a scoping session) is folded in here as a short document", and playbook files are **deleted once their session ships** (`.claude/rules/paths/docs.md`), so after this merge the only trace of S10.2's fate would have been a first draft of the new doc calling it "cancelled" — a word nothing on the record supports. This row is the durable copy. The S10.1 QA note's "Next steps" still points at `docs/playbook/S10-2.md`, which no longer exists; that note is history and is left as written |
| 2026-09-22 | S11.3 (correction) | **Corrects this session's own first R5 implementation and the spec text describing it: R5 does NOT inherit R1's `elevation_m == 0` gate.** A water heater on a stand now gets its topple reach measured like any other | Caught by the grounding-auditor (N1). The first cut of the BUG-03 fix reused R1's whole trigger to decide whether to compute geometry, so an unsecured water heater raised on a platform — common in a garage, and required outright where the ignition source must be lifted — emitted a finding with no `target`, no `reach_m` and no `threshold_m` **even with a bed squarely inside its topple band**. I had then written that gap into the spec in a narrower form ("a heater with nothing in reach"), which understated it. R1's elevation gate exists to separate floor-standing furniture from a wall shelf (R2's job); a raised water heater is neither, and it still topples. Worth stating plainly: the same session that fixed BUG-03 for costing the user a measured number nearly shipped a second case of costing them one, and the spec sentence describing the gap was the thing that made it look handled |
| 2026-09-22 | S11.3 | **BUG-03 is fixed by R5 *absorbing* R1's geometry, not by deleting the R1 finding.** An unsecured water heater emits one `water_heater_unsecured` finding that now carries `target`, `reach_m` and `threshold_m` when its topple band reaches a bed, a sofa or an egress approach | The S10.1 QA note's recommended fix was `if cat == "water_heater" and not obj.secured: continue` in R1. That is right about which rule wins and wrong about what it costs. R5's trigger is categorical — `category == water_heater and not secured`, no geometry — so deleting the R1 finding would have left the user, for that object, **the only finding in the engine with no measured number**, which spec §2 explicitly forbids ("if a rule cannot state a measured value, the threshold it violates, and a cited reason someone should care, the rule does not ship"). Live on `twostory.json`: the discarded R1 finding was the only thing measuring 0.69 m to the back door. One card, one action, measurement intact. **Residual gap stated rather than papered over:** a heater with nothing in reach still states no number; it is in `BLOCKERS.md` under S11.3 and in the spec's R5 section, and was NOT closed by relabelling the object's own height as a threshold it violates |
| 2026-09-22 | S11.3 | **BUG-04 could not be fixed by changing the string.** The opening label now comes from `op.kind`, and the `target` field comes from an explicitly tracked target kind returned by a shared `_topple_target` helper that both R1 and R5 call | `target` was derived as `"egress" if "door" in best_target_name else "bed" if "bed" in best_target_name else "sofa"` — it read the *English detail sentence* to decide a typed field. So the one-line fix the QA note recommends (`"window" if op.kind == OpeningKind.window`) would have removed the substring `"door"` and silently retargeted the finding to `"sofa"`, in a fixture that contains no sofa: a narration fix turning into a data corruption with every test still green. Worth recording as a class, not an incident — deriving typed data from generated prose is the defect, and the rename only exposed it |
| 2026-09-22 | S11.3 | **A fifth defect (BUG-05) was found and fixed in the same rule, and one defect (BUG-02) was re-scoped from "R1" to "all five rules"** | BUG-05: R1 set `is_high = True` at the top of the openings loop for any room with a single opening — *before* `_obb_intersects_circle` had said whether the topple band reached it. Every unsecured tall object in a one-door room therefore came out `high` and capped the composite score on geometry the engine never checked; spec §4 R1 says high only when the band *reaches* the only egress. BUG-02: the QA note filed the cross-room bleed under R1 because that is where it was observed, but `room_objects` is built once and read by all five rules, so R3 bled across walls identically — tested. Both are inside the session's OWNED FILES and inside the rule being repaired; leaving a known false `high` in place to stay inside a narrower reading of "fix BUG-01..04" would have been the wrong trade |
| 2026-09-22 | S11.3 | **Custom/trained ML for object detection stays rejected, and the conditions for revisiting it are now written down as five falsifiable tests rather than a preference** (`docs/decisions-object-detection-future.md`, folding in the cancelled S10.2) | The scope lock already excluded it (product spec §4) and the S7.9 Vision spike already returned NO-GO (1 of 5 target classes, 2026-09-10) — but neither said what evidence would change the answer, which is what makes a rejection re-litigable every session. The new argument is this session's own: **all four S10.1 QA defects were logic bugs in the deterministic engine and none was a perception failure**, two of them shipping on stock demo fixtures. Also recorded there: the one class the spike classified correctly (television) is the one class RoomPlan already returns for free, and `secured` — the single field gating R1 and R5 — is occluded by the object itself and detectable by no sensor at any price. It is a question, and the hazard hunt asks it |
| 2026-09-22 | S11.2 | **Earthquake and tornado checklist items are `scoring: true`, at the same flat `info`/-5 weight as fire.** The fixture scores move: 83/80/78 becomes **73/70/66**, and `docs/preparedness-score-weights.md` is re-derived from a run rather than adjusted | Before this, neither peril had a single scoring item. Both sub-scores sat at a constant **95 on every home**, so `0.50 x min(sub_scores)` always resolved to fire and two of the three pillars in the "weakest link" composite carried no information at all — a judge reading `score.py` finds that in a minute. The alternative (keep them advisory) preserves the demo numbers and ships a composite whose weighting is decorative. Scoring them adds no false precision **because the items are behavioural, not measured**: a checkbox is a fact the resident asserts, so this respects the 2026-09-21 ruling that these perils carry no app-checkable numbers. The guard against the tier becoming a weight is `test_guidance_based_perils_use_the_same_flat_deduction_as_fire` plus `test_no_authored_earthquake_or_tornado_item_invents_a_threshold` — the latter covering authored items only, title/detail/why, sourced statistics allowlisted, and blind to a spelled-out number (scope stated in the weights doc; the first version of this row overclaimed it, which the grounding-auditor caught) |
| 2026-09-22 | S11.2 | **`basis` is a parallel `dict[str, str]` keyed like `sub_scores`, optional on both sides, and Swift decodes it as `String` rather than an enum** | A nested object would have changed `sub_scores`'s shape and broken every existing client; a parallel map is additive, and an older iOS build simply ignores one unknown key. Optional on the pydantic side so a client predating S11.2 decodes a response without it (`test_basis_is_optional_so_older_clients_still_decode`). `String` rather than a Swift enum because **decoding an unknown enum case throws and would fail the entire response** — if a fourth tier is ever added, an old build must degrade to showing no label, not to a broken score screen |
| 2026-09-22 | S11.2 | **Three files outside S11.2's OWNED FILES were edited: `escape_plan/Models/ScoreModels.swift`, `backend/tests/test_checklist_hazards.py`, and `docs/peril-objective-mappings.md` was corrected beyond "where it understates".** The playbook's `backend/app/models.py (the RouteFinding class ONLY)` names the wrong file — `RouteFinding` lives in `backend/app/routing/plan.py`, and needed no edit | (1) The mission says to decode `basis` in `APIClient+Score.swift`, but that file contains no struct — `ScoreBreakdown` is a Codable in `ScoreModels.swift`, so the field has to go there. Checked all 13 playbook files: no other S11 session owns it. (2) `test_checklist_hazards.py:34` pinned `"adhesive straps"` and went red the instant the fabricated citation was fixed; `BLOCKERS.md` explicitly assigns that fix to S11.2 and says it must move in the same commit. (3) `peril-objective-mappings.md` cited `fema-earthquake` for post-shaking evacuation and `shakeout-guidance` for Drop/Cover/Hold On, neither of which carries the claim — leaving a known misattribution in an owned file to stay inside a narrower reading of the mission would be the wrong trade |
| 2026-09-22 | S11.2 | **Three further fabricated-but-resolving citations were found in `checklist.py` and fixed: gas shutoff, electrical panel and the "72-hour kit" all cited `fema-earthquake`.** The kit item's quantities ("water, one gallon per person per day for three days") were deleted outright, not re-pointed; the item id `supply_kit.72h` is kept so persisted done-state survives | These were **not** on the S11.1 grounding-auditor's list — found by grepping what `fema-earthquake` is cited for across the whole corpus, which is only ever securing objects and Drop/Cover/Hold On. `ready.gov/earthquakes` has no gas, no electrical and no supply-kit content. Gas and electrical re-point to `shakeout-guidance-after`, which carries the real rules including the asymmetry that matters (shutting gas off has a named trigger; turning it back on is never the resident's action, `usgs-earthquake-donts`). **Nothing in the corpus supports a 72-hour kit or a per-person water quantity**, so the item now says only what `earthquake-after-shaking.md` sources: a grab-and-go bag of medication, documents and eyewear, and flashlights rather than candles. Worth stating plainly — this is the third session in a row to find this class of defect, and in every case the cite resolved and every validator was green |
| 2026-09-21 | S11.1 (correction) | **Corrects the S11.1 "four claims" row below, which miscounts itself.** The accurate tally is **six claims re-pointed** (the row's own list is right; its "three" is wrong) and **four claims deleted**, not two. The two the row omits: **"keep a crescent wrench or pipe wrench near the valve"** and **"when exiting, avoid using elevators"** — both were attributed to `fema-earthquake`, neither is on ready.gov/earthquakes, and I verified with grep that both are now absent from `backend/corpus/`, `backend/app/` and `escape_plan/`. `earthquake-securing-home.md`'s "What this corpus does not claim" section names only the two securing-related deletions and is likewise incomplete for the two above | Caught by the grounding-auditor. Recorded as a new row because `decisions.md` is append-only and an old row's meaning must never be edited (`.claude/rules/paths/docs.md`). Worth stating plainly: a decisions entry that undercounts its own deletions is the same category of defect as the misattributions the session was fixing — the log is the mechanism, so it has to be right about itself. The wrench and elevator claims are both plausible and both may be true; they went the same way as the drywall-anchor claim, because "no source, no ship" has no plausibility exception |
| 2026-09-21 | S11.1 | **A source id may not be added to `sources.json` unless some markdown corpus doc actually cites it.** Adding `usfa-extinguishers` and `usfa-batteries` for the tips file alone was wrong; the extinguisher decision rule went into `escape-planning-nfpa.md` and lithium-ion batteries into `heating-electrical-fire-safety.md` to close it | `backend/tests/test_ai.py::test_corpus_block_matches_sources_json` caught this in my own diff. `valid_source_ids()` accepts every id in `sources.json`, but the corpus block the model is shown is built from the **markdown files** — so for one commit the server would have accepted `usfa-extinguishers` on an extinguisher claim the model invented, with no document behind it. That is the "AI never invents safety guidance" law failing in exactly the way the law exists to prevent, and `validate.py` cannot see it (the ids resolve fine). **`prevention_tips.json` is not a corpus document for this purpose** — it is consumed by the iOS app, never shown to the model. The rule to carry forward: a new source id needs a home in a markdown doc in the same commit, and the backend suite is what proves it |
| 2026-09-21 | S11.1 | **Earthquake and tornado add NO new numeric thresholds, to `egress_thresholds.json` or anywhere else. "No codified threshold found" is the finding.** The two numbers the sources do carry are recorded as prose in the corpus and deliberately left out of every machine-readable threshold file | The mission asked for values "a named standard actually codifies". After reading the sources, there are none a home app can evaluate. (a) **Water heaters:** ShakeOut's "two metal straps" is a practice, not a dimensioned code value with an imperial/metric pair; California H&S §19211 makes strapping legally mandatory but explicitly delegates the method to the California Plumbing Code, and CPC §507.2's strap positions (upper third / lower third, ≥4 in above the controls) are reachable only through plumber blogs and county restatements, never a primary I could fetch — so they are not encoded. §19211 is also California-only, where `egress_thresholds.json` holds a national model code. (b) **Tornado:** FEMA RA2 gives 200–250 mph safe-room design wind speed against 140–150 for conventional construction, but that is a *construction design criterion* — no resident, phone or LiDAR scan can measure whether a room meets it. Encoding it would invite a scorer to treat it as checkable. (c) Everything else — "most interior room", "as many walls as possible" — is qualitative in the source and stays qualitative. This absence is not a gap to fill later; it is the substance of S11.2's `guidance_based` tier, and manufacturing a number to make scoring tidier is the exact failure the tiering exists to prevent |
| 2026-09-21 | S11.1 | **Four earthquake/tornado claims were attributed to pages that never carried them. Three are re-pointed to sources that do; two are deleted outright.** Re-pointed: the gas-shutoff trigger (`usgs-earthquake` → `shakeout-guidance-after`), never restoring gas yourself (`fema-earthquake` → `usgs-earthquake-donts`), the Triangle of Life rebuttal (`usgs-earthquake` → `usgs-triangle-of-life`), "lowest floor" (`noaa-tornado` → `noaa-tornado-ww`), helmets and "as many walls" (`noaa-tornado` → `noaa-tornado-shelter`), bed-shaker/strobe alerting (`noaa-tornado` → `noaa-nwr-accessibility`). **Deleted:** that standard drywall anchors are specifically inadequate, and that earthquake-rated adhesive nylon straps are an established renter substitute for drilling. `earthquake-securing-home.md` states in the open that both were removed and why | Found while checking the mission's "fetch the URL yourself before stamping a date" instruction. `usgs.gov/.../prepare` is a **link directory** with no safety text at all, yet four claims cited it; `ready.gov/earthquakes` has **no gas content**, yet carried the wrench and gas-restoration guidance; `weather.gov/safety/tornado-during` has no mention of lowest floor, helmets or accessible alerting. `validate.py` was green over all of it because it checks that a cite **id resolves**, never that the claim is **on** the page — a gap no offline script can close. The two deleted claims are plausible and may well be true, but "no source, no ship" does not have a plausibility exception, and the honest renter guidance that IS sourced (move bookcases away from beds, heavy items low, putty for small objects) is now what the doc offers instead |
| 2026-09-21 | S11.1 | **No candle prevention tips, despite the mission naming "kitchen and candle habits".** Kitchen tips ship; candle tips do not | `usfa.fema.gov/prevention/home-fires/prevent-fires/candles/` returns **404** and no other reachable source in the corpus's orbit carries candle guidance. Writing the tip and citing an adjacent USFA page would be precisely the misattribution this session spent its time removing. Logged rather than quietly dropped so a later session can add it if a real source turns up |
| 2026-09-21 | S11.1 | **`backend/corpus/check_urls.py` is added but deliberately NOT wired into `validate.py`, and a bot-walled 403 or a JS shell reports as BLOCKED / NO-TEXT rather than as a failure** | `validate.py` must stay offline, fast and stdlib-only — it runs before the backend venv exists and gates every session, so it cannot depend on the network. The content check therefore lives in a separate opt-in script that re-fetches each URL and greps per-source `verify_keywords`. On the reporting choice: **fema.gov** rejects every scripted fetch (urllib and curl, full browser headers included) while serving browsers normally, and **nfpa.org** returns a ~40-character JS shell. Marking those FAIL would leave the run permanently red, which trains the next person to ignore it — the failure mode this repo's tracker already has a history of. They are counted as "need a manual check" instead, and fema-sourced content was read by hand (Quartz text extraction of the RA2 PDF) |
| 2026-09-19 | out-of-band hotfix | **The `ISO8601DateFormatter.homeModelWhole` / `homeModelFractional` / `parseHomeModelDate` helpers are ported into `escape_plan/Models/HomeModel.swift`; the branch's custom `HomeModel.decoder` is NOT carried over.** `HomeModel.decoder` stays `.iso8601` | Same merge (`d6e982c`), same shape as the backend break: main's `Models/HomeModel.swift` met the branch's `Persistence/HomeDocument.swift`, which calls helpers only the branch defined, so `main` has not compiled as an iOS app since. The helpers are ported because `HomeDocument` genuinely needs them and the fix they carry is real — an unparseable `meta.modified` returned nil and sorted the home to the bottom of the library with no error anyone would see. The custom decoder is not, because **the branch's own comment says it is not a bug fix**: plain `.iso8601` already accepts fractional seconds on this deployment target. Worth recording separately: **EditorCore's 516 passed over a non-compiling app.** `Models/` is symlinked into the package, `Persistence/` is not, so `swift test` proves only the symlinked subset. `scripts/typecheck-ios.sh` was the only check in the gate that could see this |
| 2026-09-19 | out-of-band hotfix | **`actions.new_draft` stamps `schema_migrator.CURRENT_VERSION`, not a constant of its own; `SCHEMA_VERSION` is NOT reintroduced into `app/models.py`.** The 2.0-era name arrived with the `s6-1-schema-2-0` merge (`d6e982c`) and was never defined on `main`, whose `models.py` had already moved to 2.1. Fixed on `fix-schema-version-import`; `test_builder_actions.py` now reads the accepted version off `HomeModel`'s `Literal` and asserts the draft matches | The merge was **textually clean and semantically broken** — the same class as the 2026-09-18 rotation finding. It took main's `models.py` and the branch's `actions.py`, which live in different files, so git reported no conflict; `app.main` then could not import, the backend suite was 13 collection errors rather than 556 passed, and Render deploy `6537170320` failed 73s in. Adding `SCHEMA_VERSION` back would create a **second** name for the current version alongside `CURRENT_VERSION`, which is the condition that made this possible; the fix removes the duplicate instead of completing it. Prod was never down — Render kept serving `b45446a3` — but `main` was undeployable for the whole window |
| 2026-09-18 | S11 baseline | **The product is reframed around prevention and readiness, and the playbook is replaced by the S11 arc (13 sessions, three lanes).** The 65-file playbook is deleted (recoverable at tag `archive/playbook-v1`); `docs/playbook/01-product-spec.md` is rewritten as spec v3 and `docs/playbook/README.md` holds the lanes, branch protocol and conflict rules. Scope lock restated: fire + earthquake + tornado with honest tiering (fire code-quantified, the other two FEMA/NOAA-grounded), iOS only, LiDAR plus editor primary with the text/photo builder as a draft-only fallback, accounts optional, no custom ML | A working firefighter said firefighters cannot use a stored layout in a working fire and would distrust it after a remodel, but that the app is marketable as a prevention and education tool with an opt-in share to the department. He also described the department's own manual Clutter Survey Program, which our hazard engine matches, and said self-reported clutter reaching a department is unrealistic. The review also found earthquake and tornado are far thinner than fire (6 fire corpus docs vs 1 and 1, no codified numeric thresholds), so they must be deepened and labeled honestly rather than presented as equal pillars |
| 2026-09-18 | S11 baseline | **Accounts and cloud sync (S8) are KEPT but demoted: optional, soft-gated, absent from the pitch.** Tag `archive/s8-cloud-sync` marks the pre-demotion state. **This corrects the 2026-09-14 S9.1 row below**, which said "Firebase Auth (S8) deleted": the arc was never Firebase (it is JWT, Argon2id and MongoDB via PyMongo async), and it was not deleted: it was built and verified on `origin/main` while local `main` diverged | Local `main` was 2 ahead and 164 behind `origin/main`; origin holds a teammate's complete, tested arc with a soft gate ("Continue without an account"), owner-approved 2026-09-14. Deleting 160 commits for a pitch-focus reason is the wrong trade; the objection (dilutes the deterministic-engine story) is met by keeping it out of the pitch. Session S11.7 proves the app works signed-out and adds privacy copy and delete-my-data |
| 2026-09-18 | S11 baseline | **SemanticMatcher keeps origin's rotation direction; local commit `dde7f08`'s rotation flip is NOT carried over.** A convention-independent 30 degree known-answer test (`testDoorLandsOnModelDoorAfterA30DegreeRotation`) passes on origin's code. The existing 90 degree test could not tell the direction apart because the matcher also tries angle + 180. **Open:** whether the candidate filter should compare perimeter (`dde7f08`) or bounding-box area (origin): the perimeter change also broke origin's EditorCore tests via a new protocol requirement, so it is not carried over until a real scan justifies it (S11.10). `docs/tracker/notes/S9-Adversarial-Audit-Final.md` is marked superseded | The merge of `origin/main` into local `main` was textually clean but semantically unsafe: it silently combined the flipped rotation with tests written for the original. Taking origin's verified, tested version and adding a discriminating test resolved it with evidence rather than by picking a side |
| 2026-09-16 | S8.3 (follow-up) | **`IPHONEOS_DEPLOYMENT_TARGET` lowered 26.5 → 17.0** in all four build configurations | 26.5 was never a decision — it is what Xcode defaults a new project to, and the owner confirmed nobody set it. It would have shipped a Congressional App Challenge submission installable only on the very newest iOS, so a judge opening it on anything older gets nothing. The floor was **measured, not guessed**: the app type-checks clean at iOS 17.0 and 18.0 (exit 0, both `-DDEBUG` and release) and fails at 16.0 with exactly 38 `is only available in iOS 17.0 or newer` errors — so 17.0 is the exact floor, and it is the number `CLAUDE.md` and `rules/languages/swift.md` have claimed all along for the documented reason (RoomPlan's merged multi-room `CapturedStructure`). The docs were right; the project file was wrong. **Compile-verified is not run-verified**: nothing has ever executed below 26.5, so an older-runtime spot check is now a device-pass item in `BLOCKERS.md` §2 |
| 2026-09-15 | S8.3 (review) | **`restore()` is non-destructive; only a locally-known-expired token is deleted.** A nil read leaves the store untouched | `KeychainTokenStore.load()` returns nil for **any** non-success status, and the item is stored `AfterFirstUnlock` — so a background launch before the device's first unlock (iOS does this after a reboot) yields `errSecInteractionNotAllowed`, which reads as nil. The original code deleted on that path, signing the user out **permanently** because their phone rebooted in their pocket, with no error and nothing to retry. Being unable to READ a token and having none look identical on screen; they must not look identical to the store. `UnreadableTokenStore` exists purely to keep that distinction tested |
| 2026-09-15 | S8.3 (review) | **A `generation` counter is captured before every `await` and re-checked after**, in `refresh()`, `signIn()` and `register()` | The guards ran before the suspension only. `RootView` fires `refresh()` at launch against a Render instance that can take most of a minute, and Settings' Sign out is reachable throughout — so a 200 arriving late wrote the session straight back, leaving the app showing an account with `token == nil` and nothing in the Keychain, which every S8.4 request would then trip over. Both new tests were confirmed to FAIL with the guard removed, so they pin the behaviour rather than merely accompanying it |
| 2026-09-15 | S8.3 (review) | **`signOut()` does NOT re-arm the auth gate**, and a successful `restore()` marks the gate as already answered | Reverses the same session's earlier choice ("signing out is a request to be asked"). `shouldPresentGate` drives a **root-level switch** between `AuthGateView` and `ContentView`, so re-arming it destroys the entire ContentView subtree — tab selection, navigation stacks, any in-progress edit — and drops the user on a full-screen welcome screen they did not ask for. Unacceptable from `refresh()`'s 401 path, which does it with no interaction at all, seconds after launch. It directly contradicted this layer's own stated rule that nothing in it may block the rest of the app. Signing back in is available from Settings (`AuthSheetView`), which is what makes the soft gate genuinely reversible |
| 2026-09-15 | S8.3 (review) | **`AuthClient` is `@MainActor`** | `baseURL` is mutable and written from the main actor (Settings' `setBaseURL` via `AuthSession.baseURL`), while the `async` methods were `nonisolated` and read it on the global concurrent executor — a torn read of a refcounted struct, not a benign race. It type-checked only because the SwiftPM package pins Swift 5 language mode; Swift 6 would reject it. Isolation costs nothing here because the network work happens inside `URLSession` and `await session.data(for:)` suspends rather than blocking |
| 2026-09-15 | S8.3 (review) | **Test tokens are minted at runtime, never pasted as literals** | `AuthSessionTests` originally pinned a genuinely backend-signed JWT — which carried a fixed `exp` of 2026-09-16T06:39:01Z. `AuthSession.restore()` checks expiry against the real clock with no seam to inject one, so sixteen tests were scheduled to go permanently red that morning, in the one file whose entire purpose is to keep S8.3 verified. Caught roughly 26 minutes before the cliff. Backend-signed tokens are still used where the test injects `now:` (`AccessTokenTests`), which is where pinning the real claim encoding actually belongs |
| 2026-09-15 | S8.3 | **The auth gate is SOFT.** `AuthGateView` appears at root when no token exists — the brief's "show the Auth flow if no token exists" — but carries **"Continue without an account"** as a first-class button, remembered in `auth.gate.dismissed`. `AuthSheetView` in Settings lets someone change their mind later | A literal reading is a wall in front of the whole app, and this app is local-first: the editor, routing, drill, export and persistence all work with no server. A wall would mean the CAC demo is one Render cold start away from being a login screen, and that the golden-path recording depends on Atlas being up. It would also have required a live account for all 8 UI tests. The account buys cloud backup and a second device — which is what S8.4 builds — so that is exactly what the gate offers and nothing more. Owner-approved during planning, 2026-09-15. The escape hatch must stay reachable from Settings or the soft gate is a hard gate with extra steps |
| 2026-09-15 | S8.3 | **`escape_plan/Auth/` is pure Foundation and symlinked into `tools/editorcore` as `Sources/EditorCore/Auth`**, the way `Editor/Core` already is. Only the three SwiftUI screens live outside it | This machine cannot run the iOS simulator and `FIRST-PRIORITY.md` is open precisely because four bodies of Swift have landed since 2026-09-09 with no recorded result. Putting the client, token store, session state machine, error mapping and validation behind a Foundation-only boundary meant **84 new tests that actually execute** (suite 295 → 379) rather than a fifth unverified body. The cost is a rule that has to be respected: **a SwiftUI import anywhere in `Auth/` silently removes all of that coverage**, so it is called out in the directory's own header comments and in `escape_plan/CLAUDE.md` |
| 2026-09-15 | S8.3 | **`AuthClient` takes its `URLSession` as an injected dependency**, where every `APIClient+*` extension calls `URLSession.shared` directly | Required by the decision above — a stub installed on a private `URLSessionConfiguration` is what makes the wire contract testable in the package. The app-target alternative already in the repo (`OfflineStubProtocol`) calls `URLProtocol.registerClass`, which affects `URLSession.shared` process-wide and is why that suite must be `.serialized`. Not a criticism of the existing extensions; the new constraint is testability without a simulator |
| 2026-09-15 | S8.3 | **A separate `AuthFailure` type rather than a new `BackendFailure.Operation` case** | `BackendFailure` is shared by six screens and reads the same status codes differently: 401 there means "the build's shared bearer token is wrong, open Settings", here it means "that password is wrong" and Settings cannot help; 503 there means "busy, retry", here it means the operator never set `MONGODB_URI` and retrying forever will not fix it; 409 has no case there at all. Bending the shared type to cover both vocabularies would blur the distinction it was written to draw. `AuthFailure` deliberately mirrors its shape (kind / message / isRetryable / symbol) so the two read as one system |
| 2026-09-15 | S8.3 | **PLANNED AND REVERSED: auth does NOT get its own `JSONDecoder`.** It uses `HomeModel.decoder`, the house convention | The session plan called for a bespoke decoder on the premise that `.iso8601` cannot parse the fractional seconds pydantic emits (`2026-09-16T05:33:58.567000Z`). **Measured, that premise is false on this project's platform**: `JSONDecoder.dateDecodingStrategy = .iso8601` parses it correctly and preserves the 567 ms, and the deployment target is **iOS 26.5**, not the iOS 17 the root `CLAUDE.md` still claims — so the lenient Foundation parser is guaranteed. The real trap is adjacent and is what the tests now pin: a bare `ISO8601DateFormatter()` returns **nil** for that same string, so `.iso8601` and `ISO8601DateFormatter` are not interchangeable. Recorded because writing code justified by a fiction is how a comment outlives the fact it describes |
| 2026-09-15 | S8.3 | **First launch purges the Keychain** (`AuthSession.purgeKeychainOnFirstLaunch`, flagged in UserDefaults) | On iOS a Keychain item **outlives the app that wrote it** — delete the app, reinstall, and the old token is still there. Without the purge a reinstall silently resumes a session the user may have deleted the app to get out of. UserDefaults does *not* survive deletion, which is exactly what makes it the correct home for the "have I ever run before" flag. Tested in `AuthSessionTests` |
| 2026-09-15 | S8.3 | **`refresh()` signs out on 401 but never on offline, timeout or 5xx** | The backend re-reads the user on every request, so a deleted account stops working immediately and 401 genuinely means "this session is over". Every other failure is about the network or the server, and dropping someone's session because their train went into a tunnel is unforgivable in a safety app they may be opening *because* something is wrong. Three tests pin it |
| 2026-09-15 | S8 (live verification) | **`_utc_now()` truncates to milliseconds.** Every `created_at`/`updated_at` in `cloud_models.py` is generated already rounded to millisecond resolution | **BSON stores datetimes as milliseconds since the epoch**, so microseconds do not survive a write — measured against live Atlas: written `…744441Z`, read back `…744000Z`. Any `written == read_back` assertion therefore passes against `tests/fake_mongo.py` and fails against a real server, which is precisely the trap S8.4's merge would fall into while comparing a local copy to a fetched one (and the same class as S8.1's `tz_aware` finding). Truncating at generation makes the model a fixed point of the storage round-trip. Sub-millisecond precision has no meaning for ordering syncs between devices whose clocks disagree by far more. `test_cloud_mongo.py` asserts the server really does truncate, so if a future MongoDB gains microsecond resolution the test fails and says so — a silently unnecessary workaround is how the next reader concludes the comment is wrong |
| 2026-09-15 | S8 (live verification) | **`/homes` serialises its id as `id`, not `_id`** — `response_model_by_alias=False` on both routes. The alias stays on the model for `to_document()` | `StoredHomeModel.id` is aliased to `_id` so the Mongo primary key is written correctly — a storage concern. FastAPI serialises response models **by alias by default**, which leaked that alias onto the wire: `POST /homes` returned `{"_id": …}`. Two reasons to stop it. It contradicted `/auth/me`, which returns `UserPublic` with a plain `id`, so one API spoke two dialects; and it would force S8.4's Swift `Codable` into a `CodingKeys` mapping — surrendering free `Identifiable` conformance — to accommodate a database detail the client has no business knowing. `populate_by_name=True` means an inbound `id` still validates, so the read side loses nothing. Found by inspecting a real response body; no fake-backed test had ever asserted the wire shape |
| 2026-09-15 | S8 (live verification) | **`created_at` is carried forward on a home update** instead of being re-defaulted | `HomeRepository.upsert` is a full `replace_one`, so the freshly constructed `StoredHomeModel` overwrote the stored `created_at` on every write. The field therefore meant "last written" — indistinguishable from `updated_at` — and any S8.4 merge heuristic reading it would have been reading noise. Found while tracing the `_id` fix; not a Mongo-specific bug, but only visible once real documents were being updated rather than asserted about |
| 2026-09-15 | S8 (live verification) | **A configured-but-unreachable database returns 503, not 500.** A guarded `pymongo.errors.ConnectionFailure` handler in `main.py` sits alongside the existing `CloudSyncDisabled` one | Found on the **deployed** service: `MONGODB_URI` was set but Atlas was not allow-listing Render's egress IPs, so `/health/db` said `unreachable` while `POST /auth/register` returned a bare **500 with no body**. `CloudSyncDisabled` only covers "no database configured"; "configured but unreachable" is a third state with the same right answer — 503, "the same request may work shortly" — mirroring the split the Anthropic handler already makes. `ConnectionFailure` is the precise seam: it is the base of `ServerSelectionTimeoutError`, `NetworkTimeout`, `AutoReconnect` and `WaitQueueTimeoutError`, and is **not** a base of `OperationFailure`, so a genuine bug in one of our queries still surfaces as a 500 rather than being dressed up as a transient blip. The import is guarded so `database.py`'s "the app still imports with no driver present" property survives. Matters for S8.3/S8.4: an iOS client cannot tell "retry this" from "your request was wrong" if both are 500 |
| 2026-09-15 | S8 (live verification) | **The `mongo` suite runs against a throwaway database, named per-run and dropped afterwards** — deliberately not `MONGODB_DB_NAME` | `pytest -m mongo` is run with the same `MONGODB_URI` a developer uses for real work. Pointing the suite at the configured database would have it creating and deleting users in the same place the app stores them; one absent-minded run against a populated cluster is all it takes. A per-run name means the worst case of a misconfigured URI is an empty scratch database. The fixture also skips (not fails) when the server is unreachable, so a laptop off the allow-list reports "no reachable MongoDB" instead of 22 red tests |
| 2026-09-14 | S8.2 | **Argon2id via `argon2-cffi` for password hashing — NOT passlib, which the playbook's ecosystem still assumes, and not bcrypt.** Also rejected `pwdlib`, which is what FastAPI's current tutorial recommends | passlib has had **no release since 2020-10-08** and now **hard-fails against bcrypt 5.0.0** (2025-09-25): its own backend probe feeds a >72-byte secret to `hashpw`, which changed from silent truncation to raising `ValueError`. passlib declares no bcrypt upper bound, so a clean `pip install` today picks bcrypt 5 and breaks on first use — verified empirically, not from bug reports. Bare bcrypt inherits the 72-byte limit as a crash and OWASP now files it under legacy. `pwdlib[argon2]` is FastAPI's current recommendation and would be defensible, but it is **0.3.1, "Development Status :: 4 - Beta", one maintainer** — and it is a thin wrapper over argon2-cffi, which is Production/Stable. For a submission six weeks out, the wrapper's convenience did not justify a 0.x dependency. Argon2 has no input length cap, so the entire 72-byte pre-hashing minefield does not apply |
| 2026-09-14 | S8.2 | **PyJWT pinned `>=2.13.0` as a security floor, not a preference.** Two PyJWT defaults are explicitly overridden: `algorithms` is always passed, and `options={"require": ["exp", "iat", "sub"]}` | CVE-2026-48522 through 48526 (disclosed 2026-06-15) are all fixed in 2.13.0 — algorithm allow-list bypass, a public JWK accepted as an HMAC secret yielding **forged HS256 tokens**, and JWKS SSRF. Below that floor is not a judgement call. The `require` option matters because **PyJWT's `verify_exp` only checks `exp` if it is present**, so a hand-made token that simply omits the claim never expires — the easiest real vulnerability to ship in a JWT layer, and a test now pins it. python-jose was rejected on maintenance velocity (3.7 years between releases, dropped from FastAPI's docs), NOT on open CVEs — its 2024 CVEs *are* patched in 3.5.0, and saying otherwise in a design defence would be inaccurate |
| 2026-09-14 | S8.2 | **The service refuses a `JWT_SECRET_KEY` shorter than 32 bytes**, rather than warning | PyJWT emits `InsecureKeyLengthWarning` below the RFC 7518 §3.2 minimum and signs anyway. A warning in a deploy log is easy to miss, and a short HMAC secret is brute-forceable — at which point anyone can mint tokens for any user. An ABSENT secret still means "auth disabled" (the same split as `MONGODB_URI`): not configuring a feature is a choice, misconfiguring it is a mistake |
| 2026-09-14 | S8.2 | **Login always performs a password verification, against a dummy hash when the email is unknown; the user is re-read from the database on every request; a home id owned by someone else returns 404, not 403** | Three deliberate anti-enumeration choices. Without the dummy hash an unknown address returns in microseconds while a real one costs a full Argon2 hash — a timing oracle for who has registered. Re-reading the user means deleting an account revokes access immediately rather than when its token expires, which a stateless JWT otherwise cannot do. 403 on another user's home would confirm that the id exists; 404 reveals nothing |
| 2026-09-14 | S8 arc | **The S8 Cloud Sync & Authentication arc is APPROVED by the owner.** "No user accounts" and "multi-user sync" are removed from the scope lock; accounts, a MongoDB-backed store and cross-device sync are in scope. Scope locks updated in lockstep: `CLAUDE.md` and `docs/playbook/01-product-spec.md` (both the in-scope line and the explicit out-of-scope list) — the same pattern as the 2026-09-05 multi-peril and 2026-09-08 object-hazard reversals | The owner authorised it directly on 2026-09-14 after the arc arrived on `origin/main` without an approval entry. Recorded as its own row because the arc was written and pushed *before* it was sanctioned, and a later reader must be able to see that the authorisation was a separate act. **This reverses a decision recorded the same day**: the S9.1 entry below deleted an S8 Firebase-auth arc precisely for violating the lock this row lifts. Both rows are kept — the contradiction is the history, and editing the earlier one would hide it. Two consequences are open: `docs/demo/script-v1.md` still pitches local-only privacy, and the submission's "explicitly out of scope" answer must no longer say multi-user sync |
| 2026-09-14 | S8.1 | **PyMongo's native async API (`pymongo.AsyncMongoClient`), NOT Motor or Beanie as the playbook specifies.** Pinned `pymongo>=4.13,<5.0` (4.13 is the async-GA floor; 4.18.1 installed) | **Motor reached end-of-life on 2026-05-14**, four months before this session, and MongoDB now directs new code at the PyMongo async API. Writing the project's first database layer against a dead driver would have been a knowing defect. Beanie is alive (2.2.0) and already off Motor, but it is an ODM this layer does not need and it caps Python at <3.14. Two Motor habits do not carry over and are called out in `database.py`: `close()` is a coroutine, and the client must be one long-lived instance, not one per request |
| 2026-09-14 | S8.1 | **Cloud sync is OPTIONAL: a missing `MONGODB_URI` disables the layer instead of refusing to boot.** This deviates from the acceptance criterion "backend starts successfully and connects to MongoDB". `/health/db` reports `disabled`/`ok`/`unreachable`, and returns 200 even when unreachable | `get_settings()` fails closed on a missing `BACKEND_BEARER_TOKEN` because an unauthenticated backend is a security hole. Copying that pattern for Mongo would have a different effect: the routing engine, the corpus and every pre-S8 endpoint need no database, and the demo path runs entirely on them — so a fail-closed Mongo would trade a working product for an unbuilt feature, and would have broken all 394 existing tests. The unreachable-but-200 choice is so a down database reads as a down database rather than as the whole service being broken |
| 2026-09-14 | S8.1 | **No `mongomock`, no `mongomock-motor`, and no Docker/Testcontainers in the default test path.** The DB is faked by a hand-written stub implementing only the operations `Database` touches; tests needing a real server are marked `mongo` and excluded by default, mirroring the existing `live` marker | `mongomock` is stale (4.3.0, Nov 2024), has no Python 3.13 classifier and no async support (issue #916 open, unanswered). `mongomock-motor` mocks `AsyncIOMotorClient` and would drag the EOL Motor back into the tree purely for tests. Testcontainers would work but makes Docker a precondition for running the suite at all, on a machine that already struggles with `xcodebuild`. The stub costs ~30 lines and keeps the default suite infrastructure-free |
| 2026-09-14 | S9.1 | **Semantic Relocalization replaces ARWorldMap for AR Drills. Firebase Auth (S8) deleted.** Playbook files S8/S9 updated or deleted to reflect this architectural shift and enforce the "no user accounts" scope lock. | ARWorldMap files are too large (20-50MB) and brittle to environmental changes. We have a robust semantic HomeModel, so live geometric matching is faster, smaller, and more resilient. S8 was purged as it violated explicit project scope locks in CLAUDE.md. |
| 2026-09-08 | S7 arc | **Object-hazard detection is APPROVED as the S7 arc, reversing the "furniture detection" scope lock.** Rule book: `docs/object-hazard-spec.md`; charter: `docs/playbook/07-object-hazard-intro.md`; ten sessions `S7-1.md`…`S7-10.md` + `S7-EXECUTE.md`. Scope locks updated in lockstep: `CLAUDE.md`, `.claude/rules/global/conventions.md`, `docs/playbook/01-product-spec.md` — same four-file pattern as the 2026-09-05 multi-peril reversal. The sanctioned form is RoomPlan scan objects + guided manual tagging feeding a deterministic hazard engine; custom/trained ML is now *explicitly* on the out-of-scope list where "furniture detection" used to be | The owner directed the feature 2026-09-08 and the scoping vetted it rather than just transcribing it. Three honesty rulings shaped the arc and are binding (spec §2): the core "detection" is data RoomPlan already produces and the app throws away (`apple-raw.json` has objects; the wire format and `/convert` drop them), so this is plumbing + judgment, not ML; transient clutter (backpacks, cords) is NEVER claimed as detected — recurrence items, the hazard hunt, and the stretch re-scan diff are the honest substitutes; and every finding must carry a number, a threshold, a citation and an action, because the feature's answer to "the user can see the bookcase themselves" is measurement against codified standards, not perception. **Nothing was built as part of this approval** — docs only, plus the `origin/main` merge (S6.4–S6.9 landed remotely; local was 1 ahead/9 behind) and a fresh green baseline: backend 348 not-live, EditorCore 270, corpus 17/8. iOS not run (owner's standing simulator restriction on this machine) |
| 2026-09-05 | S6.2 | **Deliberately did not add numeric thresholds for earthquake or tornado.** `egress_thresholds.json` was not modified. | The playbook instructed adding thresholds "if and only if you find genuinely numeric, codified thresholds worth computing on." Research across USGS, FEMA, NOAA, and Red Cross revealed qualitative rules (e.g. "lowest floor, most interior room", "secure tall furniture to studs") rather than codified engineering thresholds like the fire egress window measurements. No numbers were manufactured to make the engine's job easier. |
| 2026-09-05 | S6.1 | **`routingHint` for the two sensory tags says only that they do not affect routing — no promise of checklist or narration behaviour** | Caught by the swift-scenekit-reviewer, and it was the worst thing in this session's diff. The first draft told a deaf user that toggling the tag "adds alarms you can notice — a strobe or bed-shaker — to your checklist" and a blind user that "your route is written out step by step". Neither was true: `backend/app/scoring/checklist.py` contains zero references to `ProfileTag` (that is S6.4, unstarted), and `RouteNarration` produces step-by-step narration for EVERY profile regardless of tags. `routingHint` is wired straight into `.accessibilityHint`, so both strings would have been read aloud, as fact, to the exact person they were about — and both violated the function's own documented invariant that these sentences describe engine behaviour. Aspirational copy is a lie when the feature has not shipped. S6.4 updates it when the checklist item actually lands |
| 2026-09-05 | S6.1 | **`EditorValidation` now walks `floor.safety_points`** | The pydantic half of this change added safety_point ids to the global uniqueness pass; the Swift mirror gained the field but not the invariant. A safety point whose id collided with a room's, or one literally named `EXTERIOR`, passed client-side validation and would have 422'd on the next `/routes` call. Invisible because all three seeded fixture points are well-formed. `HomeModelCodableTests` states that this validator exists precisely to keep the Swift mirror honest against `backend/app/models.py`, so the gap was a direct violation of its stated purpose. Three tests added, including the negative cases |
| 2026-09-05 | S6.1 | **`household` is declared explicitly nullable in the schema** (`oneOf: [$ref, null]`), not a bare `$ref` | Caught by the post-change schema-contract-guardian run, and it was a defect this session introduced: pydantic serializes an unanswered household as an explicit `"household": null`, and a bare `$ref` to an object type rejects null — so 2.0 briefly shipped a contract its own serializer violated. `meta.address_optional` and `meta.last_scanned` were already nullable for exactly this reason; `household` had broken the pattern. A regression test now asserts that what pydantic **emits** validates, which is the property the fixtures alone cannot check, and a companion test confirms nullability did not widen into accepting a malformed household |
| 2026-09-05 | S6.1 | **HomeModel schema bumped 1.1 → 2.0.** Added: `hearing_impaired`/`vision_impaired` profile tags, optional top-level `household` (tenure, existing_equipment), per-floor `safety_points[]`, `object.secured`, `meta.last_scanned` | The readiness pivot needs four things the contract could not express: who the household is beyond routing tags, where the utility shutoffs are, whether furniture has been secured, and how fresh the scan is. **Deliberately NOT added**: no `safe_room` field (S6.3 computes it from geometry; caching a derived value invites it to go stale against the model it derives from), no checklist state (`ChecklistState` already persists id→done on the iOS side), no peril enum (perils are an engine concept, not a document concept) |
| 2026-09-05 | S6.1 | **Backward compatibility is option (a): a 1.1 document loads as-is and is normalized to 2.0 in memory; nothing is rewritten on disk without an explicit save.** pydantic accepts `{1.1, 2.0}` via an accept-and-normalize validator; `SchemaMigrator` gains a 1.1 → 2.0 re-stamp step | Every 2.0 addition is optional, so this is not a judgement call — it is a verified property: `bungalow.json` with only its version string changed validates against the new schema with **zero** errors, gaining no keys. Normalizing on load means downstream code never branches on version. Rewriting the user's file silently was rejected: persisting an upgrade is the caller's explicit act |
| 2026-09-05 | S6.1 | **`profile.tags` removed from the schema's `required` list** — a pre-existing three-way disagreement fixed while the version was open | The schema marked `tags` required while BOTH mirrors treated it as optional (pydantic `default_factory=list`, Swift `decodeIfPresent ?? []`), and `HomeModel.swift`'s own header comment described it as a defaulted field whose omission still decodes — true of Swift, but such a document was JSON-Schema-invalid. Two of three representations agreed, so the schema was the outlier. Fixed now rather than later because shipping 2.0 with it means the next `tags` mismatch gets misattributed to this bump. Found by the schema-contract-guardian baseline audit |
| 2026-09-05 | S6.1 | **`HomeModel.decoder` parses ISO-8601 with OR without fractional seconds, explicitly**, and `HomeDocument`'s two independent date paths now share that policy | **Correction to this row as first written:** it claimed `.iso8601` REJECTS fractional seconds and that this was therefore a bug fix. The swift-scenekit-reviewer tested it — on the Foundation shipping with this build's deployment target (iOS 26.5), plain `.iso8601` already accepts them, so the original claim was false and nothing was broken. What is kept, and why: the accepted set is now explicit rather than dependent on undocumented platform behaviour the fixture round-trip cannot see a regression in, and `SchemaV2ContractTests` pins the whole accepted/rejected set (fractional and offset forms accepted; naive-without-offset, malformed and empty all `.dataCorrupted`). The genuinely useful half was consolidation: `HomeDocument.decode` built its OWN `.iso8601` decoder — that, not `HomeModel.decoder`, is what runs on load-from-disk and share-sheet import — and the library-listing formatter returned nil on an unparseable `meta.modified`, sinking that home to `.distantPast` at the bottom of the list with no error. Both now route through one shared parser. Encoding stays whole-seconds; the resulting precision loss on re-save is filed in TODO |
| 2026-09-05 | S6.1 | **`escape_plan/Fixtures/*.json` ↔ `schema/fixtures/*.json` byte-equality is now enforced by a test** (`test_the_apps_bundled_fixtures_match_the_contracts`) | The app bundles byte-identical copies because it cannot read outside its bundle — a sound design with no guard on it. They went stale the instant the contract moved, and the app would have shipped v1.1 homes against a v2.0 build with nothing failing. The copies stay; the test is what makes them safe |
| 2026-09-05 | S6.1 | **PROCESS GAP: the schema-guard hook does not fire for Bash-based edits.** `.claude/settings.json` matches `Edit\|Write` only, so `schema/homemodel.schema.json` was modified in this session without the advertised confirmation prompt | `CLAUDE.md` states that editing the schema "asks for confirmation"; that is true only through the Edit/Write tool path. A heredoc, `sed`, or any script writes it silently. S6.1 is the one session explicitly permitted to change the schema so nothing was bypassed in substance, but the guard is porous and should not be trusted as the thing that prevents an unreviewed schema change. Filed as a TODO with its next action |
| 2026-09-05 | S6 arc | **The readiness pivot is APPROVED. It is no longer a proposal.** Scope is now fire + earthquake + severe weather (tornado). The scope locks in `CLAUDE.md`, `.claude/rules/global/conventions.md` and `docs/playbook/01-product-spec.md` were updated in lockstep; `06-pivot-intro.md`'s status line now reads APPROVED | The arc was scoped and parked the same day as a proposal, with `TODO.md`'s first line being the pivot-or-finish decision itself. The owner answered it: pivot. Recorded as its own entry rather than by editing the scoping entry above it, so the sequence stays legible — the arc was written before it was sanctioned, and a future reader should be able to see that the decision was a separate act. **Nothing was built as part of this approval**: no S6 session has been run, no code, schema or test was touched. What changed is authority, not implementation. Two consequences are open and named in `TODO.md`: `docs/demo/script-v1.md` still pitches a fire-only product and its truth ledger cites the old lock, and `docs/START-HERE.md`'s UI/UX handoff is still `active` while the arc now competes with it for the same weeks before Oct 24 |
| 2026-08-25 | narrows_route | **The obstruction analysis now runs whenever the home has any furniture, not only when something is already fully blocked.** `engine.py`'s gate went from `if graph.blocked_openings` to `if graph.blocked_openings or any(floor.objects ...)` | The old gate could never surface a `narrows_route`, by construction: a narrowing is a doorway that is still reachable, so it is never in `blocked_openings`, so the analysis that would have found it was never run. The finding had been computed and discarded since the B3 revamp. The performance intent the gate was protecting is preserved without it — `analyze_obstructions` already skips every room whose object list is empty, so a furniture-free home still costs nothing, and `test_furniture_free_homes_gain_no_findings` pins that the four stock fixtures gained no findings |
| 2026-08-25 | narrows_route | **`Obstruction` grew `target_width_m` — the width a given finding is judged against — kept separate from `required_width_m`, which stays the citable IRC R311.2 code number** | Surfacing the finding exposed a sentence that contradicted itself: "squeezes to 0.90 m — under the 0.81 m a door needs". A narrowing is flagged against the COMFORT width (code + `COMFORT_MARGIN_M` per side = 1.11 m), but `detail` printed the code width, and `suggested_move_m` was measured against it too and so floored at a meaningless 0.05 m. Folding the comfort width into `required_width_m` would have been the smaller diff and was rejected: the margin is our judgement, not a code threshold, and a citation attached to it would then be false. Two fields keeps the corpus number citable and the comparison honest. `target_width_m` is also exposed to the agent's `check_obstructions` tool, which was being handed the same contradiction |
| 2026-08-25 | narrows_route | **A squeeze shares the existing non-severe warning tint rather than getting a third badge colour; the distinction is carried by icon and title ("Tight squeeze")** | START-HERE forbids introducing new colours, and the White Model overhaul exists specifically to undo colour proliferation. A third tier is arguably right — a passable-but-tight doorway is milder than "no second way out" and currently looks identical — but that is a design call for the UI/UX pass, not something to invent unilaterally mid-fix. Flagged in TODO.md rather than decided here |
| 2026-08-05 | Handoff | **The open team handoff is a SessionStart hook (`.claude/hooks/session-start/handoff-banner.sh`) *and* a mirrored block at the top of the root `CLAUDE.md`, both driven by `handoff_status` in `docs/START-HERE.md`'s front-matter.** The hook self-silences when that flag reads `closed`; the README says to close the handoff rather than delete the hook | Every teammate drives this repo through Claude Code, so the reliable place to put "here is what you should be working on" is the session context, not a document someone has to remember to open. Belt and braces on purpose: the hook lands first and unconditionally, but a teammate who hasn't trusted this project's hooks (or who is using a different harness) would never see it, so the same words live in `CLAUDE.md`, which is always read. Neither is *literally* unskippable — both instruct the model rather than forcing it — so the message is short, states the three known traps inline (dry Anthropic credits, SourceKit lying, the 1-in-3 iOS flake), and explicitly tells the assistant to help with whatever the user actually asked rather than hijacking the session. A kill switch that is easier to use than deleting the mechanism is what stops the mechanism from being deleted |
| 2026-08-05 | Camera feel | **Screen→world conversion branches on the camera's ACTUAL projection, read off `SCNCamera`, not on `CameraTuning`.** `CameraRigModel.Projection` is an enum (`.perspective(fovDegrees:)` / `.orthographic(halfHeight:)`) so the call site must name its projection; `OrbitCameraRig.truck` reads `camera.orthographicScale` back rather than recomputing it | `truck` converted points to meters with `metersPerPoint(fovDegrees:)` unconditionally while `CameraTuning.usesOrthographic` is `true` — so under the shipping projection the house did not track the finger, it drifted at a constant wrong ratio. That is the most likely single cause of "panning feels wrong". The failure was silent because the wrong answer still *moves* the house. Reading the scale back off the camera also picks up the portrait aspect widening `apply()` does, which any independent recomputation would have to duplicate and could drift from |
| 2026-08-05 | Camera feel | **The pinch anchor is resolved once at `.began` and cached for the gesture** (`beginPinch` / `pinch` / `endPinch`), replacing a full-scene `hitTest` on every recognizer update | Correctness first, cost second: zoom-toward-anchor is defined against a *fixed* point, so re-resolving mid-pinch let the anchor crawl under the fingers. The cost was 60–120 full-scene hit tests per second against walls, doors, windows, furniture, route tubes and figures on a multi-floor model. `CameraGestureFeelTests` includes a control asserting the two centroids genuinely resolve to different anchors, so the test cannot pass vacuously |
| 2026-08-05 | Camera feel | **`OrbitCameraRig.apply()` writes one `simdTransform` built from the model's own basis, instead of `node.position` + `node.look(at:)`**; every gesture-driven write is wrapped in an explicit zero-duration `SCNTransaction`. Animated paths (`settle`, `recenter`, `focus`, `doubleTap`, `animate`) keep their explicit non-zero transactions | `look(at:)` is a second transform solve per frame, and as a *separate property write* it interpolates on its own curve inside an animating transaction — position and orientation took different paths and the camera swam through an arc between poses. Gesture writes also inherited whatever ambient transaction was open (SceneKit's implicit default is 0.25 s), landing a frame or more late. The basis is provably identical to what `look(at:)` produced with the default world up (+Z = `toCamera`, +X = `right`, +Y = `up`), which is what the `PlaybackCameraController` tour handoff depends on — `testTransformMatchesWhatLookAtProduced` pins it against a real `look(at:)` node, and the 80° pitch clamp keeps it out of the gimbal case |
| 2026-08-05 | Camera feel | **`SCNView.rendersContinuously` has exactly two inputs and they are OR'd**: the scene's own (`UnifiedSceneController.wantsContinuousRendering` — route pulse, playback) and the camera's (gesture in flight, inertia running, or an explicit spring animation still inside its duration). No caller writes `scnView.rendersContinuously` directly any more | They were the same property written from two places that clobbered each other: HouseScreen set it true for the route pulse, then the rig's sink set it false the moment inertia stopped, silently freezing the pulse. Extending the camera's half to cover the *whole gesture* is the fix for the one-frame-behind drag; extending it to cover explicit animations fixes a separate invisible bug — the rubber-band spring-back ran as an `SCNTransaction` interpolation that nothing on a static scene ever asked to draw, so it SNAPPED |
| 2026-08-05 | Camera feel | **One camera-gesture implementation, `Renderer/CameraGestureDriver.swift`, shared by both 3D hosts.** `UnifiedSceneView` was NOT deleted — DrillScreen mounts it — it was made to call the same driver. The hosts keep only what is genuinely theirs: which recognizers exist, and (editor only) whether a one-finger pan is an edit drag | There were two gesture models for the same house and only one worked. `UnifiedSceneView` wired no `beginOrbit`/`endOrbit`/`settle` and never assigned `rig.onChange` or `rig.continuousRenderingSink`, so the drill surface had no inertia, no axis-lock reset, no spring-back, and any frame the rig drove itself was computed and never drawn. Divergence regrows every time either file is edited, so the arbitration, the gesture lifecycle and the release behaviour had to stop being per-file |
| 2026-08-05 | Camera feel | **Two-finger input is pan and zoom and never orbits, and the suppression LATCHES** — lifting back to one finger does not resume orbiting. Stated once, purely, in `CameraRigModel.PanArbiter`, and re-evaluated on every event rather than latched at `.began`. Release behaviour (inertia / spring-back) is applied by whichever camera gesture ends LAST | Both hosts latched `numberOfTouches >= 2` at `.began` only while pinch and pan recognized simultaneously: start one finger, add a second, and the pan kept *orbiting* at the two-finger centroid velocity while the pinch drove zoom — the camera fought itself. Not re-latching on the way back down is deliberate: handing a gesture to a different transition halfway through is the same bug in a slower costume. The last-one-out release rule exists because a two-finger manipulation has both recognizers live, so whichever finished first used to fire inertia while the other finger was still on the glass |
| 2026-08-05 | Camera feel | **Pan carries exit velocity on the same 0.25 s half-life as orbit**, decaying against the soft (rubber-banded) clamp so coasting into the bounds springs back rather than stopping against a wall | Orbit coasted and pan stopped dead — two different feels for the same house from the same finger. Sharing the decay curve rather than picking a second one is the point |
| 2026-08-05 | Camera feel | **Movement limits loosened: pan apron `0.25 → 0.6 ×` extent, zoom floor `0.8 → 0.35 ×` extent — and BOTH `isOffHome` thresholds had to follow** (drift `0.15 → 0.35`, near distance `0.7 → 0.5`). Orbit rate `π → 0.6 π` per view height; axis-lock sample `12 → 20` pt, now one shared constant driving both the decision and its trigger | A quarter-extent apron engaged the rubber band almost as soon as the pan started, reading as "I can't move the house"; a 0.8 floor is barely closer than the 2.2 opening shot, so a single room could never be inspected. The `isOffHome` follow-through would have been a bug if missed: the chip fired above 0.15 drift *against an apron of 0.25* (over half the pan range) and below 0.7 distance *against a floor of 0.8* (i.e. on any zoom-in at all), so loosening the limits alone would have made the recenter chip permanent. **These are a starting point tuned by reasoning and by test, NOT by feel on a device** — the orbit rate and the axis-lock threshold interact and both need a human hand |
| 2026-08-05 | Camera feel | **Frame-time profiling (#10) was not done and nothing was changed on guesswork.** MSAA 4X, camera SSAO and the route pulse shader all still run during gestures. The one part that needed no hardware WAS fixed: `rendersContinuously` was pinned on forever whenever a route plan existed, including under Reduce Motion where `RouteOverlay` installs neither the pulse shader nor the repeating action | There is no target device available, and a simulator frame time on an M-series Mac does not answer "does an iPhone hit 60 fps". Dropping MSAA during a gesture would also visibly change the scene, which the brief explicitly ruled out. Reporting an unmeasured tuning as done would be worse than leaving it open — the levers are isolated behind `CameraGestureDriver.onPhaseChange` and the next action is recorded in TODO.md. The Reduce Motion case is unambiguous waste: a completely static scene rendering at 60 fps forever, on the setting most likely to be chosen for battery and thermal relief |
| 2026-08-05 | Fire-origin sim (lane A) | **`/evacuate` is deterministic engine code, never an AI call.** New `backend/app/routing/hazard.py`: the hazard walks the same S1.1 `NavGraph` that `/routes` builds, and every occupant path is Dijkstra through the same `_edge_cost`, so S3.4 profile constraints apply unchanged. `engine.py` was **not** modified — the one thing its Dijkstra cannot do (ban room nodes) is a thin sibling search in `hazard.py` that reuses `engine._edge_cost` / `_route_from_search` / `_SearchResult` / `_openings_by_id`. `POST /evacuate` behind the existing bearer token, thin wrapper like `/routes`, 404 on an unknown origin room | The headline feature is "tap a room, watch every route re-solve around the fire". If that re-solve were an AI call, the project's entire architectural claim collapses — and the judge question "isn't this an AI wrapper?" would have no answer. Reusing the one graph rather than building a parallel topology is also what keeps the blocked-opening and egress-threshold work automatically true of the simulation. Importing four private names from `engine.py` is the acknowledged cost; the alternative was widening `engine.py`'s public signatures mid-session while another lane read them |
| 2026-08-05 | Fire-origin sim (lane A) | **Every number in `hazard.py` is an animation parameter, not a corpus threshold**, in two separately-documented constant blocks whose docstrings say so outright. Spread: `ROOM_SPREAD_DELAY_S` 45 s per opening crossed, `STAIR_SPREAD_DELAY_S` 30 s per flight. Occupants: `WALK_SPEED_MPS` adult 1.20 / child 0.90 / elderly 0.75 / wheelchair 0.85 / pet 1.10 / unknown 1.20 m·s⁻¹, `STAIR_RUN_M` 4.0, `STAIR_SPEED_FACTOR` 0.5, `DOOR_CROSSING_TIME_S` 2.0, `WINDOW_EGRESS_TIME_S` 15.0. **No constant was tuned to change an outcome** — these are the first values written | Constant-rate spread is a deliberate simplification: real fire growth is exponential, geometry-dependent and dominated by fuel load and ventilation, none of which this app models. The documentation discipline is copied from `routing/profiles.py`, which had the same problem with its penalty magnitudes. Stating the simplifications (doors always open to the hazard; occupants start at t=0 with perfect route knowledge and no detection delay) is what makes `is_illustrative: true` an honest flag rather than a disclaimer nobody earned. `WINDOW_EGRESS_TIME_S` being categorically larger matters: the timeline must never make a window "second way out" look equivalent to a door |
| 2026-08-05 | Fire-origin sim (lane A) | **Hazard climbs stairs; hazard never leaves the building; a blocked opening also blocks the hazard.** Stair spread is its own constant and is modelled symmetrically (downward as fast as upward). `exit_crossing` edges are never traversed, so spread cannot go room → EXTERIOR → another room (asserted by test) | Heat and smoke rise and a stairwell is the chimney — a downstairs fire must be shown threatening upstairs bedrooms, and that is the one piece of qualitative fire behaviour worth honouring. Symmetry is wrong and is documented as wrong. The blocked-opening consequence is also wrong in reality (a wardrobe stops a person, not smoke) and is accepted knowingly: it falls out of reusing the one graph, which is the larger win |
| 2026-08-05 | Fire-origin sim (lane A) | **Igniting the room with the only exit produces an honest empty result, never a fabricated path.** Per occupant the engine iterates to a fixpoint — solve, time the route, ban every room the hazard makes untenable strictly before that occupant clears it, re-solve. If nothing survives, the occupant gets the **existing** `no_viable_route` `RouteFinding` on a new additive `timeline.findings` and **no track at all**. Verified on `apartment.json` (single exit `d_entry` off `r_hall`, all three windows fail egress): igniting `r_hall` returns `tracks: []` plus one finding. `overtaken_by_hazard` is reported truthfully and is never suppressed; the occupant's own start room is never banned, so someone standing in the ignited room still gets a track — flagged | Inventing a new failure mode would have meant a new enum case in three places; the honest negative result the engine already had is exactly right. Drawing a figure walking through fire to keep an animation comfortable is the single worst thing this feature could do, so the flag is load-bearing and the UI is required to surface it |
| 2026-08-05 | Fire-origin sim (lane A) | **A home with no profiles synthesizes one adult occupant per room** (`occupant.<room_id>`, name = room name, floor-then-room document order, default constraints). A home *with* profiles gets exactly one track per profile from `bedroom_room_id` and nothing is synthesized | `schema/fixtures/bungalow.json` has an empty `profiles` list, as does every freshly scanned home. Returning an empty animation for the most common starting state would make the headline feature look broken on first run. Deterministic and clearly labelled as a demo affordance in the module docstring |
| 2026-08-05 | Colour system (lane C) | **Cool hues are reserved for routes; warm hues are reserved for hazard.** Primary route `#FF5A1F` → `#123FB0`, secondary `#FF9E6E` → `#4180D4`; hazard family reserved as `hazardCore` `#F97316` / `hazardEdge` `#B91C1C` / `hazardHalo` `#FDBA74`. Measured separation: ΔL 0.145 / 0.111 / 0.256 and printed greys 74 / 127 / 154 | Adding a fire-origin visualization put a second coloured system into a scene designed around exactly one. Orange route plus red hazard is the textbook deuteranopia collision, and "the way out" versus "the thing that will kill you" is the one distinction this app cannot afford to blur. Blue↔orange is the axis that survives deuteranopia, protanopia *and* tritanopia, because it separates on the blue-yellow channel rather than the red-green one. Routes took cool (the calm instruction), hazard took warm (the alarm). **The renderer lane must take its hazard colours from `DollhousePalette`'s reserved warm family and must not introduce a cool hazard tone** |
| 2026-08-05 | Colour system (lane C) | **Route hierarchy is encoded three times over and hue is only one of them**: primary is a solid tube and secondary is real dashed *geometry*; meaningful waypoints carry sequential numbered chips; and the three systems are separated by ≥0.08 relative luminance and ≥20 printed grey levels, asserted with real numbers in `escape_planTests/RouteEncodingTests.swift`. The dash moved out of a fragment shader into `RouteGeometry.dashes` (0.45 m mark / 0.28 m gap by arc length) | A shader dash cannot be unit-tested, and its period lived in UV space so the apparent dash length changed with route length. Geometry is testable, and the PDF export lane — which has no fragment shaders — now consumes the same mark list, which is why the printed black-and-white plan is legible at all. The numbered stops are what carry route *direction* once Reduce Motion drops the travelling pulse, which is why they are a requirement rather than a nicety |
| 2026-08-05 | Evacuation UI (lane B) | **The "Illustrative" disclaimer's *presence* is unconditional; the server's `is_illustrative` flag only selects the wording.** It lives in the scene card's floating overlay, so it survives immersive mode and cannot be scrolled past; it is conditioned solely on a timeline being loaded. Ignition reuses the editor's existing room selection (select, then Ignite) plus a peer room-list picker, rather than adding a hit-test hook to `UnifiedSceneController` | Gating a safety caveat on a server boolean makes it deletable by a backend bug. Two-step ignition also means a destructive-sounding action is confirmed rather than fired by a stray tap, and the room-list picker is a genuine peer path rather than an accessibility bolt-on — a VoiceOver user cannot reliably tap a 3D surface. Any accepted edit clears the simulation, on the same reasoning that drops the route plan: a timeline solved against the old model is a picture of a house that no longer exists |
| 2026-08-05 | Drill mode (lane E) | **Only "twice a year" is corpus-backed; every other practice cadence ships as explicitly-unclaimed user preference.** The corpus states it twice independently — `escape-planning-nfpa.md` `[cite: nfpa-escape-planning]` and `home-fire-escape-redcross.md` `[cite: redcross-escape-plan]` — and both cite chips render next to the number. `PracticeCadence.isCorpusBacked` is true for that value and nothing else, and a test reads the real corpus markdown off disk so the app's number cannot drift from its source. **The notification body states no interval at all** (a banner has no room for a citation), also test-enforced | Offering only twice-a-year was considered and rejected: households legitimately want to practise more often, and refusing the option does not make the app more grounded — labelling it does. The rule "no source, no number" is absolute, so the alternative was to attach a safety claim to an interval nobody published |
| 2026-08-05 | Drill mode (lane E) | **The modeled time-to-exit comparison may come only from `OccupantTrack.egress_time_s`.** Deriving one from `Route.length_m` ÷ an assumed speed was explicitly rejected. With no timeline the comparison says so plainly. The framing is always "how your practice compares to the modeled walk", and a test asserts no branch can contain survival / pass / fail / danger vocabulary. Practice log is a per-home schema-versioned JSON document (`<Documents>/DrillLog/<home_id>.drilllog.json`); abandoned drills are recorded, not discarded | A length-over-speed number would be a fabrication wearing the costume of a measurement — and the whole point of `is_illustrative` is that even the engine's own number is a drawing of a route, not a prediction. Abandoned drills are kept because hiding them flatters the household and makes "best time" meaningless; `best` counts completed drills only, so a five-second walk-away can never become one. The log cannot live in the HomeModel because that schema is frozen and its documents *are* the export format |
| 2026-08-05 | Printable plan (lane F) | **The printed plan is redrawn in 2D from the schema, never a screenshot of the SceneKit scene**, and the **meeting point is user free text in `UserDefaults`** (`export.meetingPoint.<home_id>`), not a schema field. `EscapePlanExporter` holds only a `HomeDocumentStore` and a `RoutePlanCache` and has no `APIClient`, so it is offline by construction | A snapshot is a raster of a perspective view with translucency and soft shading — everything that survives worst on a black-and-white laser printer, which is the exact device this artifact targets. Redrawing gives vector output, a deterministic result tests can assert on, and full control of the greyscale encoding; geometry conventions are borrowed from `DollhouseGeometry` so print and 3D cannot disagree about where a door is. A `meeting_point` schema field would require a `schema_version` bump plus lockstep pydantic and Swift changes for a string only the printout consumes — the engine does not route to it and the agent does not inspect it. Consequence: it is device-local and a duplicated home starts blank |
| 2026-08-05 | Accessibility (lane D1) | **Chrome colours no longer bridge `DollhousePalette`, and `Theme.supporting` is no longer `Color.secondary`.** 15 real WCAG AA failures fixed across twelve screens; worst was white on the dark-mode accent in a chat bubble at **2.71:1**. `Color.secondary` composites to ~#8A8A8E on white — **3.44:1** — a genuine failure on the caption text every screen uses it for. WCAG relative-luminance and contrast maths now live in `Theme.swift` with 14 assertions in `escape_planTests/ThemeContrastTests.swift`, including two negative tests locking the regressions shut. The score ring is *abandoned for a bar* above `.accessibility1` rather than shrunk; decorative hero glyphs are hidden and dropped at AX sizes rather than scaled | Deviating from the platform's own `secondaryLabel` is deliberate: a fire-safety app whose citations are unreadable is worse than one that looks slightly off-system. The consequence of unbridging chrome from the renderer palette is that a renderer colour change no longer propagates automatically — `ThemeContrastTests` is the replacement guard, and it is a better one, since the old bridge propagated a value that failed AA. A ring cannot grow with 310% text without clipping the number or eating the screen, and `minimumScaleFactor` would defeat the point of asking for large text |
| 2026-08-04 | S1.6 (defect) | **Anthropic SDK failures map to a labelled 502/503 via one app-level exception handler**, not per-endpoint `try/except`. `@app.exception_handler(anthropic.APIError)` in `main.py`: **503** when the same request may work shortly (`RateLimitError`, `APIConnectionError`, status 500/502/503/529), **502** when an operator has to act (no credit, bad key). Detail is the API's own `error.message` sentence (via `_anthropic_message`), not the SDK repr — `exc.message` is `"Error code: 400 - {'type': 'error', ...}"`, fine for a log and useless in a banner. Full exception logged server-side with `exc_info`. 6 tests in `backend/tests/test_api_ai_errors.py` (suite 258 → 264) | **Found by testing the endpoints against an account whose credit balance had run out.** Each AI module raised its own domain error (`GroundingError`/`AgentError`/`BuilderError`) for the *missing-key* case only — the `client.messages.create` calls themselves were unguarded, so a dry account, a rate limit, or an API outage escaped as a bare `500 Internal Server Error` with no body the app could act on. That is precisely the failure mode a live demo hits. App-level over per-endpoint because it covers `/explain`, `/analyze`, `/build`, `/score?include_recommendations`, the `/chat` router, and anything added later, in one place. The 502/503 split exists so the app can choose between a retry affordance and an honest "AI unavailable" banner. The deterministic endpoints are untouched by design and a test pins that (`/routes` + `/score` still 200 while the AI is dead) |
| 2026-08-04 | S3.5 (defect) | **`ScoreScreenshotUITests` waits on the "How it's scored" section header, not `navigationBars["Score"]`** | `ScoreScreen` sets `.navigationTitle(breakdown?.home_name ?? "Score")`, so "Score" is the **loading** title and is replaced by the home name the instant data lands — the assertion failed on exactly the runs that *worked*. Three earlier attempts were written off as UI-automation flakiness plus a 99%-full disk; the disk was real, but this assertion would have failed forever regardless. Caught because the run that "failed" still wrote a screenshot showing a perfectly rendered screen. Test now passes; evidence committed at `docs/evidence/score-screen-2026-08-04/` |
| 2026-07-27 | S3.5 (defect) | **Added deterministic IRC R310 egress-window checklist items** (`egress.window.<opening_id>`, category `egress`, `scoring: false`, cited `irc-2021-r310`), generated by `checklist.egress_window_items()` calling the existing `routing.egress.check_egress`. `build_checklist` and `compute_score` take an optional `thresholds` argument (omitted → no egress items, so pre-existing callers are unaffected); `/score` passes the thresholds it already loads for routing. Scoped to sleeping rooms, which is where R310 requires an emergency escape and rescue opening. 4 new tests (suite 39 → 43 in `test_scoring.py`, 238 → 242 overall); the shared `_scored` helper now passes thresholds so the tests see the checklist the endpoint actually returns | **Found while diffing a duplicate S3.5 implementation against this one:** on `twostory.json` with no `/analyze` run, the checklist was 9 items and *none* mentioned the planted kids'-bedroom window (0.4 m wide vs the 0.508 m minimum — a window a child cannot climb out of). The whole-house router raises no RoutePlan finding for it (its secondary route legitimately leaves by a different exit — see the 2026-07-16 S3.2 row), so the danger surfaced only if someone happened to run the agent. The check costs nothing and needs no AI. Non-scoring for the same double-counting reason as route findings. |
| 2026-07-27 | process | **A duplicate S3.5 backend was built from a clone that was 59 commits behind `origin/main`, because the session was planned off `docs/tracker/board.md` without fetching first.** The board was 11 days stale and still listed S3.5 as BLOCKED; it had in fact been merged 2026-07-16, iOS included. The duplicate was discarded (kept locally on branch `s35-preparedness-score` only, never pushed to `main`); only the genuine gap above was salvaged. **Rule going forward: `git fetch` before trusting any tracker file to describe current state** — committed docs describe the commit they live in, not the remote | Tracker files are evidence, not live state. This is the same class of failure the 2026-07-23 tracker-consolidation note describes ("the tracker contradicted itself in nine places because this was a habit rather than a mechanism"), one layer up: the mechanism can't help if the clone predates it. |
| 2026-07-23 | Lane C (S3.2/S3.5 defect) | **Agent findings now carry a stable content-derived `id`** — sha256 of severity + sorted room_ids + a normalized slug of the finding text, 12 hex chars, computed by `app.scoring.findings.finding_id()` (lives in scoring so the id scheme never depends on the Anthropic SDK; the agent imports it). Stamped server-side in `_validate_findings` — anything the model puts in the field is overwritten. `checklist.py` keys done-state on `agent_finding.<id>` with a positional `agent_finding.<index>` fallback for id-less findings. **Migration story: old positional checkmark keys are simply orphaned** — a stale checkmark was already the status quo failure mode, so no migration shim. iOS untouched: `AgentFinding` decodes with explicit CodingKeys and ignores the new field; `/score` requests don't send findings today, so the fallback path is what runs until iOS threads the id through (TODO(integration) recorded in TODO.md). A new `test_finding_lockstep.py` pins the two hand-synced `Finding` classes (agent vs scoring) to identical field names/types/requiredness (documented exception: `evidence`), closing the no-drift-test defect | Re-analysis reordering no longer mis-keys checkmarks; content addressing means wording changes orphan (not mis-assign) a checkmark, which is the safe failure. Server-side stamping keeps ids out of the model's hands |
| 2026-07-23 | Lane C (S3.1/S3.2/S3.3 live) | **First-ever live runs forced three AI-layer changes for `claude-sonnet-5`.** (1) `temperature=0.2` removed everywhere — the API now rejects non-default sampling params with a 400 ("deprecated for this model"); output stability rests on schema-enforced tool use + server-side citation validation, superseding the "temperature low" rule in `.claude/rules/vendors/anthropic.md`. (2) `thinking={"type": "disabled"}` set explicitly — sonnet-5 runs adaptive thinking when the param is omitted, which blew the S3.2 <60s budget (71s measured; ~40s after). (3) `/explain`'s tool def gained `strict: true` plus a ValidationError retry branch after a live response emitted a stray `action_2` field that crashed `model_validate` unhandled (would have been a 500). Also: with thinking off the agent fabricated evidence refs (`check_egress:w_kids` instead of literal `toolu_` ids), gutting results via validation — fixed with tightened evidence instructions and a bounded resubmit loop (`MAX_SUBMIT_RETRIES=2`): an invalid submission is bounced back as an error tool_result instead of silently returning a gutted result. S3.1 explain goldens were captured before the thinking change; their asserts are structural and pass under the final config | Live behavior is the only real test of an AI layer; all four issues were invisible to the scripted-client suites. The resubmit loop keeps "zero findings without evidence" enforced while no longer punishing recoverable formatting mistakes |
| 2026-07-23 | Lane C (S3.1 acceptance) | **The playbook's "p95 /explain < 6s with caching" acceptance is unmet and unattainable in the current shape — recorded honestly, not fudged.** Measured on sonnet-5 with cache hits confirmed on every request (read=9450, created=0): warm mean 26.3s, p95 30.2s over 10 samples; haiku-4-5 comparison ~18.5s warm. Latency is output-bound (~1,600–2,500 output tokens for a whole-home 7-room explanation), so caching cannot fix it. Needs a team decision: terser output, per-room explain calls, streaming UX, a faster model, or a revised target (tracked in TODO.md). Separately, `test_ai_live`'s 30s per-request sanity ceiling flaked on normal variance (23–50s observed, one transient 95s garbled-generation glitch) and was raised to 90s with the measurements documented inline — it is a pathology guard, not the p95 acceptance. The playbook-mandated <60s agent bound is untouched (39.9–42s observed post-fix) | Passing the gate by weakening the acceptance silently would be worse than recording the miss; the numbers and levers are now in one place for the team to decide |
| 2026-07-23 | S4.4 (Lane B) | **Shipped default backend is the deployed Render URL.** `APIClient` now defaults `baseURL` to `https://escape-plan-backend.onrender.com` (the old `developmentDefaultBaseURL` constant is gone; `localDevBaseURL` = `http://localhost:8000` remains reachable via a DEBUG-only "Developer" section in Settings). The shared bearer token is **not in source or git**: `APIClient` reads an optional bundled `escape_plan/BackendConfig.local.json` (`{"bearer_token": "..."}`), which is gitignored — a teammate drops the file in before archiving a demo build and the synchronized project group bundles it automatically; without it the token is empty and Settings prompts. UserDefaults overrides (Settings edits, UI-test launch args) still win over both defaults | A fresh install previously talked to nothing until both URL and token were typed by hand — a dead demo. The URL is public knowledge (committed in docs); the token stays secret via the gitignored bundle-resource pattern, which needs no pbxproj surgery (xcconfig + custom Info.plist keys would) while Lane A has the project open |
| 2026-07-23 | S4.4 (Lane B) | **Routes render x-ray (always on top).** Route tubes, exit glows, stair stubs, and the new start marker set `readsFromDepthBuffer = false` + renderingOrder above the walls'. Before-screenshots proved the old rendering invisible: stacked double-sided translucent walls (4-6 surfaces from a three-quarter camera) alpha-dimmed the 6 cm tubes to nothing — the demo's money shot showed a gray box with a green door. Also: primary tube radius 0.06→0.10, route lift 0.22→0.30, camera tour eased (`easeInEaseOut`), tour lens widened to 65°, tour gaze aimed down at the path | The route is the one thing the screen exists to show; physical correctness (occlusion) loses to legibility here, matching how the room labels and warning badges already rendered through walls |
| 2026-07-23 | S4.4 (Lane B) | **Launch screen stays the system-generated blank** (`INFOPLIST_KEY_UILaunchScreen_Generation`). Customizing it requires either a storyboard file reference or a physical Info.plist — both pbxproj edits — while Lane A concurrently holds the project open; a fake in-app splash was rejected as an anti-pattern (delays first interaction). Left as an integration-window item in TODO.md | Lowest-value item on the S4.4 list vs. the only one needing shared-project-file surgery mid-parallel-lanes |
| 2026-07-23 | S4.4 (Lane B) | **App icon is generated, not designed externally**: `scripts/make_app_icon.swift` (CoreGraphics, run with `swift scripts/make_app_icon.swift <outdir>`) produces the 1024px light/dark/tinted PNGs (night-blue gradient, white house outline, green doorway, ember route arrow). No new dependency; `tools-used.md` unchanged | Zero-dependency way to a real icon; the motif is the product (house + route out the door) |
| 2026-07-23 | Lane A (S2.1/S2.2 completion) | **`HomeModelStore` and `UndoStack` are `@Observable`; every manual `revision += 1` deleted.** `import Observation` in `Editor/Core` (Foundation-family — the core stays UIKit/SwiftUI-free; `tools/editorcore` platform floor bumped macOS 13→14 for the macro). `EditorScreen`/`EditorSceneView` re-render off the store's own `model`/`selection`/`activeFloorId` and the undo stack's `canUndo`/`canRedo`; `EditorSceneView` receives `model`/`selection`/`activeFloorId` **by value** so the representable's diff actually fires `updateUIView`. Kills the whole stale-render class from the 2026-07-22 acceptance: toolbar now enables Add Stairs on plain tap-selection, redo works on the first tap, and the stale yellow highlight is repainted because selection changes reach `updateUIView` | The revision counter was a hand-maintained shadow of "did anything change" and every missed bump was a UI bug. Observation makes the store itself the signal — a forgotten call site is no longer possible |
| 2026-07-23 | Lane A (openings) | **Opening authoring: `addOpening`/`deleteOpening`/`setOpeningKind`/`setOpeningWidth` + pure `OpeningPlacement`.** Interior-vs-exterior is **derived from geometry at creation time, never asked**: another room's edge collinearly overlapping the opening's span on the host wall ⇒ interior (`room_ids = [host, neighbor]`), else `[host, EXTERIOR]` (a door there is an exit; a window there is the fixtures' egress-window encoding). Editor defaults per kind — door 0.9×2.0 m sill 0, window 1.0×1.2 m sill 0.8 — copied from the hand-authored fixtures (editor conveniences, NOT safety guidance; egress viability stays the backend annotator's). Kind switch jumps height/sill to the new kind's defaults, keeps width+span. **Drags never re-derive `room_ids`**: scan-converted homes may encode adjacency their footprints can't reproduce exactly (RoomPlan rooms don't share wall lines), so normalizing on drag could silently disconnect a scanned interior door. New validation closes the S2.2 known gap: same-edge openings must not overlap in t (all three fixtures audited clean before adding). Placement UI is a one-shot tool (Add Door/Window → tap a wall → `HitTesting.wallPoint` → dispatch), with the new opening auto-selected and an Interior/Exterior readout in the selection inspector | Deriving adjacency is the only design that never asks the user a question the geometry already answers, and creation-time-only is the conservative choice for scan data. The overlap check was flagged 2026-07-22 as the missing backstop for `dragOpening` sliding a door through another |
| 2026-07-23 | Lane A (bug 1) | **`HomeModelPersisting` conformer is a new `EditorSession` (@Observable: store + undo stack + `wasDeletedExternally`), not `HomeModelStore` itself** — the doc comment's suggestion would have put app-lifecycle state in the pure core, and the store can't clear an undo stack it doesn't own. Protocol is now `@MainActor` (its only caller, `HomeLibrary`, already is). `EditorScreen` registers the session as `library.editor` on load, unregisters on disappear, and dismisses when `wasDeletedExternally` flips; `UndoStack.reset()` added. Note the seam only connects screens sharing a `HomeLibrary` instance (HomeScreen→Editor push); the Editor *tab*'s standalone screen has no library and stays unregistered | The session wrapper keeps EditorCore pure while giving the seam a home; deleting a home's undo history on external delete is mandatory because those snapshots would resurrect the deleted document |
| 2026-07-23 | Lane A (evidence) | **Manual-build acceptance driven by an env-gated UI test (`ManualBuildRecordingUITests`, `TEST_RUNNER_MANUAL_BUILD=1`) + `simctl recordVideo`, following the S4.1 golden-path recording idiom.** The test inverts the editor camera's deterministic ortho framing (bbox + 1.5 m padding, `scale = max(w,d)/2`) to convert floor-plan meters into taps; `SCNView` gained accessibility id `editor.scene` for it. Rooms are joined by dragging corners onto neighbors (vertex snap lands them exactly — also live proof of drag+snap through the wired bridge). Evidence: `docs/evidence/lane-editor-manual-build{.mp4,-home.json,-routeplan.json}` — recording transcoded to 0.5 MB (ffmpeg, local tool only, not a project dependency); `/routes` returned primary+secondary for all 4 rooms | Repeatable by anyone with the simulator + local backend, and the recording shows the two on-camera bugs (stale toolbar, second-tap redo) actually gone |
| 2026-07-22 | S3.3 fix + S3.2 prep | **Closed the 2026-07-22 "S3.3 (found, not fixed)" finding: `/chat` now returns a deliberate 502 when `ANTHROPIC_API_KEY` is unset.** `api_chat.post_chat` catches the base `GroundingError` (raised by `service._client()`; NOT a parent of `ChatGroundingError` — they're sibling `Exception` subclasses) in the same 502 clause, mirroring `/explain`/`/analyze`. Regression test `test_chat_endpoint_maps_missing_key_grounding_error_to_502` verified red-on-old-code/green-on-fix. Also wrote `backend/tests/test_agent_live.py` (marked `live`, key-skipped), the missing S3.2 live acceptance suite the board flagged: encodes the playbook criteria (apartment `d_entry` single-exit, twostory `w_kids`/`r_bed_kids`, zero findings without trace-resolving evidence, <60s) with `test_ai_live.py`-style first-run golden snapshots (`tests/golden/agent_<case>.json`). Backend suite 197 green; the live run itself remains key-blocked for P1's key session | The 500 was an accident of exception hierarchy, not a decision — the iOS client already treats all 5xx alike, but the JSON 502 matches the other AI endpoints and the session brief's assumption. Writing the live suite now means P1's key session is pure run-and-review, no authoring |
| 2026-07-22 | S5.1 | **Script + storyboard promoted to v1 (`docs/demo/script-v1.md`, `storyboard-v1.md`; v0 files marked superseded, kept).** Run ahead of the S4.1 prerequisite by explicit direction (second approved instance of the 2026-07-16 deviation) — the build state now supports it: S2.1–S2.3/S3.2–S3.5 code-done resolved most of v0's `[PENDING]` tags to true-now, tracked per claim in a truth-ledger appendix. Three content rulings: (1) Beat 2's unsourced "eighty percent" reworded to "most of the way there" per the v0 honesty note — S1.5 never produced a measured number; (2) Beat 5 locked to the build's actual semantics — the kids'-room finding is "window too small" via the agent's `check_egress` (engine's `no_secondary_egress` doesn't trip there), and the on-camera profile switch is `mobility_limited`/`elderly` only (child is a tested no-op); (3) the storyboard now **defines the canonical b-roll path contract** (`docs/demo/broll/s<xy>-<shot>.mov`) that concurrent capture work delivers into — v0's "first person to record it creates it" is now binding names. VO: 436 words ≈ 2:54 at 150 wpm. Acceptance (team table-read < 3:15, P1 tech-accuracy pass) deliberately left unchecked — needs humans | The doc-only lane could run while device/key sessions proceed elsewhere; every judge-checkable claim now cites either `sources.json` or a decisions.md entry, and the path contract lets b-roll land without coordination |
| 2026-07-22 | integration (S2.2×S2.3×S3.3×S3.4×S3.5) | **Closed S3.4's `TODO(integration)`: PlanScreen now has a "Who" profile picker.** Selecting a family member calls the existing `fetchRoutes(home:profileID:)` seam S2.3 had already left in place, and jumps the room selection to that profile's `bedroom_room_id`; "Everyone" (nil) restores the unconstrained whole-house plan. Switching homes resets the selection. The client still sends only `profile_id` — tag→constraint translation stays server-side, and nothing client-side re-derives a route | The two halves were built in parallel against an agreed seam, so joining them was wiring, not new logic. Auto-selecting the profile's bedroom makes the Grandpa-vs-Maya acceptance a one-tap demo instead of a two-step one |
| 2026-07-22 | integration | **Fixed `DollhouseRendererTests.testBundledFixturesMatchSchemaFixtures`**, failing since the 2026-07-16 model-layer unification: it compared `schema/fixtures/*.json` against `escape_plan/Resources/Fixtures/`, a directory that merge deliberately deleted (the fixtures moved to `escape_plan/Fixtures/`). Repointed the path; all three fixtures are byte-identical, so the guard passes and is live again. Full `escape_planTests` suite is now green with no known failures | The test is a real drift guard between the canonical schema fixtures and the bundled app copies — leaving it red normalized a failing suite and would have hidden actual drift. Two lanes independently reported it as "pre-existing and unrelated," which is exactly how a stale failure survives |
| 2026-07-22 | S2.2 | **`dragOpening(openingId:t:)` action shape**: `t` is the opening's requested midpoint position (normalized [0,1]) along its host wall; the `HomeModelStore` reducer derives `t0`/`t1` from `t` and the opening's existing `width_m`, clamps into `[0,1]`, and writes back to `wall_segment`. No `SnapEngine` involvement — snapping is a 2D point/delta concept (vertex/wall/axis/grid) with no analogue for a 1D walk along a fixed wall; `EditorValidation.validateOpening` (unchanged) is the real backstop. **Known gap, not closed here**: no pairwise opening-overlaps-opening check exists anywhere in the codebase (pre-existing, not introduced by S2.2) — `dragOpening` can slide one door through another's t-range | Keeps "how wide is this door" logic in one place (the reducer), matching how `dragEdge` already owns its own delta math. Flagging the overlap gap rather than silently adding unrequested validation scope |
| 2026-07-22 | S2.2 | **Stairs authoring**: added `addStairs(fromFloorId:fromRoomId:toFloorId:toRoomId:footprint:kind:)` and a companion `deleteStairs(stairsId:)` (not one of the three acceptance criteria, but the minimum way back from a bad placement — mirrors `deleteRoom`'s guard-then-remove shape). The reducer only checks that both floor/room ids resolve; `EditorValidation.validateStairs` (unchanged) is the real gate (from/to distinctness, footprint simplicity, provenance). **No geometric containment check** that `footprint` sits inside the `from`/`to` rooms — schema-valid but visually nonsensical placements are accepted. Minimal UI: select a room on the active floor, tap "Add Stairs," pick a room from the sheet listing rooms on the floor immediately above; footprint defaults to a 1m×1m square at the `from` room's centroid; `kind` hardcoded to `.straight` (no kind picker) | "Validated" per the acceptance criterion means "passes the existing whole-model validator," not "is geometrically sane" — containment was out of scope for this session. `deleteStairs` was cheap enough to include so `addStairs` isn't a dead-end action |
| 2026-07-22 | S2.2 | **Undo/redo**: new `UndoStack` (`Editor/Core/UndoStack.swift`), built on `HomeModelStore.Commit`'s existing before/after snapshots via `onCommit`. A continuous drag (`dragVertex`/`dragEdge`/`dragRoom`/`dragOpening`, `isContinuousDrag == true`) fires `dispatch` on every gesture `.changed` event — coalescing by matching the action's subject (same room/opening id) can't distinguish "still dragging" from "let go and immediately started a new drag on the same thing," so `SceneKitEditorBridge.handleDrag` explicitly brackets the gesture instead: `.began` calls `undoStack.beginCoalescing(snapshot:)` (captures the pre-drag state), every `.changed` still autosaves per-step as before, `.ended`/`.cancelled`/`.failed` calls `undoStack.endCoalescing()`, which pushes exactly one `Commit` for the whole gesture (or nothing if nothing actually changed). Non-continuous actions push one undo entry per dispatch, unchanged. `replaceModel` (used by undo/redo) deliberately never fires `onCommit`, so `EditorScreen`'s `undo()`/`redo()` handlers explicitly bump `revision` and call `autosave(...)` themselves after `undoStack.undo(on:)`/`redo(on:)` — mirroring `addRoom()`'s existing manual-bump pattern — so undo/redo can never re-push themselves onto their own stack while still keeping disk and the 3D view in sync. `UndoStack` is deliberately **not** `@MainActor`-annotated (matches `HomeModelStore`'s own "main-actor UI state by documented contract, not enforced" convention), so its own logic stays synchronously unit-testable | Bracketing the gesture rather than merging by subject-match is the only design that correctly separates "one continuous gesture" from "two separate taps on the same target." Not autosaving inside `replaceModel` is exactly why undo/redo can't fight autosave or loop back onto themselves |
| 2026-07-22 | S2.2 | Added `Selection.stairs(stairsId:)` (needed so `deleteStairs` has a selection target). Its SceneKit highlight (`EditorSceneController.highlightCenter`) is left as a no-marker case, same as the pre-existing `.opening` case — deferred, not silently skipped: a device-coupled rendering change with no way to verify off-device this session | `.opening` already had this exact gap; adding `.stairs` alongside it rather than inventing new scope |
| 2026-07-22 | S2.2 | **A real iOS 26.5 simulator runtime IS installed on this machine** (iPhone 17/17 Pro/17 Pro Max/17e/Air, all bootable) — contradicting every S1.3–S2.4 decisions.md entry that assumed none existed. Ran the full `escape_planTests` suite via `xcodebuild test -destination 'platform=iOS Simulator,id=...'`: every test passes except the pre-existing, unrelated `DollhouseRendererTests.testBundledFixturesMatchSchemaFixtures`, which references a deleted path (`escape_plan/Resources/Fixtures/`) left over from the S2.1×S0.3 "Model-layer unification" merge — not caused by S2.2, not fixed here (out of scope: touches Renderer, not Editor). Also booted the simulator, installed, and launched the app — it reaches the Home tab without crashing. Full on-screen gesture/tap verification of S2.2's three acceptance criteria is still not done (no simulator-automation tool available in this environment) and is left for a human | Earlier "no simulator, so acceptance is code-done-only" framing across S1.3–S2.4 no longer holds — flagging so those sessions' device-acceptance boxes get revisited, and so this session's own boxes are left unchecked for the right reason (no automation tool, not no simulator) |
| 2026-07-22 | S3.3 (iOS half) | **Assistant chat screen built** (`Screens/AssistantScreen.swift` rewrite + new `Networking/APIClient+Chat.swift` + new `Persistence/ConversationStore.swift`). Wire types are exactly the server's `extra="forbid"` shape — a separate persisted `AssistantMessage` (id/citations) projects down to the `{role, content}` `ChatMessage` for requests, locked by `escape_planTests/ChatRequestEncodingTests` (4 tests, RUN GREEN on the iPhone 17 Pro simulator — a runtime is now installed on this machine, unlike the S2.1/S2.4 sessions). `route_plan`/`profiles` deliberately not sent in v1 (optional server-side; chat grounds in the home alone). Chat grounds in the most-recently-modified saved home, falling back to the bundled twostory fixture on a fresh install; conversation persists to `<Documents>/Assistant/conversation.json` (atomic, HomeDocumentStore-style) after every appended message plus on scenePhase→background, so it survives force-quit. Inline `[cite: source-id]` tags render **verbatim** in the reply bubble with the server's `citations` array echoed as chips beneath. The extension uses `URLSession.shared` (APIClient's `session` is private and APIClient.swift was out of scope; its default is `.shared` anyway); 60s timeout for Render cold starts | The wire/persisted type split is forced by the server contract: any extra encoded key on a history message 422s the whole call. Rendering citations verbatim (not stripped/prettified) is the session requirement and the honest UI for the grounding story. |
| 2026-07-22 | S3.3 (found, not fixed) | **A missing `ANTHROPIC_API_KEY` makes `/chat` return a plain-text 500, not the 502 the session brief assumed.** `api_chat.post_chat` catches `ValueError` (→422) and `ChatGroundingError` (→502, fabricated citations after retries) but NOT the base `GroundingError` that `service._client()` raises when the key is unset — it propagates to FastAPI's generic 500 ("Internal Server Error", not JSON). Verified live: local uvicorn without the key, `/chat` on twostory → 500. `/explain` and `/analyze` in `main.py` DO catch it (→502). The iOS client treats all 5xx as one "assistant unavailable" state with Retry (the user's message stays in the thread), so the app behaves correctly either way. Backend not touched — `app/` is P1's lane per the session scope | Flag for P1: adding `GroundingError` handling to `api_chat.py` (mirroring `/explain`) would make the no-key state a deliberate 502 instead of an accidental 500. Recorded here so it isn't rediscovered when the key session runs the live smoke tests. |
| 2026-07-16 | post-merge | **Model-layer unification: S2.1's stub `Models/Generated/HomeModel.swift` deleted; S0.3's `Models/` is the single Codable mirror.** Renderer, Editor Core, SceneKit bridge, and the shared tests ported via mechanical renames to S0.3's snake_case schema-exact API (`Point2D`→`Point`, `EXTERIOR_ROOM_ID`→`EXTERIOR_ID`, `SourceKind`→`Source`, `fromEnd/toEnd`→`from/to`, camelCase members→`room_ids`/`wall_segment`/`width_m`/… and `Meta` timestamps are now `Date`, coded via `HomeModel.decoder`/`encoder()`). Nothing added to `Models/`; the non-schema conveniences the editor/renderer need (positional `Point.init(_:_:)`, `HomeModel.currentSchemaVersion`, `floor/floorIndex/locateRoom`, `Floor.room`) live in a new `escape_plan/Editor/Core/ModelSupport.swift`. Editor Core dropped its `public` modifiers (S0.3's types are internal; both runners compile everything into one module anyway). `tools/editorcore` symlink repointed `Generated`→`escape_plan/Models`; `Editor/Core/Geometry.swift` renamed `EditorGeometry.swift` (basename collision with `Models/Geometry.swift` under SwiftPM). Deleted the S1.3-lane duplicate `escape_plan/Resources/Fixtures/*.json` (byte-identical to S0.3's `escape_plan/Fixtures/`, and Xcode refused to bundle both). Persistence and the scan exporter needed no changes (JSONValue tree / own export types) | The stub was always marked replace-with-S0.3; keeping two `HomeModel` declarations can't compile. S0.3's layer is the reviewed schema mirror with the round-trip gate, so consumers move to it rather than the reverse — and the "pure mirror, extensions live consumer-side" rule from the earlier renderer port carries over unchanged. |
| 2026-07-16 | post-merge | `/convert` route decorator gains `response_model_exclude_none=True` (only `/convert`; other endpoints' response models don't serialize schema-checked optionals). Fixes the S1.4-lane finding that unset optionals (e.g. every opening's `egress`) serialized as explicit `null`, which the JSON Schema rejects. Regression test: `test_convert_response_has_no_null_optionals` in `backend/tests/test_api.py` walks the whole response for nulls | The converter never sets `egress`/`confidence` on manual items; an explicit `"egress": null` makes the endpoint's own output fail `python3 -m app.validate`. Omitting unset fields is what the schema (and the Swift decoder) expects. |
| 2026-07-16 | post-merge | Renderer ported from the deleted S1.3 stub model to the merged S2.1 `Models/Generated/HomeModel.swift`: mechanical renames (`Point`→`Point2D`, `Polygon`→`[Point2D]`, `roomID`→`roomId`, `stair.from/to`→`fromEnd/toEnd`, `WallSegment`→`WallSegmentRef`). Renderer-only conveniences (`Point2D.init(x:y:)`, `HomeModel.floorsByLevel`) live in `escape_plan/Renderer/HomeModel+Renderer.swift`, not in the schema mirror. Duplicate test-support `Fixtures` enum (S2.4 vs S2.1 lanes) resolved by renaming the persistence one to `PersistenceFixtures` | `HomeModel.swift` must stay a pure schema mirror ("never add a field here without a schema bump"), so anything the renderer needs beyond schema fields is a retroactive extension in a Renderer-side file. |
| 2026-07-16 | S1.6 (deploy) | Backend deployed to Render at `https://escape-plan-backend.onrender.com` via the committed `render.yaml` blueprint. `ANTHROPIC_API_KEY` left **unset** on Render (Render's Blueprint form accepted a blank value for this `sync: false` var) — confirmed it's not required to boot: only `BACKEND_BEARER_TOKEN` gates startup (`app/config.py` fails closed without it); `/explain` will return HTTP 502 (`GroundingError`) until a real key is added via Render dashboard → Environment. Verified via curl from a dev machine: `/health` 200 OK (~0.39s warm), `/routes` on `twostory.json` 200 OK (~0.27s warm) — both well under the 2s bar. The formal **phone-on-cellular <2s acceptance check is DEFERRED BY TEAM DECISION**, not done today: no REST client was available on the test phone, and nothing else in the current session plan is blocked on this number (S0.3/S1.3 haven't started, so `APIClient.swift` isn't wired yet). It will be exercised naturally when P2 wires the app to this live URL later. | Avoided installing a REST client or tethering just to check a box early when no other work is stalled on it. Blank `ANTHROPIC_API_KEY` is the honest state (no real key exists yet) rather than a placeholder string that would look like configured-but-broken. |
| 2026-07-16 | S3.2 | **Built as PREP, not DONE — no ANTHROPIC_API_KEY available in this environment and none will be added today.** Full agent loop, all 6 tools, `/analyze` endpoint, and 22 tests all pass, but every test uses a scripted Anthropic client (`ScriptedClient` in `backend/tests/test_agent.py`) standing in for the model — there is no live counterpart yet (unlike S3.1's `test_ai_live.py`). Acceptance criteria are verified against the *deterministic* tool outputs (real engine calls) and the *validation* logic (evidence/citation enforcement), not against real model behavior | Session run in a parallel git worktree (`s32-agentic-analysis`) alongside S3.3 prep and S0.3, with no key issued. Real model behavior (does Claude actually inspect systematically and produce sound findings) still needs one live run once a key exists — same shape as S3.1's pending human step. |
| 2026-07-16 | S3.2 | **Found: the twostory.json "kids' room lacks secondary egress" planted issue does NOT trip the S1.2 engine's `no_secondary_egress` RouteFinding.** The engine's secondary-route search only requires a different final exterior *exit* (bans the primary's exit, soft-penalizes reused openings) — it happily routes the Kids' Bedroom's secondary back out through the shared landing door and the downstairs back door, since that's a different exit than the primary's front door. The room's own window (`w_kids`) genuinely fails egress (0.4m width < 0.508m required, area 0.4m² < 0.53m² required — confirmed via `check_egress`), so the *room* has only one physical way out even though the *house*-level router considers it resolved. Not a bug to fix (S1.2 is DONE, signed off, 19 passing tests) — it's a semantics gap between "two ways out of the house" and "two ways out of the room" | This is exactly why S3.2 gave the agent `check_egress` as a tool distinct from `compute_routes`: the agent can (and in the test suite, does) catch this via a direct opening-level check that the whole-house router's definition doesn't surface. Flagging for P1/team awareness — if judges or the playbook's acceptance language expect the RoutePlan itself to carry a `no_secondary_egress` finding for `r_bed_kids`, it won't; the agent's own finding (backed by `check_egress` evidence) is what carries it instead. See `docs/agent-trace-example/README.md`. |
| 2026-07-16 | S3.2 | Evidence + citation validation is enforced server-side, not just requested of the model: `_validate_findings()` drops (does not retry) any finding whose `evidence` list doesn't resolve to a real `tool_use_id` in that run's trace, or whose `citation` isn't a real `sources.json` id. Dropped findings are reported back in `AnalysisResult.dropped` (reasons) rather than silently discarded | Unlike S3.1's citation retry loop (feed the rejection back to the model, retry up to 2×), S3.2's loop is already capped at 15 iterations end-to-end — adding a nested retry for finding-level validation risked blowing past the <60s acceptance target. One-shot filter-and-report is cheaper and the `dropped` field keeps the failure visible instead of invisible. |
| 2026-07-16 | S3.2 | `search_corpus` tool does paragraph-level keyword search (split each corpus doc's body on blank lines, score by literal word overlap with the topic), separate from S3.1's `grounded.py::corpus_text()` which embeds the whole corpus doc-by-doc into the `/explain` system prompt | The agent needs to *look things up* mid-inspection (small tool results, many turns) rather than have the entire corpus pre-loaded once; paragraph granularity keeps tool_result payloads small. No new dependency — stdlib `re` only. |
| 2026-07-16 | S3.3 (prep) | **Approved deviation: built S3.3's backend before its S3.1 prerequisite finished** (S3.1 is "CODE DONE — one human step from DONE"; the human live-run/review hasn't happened yet). New `backend/app/ai/chat/` module (`summary.py`: pure HomeModel/RoutePlan/Profile → compact text summaries, no I/O; `service.py`: stateless multi-turn `chat()`) + `backend/app/api_chat.py` router, wired into `app/main.py` with two lines (an import + `app.include_router(chat_router)`). Reuses S3.1's `grounded.corpus_text()` / `valid_source_ids()` for the cached corpus block rather than re-embedding the corpus; duplicates its small `_log_cache_usage` helper and the bearer-token dependency (≈10 lines each) instead of importing private symbols from `grounded.py`/`main.py`, since importing `require_token` from `app.main` would create a `main ↔ api_chat` circular import (`main` includes the chat router). Citation contract for free-text chat: inline `[cite: source-id]` tags are validated against `sources.json`; a reply needs zero citations (small talk, 911 deferrals), but any citation present that doesn't resolve is fabricated and triggers the same reject/retry loop as `/explain` (`ChatGroundingError` → HTTP 502). System prompt adds a third `cache_control` breakpoint for the house/plan/profile summary block (beyond the corpus block S3.1 already caches) — a chat session reuses the same home across every stateless turn, so it's a legitimate second cache target. **S3.3 backend is NOT done, labeled prep** — same shape as the S1.5-prep precedent: mocked/structural tests pass locally, but the live acceptance smoke tests (`tests/test_chat_live.py`, marked `live`) haven't been run because `ANTHROPIC_API_KEY` wasn't present in this session's shell (see session note). iOS chat UI is out of scope (P2, separate playbook task). | Matches team direction to prep S3.3 backend ahead of the blocking human step, per the S1.5-prep precedent (build the prerequisite-independent half now, validate once the blocker clears). Avoiding a circular import kept `api_chat.py` a clean, independently testable router file rather than reaching into `main.py`'s internals. |
| 2026-07-16 | S2.4 | **A saved home is stored as exactly the HomeModel JSON — no envelope, no metadata sidecar, no index file.** One file per home at `<Documents>/Homes/<home_id>.homeplan.json`; the home-list rows (name/floors/rooms/modified) are derived by reading the documents, not cached. Writes are atomic | Export is then the stored file byte-for-byte, so "the export validates against the schema" is true by construction rather than by a second serializer staying in sync. An index would be one more thing that can disagree with disk; N is small (a household has a few homes), so deriving the list is cheap. |
| 2026-07-16 | S2.4 | Persistence holds documents as a lossless `JSONValue` tree, not as decoded `HomeModel` structs. Generic `save(model:)` / `load(homeID:as:)` entry points exist for S2.1's Codable `HomeModel` | Keeps this layer from becoming a second, drifting copy of the schema, and makes unknown-field preservation automatic: a document written by a newer build round-trips instead of silently losing fields this build doesn't model. Also let S2.4 land while S2.1's `HomeModel` was still in flight in a parallel lane. |
| 2026-07-16 | S2.4 | `schema_version` on load: newer than the build → **refuse** (`documentTooNew`, file left untouched, rest of the library still lists); older → run the `SchemaMigrator.migrations` registry, unregistered step fails loudly. Registry is empty (1.0 is the first version) — the stub is shape-only. Version compare is numeric per component, so "1.10" > "1.2" | Guessing at a future document's fields risks silently mangling a home someone's escape plan depends on. Refusing gracefully is recoverable (update the app); a bad migration is not. Numeric compare is the bug you only find after the tenth bump. |
| 2026-07-16 | S2.4 | Import (of an exported/shared file) assigns a **fresh `home_id`** rather than restoring the original id | Re-importing your own export must not silently overwrite the home you still have. Duplicate does the same, so ids stay unique per device. |
| 2026-07-16 | S2.4 | Swift tests read the real `schema/fixtures/*.json` off the host filesystem via `#filePath` (overridable with `ESCAPE_PLAN_REPO_ROOT`) instead of copying fixtures into the test bundle | Per rules/paths/schema.md the fixtures are the project-wide test bed; a bundled copy would drift from what every other lane tests against. |
| 2026-07-16 | S2.4 | **Acceptance runs via `./scripts/verify_export_validates.sh`** (SwiftPM harness on macOS + `python3 -m app.validate` over the export) rather than `xcodebuild test`. **Blocker: no iOS simulator runtime is installed on this machine** ("iOS 26.5 is not installed" — Xcode ▸ Settings ▸ Components), so no `xcodebuild test` destination exists. Compile is verified with `xcodebuild -target escape_plan -sdk iphonesimulator26.5` | The Persistence module is Foundation/Combine/SwiftUI only, so it runs unmodified on macOS — the acceptance is real, not simulated. The python validator can't run inside a test host anyway, so the export check is a two-step script regardless. Once a runtime is installed, `xcodebuild test` runs the same test file in the app target and is the check that counts. |
| 2026-07-16 | S3.4 (backend half) | **No schema change was needed** — `Profile` (id/name/tags/bedroom_room_id) and `HomeModel.profiles` already existed from S0.2, and `twostory.json` already ships Maya + Grandpa. Playbook's "age band" is NOT implemented (not in the schema; `child`/`elderly` tags already carry what routing needs), and `hearing_impaired` is NOT a tag (not in the `ProfileTag` enum; it's alarm guidance, not routing — belongs to the S3.5 checklist). Both would need a `schema_version` bump + sign-off | Guardrail: profiles live in request models unless the playbook demands a schema change. It didn't — the contract already covered the feature. Neither omission blocks the acceptance criterion. |
| 2026-07-16 | S3.4 | Split the tag mapping into **hard** constraints (remove the edge) vs **soft** penalties. Added two additive `RoutingConstraints` fields — `stair_penalty_m`, `window_penalty_m` (both default 0.0 = exact pre-S3.4 behaviour). `mobility_limited` → hard `avoid_stairs`+`avoid_windows`; `elderly` → soft `stair_penalty_m=10.0` + `max_sill_height_m` read from the corpus thresholds; `child` → soft `window_penalty_m=20.0`; `pet` → nothing. Tags compose strictest-wins. Table: `backend/app/routing/profiles.py`, rationale: `docs/profile-constraint-mappings.md` | Corpus distinguishes "not usable routes" (wheelchair + stairs → must disappear; showing an unusable route is worse than showing none) from "prefer stair-free **where available**" (older adults → must only cost more; a hard ban would manufacture a false no-viable-route flag). The penalty magnitudes are documented as engineering choices, NOT dressed up with a citation — the corpus gives no number for "prefer" and we won't invent one and attribute it to NFPA. |
| 2026-07-16 | S3.4 | **Known limitation, deliberately documented not hidden:** the `child` window penalty changes **zero** routes on all three fixtures — the engine's universal `WINDOW_EXIT_PENALTY` (12.0) already dominates every door/window choice those homes offer. Locked by `test_child_penalty_is_a_no_op_on_the_current_fixtures`. `elderly` and `mobility_limited` both demonstrably change twostory outcomes | The mapping encodes the corpus's intent and would bite in a home with a closer call, but the `child` tag's real effect today is the S3.1 explanation phrasing, not the geometry. A test that asserts the no-op stops anyone quietly overclaiming it in the demo video. |
| 2026-07-16 | S3.4 | `/routes` gains optional `profile_id` (resolved against `home.profiles`); `RoutePlan` gains nullable `profile_id`. Both additive — pre-S3.4 requests are byte-identical. `profile_id` + explicit `constraints` together → **422**, unknown `profile_id` → **404**; `compute_route_plan` raises `ValueError` on both-args | Fail loudly rather than fall back: silently letting explicit constraints override the derived table would void the guarantee the mappings doc makes to judges, and falling back to unconstrained routing on a typo'd id would hand a mobility-limited user a staircase. Client sends an id, not constraints, so the mapping table stays server-side and un-forkable. |
| 2026-07-16 | S3.5 | **Approved deviation: built S3.5's backend half before its S3.2 prerequisite** (parallel-lane direction). Agent findings are consumed through an explicit interface transcribed from `docs/playbook/S3-2.md` — `backend/app/scoring/findings.py`, marked `TODO(integration)`. Scoring reads only `severity` off a finding, so the merge risk is narrow: severity spelling (`"med"` vs `"medium"`) and whether findings carry a stable id (the checklist currently synthesizes positional ids). **S3.5 is not fully DONE:** the iOS score screen + count-up animation remain, and the findings component has never seen a real `/analyze` payload | S3.2 is in a teammate's worktree; the scoring engine is a pure function of routes + findings + checklist state and needs none of S3.2's implementation, only its output shape. Keeps both lanes moving; the interface file is the merge checklist. |
| 2026-07-16 | S3.5 | Score weights per the playbook (30 primary / 25 secondary / 20 findings / 15 alarms / 10 practice), with two deviations: (a) primary/secondary are **proportional** (`30 × rooms_with_route/total`), not all-or-nothing; (b) the findings component **deducts per finding** (high 10 / med 4 / low 1, floored at 0) instead of the playbook's binary "no high-severity findings". The total rounds **half-up**, not Python's banker's rounding. All arithmetic hand-reproducible from `docs/preparedness-score-weights.md`; `backend/tests/test_scoring.py` asserts every worked example on that page | Partial credit makes the score actionable — fixing one trapped bedroom must visibly move the number, and one low-severity note must not read like a bedroom with no egress. Banker's rounding would round 77.5 up but 76.5 down, silently making the published hand-calculations wrong. |
| 2026-07-16 | S3.5 | Only smoke-alarm and practice checklist items are **scoring**; route findings, agent findings, and grounded AI recommendations are all `scoring: false`. Absent findings → findings component sits at **full** marks, not zero. `/score` is a thin wrapper that recomputes the RoutePlan from `home` + `constraints` so the score always matches the plan on screen (profile constraints included); `include_recommendations: true` is the only AI path, appends non-scoring items only, mapped from S3.1 with citations re-validated at the boundary (`GroundingError` → 502, matching `/explain`) | Route/agent items are fixed by changing the home and re-running the engine, which moves components 1–3 on its own — paying out for the tick as well would double-count. Full marks with no findings means the score reports what's known rather than penalising a household for not yet running an inspection. Keeping AI items non-scoring is the honest answer to "isn't the score just the AI's opinion?". |
| 2026-07-16 | S5.1 (draft) | **Approved deviation: drafted S5.1's demo script + storyboard before its S4.1 prerequisite**, as an explicitly-marked draft v0 (`docs/demo/script-v0.md`, `docs/demo/storyboard-v0.md`). **S5.1 is NOT done** — every visual claim is tagged `[PENDING: S<x>.<y>]` against the session that must ship it, and the whole draft is re-read when S5.1 formally starts. Docs only; no code. Beat 2's playbook-supplied "80%" scan-quality figure is flagged as a characterization, not a sourced statistic — S1.5's calibration replaces it with a real number or it gets reworded | A script written in October from zero is a script written under deadline. Drafting now turns S5.1 into an edit pass and, more usefully, surfaces the b-roll shot list early enough that each session can record its own footage as it lands instead of restaging it. |
| 2026-07-16 | S1.3 | **Approved deviation: built S1.3 before its S0.3 prerequisite is on this branch** (parallel-lane direction). Wrote a minimal HomeModel Codable layer at `escape_plan/Models/Generated/HomeModel.swift`, mirroring the schema field-for-field but with no validation and no store/undo plumbing — marked `TODO(integration): replace wholesale with S0.3's model layer on merge`. S0.3 is being built in a separate worktree | The renderer needs *a* decoded model, not *the* model layer; both are written against the same schema, so the swap should be delete-and-rebuild rather than a rewrite. Front-loading the visual core keeps the S1.3 lane unblocked while S0.3 lands. |
| 2026-07-16 | S1.3 | Renderer stayed on **SceneKit** (playbook default; RealityKit not evaluated). `escape_plan/Renderer/` splits into a pure-geometry module (`DollhouseGeometry` — no SceneKit node construction, unit-tested) and a node builder (`DollhouseSceneBuilder`) — the same pure-function split the backend uses for routing | The editor (S2.x) mutates the model constantly and must rebuild scenes cheaply; a pure `HomeModel → scene` function with no hidden state makes rebuilds safe and the geometry testable without a renderer or a device. |
| 2026-07-16 | S1.3 | Renderer conventions, all fixed in `DollhouseGeometry`: plan (x, y) → scene **(x, −z)** with +y up; floors stack by `level` (not array order) on accumulated `height_m`; shared walls **deduplicated** by unordered rounded endpoint pair; opening markers centered on the **midpoint of [t0, t1]** and sized by **`width_m`** (schema: the t-range is placement, not size), clamped to the host edge; stair `kind` L/U render as a straight-flight proxy across the footprint's long axis | Adjacent rooms each own the shared wall in their own polygon — rendering both puts two coplanar transparent boxes in one place and z-fights. Clamping means bad `width_m` data can't overhang a wall. The schema stores a footprint + kind for proxy geometry only, so an L-shaped proxy would be inventing geometry the model doesn't carry. |
| 2026-07-16 | S1.3 | Semi-transparent walls use `writesToDepthBuffer = false` + `renderingOrder = 10`; room labels use `.constant` lighting with depth read/write off and `renderingOrder = 100` | A transparent surface that writes depth hides whatever is drawn behind it — for a see-through dollhouse that's exactly the content you want to see. Labels are UI, not geometry: they should stay legible through a wall. |
| 2026-07-16 | S1.3 | Fixtures **duplicated** from `schema/fixtures/` into `escape_plan/Resources/Fixtures/`; `DollhouseRendererTests.testBundledFixturesMatchSchemaFixtures` byte-compares them and fails if the copies drift | An app bundle can't read outside its own resources at runtime, and `schema/fixtures/` is the project-wide test bed we're told not to fork. The equality test makes the duplication safe rather than silently divergent. |
| 2026-07-16 | S1.3 | `escape_planApp.swift` now launches `DollhouseDemoView` instead of the stock Core Data template's `ContentView` (`Persistence.swift`/`ContentView.swift` left in place, now unreferenced). Demo controls are also driveable from launch arguments (`-fixture twostory -explode 1.0 -hideFloor f2`) | The renderer has to be runnable to verify acceptance at all. S0.3 replaces this entry point wholesale (marked `TODO(integration)`). Launch args make the acceptance screenshots scriptable via `simctl` instead of hand-tapping the simulator. |
| 2026-07-16 | S1.3 | **Acceptance in this lane is simulator-only.** The playbook's on-device 60fps check and the 30-sec per-fixture screen recordings (demo-video b-roll) remain **BLOCKED-ON-HUMAN**. Local toolchain had **no iOS platform installed at all** — `xcodebuild -downloadPlatform iOS` (8.5 GB) was required before anything could build | P3 has no physical device, and the 60fps criterion is explicitly on-device — frame rate on a Mac's GPU says nothing about an iPhone's, so it cannot be honestly signed off from a simulator. Flagged so nobody reads a green simulator build as a passed acceptance. |
| 2026-07-16 | S2.1 | **No iOS simulator runtime is installed on this machine, so `xcodebuild test` cannot run a single test.** Added `tools/editorcore/` — a macOS SwiftPM harness that compiles the *same* source files via **symlinks** (`Sources/EditorCore/{Core,Generated}` → `escape_plan/{Editor/Core,Models/Generated}`, `Tests/…/Shared` → `escape_planTests/EditorCore`). No duplicated sources. Shared test files pick their module with `#if SWIFT_PACKAGE` (`EditorCore` vs `escape_plan`). Two runners, one source of truth: `swift test --package-path tools/editorcore` (89 tests, runs here today) and `xcodebuild test` (runs on a machine with a simulator). App target verified with `xcodebuild build -target escape_plan -sdk iphonesimulator26.5 CODE_SIGNING_ALLOWED=NO` — the `-destination 'generic/platform=iOS'` form fails ("iOS 26.5 is not installed") because device support is absent | The acceptance criterion is "unit tests prove no sequence of store actions can produce an invalid model" — unrunnable tests prove nothing. Keeping the editor core pure (Foundation only) is required by the playbook anyway, so it costs nothing to also make it testable off-device, and it gives a ~5s feedback loop instead of a simulator boot. |
| 2026-07-16 | S2.1 | Editor core split into `Editor/Core/` (pure: Geometry, Snapping, EditorValidation, EditAction, HomeModelStore, HitTesting — no SceneKit/UIKit) and `Editor/SceneKit/` (one file, `SceneKitEditorBridge`, `#if canImport(SceneKit)`-guarded). The bridge talks to an `EditorSceneAdapter` protocol (3 methods: `worldPoint(from:)`, `metersPerPoint()`, `highlight(_:)`) instead of S1.3's node graph | S1.3 is in a parallel lane and not on this branch. An explicit 3-method seam is reviewable and lets 100% of the edit *logic* be tested now; only unprojection/highlighting is deferred to merge. Hit-testing (what a tap selects) is pure and tested — only coordinate conversion is device-coupled. |
| 2026-07-16 | S2.1 | `HomeModelStore.dispatch` reduces onto a **copy**, validates with `EditorValidation`, then commits or rejects wholesale; `init` throws on an invalid seed model. Validation is a client-side mirror of `backend/app/models.py` (CCW, self-intersection, cross-refs, global id uniqueness, scan⇒confidence). Verified by mutation testing: deleting the validation gate turns the invariant suite from 0 → 51 failures | Makes "no gesture puts the model in an invalid state" a structural property rather than a discipline. Reducing onto a copy means a rejected action cannot leave partial state behind — asserted after every step of the fuzz. |
| 2026-07-16 | S2.1 | Destructive edits **refuse rather than cascade** when a *user-authored* reference would be lost: deleting a room/floor referenced by a profile's `bedroom_room_id`, or a room where stairs land, is rejected. Openings DO cascade with their room, and stairs cascade with a deleted floor. Deleting the last room on a floor / the last floor is rejected | Openings only exist to connect their room, so cascading loses nothing. A profile's bedroom assignment is information the user typed and cannot recover — a silent cascade would destroy it. Schema requires ≥1 floor per home and ≥1 room per floor, so the other two are contract limits, not policy. |
| 2026-07-16 | S2.1 | Snapping priority: vertex → wall → axis → grid, with axis locks overriding the grid **per-coordinate**. Room/wall drags snap the *translation delta*, not each vertex. Defaults: 10cm grid, 5cm axis tolerance, 25cm wall/vertex capture. A room never snaps to its own geometry | Wall snap must beat grid or off-grid scan-derived walls become unsnappable. Snapping the delta keeps an off-grid (converted-scan) footprint rigid — per-vertex snapping would deform it. Self-snapping would collapse a wall to zero length. |
| 2026-07-16 | S2.1 | Wrote a minimal `escape_plan/Models/Generated/HomeModel.swift` marked **replace-with-S0.3** (mirrors schema v1.0; `from`→`fromEnd` CodingKeys, `[x,y]`-array Point2D, computed `egress` round-tripped but never authored). Round-trip tested against all 3 fixtures at both the Swift and the JSON-key level | S0.3 is in a parallel lane; the editor core needed types to compile against. The JSON-level round-trip is what makes the stub safe to delete on merge — if S0.3's models pass the same tests, the swap is a no-op. |
| 2026-07-16 | S2.1 | "Start from an empty model" is implemented as `HomeModelStore.newHome()` = one floor + one starter room; `addFloor` likewise seeds a starter room | The schema has `floors: minItems 1` and `floor.rooms: minItems 1`, so a zero-room home is not representable. The emptiest *valid* document is the honest starting point. |
| 2026-07-16 | S1.4 | **Hand-rolled the raw scan JSON exporter instead of `JSONEncoder().encode(capturedStructure)`.** `escape_plan/Capture/Export/` emits the exact shape `backend/app/convert/README.md` pins (flat 16-float column-major transforms, `{"high": {}}` confidence, per-room surface arrays). Apple's own encoding is still written beside every scan as `apple-raw.json` | Apple's synthesized Codable output for `CapturedStructure` is undocumented and free to change between iOS releases; the converter is built against a pinned shape, so the app should emit that shape deliberately rather than hope. `apple-raw.json` preserves ground truth for S1.5's calibration diff, which is the point of S1.4's handoff. |
| 2026-07-16 | S1.4 | **Protocol seam between RoomPlan and the exporter** (`ScanSurfaceConvertible`/`ScanRoomConvertible`/`ScanStructureConvertible`). Only `Export/RoomPlanScanSource.swift` plus the controller/view files import RoomPlan; the format logic is Foundation-only | `CapturedRoom`/`CapturedRoom.Surface` have no public initializers, so no test can construct one — without the seam the export format is untestable by construction. The seam also lets `tools/scan-export-roundtrip/run.sh` compile the exporter natively with `swiftc` and push synthetic geometry through the real Python converter, making S1.4's exporter acceptance verifiable with no device and no simulator runtime. |
| 2026-07-16 | S1.4 | **Multi-room = continuous capture merged by the iOS 17 `StructureBuilder`; fallback = export rooms unmerged** with `capture.mode: "sequentialRooms"` + a `fallbackReason`, identical wire format, surfaced in the review UI (never silent). Added a `capture` provenance block (mode/exportedAt/device/appVersion) to the export | The playbook's recommended path with its sanctioned fallback ("fall back to sequential room scans merged by S1.5 and document it"). Identical wire format means the fallback costs S1.5 only its shared-door pairing strategy (geometric instead of by-identifier), not a second code path. The converter ignores unknown top-level keys, so `capture` rides along free — and tells S1.5 which pairing path to trust. |
| 2026-07-16 | S1.4 | Added `INFOPLIST_KEY_NSCameraUsageDescription` (+ `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`) to Debug + Release in `project.pbxproj` | RoomPlan hard-crashes without a camera usage string — the deferred device step would have failed on first launch. File sharing is how scan directories get off the device into `schema/fixtures/scans/`, which is S1.4's handoff artifact. Known pbxproj merge-conflict risk with other iOS lanes, accepted per the agreed lane convention. |
| 2026-07-16 | S1.4 (found, not fixed) | **`/convert` returns schema-invalid JSON**: `response_model=HomeModel` without `response_model_exclude_none=True` serializes the computed-only `egress` field as `"egress": null`, which `homemodel.schema.json` rejects (it types `egress` as an object; per S0.2 it should be absent until the S1.1 annotator runs). Verified live via TestClient on the committed fixtures: 200 OK with an invalid body | Pre-existing and independent of S1.4 (reproduces with none of the capture code in the path), and `app/main.py` belongs to the backend lanes which merge separately — an edit from an iOS branch would conflict. Recorded here and in the S1.4 tracker note so it isn't lost. Affects any client validating `/convert` responses against the schema, including S0.3's Swift Codable round-trip test. |
| 2026-07-16 | S0.3 | Replaced the stock "App with Core Data" template wholesale: deleted `Persistence.swift` + `escape_plan.xcdatamodeld`; added `Models/` (Codable structs mirroring `schema/homemodel.schema.json` field-for-field — snake_case property names, same optionality/defaults as the schema, not Swift naming convention), `Screens/` (TabView shell: Home/Editor/Plan/Assistant/Settings), `Networking/APIClient.swift`. Xcode project confirmed staying at repo root (not `ios/`) — moving it was never revisited since S0.1 and doing so now would still break the open Xcode session for no benefit before Phase 2 | Matches the playbook default (local JSON persistence, not Core Data) and the S0.1 flag left for this session. Root-vs-`ios/` was a live decision point per that flag; kept root to avoid churn. |
| 2026-07-16 | S0.3 | Swift's `Stairs.from`/`.to` use the JSON field names directly with no `CodingKeys` alias — `from` isn't a reserved word in Swift (unlike Python, where `backend/app/models.py` needed `from_` + an alias). `Point` is a custom `Codable` type that (de)serializes as a bare 2-element JSON array, not a `{x, y}` object, to match `$defs/point` exactly. Fields the schema marks `"default": []` (`HomeModel.stairs/profiles`, `Floor.openings`, `Profile.tags`) get hand-written `init(from:)` with `decodeIfPresent(...) ?? []` so a document omitting the key still decodes, even though all 3 committed fixtures include it explicitly today | "Codable structs mirroring the schema exactly — field names, enums, optionality" (swift.md). Worth flagging for P1: the Swift mirror is more defensive about omitted-default-array keys than the current fixtures require — no drift risk today, but the pydantic side should double check it treats an omitted `stairs`/`profiles`/`openings` key the same way if S1.5 or the editor ever emits one. |
| 2026-07-16 | S0.3 | Round-trip test (`escape_planTests/HomeModelRoundTripTests.swift`) does decode → encode → decode → `Equatable` compare on the decoded model graphs, run against all 3 fixtures (bungalow/apartment/twostory), not a literal byte/string diff of the two JSON blobs | `JSONEncoder` doesn't guarantee key order/whitespace matches the source file's formatting even when content is identical, so a byte-literal compare would be a false-negative machine. Struct `Equatable` (all stored properties, synthesized) is the correct "semantic" compare for a decode→encode round trip. |
| 2026-07-16 | S0.3 | `schema/fixtures/*.json` copied into `escape_plan/Fixtures/` as real files (not a symlink) so Xcode's `PBXFileSystemSynchronizedRootGroup` bundles them as app resources; a small `Bundle(for:)` token type shares the app bundle lookup with the test target via `@testable import`. **Known drift risk, flagged for we**: these are copies, not the single source of truth — if `schema/fixtures/` changes, `escape_plan/Fixtures/` needs a manual re-copy until a build-phase script or symlink is added (not attempted this session — lower risk to just copy given the `.pbxproj` uses the newer synchronized-group format and its symlink-following behavior for resource bundling wasn't verified) | Simplest reliable path to a bundled resource under this project's file-system-synchronized (Xcode 16+) group format; explicitly deferred a build-script solution rather than risk a `.pbxproj` edit this session. |
| 2026-07-16 | S0.3 | `APIClient` base URL/bearer token are runtime-configurable via `UserDefaults`, edited from the Settings tab (not hardcoded, not `Info.plist`); default is `http://localhost:8000`. Acceptance box "runs on a real device" stays open — needs a human with the physical device; xcodebuild build+test both ran clean against iOS Simulator (iPhone 17, iOS 26.5) | Base URL needs to flip from local dev to the deployed Render URL (S1.6 human step) without a rebuild; `UserDefaults` is the lightest mechanism that supports that pre-S2.4 (before real persistence lands). |
| 2026-07-16 | S0.3 | `xcodebuild test` (unscoped) reports `** TEST FAILED **` only because of the *stock* `escape_planUITests.testLaunchPerformance()` (unmodified this session, pre-existing since the S0.1 template) timing out (~525s) with `FBSOpenApplicationServiceErrorDomain … RequestDenied` in this sandboxed dev environment — a simulator app-foregrounding limitation, not a regression. All 4 `HomeModelRoundTripTests` (including the decode→encode→decode round trip on all 3 fixtures) pass; `-only-testing:escape_planTests` reports `** TEST SUCCEEDED **` | Distinguishing "acceptance-relevant test failure" from "sandboxed-simulator UI-automation flakiness" — the S0.3 acceptance criterion is the round-trip test, which is green. Documented rather than silently deleting/skipping the stock UI test. |
| 2026-07-13 | S1.5 (prep) | **Approved deviation: started S1.5's device-independent half before its S1.4 prerequisite**. Built `backend/app/convert/` as a pure module against an ASSUMED RoomPlan export format (documented in `backend/app/convert/README.md`: column-major simd transforms, `{"high": {}}` confidence objects, per-room surface arrays, shared doors appearing in both rooms), validated only on 3 synthetic fixtures (`schema/fixtures/scans/`, generated by `backend/scripts/gen_scan_fixtures.py`). **S1.5 is NOT done** — real S1.4 exports must be diffed against the README's assumptions first. `/convert` endpoint deliberately not wired (S1.6 lane owns FastAPI) | Playbook calls S1.5 "the hardest single module"; the polygon/mapping pipeline needs no device. Front-loading it means S1.4→S1.5 becomes a validate-and-calibrate step instead of a build step. |
| 2026-07-13 | S1.5 (prep) | Converter behavior choices: shared doors paired by identifier first, then geometric coincidence (≤0.35 m, parallel); unpaired doors/windows → `[room, EXTERIOR]`; RoomPlan `openings` (doorless passages) emitted as doors (schema has no passage kind); opening >0.5 m from every wall edge kept but demoted to confidence ≤0.25; degenerate room geometry falls back to a bounding box at confidence ×0.3 (never crash/drop); one floor per scan session; all output ids uuid5-derived from input identifiers so conversion is idempotent | "80% right + flagged uncertainty" per the playbook — the Phase-2 editor is the corrector. Deterministic ids make idempotency testable and diffs stable. Known failure modes listed in the module README for the S1.4 calibration pass. |
| 2026-07-13 | S3.1 | Golden tests assert structural stability (same rooms explained, ≥1 valid overlapping citation) against committed snapshots rather than exact-text equality; live-API tests live behind a `live` pytest marker excluded by default (`pytest.ini` addopts), run via `ANTHROPIC_API_KEY=... python3 -m pytest tests/test_ai_live.py -m live -v` from backend/. First run writes the snapshot for hand review | Model wording isn't deterministic even at temperature 0.2 — exact-text snapshots would be permanently flaky; the safety-relevant invariants (coverage + citations) are what must not drift. Marker keeps the default suite hermetic and free. |
| 2026-07-13 | S3.1 | Citable ids = exactly the `sources` array of sources.json (compilation primary ids like `fire-facts-stats` are NOT citable); uncited/fabricated citations rejected server-side and retried up to 2× by feeding an `is_error` tool_result back; still bad → `GroundingError` → HTTP 502. Red-team deferral goes through `answer_grounded_question()`, a plain-text helper sharing the same cached system prompt (reused by S3.3 chat later) | Matches the S0.4 corpus rule that compilation docs only cite underlying sources; tool_result feedback is the idiomatic Anthropic retry channel; 502 (not 500) tells the app the upstream AI output was rejected, deterministic routes remain available. |
| 2026-07-13 | S1.6 | Deploy target Render via committed `render.yaml` blueprint (`rootDir: backend`, free plan, `BACKEND_BEARER_TOKEN` generateValue, `ANTHROPIC_API_KEY` sync:false). **Deploy + phone-on-cellular acceptance is BLOCKED-ON-HUMAN** — P1 must create the Render account; exact steps in backend/README.md § Deploy. Runtime pinned 3.12 on Render (3.13.5 local) | P3 can't create hosting accounts or receive the dashboard-entered secret. Blueprint makes the human step ~5 minutes and keeps all config reviewable in git. |
| 2026-07-13 | S1.6 | `/health` is unauthenticated (platform health checks); every other endpoint requires the shared bearer token via constant-time compare, and the service **fails closed** — refuses to serve if `BACKEND_BEARER_TOKEN` is unset. matplotlib moved out of `requirements.txt` into new `requirements-dev.txt` | An accidental unset-env deploy must not expose an open backend; Render needs an open health path. Keeps ~60MB of plotting deps out of the free-tier deploy image. |
| 2026-07-10 | S1.2 | Secondary route = re-run Dijkstra with the primary's EXIT banned + primary's intermediate openings soft-penalized (+25m-equiv); a secondary must leave through a different exit. Window exits carry a +12m-equiv penalty (doors preferred); stairs cost 6m-equiv. Bottleneck = opening whose removal disconnects ≥2 rooms from all exits | Playbook's default edge-avoidance strategy; "different exit" is the routing meaning of NFPA's "two ways out". Full removal of all primary openings would falsely kill secondaries that legitimately reuse the room's only door. Constants documented in engine.py for judge Q&A. |
| 2026-07-10 | S1.1 | Graph: nodes = rooms + openings + EXTERIOR (no separate stair nodes — stairs are room↔room edges tagged with the stair id); non-viable windows stay in the graph as flagged dead-end nodes (`excluded_exits` with reasons) rather than being dropped. Doors are egress-checked too (IRC R311 width/height) | Fewer node types keeps Dijkstra and waypoint extraction simple; flagged-not-dropped feeds the S3.2 agent's "too-small window" findings. Debug renderings: `python3 backend/scripts/render_graphs.py` → docs/graphs/. |
| 2026-07-10 | S0.2 | Schema strictness choices: ids globally unique across ALL entity kinds (not per-type); `room_ids` always exactly 2 entries (interior = 2 rooms, exit = room + `EXTERIOR`); `additionalProperties: false` everywhere; `confidence` required only when `source: "scan"`; `egress` is a computed-only field absent until the S1.1 annotator runs | Global uniqueness makes every id a valid graph-node key with no namespacing; a closed schema catches typos at the contract boundary; version bumps handle future additions. |
| 2026-07-10 | S0.2 | Both validators are the contract: JSON Schema (shape) AND pydantic (geometry/cross-refs). CLI `python3 -m app.validate` runs both. Added `backend/requirements.txt` early (pydantic, jsonschema, pytest, matplotlib) ahead of S1.6's full scaffold | JSON Schema can't express CCW/self-intersection/reference checks; S0.3's Swift round-trip test should treat pydantic-valid fixtures as ground truth. |
| 2026-07-10 | S0.2 | Broken-fixture acceptance implemented as `schema/fixtures/invalid/` (3 files: dangling room ref, CW polygon, duplicate ids) exercised by pytest | One "broken fixture" per failure class gives clearer regression coverage than a single kitchen-sink file. |
| 2026-07-10 | tooling | Built out a committed `.claude/` control center (rules, hooks, commands, agents, workflows) and changed `.gitignore` to ignore only `.claude/settings.local.json` instead of all of `.claude/` | So we's Claude sessions load the same project rules, `/session` protocol, and guardrails (schema-edit confirmation hook, API-key pre-commit scan). Root CLAUDE.md now @-references `.claude/rules/global/`; iOS-side CLAUDE.md stub added at `escape_plan/`. No new dependencies (hooks are bash + python3 stdlib). |
| 2026-07-10 | S0.4 | Marked complete ahead of P1's corpus review | Self-verifiable criteria pass (citation traceability + thresholds validation, enforced by validate.py). P1's "sufficient for S3.1" sign-off recorded as done at P3's direction — P1 should still read docs/corpus-summary.md and reopen S0.4 if the corpus is insufficient. |
| 2026-07-10 | S0.3 (flag for P2) | Current Xcode scaffold is the stock "App with Core Data" template — left untouched on purpose | S0.3 can't start until S0.2 (schema) is done. Note for P2: playbook default persistence is local JSON via FileManager, Core Data only if P2 prefers — expect to replace the template's Persistence.swift/ContentView.swift wholesale, and decide whether the project moves under `ios/`. |
| 2026-07-10 | S0.4 | Corpus is ~8 dense pages, under the playbook's 15–25 page target | Dense structured guidance beats padded prose for prompt grounding; every planned topic is covered. Expand in S3.1 if explanation quality demands it. |
| 2026-07-10 | S0.4 | Added `validate.py` (stdlib-only) in `backend/corpus/` | "Thresholds file validates" acceptance needs a checkable definition; stdlib-only because the Python env isn't scaffolded until S1.6. Checks source resolution, front-matter, inline `[cite:]` tags, and imperial↔metric consistency (1% tolerance). |
| 2026-07-10 | S0.4 | Citation convention: inline `[cite: source-id]` tags; compilation docs (`fire-facts-stats`, `special-considerations`) have non-source primary ids | Gives S3.1's citation validator an exact, greppable format; compilation docs only ever cite underlying external sources. |
| 2026-07-10 | S0.4 | Thresholds carry both imperial (as codified) and metric values; metric is authoritative for computation | HomeModel schema is in meters; imperial preserved so citations match the code text judges can check. |
| 2026-07-10 | S0.1 | Xcode project stays at repo root (`escape_plan/`, `escape_plan.xcodeproj`) instead of `ios/EscapePlan/` for now | Project was created before the monorepo layout was adopted; moving it mid-session breaks the open Xcode workspace. Revisit before Phase 1 iOS work (S0.3) — P2 can relocate it when scaffolding, or we keep root placement and document it. |
| 2026-07-10 | S0.1 | Repo/init tasks executed by P3 (Claude Code) rather than P1 | Team assigned P3's full lane to Claude Code; P1 asked for the init to be done now. |

---

## 2026-07-22 — Repo assessment, entry-point wiring, doc consolidation

| Decision | Why |
|---|---|
| `docs/tracker/board.md` + `checklist.md` collapsed into one `docs/tracker/TODO.md` | The two contradicted each other in ~9 places (S2.3 blocked on one and fully checked on the other, same day; three sections each labelled "(latest)"; test counts disagreeing three ways). Two status files means two things to keep in sync, and neither was. One file listing only open work, each line naming its next action. |
| `docs/plan.md` deleted | 40,429 bytes vs `cat docs/playbook/*.md` = 40,599 — the same document pre-split, orphaned since 2026-07-10, linked from nowhere. A silent second source of truth. |
| P1/P2/P3 lane labels stripped from live docs; `docs/tracker/notes/` deliberately untouched | Owner lanes had stopped matching who actually did the work. Notes are a dated append-only archive and the project's process evidence — rewriting them retroactively would falsify the record rather than clean it. ~20 files retain prose mentions needing a hand rewrite; tracked in TODO.md. |
| Anti-staleness is four stacked mechanisms, not a convention | Stop hook auto-writes `activity-log.md` (machine-written, cannot be forgotten); `/verify-docs` + `doc-auditor` agent; freshness stamps; pre-commit **warn**. Blocking commits over docs teaches people to bypass the hook, so that one warns only. |
| Capture + DrillMode entry points wired into `HomeScreen` | Both modules were complete, tested, and referenced by zero app code. LiDAR scan is the scope-locked headline feature and was unreachable. Required a new `APIClient+Convert.swift` — no `/convert` client existed in Swift at all. |
| Scan blob carried as `JSONValue`, not a typed Swift struct | The raw RoomPlan export format is the converter's contract (`backend/app/convert/README.md`). A Swift mirror of it would be a second copy that drifts; the app hands the bytes over untouched and the backend is the only thing that interprets them. |
| `app.ai.agent.Finding` and `app.scoring.findings.Finding` stay duplicated | The old TODO said to merge them post-S3.2. `agent.py` imports `anthropic` at module level, so re-exporting would drag the SDK into the deterministic scoring path and break the division of labor. Duplication is correct here; the lockstep risk is tracked instead. |
| Shared Xcode scheme committed | `xcshareddata/` was absent — `xcodebuild -scheme escape_plan` worked only on one machine. |
| `rules/vendors/anthropic.md` globs fixed | Pointed at `backend/app/api/**`, which does not exist. The Anthropic grounding rules were silently never loading when editing the actual endpoint code (`main.py`, `api_chat.py`). |

Measured state (settles prior contradictions): backend **196** tests, EditorCore **128**, iOS **242** (238 unit + 4 UI), corpus 11 sources / 6 files. `/chat` and `/analyze` degrade to a clean 502 without a key — verified, not assumed.


## S2.4 — Persistence manual test checklist

Automated coverage (`./scripts/verify_export_validates.sh`, 17 tests) proves the store's
behaviour; this checklist is what only a human on a device can confirm — that the app really
does come back the way it was left. Run it on a device once S2.1/S2.2 wire `HomeModelStore`
to `HomeDocumentStore` (see the `TODO(integration)` notes in `escape_plan/Persistence/`).

**Kill and relaunch → everything persists**
- [ ] Save a home, force-quit from the app switcher (not just background), relaunch → the home
 is in the list with the same name, floor count, room count.
- [ ] Open it → the editor shows the same rooms/openings; nothing silently reset to defaults.
- [ ] Edit a room, force-quit *without* leaving the editor, relaunch → the edit is there
 (this is the autosave contract, and is S2.1's to honour — persistence only stores what
 it's handed).
- [ ] Relaunch with the device in Airplane Mode → the list still loads (nothing here is
 network-dependent).

**Two homes coexist**
- [ ] Save two homes with different names → both listed, correct floor/room counts each.
- [ ] Edit one → the other's last-modified is unchanged.
- [ ] Delete one → the other still opens.

**Duplicate**
- [ ] Duplicate a home → a new row appears named "<name> copy".
- [ ] Rename the copy → the original's name is unchanged.
- [ ] Delete the copy → the original survives.

**Export / share**
- [ ] Export → share sheet appears; send to Files/Mail/AirDrop → a `.json` lands.
- [ ] Open the exported file in a text editor → it's a HomeModel document, readable, not an
 app-private wrapper.
- [ ] Run `cd backend && python3 -m app.validate <exported file>` → OK.
- [ ] Re-import the exported file → it appears as a *second* home; the original is untouched.

**Schema version**
- [ ] Hand-edit a saved document's `schema_version` to `"2.0"` (via the export/import path or
 a debug build), open the list → the home is refused with the "newer version" message,
 the app does not crash, other homes still list, and the file is left on disk unmodified.

**Storage hygiene / privacy**
- [ ] Delete the app → homes are gone (scope lock: local only, no accounts, no cloud copy).
- [ ] Confirm the device id is a random UUID in UserDefaults (`escape_plan.device_id`) — not
 `identifierForVendor`, no name/email/account anywhere in the document.

## 2026-07-22 — Tab screens wired to real S1.3/S2.1/S2.4 code

`EditorScreen`/`PlanScreen`/`HomeScreen` were rewritten from S0.3-era placeholders into real
screens backed by `HomeLibrary`/`HomeDocumentStore`/`HomeModelStore`/`DollhouseSceneBuilder` —
all of which already existed and were tested, just never read by the tab shell. New file
`Editor/SceneKit/EditorSceneController.swift` supplies the `EditorSceneAdapter` conformance
`SceneKitEditorBridge` was written against (S2.1 predates S1.3 on the branch it was built in).
Chose a fixed top-down **orthographic** camera for the editor (exact screen→floor-plane math,
no conflict with `allowsCameraControl`'s orbit gestures) — the Plan tab keeps the free-orbit
perspective camera from `DollhouseSceneView`/`DollhouseDemoView` unchanged. Full writeup:
`docs/tracker/notes/2026-07-22-home-editor-plan-integration.md`. No schema, backend, or
dependency changes.

## 2026-07-22 — S3.5 iOS half: preparedness score screen

The S3.5 backend was already DONE; this lands the iOS screen. Decisions:

- **Score lives under Home, not a sixth tab.** The TabView already has five tabs (a sixth
 overflows into iOS's "More" list), and the score is per-home data — so it's a per-home push
 from the homes list (leading swipe "Score" / context menu), exactly how the editor and the
 S3.4 profiles screen are reached.
- **No client-side score math.** Every checklist toggle persists locally then re-POSTs
 `/score` with the updated `checklist_state`; the displayed number and breakdown are always
 the backend's, so "score matches documented backend math" holds by construction. Verified
 against `docs/preparedness-score-weights.md`: bungalow 75 → 80 (`practice.meeting_point`)
 → 100 (all items); twostory 75 → 77 (one alarm item, +15/7 half-up).
- **Checklist done-state persists in UserDefaults** (`checklistState.<home_id>`), NOT on the
 home document: the schema is frozen (no checklist field without a version bump) and
 `HomeDocumentStore` files are exactly HomeModel JSON by design (export is the stored file).
 This deviates from `backend/app/scoring/checklist.py`'s "persisted on the home document"
 docstring; consequence: checklist state does not travel with export/import, and deleting a
 home leaves a tiny orphaned defaults entry.
- **Request sends only `home` + `checklist_state`.** `findings`, `constraints`, `profile`,
 and `include_recommendations` are omitted (server defaults) until /analyze (S3.2 wiring)
 and recommendations land — so the findings component reads 20/20 for now, as designed.
- **`APIClient+Score.swift` uses `URLSession.shared`**: `session` is `private` (file-scoped)
 in `APIClient.swift`, which this session was forbidden to edit; the default init uses
 `.shared` anyway, so behavior is identical. This file establishes the
 `APIClient+<Endpoint>.swift` extension pattern for future endpoints.

No new dependencies (SwiftUI + URLSession only). Full writeup:
`docs/tracker/notes/2026-07-22-s3-5-score-ios.md`.

## 2026-07-22 — S3.4 iOS half: profiles CRUD UI (live re-fetch deferred to S2.3)

The S3.4 backend was already DONE; this lands the profile CRUD UI. Decisions:

- **Profiles are edited per-home from the Homes list, not from Settings.** Profiles live
 inside the HomeModel document (`HomeModel.profiles`), so the UI is a per-home push from
 the homes list (leading swipe "Profiles" / context menu → `ProfilesScreen`), sharing the
 entry-point pattern with the S3.5 score screen. Settings stays app-global config only.
- **Profile mutations go through new append-only `EditAction` cases**
 (`addProfile` / `updateProfile` / `deleteProfile`) reduced in `HomeModelStore` — so they
 get validation, the commit hook (undo + autosave), and the "rejected actions leave the
 model untouched" guarantee for free. No new validation code was needed:
 `EditorValidation.validate` already enforced every profile invariant since S2.1.
- **Bedroom picker shows ALL rooms grouped by floor** (bedroom-typed rooms hinted with a
 bed icon), not filtered to `type == .bedroom` — fresh editor homes default rooms to
 `.other`, and the schema allows any room id as a bedroom, so filtering would dead-end.
- **`ProfileTag.displayName` lives in `Screens/ProfileEditorView.swift`**, not
 `Models/Enums.swift` — Models/ stays a pure schema mirror.
- **Live route re-fetch on profile switch is deliberately NOT built** — it needs S2.3's
 route overlay on PlanScreen (untouched this session). Marked with `TODO(integration)` in
 `ProfilesScreen.swift`; the remaining S3.4 acceptance boxes stay open until then.

Tests: `escape_planTests/EditorCore/ProfileActionsTests.swift` (11 tests via the SwiftPM
harness). No schema, backend, or dependency changes. Full writeup:
`docs/tracker/notes/2026-07-22-s3-4-profiles-ios.md`.

## 2026-07-22 — S2.3 route visualization on the 3D dollhouse

Full overlay code landed (P3, on top of the same-day PlanScreen/dollhouse integration);
device eyes-on pass + acceptance recording remain, same posture as S1.3. Decisions:

- **`Models/RoutePlan.swift` mirrors `backend/app/routing/plan.py`**, not the homemodel
 schema — same snake_case wire-mirror stance as `ScoreModels.swift`. Backend-defaulted keys
 (`findings`, `bottlenecks`, S3.4 penalty constraints) decode leniently so the pre-S3.4
 committed samples in `docs/route-samples/` all decode. `RoutesRequest` omits nil
 `constraints`/`profile_id` keys entirely (backend 422s when both arrive).
- **S2.3 sends no `profile_id`** — the playbook's "default profile" has no counterpart in
 the app (nothing selects one), so the fetch is the base whole-house plan; `fetchRoutes`
 is parameterized so S3.4's live-switch TODO(integration) is UI-only work now.
- **Route tubes live in per-floor `"routes:<floorID>"` containers** under the builder's
 floor nodes: exploded view and floor hiding apply with zero overlay code. Floor crossings
 render as paired glowing stubs (one per floor, floor-local) instead of a cross-floor tube,
 which would need per-frame recompute under explode.
- **Custom tube geometry with arc-length-normalized UVs**; the primary's pulse is a
 fragment shader modifier on `u_time` (bands travel room → exit at constant speed), so
 `DollhouseSceneView` gained `wantsContinuousRendering` (continuous redraw only while
 routes are shown). Secondary dashes are alpha-zero in the shader, not `discard` —
 SceneKit's GLSL→Metal transpile of discard is unreliable across OS versions.
- **"Everyone" mode draws primaries + badges only**; both routes render once a single room
 is picked — a whole-house overlay with every secondary was unreadable.
- **Warning badges render engine findings verbatim** (`no_secondary_egress` = red `!`,
 `no_viable_route` = dark `✕`, billboard over the room) — the client never derives egress
 judgments. Acceptance for the badge runs on the **apartment** fixture per the 2026-07-16
 finding-vs-fixture note.
- **Tour = one `SCNAction.customAction`** sampling an arc-length table at 1.5 m/s with 1 m
 look-ahead on a temporary camera; explode/hidden floors reset before flight; free orbit
 restored on finish/cancel. `APIClient.swift` untouched (extension pattern per S3.5);
 90 s request timeout for Render cold starts, surfaced as a non-blocking banner.

Tests: `escape_planTests/RoutePlanTests.swift` (14) + full suite green on the iPhone 17 Pro
simulator. No new dependencies (SceneKit/URLSession only). Full writeup:
`docs/tracker/notes/2026-07-22-s2-3-route-visualization.md`.

## 2026-07-22 — S4.2 drill mode (guided walkthrough half)

Built S4.2's independent half ahead of S4.1: the playbook lists S4.1 as prereq, but
every building block the walkthrough needs was already merged (S2.3 tour, S3.4 profile-aware
`/routes`, S3.5 practice checklist seam) — S4.1's golden path shares no code with it. All new
code sits in `escape_plan/DrillMode/`; nothing else was edited. Decisions:

- **Guided walkthrough, not quiz** (the playbook's recommended format). Select a family
 member → step waypoint-by-waypoint along their primary route → cited instruction cards →
 meeting-place card → "mark plan as practiced."
- **Per-segment reuse of `RouteOverlay.startTour`**: the tour API is one continuous flight
 with a single completion, and S4.2 may not edit it. Each "Next" flies a two-waypoint
 `Route` slice of the fetched route's own waypoints — a camera path, not a computed route
 (no new coordinates; `startTour` re-measures arc length itself). Floor crossings (paired
 `stair` waypoints, same node_id) become card-only steps — no zero-length flight.
- **"Mark plan as practiced" flips exactly `practice.drill_recent`** in
 `ChecklistStateStore` (the id `backend/app/scoring/checklist.py` reserved for S4.2).
 `practice.meeting_point` stays a manual ScoreScreen toggle — the drill can't verify a
 family actually agreed on a spot. No client-side score math: ScoreScreen re-POSTs `/score`
 with the updated state, so the number moves on its next appearance.
- **Card safety copy is paraphrased from `backend/corpus/escape-planning-nfpa.md`** with
 inline `[cite: nfpa-escape-planning]` / `[cite: usfa-escape-plans]` tags rendered verbatim
 plus id chips (AssistantScreen precedent). Purely navigational lines carry no citation. A
 unit test resolves every id in the copy against the real `sources.json`.
- **Entry point deferred**: navigation is owned by the flow lane, so `DrillScreen.swift`
 carries a `TODO(integration)` (mirror HomeScreen's Score/Profiles push) instead of touching
 ContentView/HomeScreen.

Tests: `escape_planTests/DrillModeTests.swift` (8: step derivation, stair crossings, clamping,
citation resolution, practiced persistence) + full suite green on the iPhone 17 Pro simulator;
EditorCore 128, backend 196, corpus valid. No new dependencies. Acceptance ("complete a drill
for two profiles, score moves") is device-only and stays unchecked. Full writeup:
`docs/tracker/notes/2026-07-22-s4-2-drill-walkthrough.md`.

## 2026-07-22 — S4.1 onboarding flow backbone (device-independent half)

Golden-path loop built against the bundled twostory fixture (real scans wait on S1.4/S1.5);
the two acceptance boxes stay unchecked as device-only. Decisions:

- **Demo seed is a flagged COPY of twostory** — `Onboarding/FixtureSeeder` re-marks 3 items
 (top-floor first room + first two openings) as `source: scan`, `confidence: 0.4` under a
 fresh home_id, because every fixture is all-manual and "N items need review" would be
 vacuously 0. Fixture files and the drift-guard are untouched; N uses the editor's own
 `HitTesting.needsReview`, so onboarding and the pulsing badges always agree.
- **`Networking/APIClient+Analyze.swift`** — /analyze joins the per-endpoint extension
 pattern; `Models/AnalyzeModels.swift` mirrors the wire contract (same stance as
 RoutePlan/ScoreModels; the tool trace is deliberately not decoded — the app doesn't
 render it).
- **Last-good RoutePlan cache** (`Networking/APIClient+Cache.swift`) —
 `<Documents>/RouteCache/<home_id>.routeplan.json`, atomic; only connection-class URLErrors
 fall back to it (server answers like 401/422 rethrow — a stale plan must not mask a config
 problem). `PlanScreen.fetchRoutes` routes through it and shows a dated offline banner —
 the one pre-agreed touch outside the session's owned files.
- **Onboarding shows once** (`@AppStorage "onboarding.completed"`, full-screen cover from
 `ContentView`); every backend call in the flow renders an explicit
 loading/loaded/failed/offline `LoadState` — the dead-end kill list is tabulated in the
 session note.
- **Persistence bug fix (out-of-surface, flagged for P2 review)** —
 `HomeDocument.init(model:)`/`decode(as:)` used default JSONEncoder/Decoder date handling
 (Doubles) while `touched()` stamps ISO-8601 strings, so any HomeModel saved via
 `save(model:)` failed to load back (`meta.modified` type mismatch). S2.4's stub-model test
 couldn't see it; the S4.1 seeding test caught it. Both coders now use `.iso8601` per the
 schema. Pre-fix autosaved documents (Double `meta.created`) were unloadable before and
 after — delete and rebuild, or add a SchemaMigrator normalization if real ones surface.

Tests: `escape_planTests/OnboardingTests.swift` (9) + full suite green; EditorCore 128.
No new dependencies. Full writeup: `docs/tracker/notes/2026-07-22-s4-1-onboarding-flow.md`.

Addendum (same session, while producing the handoff recording): fixed a second latent dead
end — `PlanScreen` never called `reload()` when homes existed at first appearance
(`onChange(of: library.homes)` doesn't fire for the initial value), leaving an infinite
"Loading…" spinner; one-line `.task` fix. Handoff recording lives at
`docs/demo/broll/s41-golden-path-simulator.mp4` (b-roll contract dir), driven by
`escape_planUITests/GoldenPathRecordingUITests` — env-gated (`TEST_RUNNER_GOLDEN_PATH=1`,
live backend required) so the normal suite stays hermetic.

## 2026-07-22 — Device-acceptance pass (S2.2/S2.3/S3.4/S3.5 on-simulator) — P3

- **How it was driven**: no XCUITest additions (no source edits allowed this session). Used
 Facebook `idb` (`brew: facebook/fb/idb-companion` + `pip: fb-idb`) to send real HID
 taps/swipes/text to a simulator, `simctl io` for screenshots/recordings. A first attempt at
 window-level CGEvent clicking (pyobjc) was abandoned — a full-screen window from another app
 kept focus and intercepted synthetic clicks; idb talks to the device directly and needs no
 window focus. Toggle switches don't respond to idb taps — knob-drag swipes flip them.
- **Isolation is mandatory**: the default 'iPhone 17 Pro' device and `.build-merge` derived
 data are shared with concurrently running Claude sessions (an `xctrunner` from another lane
 was live mid-pass). Symptoms: spontaneous device shutdowns, app data wiped, and a *different
 lane's build* (with onboarding + the S4.1 date fix) silently replacing the one under test.
 Fix: dedicated `p3-acceptance` device + private `-derivedDataPath .build-p3`.
- **Backend**: local uvicorn (`BACKEND_BEARER_TOKEN=devtoken`, port 8000) because the Render
 bearer token isn't available to sessions; APIClient's UserDefaults-backed
 `baseURL`/`bearerToken` were written via `simctl spawn defaults write`. /routes + /score are
 deterministic — acceptance did not need ANTHROPIC_API_KEY. Native phone-on-cellular timing
 (S1.6) remains deferred as before.
- **Fixture seeding**: no in-UI fixture loader exists — `schema/fixtures/{twostory,apartment}.json`
 were copied straight into `<data-container>/Documents/Homes/<home_id>.homeplan.json`. On the
 pre-S4.1 build this tripped the (since-fixed) HomeDocument date-strategy mismatch from both
 directions (ISO fixture → "expected Double"; converted-to-Double → post-fix build says
 "expected String"). Post-S4.1 code + raw ISO fixtures work. Confirms the S4.1 fix from the
 consumer side.
- **UI bugs found for P2** (all reproducible, screenshots in `artifacts/acceptance-2026-07-22/`):
 1. `EditorScreen` toolbar state only re-renders on `revision` bumps; `store.selection` is not
 observed. A plain tap-selection therefore never enables "Add Stairs" (and after undo clears
 selection it stays stale the other way). Workaround used: drag-select then any
 revision-bumping action (Add Room) → toolbar catches up. Suggested fix: bump revision (or
 make the store observable) in the tap-selection path.
 2. A redo tap issued ~2s after undo was dropped once (state showed correctly on a second
 tap) — likely the same stale-render class.
 3. Cosmetic: `highlight(_:)` clearing to `.none` doesn't repaint until the next commit
 (`rendersContinuously=false`, no `setNeedsDisplay` on highlight-only changes), so a stale
 yellow selection marker lingers.
- **Scorecard**: S3.5 fully DONE; S2.3 + S3.4 observed except real-device 60fps (S2.3) and
 key-blocked explanation text (S3.4); S2.2 observed except the real-converted-scan door-fix
 criterion (needs S1.4/S1.5). Evidence + b-roll: `artifacts/acceptance-2026-07-22/`.

## 2026-07-23 — Revamp A1: hand-rolled orbit camera replaces `allowsCameraControl`

Approved revamp (grilled spec, saved plan): one free-camera translucent dollhouse that is
simultaneously viewer and editor, objects that block routes (schema v1.1 + within-room grid
pathfinding), and an agentic LLM house builder behind a forced human-review gate. Sequencing
A (unified view) → B (objects/routing) → C (builder). This session shipped A1:

- **`allowsCameraControl` replaced** by `CameraRigModel` (pure Foundation, editorcore-tested)
  + `OrbitCameraRig` (SceneKit binding). Why: pinch must zoom toward the pinch point (the
  stock controller zooms at the scene center), and A2's editing drags need to share gesture
  arbitration with the camera — impossible against the black-box default controller.
  Zoom-to-point math: `d' = d/s`, `pivot' = anchor + (pivot − anchor)/s`.
- **The rig node is owned by the view layer** and re-attached across scene rebuilds, so the
  editor's rebuild-on-every-edit strategy no longer resets the camera (pre-req for A2).
- **`RenderOrder` ledger** (`Renderer/RenderOrder.swift`): all `renderingOrder` magic numbers
  centralized into spaced bands (opaque 0 / objects 5 / walls 10 / glow 20 / routes 30 /
  labels 100+); route tubes now explicitly draw after the translucent shell. A renderer test
  asserts every geometry node sits in a known band and that depth-write-off materials never
  draw in the opaque band.
- **Tour teardown** now restores `pointOfView` to a caller-supplied node instead of flipping
  `allowsCameraControl` back on (RouteOverlay.startTour gained `restoreTo:`).
- `DollhouseScene.setFloorFade(_:opacity:)` added (node.opacity only — materials stay
  untouched) for the coming floor-spotlight chips.
- `DollhouseSceneView` is superseded by `UnifiedSceneView` but not yet deleted — PlanScreen
  now uses the unified view; deletion happens in A3 after the editor migrates (A2).

## 2026-07-23 — Revamp A2: editing in the unified free-camera view

- **Arbitration-by-selection**: a one-finger pan edits ONLY when it begins on the current
  selection (or a vertex/wall of the selected room) — decided once at `.began` by the pure
  `GestureArbiter` and latched for the whole gesture. Anything else orbits. Worst case is one
  extra tap; there is no mode switch.
- **One pan recognizer, branched on touch count** (1 = edit/orbit, 2 = truck), pinch runs
  simultaneously with pan. An earlier split into per-touch-count recognizers was scrapped.
- **`UnifiedSceneController` replaces `EditorSceneController`** as the `EditorSceneAdapter`:
  whole house visible while editing, unprojection onto the active floor's *presentation* Y
  (works mid-explode), `metersPerPoint()` measured by probing the drag plane (perspective-
  correct tolerances). `EditorSceneController` is now dead code — deleted in A3.
- **Wall drags slide along their normal**: `Geometry.projectOntoEdgeNormal` strips the
  along-edge component before `.dragEdge` dispatch.
- **UI-automation camera**: the manual-build recording driver can't invert a free perspective
  camera, so `-editor.topDownCamera YES` pins the old deterministic ortho frame (same math,
  verbatim). Driver updated: selects a room before dragging its corners, and **pins portrait
  orientation** — the driver's failures during this session were ultimately a simulator left
  in landscape while the device reported portrait, which silently breaks synthesized drags
  (taps survive). Documented here because it looks exactly like an app bug and cost a debug
  cycle: check orientation FIRST when synthesized drags do nothing.
- New simulator test `UnifiedEditorPipelineTests` drives SCNView projection → controller →
  arbiter → bridge → store end-to-end (perspective AND top-down modes), so the join-rooms
  regression class is caught in seconds instead of the 2-minute env-gated UI run.

## 2026-07-23 — Revamp A3: HouseScreen consolidation (+ two real interaction bugs found)

- **`HouseScreen` replaces `EditorScreen` + `PlanScreen`** (both deleted, along with
  `EditorSceneController` and `DollhouseSceneView`). One free-orbit translucent dollhouse is
  simultaneously the editor and the route viewer; tab shell is now Home / House / Assistant /
  Settings. Any accepted edit invalidates the shown plan and re-fetches `/routes` after a
  0.9 s debounce — routes remain server truth, never client-computed. `DrillScreen` moved to
  `UnifiedSceneView`. Onboarding's plan step and HomeScreen's push destinations use HouseScreen.
- **Layout law: the scene view's frame must never change mid-gesture.** Chrome (inspector,
  placement hint, route controls) lives in a FIXED-HEIGHT scrollable dock under the scene.
  Both alternatives failed in practice: chrome stacked below the scene resizes it when panels
  appear/vanish (an in-flight drag's world shifts under the finger — the driver caught vertex
  drags landing ~1.7 m off), and chrome overlaid on the scene swallows touches aimed at
  geometry behind it.
- **Pan-recognition slop is real and breaks arbitration**: a `UIPanGestureRecognizer` begins
  ~10 pt after touch-down and `translation` at `.began` does NOT fully cover the slop, so
  neither `location` nor `location − translation` is the press point. At typical zooms 10 pt
  crosses to a neighboring room's vertex — the drag then hits the wrong room and arbitration
  latches camera. Fix: `InitialPointPanGestureRecognizer` records the true touch-down point
  in `touchesBegan`; arbitration and the edit-drag anchor use that.
- **Route overlay across rebuilds**: `UnifiedSceneController.onRebuild` re-hangs the overlay
  on every rebuilt scene. The overlay lives in a stable class box, not directly in @State —
  `onRebuild` fires inside `updateUIView`, and reassigning @State there invalidates the view
  from within its own update, an endless rebuild loop.
- **Debugging pattern that worked** (promoted for reuse): a rolling gesture-event log in the
  scene view's `accessibilityValue` (gated behind `-editor.topDownCamera` so VoiceOver never
  reads it) + the driver failing with `scene.value` in the message. Simulator log streams
  never reach the cloned test simulator; this does.

## 2026-07-23 — Revamp B1: schema v1.1 (objects + ai_plan source)

One bump covers both remaining revamp projects (B's objects AND C's ai_plan source) so the
three-way lockstep churn happens exactly once. Changes, in lockstep across JSON Schema /
pydantic / Swift Codable (+ round-trip tests green):

- `floor.objects[]` (default []): `{id, category, center, size_m [w,d], height_m,
  rotation_deg (default 0), source, confidence}` — rotated box primitives, rendered as
  prisms, obstacles for B3's within-room routing. **No `room_id`** — containment is derived
  geometrically so moving a room can never dangle an object reference.
- `source` gains `"ai_plan"`; the confidence rule generalizes: scan AND ai_plan items must
  carry confidence (pydantic `SourcedModel`).
- `SchemaMigrator` 1.0 → 1.1 registered (re-stamps the version; decoders tolerate a missing
  `objects` key). Migration + decode covered by a new PersistenceTests case.
- Fixtures re-stamped to 1.1; new planted fixture `bungalow-blocked.json` (wardrobe fully
  blocking the bedroom doorway + sofa mid-room) for B3's obstacle-routing assertions.
- Scan converter now emits 1.1. FastAPI app version string is unrelated and unchanged.
- Process note: this lands as its own commit on `lane/editor`; the branch itself is the PR
  unit for team sign-off per the schema rules.

## 2026-07-23 — Revamp B2: objects rendered + editable

- Objects render as opaque rotated `SCNBox` prisms (`object:<id>`, RenderOrder band 5 —
  under the translucent shell, over the slab), muted per-category tints. Malformed size_m
  surfaces as a BuildIssue, never a crash.
- Editor vocabulary: `addObject/deleteObject/dragObject/rotateObject/resizeObject/
  setObjectCategory`; `Selection.object`; `dragObject` coalesces like other drags. Objects
  join the global id namespace in EditorValidation (pydantic lockstep). Validation is
  deliberately permissive about placement — an object poking outside a room is scan-data
  reality, not an error.
- Hit-testing: point-in-rotated-rect; objects win over the room interior, topmost
  (last-listed) object wins on overlap. GestureArbiter unchanged — an object edits only
  while selected, like every non-room entity.
- HouseScreen: Add Object drops a default box at the selected room's centroid, pre-selected
  for immediate dragging; inspector = category picker + rotate-45° + delete.

## 2026-07-23 — Revamp B3: within-room grid pathfinding (obstacle-aware routing)

- **Grid over navmesh, per ROOM not per floor**: a room ↔ opening leg is by definition
  within one room, so each object-bearing room gets its own 0.1 m occupancy grid — no wall
  bands, no opening punch-through, and rooms WITHOUT objects keep the literal pre-B3
  straight-line legs (`grid is None` fast path). Zero golden churn on the existing fixtures,
  asserted by `test_object_free_fixtures_keep_straight_legs`.
- **Determinism recipe**: integer cells, integer step costs (10/14), heap tie-break
  (f, h, row, col), chamfer 3-4 distance transform in scaled ints, ring-then-row-then-col
  endpoint landing, greedy supercover-Bresenham smoothing. Byte-equality asserted.
- **Clearance = door_min_width_m / 2 from the corpus thresholds** (metric authoritative,
  loaded never hardcoded): an object that shrinks a passage below the egress width blocks
  the leg even without touching a wall.
- **Endpoint landing radii differ on purpose**: a START (room centroid) lands generously
  (1.5 m — a centroid can sit inside the bed; the person starts beside it), a GOAL (doorway
  midpoint) must land AT the doorway (max(width/2, 0.6 m)) or the wardrobe in front of the
  door would be "reached" by standing next to it. This distinction is what makes
  blocked-doorway detection work at all.
- **Room-graph architecture kept**: blocked leg ⇒ edge omitted ⇒ existing Dijkstra re-plans
  with zero new logic; `blocked_opening` finding (additive) surfaces why. Grid work happens
  once per room in `build_graph`; `find_bottlenecks` stays graph-only. Cached grid waypoints
  splice into routes as `kind: "path"` (additive; Swift decodes both new kinds, drill cards
  treat path like room). Evidence sample: `docs/route-samples/bungalow-blocked.json` (40
  curve points + the finding).

## 2026-07-23 — Revamp C1: LLM house builder (backend agent + /build)

- `backend/app/builder/actions.py` (pure): the Python mirror of the editor vocabulary — NOT
  a Swift port. Shared semantics = the pydantic validators both halves already obey; the
  only re-expressed editor logic is parametric opening placement (span clamping +
  adjacency-derived room_ids, mirroring OpeningPlacement.swift — interior vs EXTERIOR is
  geometry, the model is never asked). Forgiving where it should be (CW polygons reversed,
  not rejected); loud, specific ActionErrors where the model needs feedback.
- `backend/app/ai/builder.py`: hand-rolled loop cloned from agent.py, cap 40 (construction
  is ~one call per entity). **No routing/egress tools** — asserted by a test. Provenance is
  structural: every created element gets source=ai_plan + confidence 0.5 from the action
  layer; the model cannot emit a "trusted" element, which is what makes the iOS review gate
  non-bypassable. An invalid submit_home bounces back with the pydantic errors so the model
  self-corrects within the budget; ending without a valid draft returns home=None + issues,
  never a broken model.
- `POST /build` (bearer-gated): {description?, image_b64?, image_media_type} → BuildResult
  {home, trace, truncated, issues}. Vision input as content blocks; PDFs will be rasterized
  client-side (C2, PDFKit) — no new backend dependency.
- Tests: 13 pure action tests (rejections emphasized), 6 scripted-loop tests, 1 live golden
  (`-m live`, needs the API key — blocked on the same key as every other live suite).

## 2026-07-23 — Revamp C2: plan-import flow + the forced review gate

- Intake scope-lock officially relaxed (per the approved revamp spec): LiDAR-only becomes
  LiDAR + AI-drafted plan import, BOTH funneling through editor review. The judge story is
  unchanged and stronger: AI accelerates input, the human verifies, the engine routes.
- **The gate is structural at every layer**: the builder can only emit `source: ai_plan`
  (action layer stamps it); `HitTesting.needsReview` says ai_plan ALWAYS needs review
  regardless of confidence; `HomeModel.hasAIDraftContent` blocks `fetchRoutes` in
  HouseScreen until `.confirmAIDraft` (a single undoable commit) flips every ai_plan
  element to manual. No prompt behavior can bypass it.
- `BuildFromPlanView` (text + photo + PDF): PDFs rasterized client-side with PDFKit at
  ~150 dpi — the backend only ever sees PNG/JPEG, zero new backend deps. Entry point lives
  in HomeScreen's toolbar next to Scan.
- This is also the fast test path the revamp wanted: describe a home → draft → review →
  routes, no LiDAR and no manual building required.

## 2026-07-24 — Look-and-feel pass, starter data, and obstruction attribution

Session goal was Anish's question, not a playbook session: *does the app work, and does it
look good?* All four suites were green before any change (EditorCore 186, backend 238,
corpus valid, iOS TEST SUCCEEDED). Looking at it on the simulator produced four findings,
three of which are fixed here.

- **The dollhouse backdrop goes dark.** `DollhousePalette.background` was a cream "diorama
  table" chosen when the renderer was viewed on its own. Inside the shipped app it butts
  against black chrome on all four sides and reads as a hole cut in the UI. It is now a
  near-black stage with a subtle vertical gradient (`stageBackdrop()`), which also gives the
  hot-orange route the contrast it was designed for. **Floor slabs stay pale on purpose** —
  they are the paper the plan is drawn on, and dark room labels have to stay readable on them.
- **Room labels ride a billboarded plate.** A label crossing a pale slab, a translucent wall
  and the dark stage within one orbit has no single text color that stays legible, so the
  glyphs went near-white on a rounded translucent plate sized from the text bounds. Adds two
  RenderOrder bands (`labelPlate` 100 / `labelText` 101); the renderer band test asserts the
  set, so it was widened in the same commit.
- **The three demo homes are now seeded on first launch** (`FixtureSeeder.seedStarterHomes`,
  called from `escape_planApp.init`). Nothing previously created Bungalow / Apartment 4B /
  Two-Story House: onboarding seeded only a degraded "Demo Home (scanned)" copy, so the demo
  path depended on hand-built data. Seeding happens at launch rather than inside onboarding
  because skipping the tour must not leave the demo with nothing to demo, is guarded by a
  defaults flag so a deliberately deleted home is never resurrected, and saves each fixture
  under its OWN `home_id` so a re-run overwrites rather than accumulating copies. Evidence
  that this mattered: before the change the S4.4 screenshot driver skipped four steps
  (including the profile-switch money shot) because it addresses those homes by name; after,
  it skips two and renders the tour and profile-switch shots.
- **`blocked_opening` findings now name the object and the distance.** New
  `app/routing/obstructions.py` attributes a blocked doorway to the specific furniture by
  **counterfactual re-rasterization** — an object is a culprit when removing it restores the
  leg — rather than by proximity, so a sofa near a door is never blamed for a doorway a
  wardrobe actually blocks. The move distance is measured (bisection on the clearance the
  leg tolerates), not invented: "move the wardrobe about 0.85 m" instead of "an object blocks
  the doorway". The same probe at two clearances separates a blockage from a squeeze.
  `RouteFinding.object_ids` is additive and defaulted (Swift decodes it with
  `decodeIfPresent`), so nothing older breaks.
- **Checklist id collision fixed on the way past**: `routes.<kind>.<room_id>` collapsed two
  blocked doorways in one room onto a single checkbox, and gave them the wrong title
  ("has no usable way out"). Blocked-opening items now key on the blamed objects and cite
  `usfa-escape-plans` ("keep exits clear"), which is the claim they actually make.
- **Garbled-generation glitch: tolerated, not retried** (Anish's call, 2026-07-24). The
  one-in-twelve corrupted-but-cited `/explain` response observed 2026-07-23 gets no
  server-side coherence gate. Accepted as API variance; the user-visible mitigation is
  re-asking. Revisit only if it recurs at a higher rate.
- **`/explain` p95 deferred, not decided.** Anish's reasoning: the submission is an edited
  video, so a slow call can be cut around. The acceptance criterion stays formally UNMET and
  is still in TODO.md — this is a scheduling decision, not a resolution.

## 2026-07-24 (later) — Route-rendering bug, live-AI unlock, builder temperature

- **Escape routes were silently not rendering in the House tab** — the app's core visual. Root
  cause (found by instrumenting with NSLog + `log stream`, after three wrong theories): the
  `onRebuild` closure in `HouseScreen.attach` captures the SwiftUI View struct, and reading
  `@State routePlan` from inside it returns a stale snapshot (perpetually nil).
  `EditorSceneView.updateUIView` rebuilds the scene to a fresh empty one on every render, and
  the stale-self redraw drew nothing — so every rebuild wiped the routes a fresh-context draw
  had just added. Fix: cache draw inputs (plan/selection/model) AND view state
  (explode/spotlight) in the stable `RouteOverlayHolder` class; `onRebuild` redraws from the
  holder, never from captured @State. The explode slider had the identical latent bug (snapped
  back to 0 on rebuild) and is fixed by the same change. This is a general SwiftUI lesson for
  this codebase: **never read @State inside a closure stored on the UIKit/SceneKit
  controller — route it through a reference-type holder.**
- **Builder dropped `temperature`.** The live builder golden failed with
  `400 "temperature is deprecated for this model"`; `agent.py`, `grounded.py` and
  `chat/service.py` already omit sampling params for the same reason. Removed it from
  `builder.py` too. Determinism there comes from the tight tool schema + the forced-review
  gate, not temperature.
- **Live AI is unlocked locally**: the key lives in repo-root `.env` (gitignored). Live suite
  is 12/12 after the builder fix. The Render dashboard env var is still outstanding for the
  deployed backend.

## 2026-07-29 — UI revamp: parametric fixture kit for the dollhouse renderer

- The renderer's single-color boxes (walls, flat opening panels, ziggurat stairs) are
  replaced by a **fixture layer** (`escape_plan/Renderer/Fixtures/`): parametric specs +
  builder protocols + a swappable `FixtureCatalog`. Rationale: every home renders from the
  same component vocabulary (consistent look across scans — the driving-viz principle), and
  builders are replaceable wholesale — `AssetFixture` bounding-box-fits a bundled
  `.usdz`/`.scn` onto any spec, so hand-modeled doors/windows/stairs plug in without
  touching the scene builder. Local-frame contract is documented in `FixtureKit.swift`.
- Walls carve REAL holes for openings (pier/sill/header box composition). The cutouts and
  the door/window fixtures are computed from the same clamped numbers on the same deduped
  wall — joins are seamless by construction, not by tuning. Two new RenderOrder bands:
  `fixtures = 6` (opaque detail under the translucent shell), `glass = 12` (panes blend
  after walls). The see-through dollhouse regime (depth-write-off walls, hot routes on
  top) is unchanged.
- All fixture tones derive from the existing `DollhousePalette` colors — restyling stays a
  one-file change. Slabs gained per-face materials (accent top / darker cut edge) and the
  house sits on a shadow-catching base plate.
- `RouteOverlay` exit glow now sizes from the opening node's bounding box (was: cast to
  `SCNBox`) — required because openings are now containers, and it decouples the overlay
  from any future fixture builder.
- **Pre-existing bug found and fixed while verifying**: HouseScreen's explode slider and
  spotlight fade never worked — the `onRebuild` closure (captured once at attach) read
  @State through a stale struct copy, so every editor rebuild reset both to defaults.
  Reproduced on unmodified main before fixing. Fix: `SceneViewStateHolder` reference box
  (the `RouteOverlayHolder` pattern); `applyViewState` reads only through the box.

## 2026-07-29 — UI craft pass: room label chips, dock sections, finding cards

- 3D room labels are now pre-rendered capsule chips (`RoomLabelSprite`) instead of raw
  SCNText — legible surface, padding, room-type accent dot; same billboard/label-band
  node contract, so the overlay's badge conventions are untouched.
- The HouseScreen dock is sectioned (View / Escape routes / Route check) with one quiet
  header style. The fixed-height-dock rule (no mid-gesture scene resizes) is preserved.
- Route findings render as severity-tiered cards (`RouteFindingViews.swift`). The card
  TITLE names the machine `kind` ("No way out", "No second way out", "Blocked doorway");
  the `detail` string below stays verbatim from the engine — presentation changed,
  the "client never writes safety judgments" rule did not. Severity colors are the same
  `DollhousePalette` badge colors the 3D scene uses, so both layers agree.

## 2026-07-29 — Glass view controls, scene card, fullscreen mode

- The dollhouse is now a **card** (continuous 26 pt corners, soft shadow, inset), and the
  view controls (floor picker, spotlight, fullscreen) **float on it** in Liquid Glass
  rather than living in the dock. The empty sky above the model was dead space; it is now
  the control surface, and the dock opens directly on route content.
- `Screens/GlassControls.swift` owns the single `#available(iOS 26.0)` fork for the app:
  `.glassEffect` / `GlassEffectContainer` on 26+, `.regularMaterial` + rim stroke below.
  Every floating control goes through it so the two OS versions stay visually consistent
  and no screen repeats the availability dance.
- **Fullscreen (`isImmersive`)** hides the dock, nav bar, tab bar, and status bar and takes
  the card full-bleed. The explode slider floats in glass at the bottom so it does not
  disappear with the dock. Disabled while touring — a frame change would fight the tour
  camera for the point of view.
- The renderer's fixed-dock contract is **partially relaxed, deliberately**: controls may
  overlay the scene as a fixed-height strip (never resizing it); the ban on mid-gesture
  scene resizes still stands, and the immersive toggle is the one frame change, always
  user-initiated from a button.
- **Rejected**: `SCNCamera.projectionDirection = .horizontal` to keep the house's width
  framed at any aspect. On a 1:2.2 full-screen viewport it implies a ~90° vertical FOV,
  which shrinks and visibly skews the model. `.automatic` stays; pinch handles the mild
  crop when entering fullscreen.

## 2026-07-30 — Merge resolution: UI branch wins the renderer, route fix is re-applied

Merging `origin/main` (vedang-123-ai, 13 commits: R310 egress scoring + the Jul 27–29 UI
revamp) into local `main` (Anish, 2 commits: look-and-feel pass, obstruction attribution,
route-rendering fix). Five files conflicted. Standing policy for this merge, on Anish's call:
**the UI branch is authoritative for anything visual** — it is newer and it is a coordinated
system, not a set of independent tweaks.

- **`DollhouseScene.swift`, `DollhousePalette.swift`, `RenderOrder.swift`, and the renderer
  test → taken wholesale from the UI branch.** The local branch had built room labels as
  SCNText on a rounded plate (`labelText` / `labelPlate` palette entries + two RenderOrder
  bands); the UI branch replaced the whole label path with pre-rendered `RoomLabelSprite`
  chips. Keeping both was not an option — they are two answers to the same problem.
  The local `stageBackdrop()` dark-gradient backdrop went with them, because the fixture kit
  derives its entire tone family from `DollhousePalette.background`
  (`basePlate = background.blended(with: exteriorWall, …)`, `wallCap`, `openingFrame`, …).
  Overriding that one constant would have silently restyled every new fixture. **Open
  question, not a closed decision:** the dark backdrop was adopted on 2026-07-24 because the
  cream one reads as a hole cut in the app's black chrome. That observation still stands and
  the UI branch never saw it. Re-decide it deliberately against the new fixture kit rather
  than treating this merge as the answer.
- **`HouseScreen.swift` → UI branch base, with the route fix re-applied on top.** This is the
  one place "take theirs" was wrong, and it is worth recording why. Both branches independently
  hit the same SwiftUI trap: `onRebuild` captures the View struct once, so @State reads inside
  it return attach-time values. Each branch fixed *half* of it. The UI branch boxed the view
  state (`SceneViewStateHolder` — explode/spotlight stopped resetting); the local branch boxed
  the draw inputs (`RouteOverlayHolder` — routes stopped being wiped on every rebuild). Taking
  the UI branch's `HouseScreen` verbatim would have reverted `RouteOverlayHolder` to
  `{ var overlay }` and restored the "controls appear but no route draws" blocker — a core
  demo-path regression (CLAUDE.md: never cut scan → editor → 3D routes → profile switch).
  Both boxes now coexist and own disjoint state; `applyOverlay()` syncs @State into the holder
  from fresh-`self` contexts and `onRebuild` calls `overlayHolder.redraw()`, never `applyOverlay()`.
- **`TODO.md` → union, with completion status winning over the stale copy.** The UI branch
  still listed "Live builder golden — blocked on ANTHROPIC_API_KEY" and "Consider surfacing
  `blocked_opening` in /score" as open; both were closed on the local branch on 2026-07-24
  before it had been pushed. Taking theirs would have resurrected finished work as TODO.
  `decisions.md` and `activity-log.md` were pure chronological appends — both sides kept, in
  date order.
- **Nothing in the backend conflicted.** The local obstruction engine (`app/routing/
  obstructions.py`) and the UI branch's R310 egress-window checklist both landed in
  `checklist.py` in different regions. Backend suite is 252 (was 238 local / 243 theirs).

Gate after resolution: EditorCore 186, backend 252, iOS 308 unit + 14 UI (6 env-gated skips),
corpus valid — all green. **Not yet visually verified**: nobody has looked at the merged
renderer on a simulator. The route fix is verified by construction, not by eye.

## 2026-08-02 — The S3.2 agent gets `check_obstructions`

Closes the "still open" half of the 2026-07-24 obstruction work: the
deterministic attribution existed and fed `/routes` + `/score`, but the AI
inspector could not reach it, so a wardrobe parked in front of a bedroom door
was only ever a checklist row — never something the agent could raise in prose
or in chat.

- **The tool is a window, not a second opinion.** `check_obstructions` calls
  `analyze_obstructions` and returns its fields verbatim, including the
  engine's own `detail` sentence. The model re-words a measured claim; it never
  produces a clearance or a move distance. Same division of labor as routing —
  and the reason the tool description spells out `blocks_opening` vs
  `narrows_route` rather than letting the model coin its own severity language.
- **Optional `room_id`, no required args.** The agent sweeps the whole home in
  one call (the common case, and cheap — rooms without objects cost nothing)
  and narrows only when it is writing up a specific room. Making `room_id`
  required would have meant one call per room against a 15-iteration cap.
- **Prompt rule 1 now names obstructions explicitly.** "Never invent a route or
  an egress verdict" did not obviously cover "don't estimate how far to move a
  sofa," and that is exactly the kind of number a model will happily supply.
- **The measurement is asserted, not hoped for.** Both the scripted test and
  the live case check that the distance in the model's recommendation equals
  the one in the trace. A recommendation that reads well but invented its
  number fails — which is the whole point of routing through the engine.
- **Severity mapping:** `blocks_opening` on a sleeping room's only way out is
  high; any other `blocks_opening` is med; `narrows_route` is low. It is a
  judgment call, so it lives in the prompt where it can be seen and argued
  with, not hardcoded where it would look like a fact.

**Unverified here:** the live case (`test_blocked_bungalow_agent_names_the
_wardrobe`) has never run — no `ANTHROPIC_API_KEY` on this machine. The `.env`
the 2026-07-24 tracker stamp refers to is gitignored and machine-local, not
something a fresh clone inherits. Its golden will be written and needs review
on the first machine that has the key.

## 2026-08-02 — Client/server enum tolerance sweep

Prompted by the Score screen being dead for six days (an unmapped `egress` checklist
category failed the whole `ScoreBreakdown` decode). Swept every Swift enum that decodes
backend output against what the backend can actually emit.

**All ten enums' values match today** — the `egress` gap was the only live mismatch. The
finding is not a second wrong value; it is that three response-only enums were one backend
addition away from breaking a core screen, and one of those additions already exists.

Made tolerant (unknown value → a fallback case, never a throw):

- `RouteFinding.FindingKind` — **the urgent one.** Findings nest inside `RoutePlan`, so an
  unknown kind failed the whole plan and rendered NO routes. `obstructions.py` already
  carries `narrows_route` with nothing surfacing it; wiring that up would have broken
  routes outright, with the engine's own `detail` prose sitting right there, readable.
- `WaypointKind` — same nesting hazard. `path` itself arrived mid-project in the revamp.
- `AgentFinding.Severity` — an unknown severity cost the user every finding the agent
  produced. Sorts as least-severe so it can never masquerade as an urgent one.

Left strict, deliberately: `RoomType`, `OpeningKind`, `Source`, `ObjectCategory`,
`StairKind`, `ProfileTag`. These are not the same kind of thing. They describe the user's
own home, round-trip through local JSON persistence, and are **encoded** as well as decoded.
A silent `unknown` fallback would decode a newer build's `"sunroom"`, re-encode it as
`"other"`, and quietly degrade the saved home on disk with no error anyone ever saw — data
loss wearing the costume of graceful degradation. They are also schema-governed: adding a
value is a reviewed act behind a `schema_version` bump, not something the backend can do to
the client unilaterally. Rationale is in the `Enums.swift` header so nobody "finishes" the
sweep later.

**The general rule this settles:** strict about structure the backend *promised* (a missing
required field is a contract break worth failing on); tolerant about values it may later
*add*. "Fail loudly on unknown enum values" sounds like the same discipline as the former.
It isn't — a test suite cannot fail on a value that doesn't exist yet, so the only thing
that ever fails is the user's app, at runtime, on the demo home.

Also added: `AnalyzeModelsTests` (6 tests). `AnalyzeModels` had shipped with no test file
at all, which is part of why its sibling break in `ScoreModels` went unnoticed.

---

## 2026-08-05 — "White Model" dollhouse overhaul (design-project handoff)

Implements the approved brief `DOLLHOUSE-REDESIGN-SPEC.md` and the locked prototype values in
`swift-implementation-notes.md`, from Claude Design project `344e3e53-37d2-4471-831c-aa50067e9d55`
(three.js prototype: `Dollhouse Prototype.dc.html` + `dollhouse-three.js`). Deviations and
judgement calls, with reasons:

**Scope: renderer core only.** The locked notes also describe a "people" layer (capsule
mannequins per family member, one route color per person, tap-to-isolate) and §10–12 describe an
app-wide chrome pass and an icon redesign. Both are deliberately NOT in this change. The people
layer needs routes fetched for every profile at once, not just the selected one — a real
`/routes` + `HouseScreen` change, not a rendering change. Owner confirmed renderer-only.

**Stayed on SceneKit.** SceneKit was soft-deprecated at WWDC 2025 (maintenance mode, no
hard-deprecation date). The redesign is materials + lighting + camera + fixture swaps — exactly
the seams `FixtureCatalog`, `DollhousePalette` and `CameraRigModel` already abstract. A
RealityKit migration would touch the editor bridge, hit-testing, gesture arbitration, route
overlay, drill mode and label sprites for zero visible gain, and the CAC deadline favors shipping
the look. Phase 1 was kept migration-friendly: camera math stays engine-free, colors stay in one
file, fixture specs stay pure structs. See spec §8.

**Walls are opaque; the exploded-view slider is gone.** These are one decision. The old renderer
answered "let me see inside" with always-translucent walls, and "let me see the floor below" with
a slider that separated the stack vertically. Stacked translucent layers multiply into gray murk
(that was the "reads as CAD" complaint), and the slider broke the model into floating slices while
costing permanent screen space. Both are replaced by: solid opaque walls + an open top + exactly
one ACTIVE floor rendered solid while every other floor ghosts (0.12 above / 0.18 below). Removed
`setExplode`, `setFloorFade`, `explodeGapM`, the `explode` state and both slider UIs, plus the
floor-spotlight toggle (ghosting subsumes it).

**Ghost floors swap materials rather than setting node opacity.** `node.opacity = 0.12` on a
subtree of overlapping boxes stacks every interior face and reproduces the murk. Each ghosted
floor's geometry swaps to one flat unlit back-face-culled white so a wall contributes exactly ONE
translucent layer. Materials are cached per node at build time (`DollhouseScene.GhostEntry`) so
the swap is reversible without a rebuild, and classification keys off the render band a fixture
already assigned — custom `FixtureCatalog` builders keep working for free.

**Two-pass route occlusion instead of `.greater` depth.** The spec asked for a second pass with
`depthFunc = .greater`. `SCNMaterial` exposes no depth-comparison function, so the same read is
achieved with ordering: pass B draws first ignoring depth at 55%, pass A draws after with a normal
depth test at full strength. Occluded stretches ghost, visible stretches are hot — no `SCNTechnique`
needed. The old single depth-off pass made routes float flatly over the house.

**Framing distance is 2.2 × extent, not the spec's 1.35 ×.** The spec's number assumed the old 50°
field of view. Dropping to a 35° long lens (to kill wide-angle distortion) narrows the visible span
by tan(25°)/tan(17.5°) ≈ 1.48×, so at 1.35× the house rendered cropped on every side. 1.35 × 1.48
≈ 2.0, plus margin for the diagonal presented at a 45° yaw → 2.2. Verified on the simulator.

**Orthographic scale is aspect-corrected.** `orthographicScale` is a half-HEIGHT; on a portrait
viewport the visible width is `scale × aspect`, so a house framed to fit vertically loses both
sides. The rig now divides by the aspect below 1. Without this, ortho framing is wrong on phones
specifically — the one form factor this app ships on.

**Accent color: deep safety green `#0E8A3E`** (spec §10 option B, owner's pick). Green chrome keeps
orange reserved exclusively for routes, so nothing in the UI competes with the escape path. Also
retires the yellow selection sphere in favor of an accent ring on the floor.

**Exits are ground markers, not colored doors.** `opening(kind:isExit:)` returned saturated green
door leaves and teal exit windows. Replaced by `ExitMarkerFixture`: a green pad with chevrons on
the plate outside each exit, readable from any orbit angle and present whether or not routes are
shown. `RouteOverlay.addExitGlow` deleted with it.

**New fixture `jagged.json`** (both `schema/fixtures/` and the bundled `escape_plan/Fixtures/`,
registered in `HomeFixture` and `Fixture`): basement 4×5 m in one corner, 20×20 m ground floor,
12×8 m upper offset to the opposite corner. This is the acceptance model for stacking — it is what
proves ghost opacities, slab outlines and the union-sized base plate read correctly when the stack
is not a tidy tower.

**Also fixed in passing:** `RenderOrder.routes` was declared but never used — `RouteOverlay`
hardcoded 50/52/55/56, outside the ledger the band system exists to enforce. All route ordering now
goes through the enum, and the render-band test covers it.


## 2026-08-05 — UI/UX pass: chrome, icon, launch, people, thumbnails

Follow-on to the same day's White Model dollhouse overhaul, covering the app *around* the 3D
view. Full gate green (editorcore 192, iOS 337, backend 264, corpus valid). No new dependencies.

**Chrome contains no route orange.** This was the real finding, not a styling preference. Seven
screens used SwiftUI's `.orange` for warnings and advisories — scan fallbacks, rejected edits,
onboarding hints, the Settings status dot, the mid band of the score ring. The dollhouse's one
governing rule is that the escape route is the only hot colour in the frame; chrome orange broke
it outside the 3D view, where a user could see route-orange and warning-orange in one scroll with
no way to know they meant different things. `Screens/Theme.swift` now owns the semantic scale:
`accent` (the deep safety green, also the selection ring), `caution` (#B45309, a dark amber that
reads as ink rather than as a lit line), `warning` (the palette's #DC2626), `supporting`. Colours
bridge from `DollhousePalette` so renderer and chrome cannot drift. `routeInk`/`exitInk` exist
only for legends that label an actual route or exit.

**One backend-failure classifier.** `Networking/BackendFailure.swift` replaced six hand-rolled
`catch` ladders that disagreed with each other; every one of them offered Retry regardless of
whether retrying could work. The backend has distinguished 502 (an operator must act — no
Anthropic credit, bad key) from 503 (retryable) since 2026-08-04, and the app was collapsing
both to one sentence. Now 502 shows no Retry button at all and names what still works ("your
escape routes still work"), which is the architecture's own argument stated in the UI. 8 tests.

**People layer diverges from the design handoff on purpose.** The handoff asked for one route
colour per household member. Rejected: four saturated hues is precisely the problem the White
Model overhaul removed, and it would put three or four hot colours in direct competition with
the route and the exit green. Instead the figures are made of the same white as everything else,
identity comes from a name pill, and the *selected* person's figure takes the accent green — the
same signal the selection ring uses everywhere. Whose route is on screen is answered by
selecting the person, not by memorising a colour key. 6 tests.

**Opening markers are parametric.** `UnifiedSceneController.highlightPlacement` replaces
`highlightCenter`. An opening's ring is derived from its host wall segment (`edge_index` + `t`),
not from a cached coordinate, so it follows a dragged wall — the same invariant the schema
imposes on the openings themselves. The ring stands upright in the wall plane via two nested
nodes rather than euler angles, because composing a 90° tilt with a yaw depends on SceneKit's
rotation order and nesting does not.

**Thumbnails turn shadows and SSAO off.** `Renderer/HomeThumbnail.swift` renders offscreen with
`SCNRenderer`. At ~74×54 pt the shadow map samples far below its own texel density and speckles
every wall face; the tile reads as noise rather than as a white model. Ambient takes over the
shadow's share so the model doesn't go flat. Cached by home id + modified date.

**Launch screen has no logo, deliberately.** `INFOPLIST_KEY_UILaunchScreen_BackgroundColor` +
a `LaunchBackground` colorset (light/dark), no image. Per Apple's HIG a launch screen should
resemble the app's first screen rather than act as a splash; matching the background makes
launch feel instant instead of like a branding interstitial. This also closes the item deferred
on 2026-07-23 for pbxproj contention — no lane holds the project file now.

**App icon** (`scripts/make_app_icon.swift`, regenerated): white house in section, orange route,
green exit pad, replacing the navy/ember icon that shared no vocabulary with the renderer. The
artwork is laid out in round numbers and fitted to the canvas by one transform, so recomposing
does not mean nudging twenty coordinates. The tinted variant encodes importance as luminance
(route brightest, cut faces next, interior recessed) since iOS composites tinted icons from
luminance alone.

**Scene rebuild is memoized on the SwiftUI-update path.** `EditorSceneView.updateUIView` rebuilt
the dollhouse unconditionally, on the sound reasoning that `DollhouseSceneBuilder.build` is a
pure function of the model and rebuilds only follow an edit commit. Evacuation playback broke
that assumption: `HouseScreen`'s body reads the playback clock, so `@Observable` invalidates the
view on every tick — and an unconditional rebuild there tore down and re-created the dollhouse,
the route overlay, the people layer and the animated evacuation layers sixty times a second,
restarting the animation it was drawing. `UnifiedSceneController.rebuildIfNeeded(home:activeFloorId:)`
skips when those inputs are unchanged; purity is exactly what makes the skip safe. It is a new
method rather than a change to `rebuild`, so explicit callers keep force semantics, and `rebuild`
records the inputs itself so the two entry points cannot disagree about what is on screen.

**The ordinary route overlay is suspended while an evacuation timeline is loaded.** The route
solved before the fire answers a different question than the fire-aware one, and showing both at
once is the one way the house screen could actively mislead. `bindEvacuationPlayback` takes
idempotent suspend/restore closures; the ordinary route comes back when the timeline is cleared.

**Parallel-lane fences need an owner for the seam.** The fire-origin work split cleanly into an
engine lane and a renderer lane with disjoint file ownership, and both lanes finished. Neither
could call `bindEvacuationPlayback`, because the caller lives in `Screens/` — fenced to the other
lane. Every component was tested and none of it was reachable in the app. Next time, either give
one lane explicit ownership of the integration point or schedule an integration pass that owns
both sides; "each lane reports what the other must do" produces two correct halves and no feature.

## 2026-09-05 — The readiness pivot is scoped, and deliberately parked as a proposal

**The app's premise was challenged and the challenge was largely right.** For an able-bodied adult
in their own home, the fire route is obvious, the owner knows the house better than a scan does,
and shortest-path-to-the-door is not by itself a reason for the app to exist. What survives the
critique was already in the repo and badly marketed: `docs/profile-constraint-mappings.md`'s
`mobility_limited` case, where the engine returns `no_viable_route` for an upstairs sleeper. The
finding — *there is no way out for this person* — is the product. The animated path is not.

**So the S6 arc reframes the app as a readiness system** (household interview → deterministic
hazard-tagged checklist as the Home tab → three perils with genuinely different routing objectives
→ composite score → opt-in responder snapshot). It is written up as nine paste-ready long-horizon
prompts: `docs/playbook/06-pivot-intro.md` plus `S6-1.md` … `S6-9.md`.

**It is a proposal, not an approved plan, and nothing was built.** The scope is far larger than the
open UI/UX handoff in `docs/START-HERE.md`, and the Oct 24 deadline did not move. The first TODO
line in the arc is the decision itself: pivot, or finish the app that exists. Recorded here so a
future session does not find nine session files and assume they were sanctioned work-in-progress.

**Decisions interrogated and locked at scoping time**, so sessions do not relitigate them: three
perils (fire, earthquake, severe weather) with real logic, not re-skinned copy; the checklist comes
from a deterministic rule table and the AI only conducts the interview; all hazards always on, no
geography gating and no risk-API dependency; HomeModel stays the source of truth with a time-based
rescan nudge; one unified hazard-tagged checklist rather than three lists; the checklist replaces
the Home tab; local-only/anonymous/no-accounts survives intact, with sharing as a manual one-way
export; the storm safe room is engine-computed with no manual override; one composite score with a
per-peril breakdown; the interview is a fixed branching wizard, not free chat; every question is
skippable and the profile is editable afterwards; the insurance and first-responder stories are
designed and demoable but **not** integrated.

**Two findings from reading the code that reshaped the prompts.** `backend/app/scoring/checklist.py`
already generates a deterministic checklist with stable ids and persisted done-state, and
`ScoreScreen` already renders it — so S6.4 and S6.6 extend those rather than building parallel
implementations. And `backend/app/routing/hazard.py` already means fire-origin spread simulation,
so the multi-peril work is namespaced `routing/perils/` to avoid overloading the word.

**The interview must work with zero network calls.** The Anthropic account is out of credits, so a
front door that needs a live model call to get past screen one would be dead on first launch. The
wizard's conversational feel comes from written copy, not per-user generation; model-generated
phrasing may only ever be layered on top of copy that already works offline.

## 2026-09-05: Schema 2.0 Transition
**Decision:** Bump `schema_version` to 2.0 to support the readiness pivot (household facts, safety points, secured furniture, sensory profile tags), but implement the upgrade *in-memory* at the load boundary rather than rewriting documents on disk.
**Rationale:** The S6 readiness pivot introduces new facts that the HomeModel must hold. We elected to make all new fields optional (or defaulted) and handle older 1.1 documents gracefully at decoding time in both Python and Swift, avoiding massive data migration for users.
**Consequences:** The JSON schema now strictly enforces `enum: ["1.1", "2.0"]` for the schema version. Pydantic and Swift decoders intercept `1.1` and bump it to `2.0` automatically, mapping missing data to `null` or defaults. The contract remains lockstep across schema/python/swift.

## 2026-09-06: S6.3 Perils vs Hazard Terminology
**Decision**: Multi-peril routing (earthquake, tornado) lives in a new `backend/app/routing/perils/` package rather than extending `backend/app/routing/hazard.py`.
**Reasoning**: `hazard.py` was established early on for fire-origin spread simulation (dynamic hazards during a fire). Overloading it to mean "disaster type" would compromise the domain language. "Peril" cleanly describes the triggering event (fire, tornado, earthquake) while "hazard" remains the specific physical threat within the simulation (e.g. fire/smoke spreading).
**Status**: Adopted in S6.3 implementation.
## 2026-09-06: Earthquake Cover Object Distance Metric
**Decision**: In Earthquake routing (`earthquake.py`), the distance to a qualifying cover object (e.g. table) is computed from the object's `center` to the room's geometric centroid, rather than requiring the occupant's entry point.
**Reasoning**: Earthquakes happen instantly. The occupant could be anywhere in the room when shaking starts, not necessarily standing at the door. The room centroid provides an unbiased, deterministic proxy for "average distance from anywhere in the room" without requiring simulation of a specific occupant position.
**Status**: Adopted in S6.3 implementation.

### 2026-09-06: S6.4 Hazard Checklist - Pre-Satisfaction vs. Suppression
When generating items driven by household facts (e.g., `existing_equipment` contains `smoke_alarm`), we chose to emit the corresponding checklist items with `done=True` rather than suppressing them entirely. This reinforces UI trust by showing the user the app recognized their declared equipment, rather than leaving them wondering if the system "forgot" the smoke alarm rule.

### 2026-09-06: S6.4 Hazard Checklist - Operational vs. Safety Items
The `rescan.home` checklist item is an engineering choice (encouraging fresh scans twice a year) and makes no direct corpus-backed safety claim. It explicitly holds `source_citation=None`. The testing suite's strict citation rule explicitly exempts items designed this way (`UNCITED_BY_DESIGN = {"rescan.home"}`).

### 2026-09-06: S6.4 Hazard Checklist - Score Non-Interference
All new checklist categories (`shutoffs`, `safe_room`, `mitigation`, `supply_kit`, `alerts`) are generated with `scoring=False`. Reweighting the score to incorporate hazard preparedness is deferred strictly to S6.7.

### 2026-09-06: S6.5 Onboarding Profile Bedroom Assignment
During the onboarding interview, we ask for residents' ages and needs, but not which specific bedroom they sleep in (because they haven't mapped their house yet, and we are seeding a demo home in the background). We implicitly map all created profiles to the first available bedroom in the seeded home (or an arbitrary room if no bedroom exists) so the profiles are immediately valid for routing. The user can edit this bedroom assignment later.

## 2026-09-06 — Review is agent-run: no human reviewers, no PR gate

**Owner's call, given directly in session**, reversing a rule in force since S0.2. Nothing is
reviewed by a tagged human any more, including `schema/`. A branch is vetted by the quality
agents plus the green gate plus the working session's judgement, then merged to `main`.

**Why.** The old rule produced one outcome in practice: S6.1 finished green on 2026-09-05 and
then sat in an open PR asking "@Anish — who signs off?" while S6.3/S6.4/S6.5 blocked on it. The
nominal reviewer and the session-runner are the same person, so the gate cost days off an Oct 24
deadline and bought no independent scrutiny.

Changed in lockstep across nine files (two auto-load every session, so a contradiction between
them is worse than either policy): `CLAUDE.md` ×2, `rules/global/conventions.md`,
`rules/global/architecture.md`, `rules/paths/schema.md`,
`agents/quality/schema-contract-guardian.md` (its brief told it the change needed team sign-off,
when in fact it *is* the review), `hooks/README.md`, `START-HERE.md`, `playbook/02-architecture.md`,
plus the schema's own `schema_version` description.

**Unchanged:** the `schema_version` bump requirement, and the `docs/tracker/` protocol — without a
human reviewer, the note and TODO entry are the *only* durable record of what was judged, so they
carry more weight, not less.

**Noted for the record:** the schema-contract-guardian, run against this very change, flagged that
an agent had edited the review policy to name agent review as the replacement for human sign-off,
and said an agent-authored statement is not authorization. That is exactly the right instinct and
worth preserving. It is satisfied here: the instruction came from the owner in session, not from
an agent. Anyone reading this later should treat the guardian's objection as still standing for
any *future* self-authorizing edit.

## 2026-09-06 — Two independent S6.1s collided; the orchestrator's base won, with fixes ported

An orchestrating agent pushed S6.1, S6.2 and S6.3 to `origin/main` while a separate session was
finishing S6.1 on `s6-1-schema-2-0`. Both implementations independently arrived at the **same**
schema 2.0 — identical top-level properties, identical `$defs`, identical enums. The collision was
textual (20 conflicting files), not architectural.

**Resolution: the orchestrator's base was taken** because it carries strictly more of the arc, and
the independent branch's genuine improvements were re-applied on top. The branch is preserved as
`my-s6-1-and-policy` and tag `backup-before-merge-s6-1-20260906-232123`; nothing was force-pushed
and nothing was lost.

**Ported:** `household` made nullable (the schema otherwise rejects the `"household": null` that
pydantic emits — 19 validation errors on a default `model_dump_json()`); `tags` removed from
`profile.required` (the schema was the sole outlier against both mirrors, a drift dating to S0.2,
not a 2.0 regression); and the review-policy documentation.

**Deliberately NOT ported: the fixture seeding.** The independent branch seeded both sides of every
interview branch for S6.4/S6.6. The orchestrator's fixtures are thinner — no `last_scanned`
anywhere, no sensory tags, one household. Reseeding would change the ground under S6.3/S6.4 tests
written against the current fixtures, so it is a TODO for whoever runs S6.4, not a unilateral edit.

**Schema edited without a `schema_version` bump, deliberately.** All three schema edits are pure
*loosenings* that correct 2.0 into agreement with its own mirrors, and 2.0 has never shipped — a
2.1 for "2.0 now matches what it always claimed" would be noise. The guardian raised this and
declined to wave it through silently, which is the correct behaviour; recording the reasoning here
is the answer.

## 2026-09-06 — The tornado engine told every bungalow to leave the house

Found by `grounding-auditor` on code that reached `main` unreviewed. `find_tornado_shelter`
short-circuited to "no safe room" whenever a single-storey home had no room with zero exterior
walls. Measured: it fired on **4 of 5 fixtures** — every occupant of `bungalow`, `apartment`,
`bungalow-blocked` and `bungalow-narrow` was told to go outside during a tornado warning, while
the corpus committed in the same push says to move to the lowest floor and the most interior room,
"such as a bathroom, closet, or hallway". Bungalow's Kitchen has zero exterior openings.

Three faults stacked: construction type is not derivable from a footprint polygon so it could not
detect a mobile home; the corpus rule is comparative, not a threshold; and it was internally
inconsistent — `twostory` has all three ground-floor rooms on exterior walls but escaped on floor
count alone. The ranking underneath already implemented the corpus rule, so removing the
short-circuit was the whole fix: `no_viable_safe_room` went from 17 across the fixtures to 0.

**Both tests that failed were pinning the defect** — one named `test_mobile_home_...` but run on a
site-built bungalow, the other asserting in its own docstring that bungalow has "no interior room".
Replaced with inverted assertions plus a six-fixture regression guard. Leave-the-house advice must
in future be gated on an explicit modelled fact (a `structure_type` field), never inferred geometry.

## 2026-09-06 — S6.2 opened a hole in the grounding guarantee

`valid_source_ids()` accepts every id in `sources.json`, so an id is only safe to accept if the
model was actually shown the document behind it. S6.2 added two corpus files and six source ids
but `CORPUS_FILE_ORDER` (grounded.py) and `CORPUS_DOC_FILES` (agent.py) stayed hardcoded to the six
fire documents. The server would therefore have validated `noaa-tornado` on a tornado claim the
model invented from pretraining — the precise failure the architecture exists to make impossible —
and `search_corpus('tornado safe room')` answered with five fire-escape paragraphs presented as
relevant excerpts. 11 of 17 ids were in the block.

Both lists now derive from `sources.json`'s `corpus_files`, with a test asserting they match and
that no acceptable id is missing from the block. **The lesson is the mechanism, not the fix:** a
hardcoded mirror of a data file will desync at the next session, and only a test makes that
impossible.

## 2026-09-07 — Claude Design pass: implemented as a restyle, not a rewrite

The owner designed Home, Assistant, Settings, Onboarding, Score and the House dock in Claude
Design (project `66734cd4-4e07-4cf5-a116-5ded7e6dec0c`, exported under
`docs/design/claude-design-export/`) and asked for it to be implemented. Every screen kept its
behaviour, data flow and accessibility identifiers; only layout and styling changed, through a
new `Screens/DesignKit.swift` token/component layer that sits *on top of* `Theme` rather than
replacing it. Deviations from the design, all deliberate:

- **Tile colours follow the app's contrast rule, not the design's palette.** The design tints
  the routes tile cool-blue and the findings tile purple. Cool means "route" and warm means
  "hazard" everywhere in this app, so the routes tile uses `Theme.routeInk` (a legend use, which
  the rule allows), findings use `DS.bodyInk`, alarms use `Theme.caution`.
- **The per-item checklist stays.** The design collapses S6.6's checklist into four stat tiles.
  The tiles are there, but the full Foundation / Know your home / Practice / Mitigate / Stay
  ready list still renders under them — the interview and checklist data are the product, the
  tiles are a summary of it.
- **The person picker stays native.** A `DSPill` picker would have dropped the
  `plan.profile.picker` identifiers the UI tests key on.
- **Not implemented:** the collapsing 400→190pt House model card, and the Export/Edit pills in
  the House title row. Tracked in TODO; the current floating glass controls already cover both.
- **The "The AI explains your plan…" footnote under the composer was removed** on the owner's
  instruction in the design chat. Settings' About footnote carries the same sentence, corrected
  to say the engine computes routes and the assistant only explains them.

## 2026-09-07 — Beta tab: the test-home library survives, leftmost

S6.6 replaced the Home tab's home library with the readiness checklist. The owner tests against
those fixture houses constantly, so the library came back as a fifth tab, **leftmost**, named
Beta (`Screens/BetaScreen.swift`, recovered from `3babbc0`'s `HomeScreen`). Leftmost was the
owner's call: it keeps the four product tabs in their order and marks the extra one as a tester's
surface. It ships in every configuration for now; wrapping it in `#if DEBUG` before submission is
a one-line change and an open question to the owner. The 3D SceneKit house stays; the design's
2D SVG house was not ported and is retrievable from the export.

## 2026-09-07 — The design export lives in-repo; the runtime shim doesn't

The `claude_design` MCP could not be authorised in the implementing session (`/design-login` is
unavailable in that environment), so the files were pulled through the owner's signed-in browser
pane via the page's own `OmeletteService/GetFile` RPC and transcribed into
`docs/design/claude-design-export/`. `Escape Plan.dc.html` is complete except for the ~19 KB
`data-omelette-injected` canvas shim (no design content; regenerated by the canvas; the omission
is documented in the file's head comment). `ios-frame.jsx` is byte-exact. `support.js` (generated
`dc-runtime`, needed only to render the canvas in a browser) is intentionally not copied. The
README there has the re-fetch recipe for when the MCP is available.

## 2026-09-07 — Two stale backends produced one misleading failure card

Home showed "Score unavailable — the server couldn't use what we sent" (422) on the first run of
the new design. Not a UI bug: the local uvicorn had been started before the schema-2.0 commits
and runs without `--reload`, so it was validating 2.0 payloads against 1.1 models. Restarting it
fixed `/score`. The deployed Render backend has the **same** problem (still pre-2.0) and adds a
~32 s cold start that the app reports as "couldn't reach the server". **Rule going forward:**
after pulling anything under `backend/` or `schema/`, restart the local server before believing a
red card, and redeploy Render before any device or judge demo.

## 2026-09-07 — Haptics live in button styles, not in call sites

"Haptics on every button" could have meant a `Haptics.press()` in 150 closures. Instead the
click comes from the button styles — `DSPressStyle`, `HapticPlainButtonStyle` (the app's
`.plain`), `GlassChipButtonStyle`, and `.hapticTap()` for system styles that can't take a custom
`ButtonStyle` without losing their look — so a new button is haptic by default and a screen only
calls the funnel for value changes (`selection` for tabs/segments/toggles, `begin` for refresh,
`swipe` for row actions). The vocabulary is documented at the top of `Support/Haptics.swift`.
The click lands on press-down, with the visual squash, not on release.

## 2026-09-07 — The gauge sweeps with a prepared generator, and only when the score changes

`DSScoreGauge` counts up with one light impact per notch (25 notches in ~1.4 s). A fresh
`UIImpactFeedbackGenerator` per notch drops most of them at that rate, so `HapticSweep` keeps one
warm. The sweep runs on first score and on score change — not on every tab return, which would
turn a delight into a tic. Reduce Motion gets the final value and a single tick.

## 2026-09-07 — Checklist rows are compact; details live one tap away

Owner's call: no detail text on the Home action items by default. Rows are title + hazard +
chevron; a tap opens a quick-details sheet whose primary button does what the row tap used to
(house / drill / toggle); a header pill expands every detail line inline for readers who want the
long form (persisted). Narrative items keep a direct checkbox so the fast path stays one tap.

## 2026-09-07 — House card collapse: scroll geometry, not preferences

The design's sticky-card trick is implemented literally: card height = 400 − scroll offset,
floor 190, with a leading spacer in the dock giving the height back and a trailing spacer
guaranteeing scroll room. The offset is read with `onScrollGeometryChange` (iOS 18+); the classic
GeometryReader-in-ScrollView preference pattern is only the iOS 17 fallback because on iOS 26 it
emitted once at layout and never again during scrolling. Resizing the SceneKit view per frame was
accepted: the only frame changes are user scrolls, which cannot coincide with a drag on the model,
and SceneKit's vertical FOV gives the design's scale-to-fit for free.

## 2026-09-07 — `fetchScore` stopped animating the checklist swap

Twice in the day the Home ScrollView lost its offset after a re-score. Animating a wholesale
replacement of the list content is the one plausible trigger; the gauge animates itself now and
rows update in place, so the `withAnimation` came out. Three refresh cycles afterwards held
position. If it recurs on device, look at the `breakdown` swap first.

## 2026-09-08: S6.9 Responder Snapshot (Security Review)
- **Local-Only Architecture preserved**: The Responder Snapshot operates entirely on the device. It relies on the offline-cached Route Plan and the `ScoreBreakdown` via `ScoreCache`, bypassing `APIClient`.
- **Consent requirement**: A plain-language consent screen is required to enable the feature. The user must manually tap "Generate" and use the system share sheet (`UIActivityViewController`). There is no automated transmission path to any service, let alone a fire department backend.
- **Anonymization guarantee**: The snapshot extractor iterates over profiles but ONLY aggregates by `bedroom_room_id` for profiles with `.mobility_limited` or `.vision_impaired` tags. Both PDF output and JSON payloads were explicitly verified in `ResponderSnapshotTests.swift` to never contain profile names, device identifiers, or location data (unless manually typed into the home name).
- **Designed-not-integrated scope lock**: The snapshot is designed for the user to hand to first responders, but explicitly avoids *integrating* with external responder systems for privacy reasons. We provide a structured JSON and PDF that the user can share at their own discretion.

## 2026-09-08 — `BLOCKERS.md` is the status mechanism; CLAUDE.md stopped auto-loading four files

Two problems with one cause. **(1)** Status lived nowhere in particular — the S6 arc was code-complete
for S6.4–S6.7 while `TODO.md` still carried all four as open, and the LiDAR trip had happened without
any file saying so. **(2)** Every session paid for that ambiguity up front: the root `CLAUDE.md`
`@`-referenced three files under `.claude/rules/global/`, and a SessionStart hook injected a 45-line
handoff recital that the model was instructed to repeat back verbatim. That was ~225 lines of
always-on context plus a forced first response, most of it duplicated between CLAUDE.md and the
rules files, before anyone had asked a question.

**What changed.** `docs/tracker/BLOCKERS.md` is new and is now the board: everything blocking or
unverified, ranked by critical path, with the standing rule (stated in `CLAUDE.md`) that anything
discovered undone goes there in the same session. `TODO.md` keeps the long-tail backlog and history
and explicitly defers to `BLOCKERS.md` when the two disagree. `CLAUDE.md` was rewritten to ~120
self-contained lines carrying a "read this when you're in that territory" routing table instead of
`@`-references, and `.claude/rules/global/` was **deleted** — its content is now in `CLAUDE.md` as
the single copy. The four live references to it (`swift-scenekit-reviewer`, `S6-9.md`,
`S6-EXECUTE.md`, `rules/README.md`) were updated. The SessionStart hook went from 45 lines to 6 and
no longer demands a verbatim recital; the traps it used to list (dry Anthropic account, SourceKit,
iOS flake) live in `CLAUDE.md`, which already loads every session.

**Why deletion rather than keeping both.** This repo's documented failure mode is docs contradicting
each other — the tracker did it in nine places, and the 2026-09-05 scope change had to be applied to
five files in lockstep. Two copies of the conventions is how that happens again. Scoped rules under
`languages/`, `paths/` and `vendors/` survive untouched because they carry real detail and were
already on-demand.

## 2026-09-08 — Three "blockers" were already dead; one diagnosis was wrong

Checked rather than inherited, and the tracker was carrying stale bad news.

- **The Render backend is current.** Its `/openapi.json` reports `schema_version const "2.0"`, a
  `Household` schema and `peril` on `RoutesRequest`, and serves all nine routes including
  `/evacuate`. Local `main` and `origin/main` are identical, so auto-deploy is working. Two TODO
  items ("redeploy from main", "deploy `/evacuate`") were false.
- **The 2026-09-07 "deployed backend is pre-2.0" note was a misdiagnosis.** It was true of a *local*
  uvicorn started before the schema commits. What made it look true of Render is that `/health`
  reports `v1.0` — a hardcoded FastAPI `app.version` (`backend/app/main.py:44`) that says nothing
  about deployed code, and which `demo-preflight.py` printed prominently. **Fixed at the source:**
  preflight no longer prints that version and instead has a `check_deployed_schema()` that compares
  the deployed `HomeModel.schema_version` against this checkout's and fails loudly on a mismatch. It
  needs no auth, so it runs even without the bearer token.
- **The LiDAR field trip is done** (2026-09-08, owner-reported): a friend's house, first attempt,
  mapped correctly, conversion held, routes animated well. This closed the project's largest
  untested hardware dependency. Marked only what was actually reported — the double-scan,
  messy-scan, idempotency and artifact-capture lines stay open rather than being swept along, since
  over-claiming in the tracker is the exact habit this session was cleaning up.

The one blocker that survived contact is the bearer token: `escape_plan/BackendConfig.local.json` is
still absent and only the owner can supply it. `.env` is read-guarded in `settings.json` and the
guard held when probed — correctly, so the token was not lifted from it.

### 2026-09-09: Object Hazard Surfacing (S7.5)

1. **Supersession Mapping:** We decided that specific object hazards (like an unstrapped wardrobe causing a topple risk near an egress path) replace the generic `mitigation.secure.<id>` items. The specific `hazard.<rule_id>.<object_id>` checklist item is generated, and any generic "strap heavy furniture" items for that object are skipped so we don't present duplicate items to the user. If the user had previously checked off the generic item, its status is carried forward as `done=True` on the new specific hazard.
2. **No Weight Change:** Object hazard findings are classified as advisory (`scoring=False`). However, if an object hazard produces a `high` severity item (e.g. unsecured water heater or topple risk over an egress path), it triggers the existing high-severity composite score cap (capping the score at 40). We made zero changes to score weights because the existing S6.7 score cap natively handles this logic exactly as intended.
3. **R4 Wording Audit Result:** We audited the `RouteNarration.swift` language around obstructed windows to ensure it did not improperly use the word "door" (a potential silent bug). The wording correctly resolves to "A way out of the Bedroom is blocked", which perfectly covers both door and window obstructions without requiring any code changes.

### 2026-09-09: S7.6 Hazard Hunt Editor

1. **Hunt Question Set:** The guided hunt checks for `heat_source` (portable heaters), `bookcase` (heavy/tall items near bed), `tv` (mounted above bed), and `water_heater` (strapped in garage/utility). It asserts nothing natively—it merely adds the objects, and the backend engine runs its physics pass.
2. **Inspector Scope:** The inspector now exposes `secured`, `mounted`, and `elevation_m` directly on the object panel to let the user address hazards.
3. **`setOpeningWidth` Closed:** The long-standing `setOpeningWidth` no-UI item was implemented as a stepper inside the Opening inspector, cleanly closing that backlog item alongside the object controls.

### 2026-09-09: S7.7 — 3D emphasis (non-device half)

1. **Finding → object resolution moved into the model, not the checklist string.** The prior
   attempt parsed a checklist item's id client-side with `itemID.split(separator: "-")`, which
   shreds `routes.blocked_opening.<room>.<obj>-<obj>` findings because object ids themselves
   contain hyphens (`obj-1a2b3c4d` from the converter, a raw `UUID().uuidString` from the Hazard
   Hunt). Replaced with `ChecklistItem.objectIDs(in:)` (`Models/ChecklistItem+Objects.swift`),
   which matches candidate ids against the ones the loaded `HomeModel` actually has — an id for an
   object that has since been deleted resolves to nothing rather than to a wrong neighbor. Covered
   by `HazardEmphasisTests` (hyphen-in-tail, multi-culprit, UUID, deleted/unknown cases).
2. **Advisory ring color reads from `Theme.cautionComponents.dark` at runtime, not a re-typed
   hex.** `UnifiedSceneController.applyHazardObjects` previously wrote `UIColor(hex: 0xF59E0B)` —
   the right color, but a second, driftable copy of it. Now built from `Theme.cautionComponents`'s
   own `SRGB`, so the 3D advisory and the UI chrome can never disagree. No new colour was
   introduced (verified by grepping the diff for `Color(`/`UIColor(hex`/raw hex literals).
3. **Fixed a real ghost-floor rendering bug found by testing the ring, not aimed at on purpose.**
   `DollhouseScene.GhostEntry` never recorded a node's as-built `renderingOrder`, so
   `setActiveFloor`'s un-ghost branch wrote `entry.node.renderingOrder = entry.node.renderingOrder`
   for every `.structure` node (walls, fixtures, **and furniture objects**, which all land in that
   bucket) — a no-op. A floor ghosted once (which the builder does immediately, since it opens on
   the top floor) permanently stuck its objects at `RenderOrder.ghostWall` (90) instead of
   `RenderOrder.objects` (2), never restoring the correct order once the floor became active again.
   Added `GhostEntry.solidRenderingOrder`, captured once at classification time (before any
   ghosting), and the un-ghost branch now restores that instead of a self-assignment. This is
   exactly the "ghost-floor stacking with mounted objects" case S7-7.md calls out — caught by
   `testAdvisoryRingLandsOnTheNamedObjectsOnly` failing with `90 != 2` on the first honest run of a
   two-floor fixture.
4. **One ring treatment for every rule; severity stays in the checklist, not the color.** A hazard-
   flagged object gets a torus ring in the advisory amber at the object's own floor plane — the
   `highlightPlacement` selection-ring pattern, reused rather than reinvented, per S7-7.md's "do
   not invent a second camera/emphasis behavior."
5. **The device pass is untouched and stays open.** Real scan + camera feel + the measured frame-
   time number need a physical iPhone and a human; see `BLOCKERS.md` §2. Nothing here claims that
   half.

### 2026-09-09: Backlog cleanup — close every agent-doable "Known defect"

Picked up an interrupted run (a Codex session ran out of context mid-pass) and finished it: closed
every item in `BLOCKERS.md` §3 "Known defects" that didn't need a schema bump, a routing-engine
redesign, or physical hardware, and fixed the tracker's own duplicate-`## 3` heading bug.

1. **Verified two items as already-closed instead of re-fixing them, per CLAUDE.md's "code exists
   is not verification" rule.** `bookcase`/`water_heater` already produce specific `hazard.*`
   items with no generic `mitigation.secure.*` duplicate — confirmed by reading
   `object_hazards.py`'s R1/R5 rules and `checklist.py`'s `suppressed_ids`, then adding
   `test_bookcase_and_water_heater_use_specific_hazards_without_generic_duplicates` to prove it
   rather than trusting the read. The "three files still say v1.1" line was also already false —
   `models.py`, `HomeModel.swift`, and the schema all say 2.1 (S7.1 fixed the files but never
   crossed the line off).
2. **`/build`'s null-serialization gap and `FloorObject.size_m`'s unbounded array were fixed for
   real**, each with a new test that exercises the previously-untested path
   (`test_build_response_has_no_null_optionals`,
   `testFloorObjectRejectsASizeWithMoreThanWidthAndDepth`). `exterior_edges`'s mixed int/string
   keys were also collapsed to one integer key space, but an independent review pass caught that
   the branch this "fixed" was already unreachable for any pydantic-validated `HomeModel` —
   `Opening._check` guarantees `wall_segment.room_id` can only be the room itself in this
   code path, never the paired room, so it was never a live double-counting trap for scan-derived
   homes the way the original `BLOCKERS.md` line claimed. Harmless hardening of dead code, not a
   bug fix; corrected in `BLOCKERS.md` rather than left overstated.
3. **Onboarding's demo-home seeding is now idempotent and testable.** `FixtureSeeder.seedDemoHome`
   returns `nil` instead of seeding into a non-empty library; `OnboardingState` gained an injectable
   `HomeDocumentStore` so tests stop writing into the real `Documents/Homes` the test host shares
   with the app. One side effect worth flagging, not fixing now: `OnboardingState.seedError` is
   reused for the benign "library already has a home" case, and `OnboardingFlowView` renders it
   with a warning-triangle icon — cosmetically alarming for a non-error, but functionally inert
   (the view navigates away in the same action). Left as a minor polish item, not reopened as a
   defect.
4. **Three corpus/grounding fixes, each re-verified live in this session** (not trusted from the
   prior pass): the FEMA safe-room claim now separates "near-absolute" (a safe room built to FEMA
   criteria) from "substantially safer" (an ordinary basement, NOAA-cited); the dead
   `fema.gov/plan/prevent/saferoom` URL now points at
   `/emergency-managers/risk-management/building-science/safe-rooms`, fetched and confirmed (via
   `WebFetch`, since `curl` alone gets a `403` from Akamai bot-protection — a new variant of the
   "HTTP 200 isn't content proof" trap S7.2 already learned, this time HTTP-status-isn't-proof-of-
   reachability-at-all) to actually contain the near-absolute-protection/FEMA-criteria language;
   `shakeout-guidance` was repointed at `/step1/` (furniture/water-heater securing) — correct for
   the furniture-securing citations, but the same source id was also cited five times for
   Drop/Cover/Hold-On content in `earthquake-preparedness.md`'s own separate section, which the
   repoint silently broke (an independent review caught this — `validate.py` only checks that a
   cite id resolves, not that its content matches the claim). Fixed by splitting into two source
   ids: `shakeout-guidance` stays on `/step1/` for the furniture/water-heater claims,
   `shakeout-guidance-dcho` (new) points at `/step5/` for the five Drop/Cover/Hold-On claims —
   both URLs fetched and confirmed live with matching content.
5. **`RouteRedrawAfterEditUITests` is retuned but not fully closed — recorded honestly, not
   claimed.** The pixel predicate now matches `DollhousePalette.routePrimary` (#123FB0 = R18/G63/
   B176 satisfies `b>110, r<80, 35<g<115, b-r>75` by direct calculation). Running it live for
   what looks like the first time ever (`TEST_RUNNER_ROUTE_REDRAW=1` against a local backend)
   surfaced a second, unrelated, pre-existing bug: the test's `-onboarding.completed YES` launch
   argument skips `OnboardingFlowView` entirely, which is the only place anything seeds a demo
   home — so a fresh simulator install has no home for House screen to show, and the test fails
   at "House screen never finished loading" before it ever reaches the pixel check. This is a new
   `BLOCKERS.md` line, not a regression from this session's fix, and not swept under the closed
   item above.
6. **`routing/perils/objective.py` deleted**, confirmed by `rg` that nothing imported it first.

### 2026-09-09: S7.4 Corrective Cycle

1. **Inline `[cite:]` Tags Removed from Engine Prose (G1):** `ObjectHazard.detail` and `Obstruction.detail` strings are rendered raw by the iOS UI (HouseScreen inspector, RouteNarrationView). Inline `[cite: source-id]` tags were breaking the view. Fix: detail strings are now tag-free prose. Grounding is structurally carried by `ObjectHazard.citation`, which `checklist.py` uses to compose the `why=` payload for the AI layer. The UI never sees citation markup.
2. **`elevation_m` Scene Placement — Early S7.7 Landing (H3):** `DollhouseScene.makeObject` sets `y: object.elevation_m` when placing furniture nodes. `FurnitureFixture` builds nodes with local origin at the object's base (y=0 is the floor of the object), so `elevation_m` correctly lifts a mounted TV's base to its wall-mount height while a floor-standing object sits at floor level. This is S7.7 scope (3D emphasis) but landed early because the one-line change is correct and was already committed in S7.6. Kept rather than reverted; pinned by a comment in `DollhouseScene.swift:465`.
3. **Typing (H5):** `compute_score`'s `object_hazard_thresholds` parameter was `Optional[Any]`, and `config.get_object_hazard_thresholds()` had no return annotation. Fixed with `TYPE_CHECKING` imports to break the import cycle while providing real types for static analysis.

## 2026-09-09 — S7.4: Object-hazard engine implementation and R4 wording
*   **Context:** S7.4 dictates the implementation of R1, R2, R3, R4, and R5 from the object-hazard spec in `backend/app/routing/object_hazards.py` and `obstructions.py`.
*   **Decision:** The engine implements R1, R2, R3, and R5 strictly as detailed in the spec with deterministic execution, using variables loaded exclusively from `object_hazard_thresholds.json`. No parameters were hardcoded. Citations were explicitly added to the deterministic detail output produced by the engine itself to guarantee any later LLM consumption correctly references the specific corpus materials (e.g. `[cite: nfpa-heating-safety]`).
*   **R4 Audit Result:** R4 extended the existing `analyze_obstructions` methodology to evaluate egress-qualifying windows by reusing threshold-parsing code. We aggressively audited `Obstruction.detail` and removed hardcoded mentions of "door" and "doorway" in favor of "opening" and "escape path". Egress-qualifying windows that are blocked by furniture now emit `blocks_opening` appropriately while non-egress windows ignore similar blockages.
*   **Spec Deviations:** Inline citations were removed because they broke the UI, so we rely on the `citation` field.

## 2026-09-09 — S7.3: Scan objects through the pipeline

**Category mapping:** RoomPlan object categories are mapped to schema 2.1 carefully: `bed`, `sofa`, `table`, `storage` pass through exactly. `television` -> `tv`, `stove`/`oven`/`fireplace` -> `heat_source`, and `refrigerator`/`dishwasher`/`washerDryer` -> `appliance`. We drop `chair`, `sink`, `toilet`, `bathtub`, and `stairs` completely to avoid polluting the model with non-hazard geometry.

**Schema stamp change:** The schema output version was updated from 1.1 to CURRENT_VERSION (2.1). S7.3 owned this change because this is where the pipeline actually generates a new home scan document containing the S7.1 additions.

**Elevation epsilon (0.01 m clamp):** A 0.01 m threshold (1 cm) was added to clamp near-zero elevations to 0.0. This prevents falsely flagging grounded objects as suspended due to minor LiDAR measurement noise.

**Drop count surfacing:** The count of discarded (dropped) objects is now surfaced directly in the conversion metadata log to maintain transparency regarding filtered geometry.

## 2026-09-09 — S7.2: Object-hazard thresholds and NFPA sourcing

**Sourcing choice:** We elected to use NFPA sources for four of the required fire safety topic areas (heating, cooking, electrical, space heaters), and USFA for the fifth (dryers). The NFPA pages and the USFA PDF were verified live and returned HTTP 200 reliably, whereas specific HTML URLs like `/causes/electrical-fires/` and `/causes/dryer-fires/` returned 404, but others like `/prevent-fires/heating/` are 200.

**Threshold definitions:** `object_hazard_thresholds.json` is explicitly divided into two blocks to maintain citation integrity:
1. `cited`: Standards rooted in safety codes (e.g., the 3-foot clearance rule from NFPA). Imperial values are preserved for citation fidelity, while metric values are authoritative for computation.
2. `engineering_constants`: Geometric judgments made by the team (e.g., `topple_min_height_m`, `topple_slenderness_ratio`, `overhead_min_elevation_m`). These carry a `basis` string explicitly stating they are *not* codified safety standards. This prevents the app from falsely presenting a team heuristic as official NFPA/FEMA guidance.

## 2026-09-09 — S7.1: schema 2.1, and the schema_version breadth ruling

**What was added.** `FloorObject.elevation_m` (number ≥ 0, default 0 — the height of the
object's *base*, so the prism spans `elevation_m .. elevation_m + height_m` and `height_m`
stays the object's own height), `FloorObject.mounted` (bool, default false), and four
`ObjectCategory` values: `bookcase`, `tv`, `water_heater`, `heat_source`. `schema_version`
is `"2.1"`. Every addition is optional and defaulted, so any 2.0 document is a valid 2.1
document minus the stamp, and both migrators treat 2.0 → 2.1 as a version rewrite.

**`mounted` is not `secured`, and merging them was considered and rejected.** `mounted` is
how the object is installed; `secured` is whether a floor-standing object has anti-topple
strapping. One field would have meant an unstrapped wardrobe reading as safe the moment
someone hung a picture on the wall. The two stay orthogonal, with a Codable test pinning it.

**Why there is no mass/weight field.** Category plus dimensions carry every signal the
spec's rules actually use. A kilogram figure would have to be guessed by the user or invented
by the app, and a fabricated number in a safety tool is worse than an absent one — it invites
a threshold comparison that means nothing. Ruled out at scoping and confirmed here.

**One `heat_source`, not three.** Fixed stoves, ovens, fireplaces and portable space heaters
share a single category because the clearance rule that reads it is identical for all of them.
Splitting them would multiply cases without ever changing an answer.

**The `schema_version` breadth ruling** (closes the tracker item that had it "disagreeing three
ways"). The three breadths are deliberate and each now carries its reason at its definition:

| Where | Breadth | Because |
| --- | --- | --- |
| JSON Schema | `enum ["1.0","1.1","2.0","2.1"]` | it validates documents **on disk**, and a 1.1 file on a user's phone is a legitimate document |
| pydantic | `Literal["2.1"]` | it validates the **post-migration in-memory model**, where anything but current is a bug |
| Swift | bare `String` | it must **read** the old stamp before it can migrate it |

The rejected alternative was `const: "2.1"` in the JSON Schema. It would have made the schema
unable to describe any document the app can actually open. The standing observation that JSON
Schema cannot distinguish a 1.1 document from a 2.1 one is true and inherent — every addition
since 1.1 has been optional, so the stamp is the only signal, which is precisely why the
migrators rewrite it.

**`FurnitureFixture` placeholders are deliberate.** The renderer's switch is exhaustive over
`ObjectCategory`, so the four new cases had to gain arms in this session or the app would not
compile. They map to existing geometry (`bookcase` → seamed box, `water_heater` → appliance,
`tv`/`heat_source` → plain box). S7.6 replaces them; shipping approximate white miniatures for
one session is cheaper and more honest than blocking the schema bump on modelling work.

**Deviation worth naming: a test's premise had to change.** `test_obstacles.py`'s no-golden-churn
guard asserted that `bungalow` and `twostory` produce straight legs because they have no objects.
Seeding `twostory` — which S7.1 explicitly requires — made that premise false. The list is now
**derived** from the fixtures rather than hardcoded, with an assert that it is non-empty, so it
covers every genuinely object-free fixture and cannot silently become vacuous. The cost is real
and recorded in `BLOCKERS.md`: the derived set is now only `bungalow.json`, so the property is no
longer verified on a multi-floor home.

**The guardian caught a defect this session created.** Widening the `schema_version` enum made
`testCurrentVersionMatchesTheSchemaContract` vacuous — it asserted *membership*, so it would have
passed with `currentVersion` reverted to any of the four values. The one test named for catching
version drift had stopped being able to. It now asserts equality against the numerically greatest
enum entry. Worth recording as a pattern: **a guard that checks membership in a set gets weaker
every time the set grows**, and the growth is usually in a different commit than the guard.

## 2026-09-08 — Object-hazard detection: scoped, vetted, approved as S7 (docs only)

**Decision:** The S7 arc exists and is sanctioned. Ten sessions (`S7-1.md`…`S7-10.md`), a
charter (`07-object-hazard-intro.md`), an orchestration brief (`S7-EXECUTE.md`), and one
authoritative rule book — `docs/object-hazard-spec.md`, which wins any disagreement with a
session file. The summary-table row above carries the scope-lock mechanics; this entry records
the scoping judgment calls a future session will otherwise re-litigate.

**What was vetted and ruled, not just transcribed:**

- **The mechanism is RoomPlan + guided tagging, with Vision photo-assist optional at the
  tail.** The owner chose this explicitly (custom ML rejected; Vision kept because it costs
  nothing if cut). S7.9 opens with a timeboxed feasibility spike whose honest possible outcome
  is a documented negative result that cuts S7.10 — written into acceptance so a NO-GO is a
  success, not a failure.
- **Near-zero contract cost, discovered during scoping, is now a locked decision.** The merged
  S6 tree already decodes all 11 checklist categories and all 6 finding kinds, so: no new
  `ItemCategory` (hazards are `mitigation` items), no new `FindingKind` (egress-window blockage
  widens `analyze_obstructions` and reuses `blocked_opening`/`narrows_route`). Schema 2.1
  (`elevation_m`, `mounted`, four categories) is the arc's only contract change.
- **Supersession over duplication:** a specific `hazard.topple.<id>` item suppresses the
  generic `mitigation.secure.<id>` for the same object, with checkmark state carried forward —
  ruled at scoping time because two strap-it items for one wardrobe is the obvious failure mode
  of extending `mitigation_items`.
- **Geometry prioritizes, never excuses** (spec §2): distance from a bed tells you which item
  to strap first; it is never a reason not to strap. Any implementation that inverts this has a
  named trap (T11) in `S7-EXECUTE.md`.
- **Cut order:** S7.10 → S7.9 → S7.8 → S7.7's visual-emphasis half; S7.1–S7.5 are never cut.

**Session mechanics this session:** the local/remote split (local 1 ahead, 9 behind) was merged
first — `activity-log.md` conflict resolved by chronological union — and the baseline re-run
green (backend 348 not-live, EditorCore 270, corpus 17 sources/8 files; iOS not run per the
owner's simulator restriction). `backend/.venv` was created from `requirements.txt` because no
interpreter on this machine had fastapi — the tracker's Python-variance warning is now true on this
machine too; session prompts say `backend/.venv/bin/python` accordingly. TODO.md's S6 section
was reconciled against the merged tree (S6.4–S6.9 code verified present — `household_items`,
`OnboardingFlowView`, the HomeScreen checklist, the composite in `score.py`, `DrillMode/`, and
the `ResponderSnapshot*` exporters; boxes updated with that evidence, full acceptance walks and
device checks not re-run).




### S7.3 — 2026-09-10
- **UI Test Sandboxing**: `RouteRedrawAfterEditUITests` was failing because the simulator's app sandbox persists between runs, so `HomeDocumentStore().list()` was returning an old blank home instead of the `Demo Home`. To ensure deterministic tests, we introduced a `-TEST_SEED_DEMO_HOME` launch argument to bypass the `.isEmpty` check and force-seed the `twostory` fixture.
- **RouteRedraw Pixel Check via Active Floor**: The White Model overhaul made unselected floors render as translucent white shells, reducing route pixel counts on ground floors when testing a route starting upstairs. We updated the test to manually select the `Upstairs` active floor picker before screenshotting to restore the original #123FB0 solid route color.

## 2026-09-10 — S7.9 Vision Feasibility NO-GO

**Decision:** S7.10 is explicitly CUT following a negative result in the S7.9 Vision feasibility spike.

**Why:** A macOS CLI script testing `VNClassifyImageRequest` on representative images (space heater, water heater, bookcase, wall-mounted TV, mirror, radiator, etc.) yielded only one usable label mapping (`television` for Wall-mounted TV). Other objects returned overly generic labels (e.g. `structure`, `portal`) or completely misidentified the subject.

The established S7 playbook gate explicitly required 2+ target classes to receive usable label mappings to proceed to S7.10. Since the condition failed, building the Vision classifier into the app's Hazard Hunt is unwarranted and the feature is cancelled. S7.9's NO-GO represents a successful completion of the spike and a clean cutoff of S7.10.

## 2026-09-10 — The hazard hunt asks about what the scan found

**Decision:** Hunt question generation moves out of `HazardHuntView` into
`HazardHuntPlan` (EditorCore, Foundation-only, pure), and the questions are now derived from
the objects already in the room rather than asked cold.

**Why it moved:** the questions lived inside a SwiftUI view, which `swift test` cannot reach
and the iOS suite never exercised. Three defects survived there unnoticed — one of them
silently disabled a rule that cites FEMA. Logic no test can reach is logic nobody is checking;
the view is now a renderer for a tested value.

**The three defects, and what replaced them:**

1. **The water-heater question was inverted.** It asked "Water heater — strapped?" and a Yes
   created a heater with `secured: true`; a No created **nothing at all**. So the user with an
   unstrapped water heater — precisely the hazard `water_heater_unsecured` exists to catch —
   answered honestly and the model recorded nothing. It is now two questions ("is there one?",
   then "is it strapped?"), and the No branch dispatches `setObjectSecured(false)` rather than
   skipping, so every combination of answers lands in the model.
   `testUnstrappedWaterHeaterIsRecordedInsteadOfDropped` is the guard.

2. **Every answer landed at the room's centroid.** All four hazard rules are measured in
   distance — topple reach to the bed, clearance from the heat source — so a confirmed bookcase
   dropped in the middle of the room was a correct answer measured against the wrong place.
   Objects the app can place from real geometry now are: the fallback bookcase goes beside the
   scanned bed (first side that fits inside the room polygon, fixed order for determinism), and
   a mounted object goes at the bed's center with `elevation_m` set. Objects it genuinely
   cannot place — a portable heater has no scanned counterpart — carry a `placementHint` the
   view renders, instead of a silent guess.

3. **It asked cold.** The hunt ignored the scan, so a room whose scan already contained a
   1.9 m `storage` unit was still asked "anything tall and heavy near the bed?", inviting a
   second object on top of the first. Now a tall scanned `storage`/`wardrobe` produces a
   *relabel* question (`setObjectCategory(.bookcase)`) against that object, and the cold
   fallback is only asked when the room has nothing topple-prone at all. Same for the water
   heater: a scanned `appliance` in a utility room is offered for relabeling before a new
   object is invented. This is the cheap half of "close the gap between RoomPlan's taxonomy
   and ours" — RoomPlan sees the box and gets the label wrong; only the label needs asking.

**Also ruled here:** the mounted-above-the-bed question is not asked in a bedroom with no bed
("above it" needs an "it"), the strap question is skipped for `mounted` objects (a wall shelf
is not a floor-standing topple risk), and the heater question is skipped in bathrooms and
kitchens. Scope discipline: no new colour (the hint uses `DS.supporting`), no new
`EditAction` — every answer is expressed in the vocabulary S7.6 already added.

**Not done here:** the placement improvement helps only where the scan found an anchor. The
general fix is the same one the S7.9 NO-GO leaves open — better identification of scanned
objects — and it stays open.

---

## 2026-09-16 — S8.4: sync compares VALUES, and the JWT stays on `/homes`

Four rulings from the iOS cloud-sync session, each one a place the obvious implementation is
wrong in a way that would not show up until it was in a user's hands.

**1. The dirty check is a fingerprint of the DECODED model, never of bytes.**
A home that has been through the server differs from the local one by bytes but not by value:
pydantic serialises absent optionals as explicit `null` and fills `objects: []` (measured
2026-09-16, 21 extra keys on `bungalow.json`). `HomeFingerprint` therefore canonically
re-encodes the decoded `HomeModel` — sorted keys, ISO-8601 dates — and digests that. Two models
that are `==` always fingerprint identically, which is exactly the property a dirty check needs
and exactly what a hash of the stored JSON would not give. A byte comparison would have marked
every synced home permanently modified and re-uploaded the user's whole library on every sync.
`HomeFingerprintTests` pins it against the real bytes `model_dump_json()` emits, so a change in
pydantic's serialisation surfaces there rather than as mystery traffic.

It is FNV-1a, not SHA-256: this is a change detector, nothing trusts it against an adversary,
and a non-cryptographic digest avoids a CryptoKit import in a directory that must stay pure
Foundation.

**2. The per-user JWT is attached to `/homes` only — the playbook's "all requests" is wrong.**
`S8-4.md` WHAT-TO-ADD #1 says to attach the bearer token to every request. The deterministic
endpoints (`/routes`, `/score`, `/convert`, `/evacuate`, `/chat`) are guarded by the *shared*
`BACKEND_BEARER_TOKEN` — "this build may talk to this server" — while the cloud endpoints use a
*per-user* JWT — "this request is this user". `backend/app/api_auth.py` deliberately does not
layer them. Mixing them would work today and break silently the moment that stops being true.
Enforced structurally rather than by convention: `CloudHomesClient` is the only code that
attaches a JWT and it can only construct `/homes` URLs. `APIClient` is untouched.

**3. Conflicts are settled by `revision` first, `meta.modified` only as the tiebreak, and a tie
goes to the server.**
`revision` is a monotonic counter the server owns, so it is the only trustworthy answer to "is
the server ahead of what I last saw?" — two devices' clocks disagree by far more than the
interval between edits. But it cannot settle a genuine conflict (edited here *and* there),
because by construction both sides are ahead; only there does last-write-wins on `meta.modified`
apply. An exact tie resolves to the server on every device, deliberately: if each device
preferred its own copy, two devices would trade the same home back and forth forever,
incrementing the revision on every exchange and never converging.

**4. Sync state lives in a sidecar file, not on `HomeModel`.**
`<Documents>/sync-state.json`, versioned, holding one record per home (remote id, synced
revision, synced fingerprint, timestamp). Adding `last_synced_revision` to the schema would have
been a `schema_version` bump with matching pydantic and Swift changes and a
`schema-contract-guardian` run — and it would have been wrong regardless: sync progress is a
fact about *this device*, two devices legitimately disagree about it, and a device-local fact
stored inside a synced document is overwritten by the very sync it describes. Nothing under
`schema/`, `backend/app/models.py` or `escape_plan/Models/` changed in this session.

**Also ruled here.** A pulled home is written with `now: home.meta.modified` so it lands
verbatim — the default stamp would make it look newer than the server's copy and push it
straight back, which is an infinite loop between two devices with nobody editing anything.
Duplicate server records for one `home_id` (two devices both creating before either syncs; the
backend has no uniqueness constraint on a field inside the document) collapse client-side to
highest revision, then latest `updated_at`, then lowest record id — deterministic so every
device picks the same winner. A pull never overwrites the home open in the editor. And
`SyncFailure` is a third error type beside `BackendFailure` and `AuthFailure` for the reason
`AuthFailure` is the second one: a 401 here means "your session expired, re-authenticate", which
is neither "wrong password" nor "open Settings".

**What this session did NOT do, stated so the tracker cannot drift:** no iOS binary was built or
launched, the sync badge has never been rendered, and "pulls down homes created on other
devices" needs two phones. S8.4 is **not ticked**. See `BLOCKERS.md` §2.

## 2026-09-16 — S8.4 review: five tests that passed because the double couldn't fail

The S8.4 branch was reviewed before merge and six defects came back, every one of them a path
that lost or resurrected a user's home. They are recorded together because they share a cause
worth naming, and because the fix for the first one changes a file that has nothing to do with
sync.

**The cause: the test double could not reproduce the hazard.** `SyncManagerTests` runs against
`InMemoryHomeRepository`, whose `writePulledHome` is one line — `homes[home.home_id] = home`.
The hazard it is supposed to guard against lives in `HomeDocumentStore.save(model:)`, which
defaults to `now: Date()` and rewrites `meta.modified`. A dictionary assignment cannot re-stamp
a date, so the ping-pong test passed no matter what the real adapter did. Same shape for the
session-expiry test, whose `onSessionExpired` double incremented a counter and changed no state,
while the production closure signs the user out and thereby erases the very status the test was
asserting on. **A double that cannot exhibit the failure is not a test of the failure**, and
both of these read as thorough coverage right up until someone traced the production wiring.
`escape_planTests/HomeDocumentSyncRepositoryTests.swift` now covers the real adapter against a
real `HomeDocumentStore`; it needs a simulator and has never run.

**The worst defect was in `FixtureSeeder`, not in `Sync/`.** `seedStarterHomes` wrote the three
bundled homes with the default `save(model:)`, stamping `meta.modified` with the install time —
and those three keep **fixed `home_id`s** so that re-running the seeder overwrites rather than
piling up copies. Harmless for two years of this project; fatal the moment S8.4 landed. Edit the
Bungalow for a month on device A and sync; install on device B; B seeds a pristine fixture under
the same id carrying today's date; with no sidecar the conflict falls to last-write-wins, the
factory home wins, it is pushed over a month of real work, and device A pulls it back down over
its own copy. The home is gone from both devices and the server, on the most ordinary sequence
of events there is.

Fixed by seeding verbatim — `try store.save(model: model, now: model.meta.modified)`. That is
the principled fix rather than a patch on the tiebreak: the fixtures' own `2026-07-10` stamp is
genuinely when their content last changed, so it makes `meta.modified` mean what the tiebreak
already assumes it means. **The general lesson is worth keeping: a timestamp that is stamped
rather than carried is not evidence of anything, and S8.4 made every `meta.modified` in the app
load-bearing.** Anything that writes one should now be read with that in mind.

**The other five, briefly.** The sidecar was not scoped to an account, so a second user on one
device inherited the first user's server record ids — now keyed on `AccessToken.subject`, with a
mismatch starting clean. The "never overwrite an open editor" guard resolved through
`HomeLibrary.editor`, but the editor has three entry points with three different libraries and
the House tab's own initialiser passes `library: nil`, so two of three paths bypassed it
entirely; `openHomeID` is now app-scoped on the repository and set by `HouseScreen` itself.
`.failed(.sessionExpired)` was unreachable on screen because the sign-out it triggers made
`RootView` re-enter and overwrite it with `.signedOut`; a sticky `needsReauthentication` flag
carries the explanation across. A lost conflict destroyed the local copy silently under a green
checkmark — the reconciler computed `.conflictRemoteWins` and the manager never read it; the
losing copy is now kept as "<name> (this device)" and the badge says so. And a deleted home came
back on the next sync, because the backend has no delete endpoint — tombstones live in the
sidecar now. The app had already learned that last one locally:
`FixtureSeeder.starterSeedDefaultsKey` exists precisely so "a home the user deleted on purpose
is never resurrected on the next launch", and sync reintroduced the same bug one layer up.

**Ruled and NOT fixed, because it is a product decision.** The app is local-first, so a home
document belongs to the device rather than to an account. It follows that when any user signs
in, every home on that device is pushed into their account — including homes a previous user of
the same device created, address and household included. Scoping the sidecar closes the
stale-record half; the question "do local homes belong to whoever signs in?" is the owner's to
answer, and it is on `BLOCKERS.md` §2 rather than settled here.

## 2026-09-16 — Two §3 defects fixed, and one file moved into the reach of `swift test`

Housekeeping after S8.4, but two of the three carry a rule worth keeping.

**`pymongo`'s logger is pinned to INFO explicitly, not left to the root level.** It logs every
command with the full document at DEBUG, and since S8.4 those documents are users' homes —
floor polygons, room names, `meta.address_optional`, household composition. The tempting fix is
"we already call `basicConfig(level=logging.INFO)`", and that is not a safeguard, it is a
coincidence: raising the root logger while chasing an unrelated bug is an ordinary thing to do,
and on a hosted service the output is retained and readable by anyone with dashboard access. So
the four pymongo loggers are set to INFO by name, and `test_logging_privacy.py` sets the ROOT
logger to DEBUG and asserts they still refuse to emit there. **A privacy control has to survive
the action it is protecting against, or it is a comment.**

**`SemanticMatcher` moved into `tools/editorcore`, and that is the more useful half of this.**
Its RoomPlan-dependent code was already behind `#if canImport(RoomPlan)`, so everything above
that guard is Foundation + simd and compiles fine as a macOS package target — it had simply
never been symlinked. One file-level symlink (the first; `Auth/`, `Sync/`, `Core/` and `Models/`
are directory symlinks) plus moving its two test files into `escape_planTests/EditorCore/`, and
nine tests that had never run on this machine now run in under a second. **Worth checking other
files for the same property:** the bar is not "is it UI-free", it is "is everything non-Foundation
already behind a `canImport` guard", and `SemanticMatcher` cleared it by accident.

**The no-door scoring fix was deliberately narrowed, by a test.** The defect was that a
candidate room with no doors scored `totalDist = 0` — lower is better — and therefore outranked
a room that matched its doors at 0.35 m. The first version of the fix also changed the
no-evidence-anywhere case from `.ambiguous` to `.noMatch`, reasoning that the caller responds to
`.noMatch` by continuing the scan. `testNoDoorAmbiguity`, written by the 2026-09-14 ambiguity
fix, failed immediately: a 180° rotation genuinely cannot be resolved without doors, and
"I can't tell" is the intended answer there. The fix now changes only the ranking. Recorded
because it is the second time in this session a pre-existing test stopped a widening, and
because the S8.4 review found the opposite failure five times over — tests that could not fail.

**`ARDrillView`'s waypoint height** now comes from `DollhouseGeometry.floorBaseHeights`, the same
stacking the dollhouse uses, rather than a second formula. Two formulas for where a floor sits
would eventually disagree and the AR view and the 3D view would draw the same route at two
different heights. It is fixed in code and verified by nothing — ARKit in a
`UIViewRepresentable`, untestable on any machine here — and is carried as a device-pass item.

---

## 2026-09-16 — Whose homes are these, and four defects the fixtures were hiding

### The scope question, ruled: first account adopts, second never does

The app is local-first, so homes exist before any account. That makes "do local homes belong to
whoever signs in?" a real question with two failure modes pointing opposite ways. Answer "no" and
the overwhelmingly common case breaks: someone uses the app offline for weeks, signs up, and
"sign in to back up your homes" backs up nothing. Answer "yes" unconditionally and a shared
device — a family phone, a demo iPad, a handed-down handset — copies the previous user's home
layout, `meta.address_optional` and household composition into a stranger's cloud account
permanently, with no prompt and nothing to undo it.

**The rule is per-home, not per-device.** `SyncState.homeOwners` records which account claimed
each home the first time it synced, and survives an account switch because it is a fact about the
device rather than about one login. Unclaimed → the signing-in account adopts it. Claimed by
someone else → skipped in **both** directions, never pushed and never overwritten, and the badge
says so rather than reporting a clean sync.

Deletions are scoped the same way, carrying the owner in the tombstone. That is not fussiness:
the three starter homes keep **fixed `home_id`s**, so without it one user deleting the bundled
Bungalow would stop a second user from ever receiving *their own* Bungalow from *their* account.
Deleting also releases the claim — a home gone from the device is owned by nobody on it, and a
lingering claim would make a later account's own copy of that id read as somebody else's forever.

**The deliberate gap:** a home owned by another account stays *visible* on the device. The
boundary for that is the phone's lock screen, not sync. Deleting a previous user's homes on
sign-in would be a far worse failure than showing them.

### Four defects, and what they have in common

`build_room_grid` blocked any footprint handed to it, so a TV bolted to the wall 1.35 m up took
walkable floor away. `extractedLongestWall` took the longest raw wall *segment*, and RoomPlan
splits a wall at every doorway, so a 10 m wall in three pieces lost to an unbroken 4 m
perpendicular one — a permanent 90° alignment error. `EditorValidation` claimed every entity id
except safety points, so the editor accepted homes pydantic rejects with a 422. And
`escape_plan/Fixtures/` — byte-identical copies bundled into the iOS app — had drifted from
`schema/fixtures/`.

**Every one of them was invisible because the test bed could not express the failing case.** The
mounted TV overlaps a bed, which is blocked anyway. No fixture carried `meta.last_scanned`, or
`hearing_impaired`, or `vision_impaired`, or — nobody had noticed — `pet`. The wall-merging lived
inside `#if canImport(RoomPlan)`, where no machine without a simulator can reach it. The bundled
copies were guarded by nothing at all.

So the fixes were as much about reach as about logic: `WallGrouping` and `SemanticMatcher` moved
*out* of the RoomPlan-only region and into `tools/editorcore`, the fixtures were seeded once to
cover **both sides** of every optional branch, and `test_fixture_coverage.py` now fails if that
coverage drains away again. The seeding rule worth keeping is that **a field present in every
fixture is as untested as one present in none** — `meta.last_scanned` had an iOS rescan prompt no
fixture could trigger, and the never-scanned path needs a fixture just as much as the scanned one.

Two of the ported contract tests found defects within minutes of landing, having sat unmerged on
`my-s6-1-and-policy` for ten days. That is the argument against parking a branch: the tests were
written *with* the behaviour they guard, and the behaviour shipped without them.

### Also decided

`obstructs_floor` keys on **`mounted`**, not `elevation_m` — mounted is the schema's "how is this
installed", while a box raised on a table is still something you cannot walk through. How far a
mounted object protrudes is not modelled, documented at the helper, and errs toward offering a
path a shoulder brushes rather than one that does not exist.

Sync now fires on **editor close** (gated on an actual commit) and on **returning to the
foreground**, deliberately not on autosave — autosave debounces during active editing, so a push
per autosave would mint a server revision every few seconds for a home nobody has finished
changing, on a free tier measured at a 42 s cold start.
| 2026-09-24 | S11.6 follow-up | **`ResponderSnapshotJSON` gets a hand-written `encode(to:)` purely so `as_of` is emitted as explicit `null` rather than omitted when a home has never been scanned.** `EscapePlanDocument` moved out of `EscapePlanPDF.swift` into its own Foundation-only file so the snapshot path can be symlinked into `tools/editorcore` | S11.6's acceptance said the snapshot "always contains `as_of`", but the five tests asserting that lived in the app test target and had never executed — no simulator. Moving them into the package made them run, and the first run failed: Swift's synthesized encoder uses `encodeIfPresent` for optionals, so a never-scanned home shipped a snapshot with no `as_of` key at all. For a document a fire department may parse with software that never saw this app, an absent key is ambiguous (old exporter? bug? no scan?) while an explicit `null` states the same thing `stalenessNote` says in words. The extraction was the precondition: the input type to the whole export path sat inside a UIKit-importing file, which is why none of this could ever be tested without a simulator |
| 2026-10-03 | S11.36 | **The route cache key now explicitly models peril, profileID and HomeFingerprint.** The `DrillScreen` consumers of the cache were removed in demo trim 2, so the remaining consumers are `HouseScreen` (dock routing, fire simulation) and the printable plan exporter. | Previously, the cache was keyed only by `home_id`, which meant one peril or person's route could overwrite another's or mask offline misses, or survive edits to the underlying home structure. Adding peril, person, and a canonical JSON fingerprint to the cache logic fixes AUD-028. |
| 2026-10-03 | S11.36 | **The route cache key now explicitly models peril, profileID and HomeFingerprint.** The `DrillScreen` consumers of the cache were removed in demo trim 2, so the remaining consumers are `HouseScreen` (dock routing, fire simulation) and the printable plan exporter. | Previously, the cache was keyed only by `home_id`, which meant one peril or person's route could overwrite another's or mask offline misses, or survive edits to the underlying home structure. Adding peril, person, and a canonical JSON fingerprint to the cache logic fixes AUD-028. |
| 2026-10-04 | Review of the S11.12/S11.39/S11.47 agent work | **Fixed three things the agents missed or mis-reported.** (1) `SettingsScreen.swift` line 392 told users the assistant "audits the home"; reworded to "explains those routes and answers questions" (the AUD-022 Path B claim, not a safety string; the S11.39 agent listed it but did not own the file). Same wording fix in `01-product-spec.md`. (2) `HomeThumbnailView.swift` was reported deleted by S11.47 but was still present; deleted. (3) `script-v2.md` said "Every answer ... cites its sources"; S11.44 allows uncited small talk and the 911 line, so it now says "every safety answer". | Pitch claims must match the build; BLOCKERS must match the filesystem. |
| 2026-10-04 | Cleanup review (branch `s11-cleanup-fixes`) | **Closed five open BLOCKERS lines and widened the citation parser.** `[cite: a, b]` is now a valid multi-id tag (was read as no citation, which forced a needless retry or fallback); local faults (EncodingError, InvalidHomeID, Cocoa file errors) get their own non-connectivity message instead of "check your connection"; `backend/README.md` no longer says every push auto-deploys. No safety string was reworded: the new local-fault sentence is app copy, not guidance. | Each was a verified defect with a test that fails without the fix. |
