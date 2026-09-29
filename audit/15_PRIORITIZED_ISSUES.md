# 15 · Prioritized Issues — master index

Every finding in this audit, one row each, sorted by severity then ID. IDs AUD-001 … AUD-050 are all used, each once;
numbering follows drafting order, not severity. "Home" is the file holding the full write-up. "Status" is as of 2026-09-28: **Open** (new in this audit), **Known** (already on
`docs/tracker/BLOCKERS.md`; re-checked here), **Known-unverified** (on BLOCKERS; not re-checkable without owner secrets).

| ID | Sev | Category | Issue | Location | Depends on / relates to | Home | Status |
|---|---|---|---|---|---|---|---|
| AUD-001 | P0 | deployment | Deployed bearer token ≠ app's token → 401 on the whole demo path | Render env, `.env`, `BackendConfig.local.json` | AUD-009, AUD-003 | 10 | Known-unverified |
| AUD-002 | P1 | deployment | Anthropic out of credits → chat, build, explain, analyze 502 | Anthropic console | blocks live checks of AUD-024, AUD-030 | 10 | Known-unverified |
| AUD-003 | P1 | security | Shared bearer token ships in the app; limiter keyed on spoofable XFF; spend unbounded | `APIClient.swift:67-78`, `rate_limit.py:119-126`, `main.py:214-233` | AUD-004, AUD-006, AUD-035 | 06 | Open (XFF half Known) |
| AUD-004 | P1 | security/perf | Unbounded home geometry → CPU/memory DoS (measured ×10 = 7.2 s/plan) | `models.py`, `nav_grid.py:28,154-161`, `main.py:500-503` | schema bump if in JSON Schema | 06 | Open |
| AUD-005 | P1 | security | `/auth/*` unthrottled; Argon2 blocks the event loop; open registration | `api_auth.py:123-157`, `passwords.py` | AUD-011, AUD-007 | 06 | Open |
| AUD-013 | P1 | data integrity | House editor holds a stale model across tabs and overwrites other writers; sync guard not restored | `HouseScreen.swift:244-265,2226-2296`, `ContentView.swift:137-154` | AUD-017, AUD-015, AUD-020, AUD-045 | 02 | Open |
| AUD-020 | P1 | feature | Profiles screen unreachable since `87c0610`; drill dead-ends for users' own homes | `ProfilesScreen.swift`, `DrillScreen.swift:146-151` | AUD-013 (another writer), AUD-019 | 14 | Open |
| AUD-021 | P1 | feature | No delete / duplicate / JSON export / import for homes; blank & demo homes accumulate | `HomeLibrary.swift:54-72`, `HomeScreen.swift:142-196`, `HouseScreen.swift:2249-2252` | AUD-039, AUD-015, sync tombstone rules | 14 | Open |
| AUD-022 | P1 | feature/pitch | `/analyze` and `/explain` have no UI; demo Beat 5 and "audits" claim unsupported | `APIClient+Analyze.swift`, `docs/demo/script-v1.md:105-115` | AUD-002 | 14 | Open |
| AUD-023 | P1 | cross-system | AI drafts scored immediately; "mandatory review" enforced only in House (regression) | `HomeScreen.swift:95-100,203-208`, `HouseScreen.swift:1623-1633` | — | 14 | Open |
| AUD-024 | P1 | integration | Photo `/build` sends HEIC/JPEG bytes labelled `image/png`, unbounded size | `BuildFromPlanView.swift:147-155,196-203`, `APIClient+Build.swift`, `builder.py:398-404` | AUD-002 (to verify live) | 05 | Open |
| AUD-025 | P1 | grounding | Drill appends client-written unconditional "Leave immediately" tornado guidance | `DrillScreen.swift:828-832`, `engine.py:365-377` | — | 13 | Open |
| AUD-034 | P1 | process | Drill fix (2 commits) exists only locally; origin has only `main` | branch `drill-3d-fallback` | AUD-036 (gate state) | 10 | Open |
| AUD-050 | P1 | privacy | Privacy copy: "signed out … uploads nothing"; "no photo is ever sent" — false | `AccountPrivacy.swift:70-85` | AUD-024, AccountPrivacyTests | 06 | Open |
| AUD-006 | P2 | security | `/score?include_recommendations` spends AI outside the cost guard | `main.py:480-523` | AUD-003 | 06 | Known |
| AUD-007 | P2 | security/db | No per-user quota on `/homes` | `api_auth.py:224-263` | AUD-004, AUD-005 | 06 | Open |
| AUD-008 | P2 | privacy | Documents (homes, sidecar, chats, raw scans) exposed in Files app in Release; scans never cleaned | `project.pbxproj:401,405,437,441`, `Capture/` | storage migration | 06 | Open |
| AUD-009 | P2 | security/UX | Saved token overrides bundled one forever; invalid server URL accepted; Advanced in Release | `APIClient.swift:42-64`, `SettingsScreen.swift:67-103,499-509` | AUD-001 | 06 | Open |
| AUD-014 | P2 | frontend state | Home switch race shows previous home's score; cancelled request shown as "can't reach server" | `ReadinessStore.swift:82-159`, `BackendFailure.swift:112-150` | AUD-046 | 02 | Open |
| AUD-015 | P2 | reliability/sync | Conflict copy made before a pull the open editor refuses → copies pile up | `SyncManager.swift:358-377`, `HomeDocumentSyncRepository.swift:97-129` | AUD-013, AUD-021 | 09 | Open |
| AUD-016 | P2 | database | `POST /homes` lost update: no base-revision precondition | `api_auth.py:224-263`, `cloud_repo.py:132-149` | SyncManager 409 handling | 04 | Open |
| AUD-017 | P2 | data integrity | Re-scan "Add to Home" bypasses reducer/validation; `try?` save | `HomeScreen.swift:84-91` | AUD-013 | 02 | Open |
| AUD-026 | P2 | integration/logic | Checklist recurrence unreachable via `/score` (bool-only state, no `now`); monthly test never recurs | `main.py:476-513`, `checklist.py:60,109-135,195-258`, `ChecklistStateStore.swift` | data migration of stored `true`s | 05 | Open |
| AUD-027 | P2 | UX/privacy | Settings fire-department share uses most-recent home, fails silently | `SettingsScreen.swift:238-261` | AUD-021 | 07 | Open |
| AUD-028 | P2 | integration | Offline route cache ignores peril, profile, model version | `APIClient+Cache.swift:37-96` | — | 05 | Open |
| AUD-029 | P2 | UX | Re-check failure labelled as score; Retry does nothing or imports an old scan | `HomeScreen.swift:459-520` | — | 07 | Open |
| AUD-030 | P2 | grounding | Chat accepts uncited safety claims (only fabricated ids rejected) | `chat/service.py:142-146,199-225` | AUD-002, AUD-035 | 13 | Open |
| AUD-031 | P2 | reliability/auth | 60-min JWT, no refresh → backup silently stops | `render.yaml`, `tokens.py`, `AuthSession.swift:101-131` | — | 09 | Open |
| AUD-032 | P2 | integration | Chat 60 s timeout < measured 51 s cold start + model time; timeout reported as "offline" | `APIClient+Chat.swift:68`, `BackendFailure.swift:133-145` | AUD-046 | 05 | Open |
| AUD-035 | P2 | backend/cost | No AI client timeouts; loops outlive clients; chat/build inputs unbounded | `ai/*.py` client factories, `builder.py:37-38`, `api_chat.py:45-51` | AUD-003 | 03 | Open |
| AUD-036 | P2 | testing | iOS suite 7 failures: keychain entitlement ×3, stale fixture expectation ×1, UI-test isolation ×3 | `KeychainTokenStoreTests`, `EvacuationMockTimelineTests.swift:5-43`, `SignedOutPathUITests.swift:29-39,125-133` | AUD-037, AUD-048 | 11 | Known (root causes new) |
| AUD-037 | P2 | CI/deploy | Render not gated on CI (low confidence); iOS suite manual-only | `gate.yml`, `render.yaml` | AUD-036 | 10 | Open |
| AUD-038 | P2 | submission | `tools-used.md` may omit Antigravity agents evidenced by local worktrees | `docs/tools-used.md` | owner confirmation | 10 | Open |
| AUD-010 | P3 | backend | `/convert` returns every exception as 422 with Python text | `main.py:371-385` | — | 06 | Open |
| AUD-011 | P3 | security | `needs_rehash` never called | `passwords.py:51-60` | AUD-005 | 06 | Open |
| AUD-012 | P3 | security/data | Untrusted `home_id` used as filename; list/load identity mismatch | `HomeDocumentStore.swift:74-100,222-224` | AUD-008 | 06 | Open |
| AUD-018 | P3 | data model | Checklist, drill log, chat not synced/exported → per-device scores | `ChecklistStateStore.swift`, `AccountPrivacy.swift` | AUD-050 | 04 | Open (trade-off documented) |
| AUD-019 | P3 | frontend | Screens build own `HomeDocumentStore()`, ignore temp fallback | 6 call sites (02) | — | 02 | Known |
| AUD-033 | P3 | frontend/cost | Single conversation slot across homes; unbounded history | `ConversationStore.swift`, `AssistantScreen.swift:330-395` | AUD-035 | 02 | Open |
| AUD-039 | P3 | docs | "Backend has no delete endpoint" comments are stale | `ContentView.swift:80`, `HomeLibrary.swift:35`, `SyncReconciler.swift` | AUD-021 | 12 | Open |
| AUD-040 | P3 | hygiene | Tracked scratch scripts at root would rewrite 2.1 code to 2.0 | `scratch_*.py`, `improved_prompt.md` | — | 12 | Open |
| AUD-041 | P3 | deployment | Local Python 3.13 vs deploy 3.12; pytest in runtime deps | `.venv`, `requirements*.txt` | — | 10 | Open |
| AUD-042 | P3 | database | Mongo index creation failure never retried | `database.py:130-144` | — | 03 | Open |
| AUD-043 | P3 | backend | `require_token` duplicated | `main.py:214-223`, `api_chat.py:27-42` | AUD-003 | 03 | Open |
| AUD-044 | P3 | tech debt | Dead code: `HomeThumbnailView`, `FixtureLibrary` | 12 | AUD-020, AUD-022 | 12 | Open |
| AUD-045 | P3 | tech debt | `HouseScreen.swift` 2,726 lines | `HouseScreen.swift` | AUD-013 | 12 | Known (deferred) |
| AUD-046 | P3 | integration | Decode errors/cancellations shown as "Couldn't reach the server" | `BackendFailure.swift:133-150` | AUD-014, AUD-032 | 05 | Open |
| AUD-047 | P3 | performance | `list()` decodes every home on the main thread, on every refresh | `HomeDocumentStore.swift:74-100` | AUD-021 | 08 | Known (deferred) |
| AUD-048 | P3 | docs | BLOCKERS/playbook statements now wrong (7 items) | `BLOCKERS.md`, `playbook/README.md`, `notes/` | AUD-036 | 12 | Open |
| AUD-049 | P3 | UX | Silent failures on user-initiated writes | `HomeScreen.swift:89`, `SettingsScreen.swift:243-260`, `AssistantScreen.swift:393`, `escape_planApp.swift:66-71` | AUD-017, AUD-027 | 07 | Open |

## Counts

| Severity | Count | IDs |
|---|---|---|
| P0 | 1 | AUD-001 (known, owner-only, unverified today) |
| P1 | 13 | AUD-002, 003, 004, 005, 013, 020, 021, 022, 023, 024, 025, 034, 050 |
| P2 | 19 | AUD-006, 007, 008, 009, 014, 015, 016, 017, 026, 027, 028, 029, 030, 031, 032, 035, 036, 037, 038 |
| P3 | 17 | AUD-010, 011, 012, 018, 019, 033, 039, 040, 041, 042, 043, 044, 045, 046, 047, 048, 049 |
| **Total** | **50** | |

## Root causes (several findings share one)

| Root cause | Findings |
|---|---|
| **R1** One home file, many writers, no per-home owner | AUD-013, AUD-015, AUD-017, AUD-019, AUD-049 (partly) |
| **R2** Revamp deleted `BetaScreen` without re-homing its actions | AUD-020, AUD-021, AUD-023, AUD-044 (partly) |
| **R3** A shared secret distributed in the client is the only anonymous-API control | AUD-003, AUD-004, AUD-005, AUD-006, AUD-007, AUD-035 |
| **R4** Features wired on one side only | AUD-022, AUD-026, AUD-021 (import) |
| **R5** Client-side text/claims not held to the server's grounding checks | AUD-025, AUD-050, AUD-030 |
| **R6** Responses and caches not tagged with what they were computed for | AUD-014, AUD-028, AUD-027 |
| **R7** Timeouts and error classification tuned for a warm server | AUD-032, AUD-035, AUD-046 |
