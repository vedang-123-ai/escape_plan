# Audit → playbook traceability

Source: the full-repository audit of 2026-09-28 (`audit/`, 50 findings AUD-001 to AUD-050; master index
`audit/15_PRIORITIZED_ISSUES.md`). This file answers one question: **where in the playbook is each finding addressed?**
Status is not tracked here. It lives in the README index (session DONE marks) and in `docs/tracker/BLOCKERS.md`.

When a finding is split, each part names the session that owns it. "Owner" means only the project owner can act
(dashboard, billing, a product decision); the listed session verifies or records the result.

## By finding

| ID | Sev | Finding (short) | Addressed by | Notes |
|---|---|---|---|---|
| AUD-001 | P0 | Deployed bearer token ≠ app's token | **Owner**; S11.14 (asks, then runs demo-preflight), S11.42 (rotation reaches installs) | Never read `.env` in a session |
| AUD-002 | P1 | Anthropic out of credits | **Owner**; S11.14 (asks), S11.49 (verifies live) | |
| AUD-003 | P1 | Shared token ships in the app; spoofable limiter key; spend unbounded | S11.27 | Per-install tokens / App Attest recorded as not feasible before Oct 24 |
| AUD-004 | P1 | Unbounded geometry and body size, CPU DoS | S11.25 (geometry bounds), S11.26 (body-size limit) | |
| AUD-005 | P1 | `/auth/*` unthrottled; Argon2 on the event loop | S11.28 | |
| AUD-006 | P2 | `/score` recommendations outside the AI guard | S11.27 | Already on BLOCKERS Part A |
| AUD-007 | P2 | No per-user quota on `/homes` | S11.30 (server), S11.32 (client handling) | |
| AUD-008 | P2 | Documents exposed in the Files app in Release; scans never cleaned | S11.40 | Application Support move: not converted (below) |
| AUD-009 | P2 | Saved token overrides forever; invalid URL accepted; Advanced in Release | S11.42 | Needs the owner's answers from S11.14 |
| AUD-010 | P3 | `/convert` returns every exception as 422 with Python text | S11.31 | |
| AUD-011 | P3 | `needs_rehash` never called | S11.28 | |
| AUD-012 | P3 | Untrusted `home_id` used as a filename; list/load disagree | S11.41 | |
| AUD-013 | P1 | House editor keeps a stale copy and overwrites other writers | S11.18 (one store, prerequisite), **S11.19** (the fix) | Blocks S11.20-S11.22, S11.24 |
| AUD-014 | P2 | Home switch race shows the previous home's score; cancel shown as "can't reach server" | S11.23 (late response), S11.37 (classifier) | |
| AUD-015 | P2 | Conflict copies pile up while the home is open | S11.22 | |
| AUD-016 | P2 | `POST /homes` lost update (no base revision) | S11.30 (server), S11.32 (client) | S11.30 must be deployed before S11.32 ships |
| AUD-017 | P2 | Re-scan "Add to Home" bypasses the reducer, `try?` save | S11.24 | |
| AUD-018 | P3 | Checklist, drill log and chat never leave the device | S11.16 (disclosure sentence) | Syncing that state: not converted (below) |
| AUD-019 | P3 | Screens build their own `HomeDocumentStore()` | S11.18 | Known (BLOCKERS "Found while doing this") |
| AUD-020 | P1 | Profiles unreachable since `87c0610`; drill dead end | S11.20 | |
| AUD-021 | P1 | No delete / duplicate / export / import; blank homes accumulate | S11.21 (delete, duplicate, blank homes, demo labels) | JSON export/import UI: not converted (below) |
| AUD-022 | P1 | `/analyze` and `/explain` have no UI; pitch claims them | **Owner decision** (S11.14 asks), S11.39 (executes), S11.49 (live, Path A) | S11.12 takes the claims diff |
| AUD-023 | P1 | AI drafts scored without review | S11.17 | Live `/build` path verified in S11.49 |
| AUD-024 | P1 | Photo `/build` sends HEIC/JPEG labelled PNG | S11.26 (server allow-list and size), S11.33 (client JPEG), S11.49 (live) | |
| AUD-025 | P1 | Drill appends client-written tornado advice | S11.15 | |
| AUD-026 | P2 | Checklist recurrence unreachable through `/score` | S11.34 (server), S11.35 (app) | S11.34 must be deployed before S11.35 ships |
| AUD-027 | P2 | Settings share uses the most recent home, fails silently | S11.38 | |
| AUD-028 | P2 | Offline route cache ignores peril, profile, model | S11.36 | |
| AUD-029 | P2 | Re-check failure labelled as score; Retry imports an old scan | S11.24 | |
| AUD-030 | P2 | Chat accepts uncited safety claims | S11.44 (stub-verified), S11.49 (live) | |
| AUD-031 | P2 | 60-minute sessions, no refresh; backup silently stops | S11.43 | |
| AUD-032 | P2 | Chat timeout shorter than the cold start; timeout shown as "offline" | S11.37 | Render paid tier is an owner decision, logged for S11.13 |
| AUD-033 | P3 | One conversation slot for all homes; unbounded history | S11.45 | |
| AUD-034 | P1 | Drill fix exists only locally | S11.14 | |
| AUD-035 | P2 | No AI timeouts; loops outlive the client; inputs unbounded | S11.26 (input caps), S11.29 (timeouts and deadlines), S11.49 (live) | |
| AUD-036 | P2 | iOS suite red: Keychain entitlement, stale expectation, UI-test isolation | **S11.8** (existing session; see the README addendum) | Root causes in `audit/11_TESTING.md` |
| AUD-037 | P2 | Render not gated on CI; iOS suite manual only | S11.31 (`/health` reports the commit), S11.46 (nightly suite, deploy gating) | Render half: owner confirms the dashboard |
| AUD-038 | P2 | `tools-used.md` may omit AI tools evidenced on the machine | **Owner** (S11.14 asks), S11.12 (existing; owns `docs/tools-used.md`), S11.47 (`improved_prompt.md`) | Must be settled before submission |
| AUD-039 | P3 | Stale "backend has no delete endpoint" comments | S11.21 (first step) | |
| AUD-040 | P3 | Scratch scripts at the root would rewrite 2.1 to 2.0 | S11.47 | |
| AUD-041 | P3 | Local Python 3.13 vs deploy 3.12; pytest in runtime deps | S11.47 | |
| AUD-042 | P3 | Mongo index creation never retried | S11.31 | |
| AUD-043 | P3 | `require_token` duplicated | S11.27 | |
| AUD-044 | P3 | Dead code | S11.20 (ProfilesScreen re-wired), S11.39 (Analyze client), S11.47 (HomeThumbnailView, FixtureLibrary) | |
| AUD-045 | P3 | `HouseScreen.swift` is 2,726 lines | S11.19 extracts only the session-lifecycle seam | Full split: not converted (below) |
| AUD-046 | P3 | Decode errors and cancellations shown as "Couldn't reach the server" | S11.37 | |
| AUD-047 | P3 | `list()` decodes every home on the main thread | S11.48 (optional, owner agrees to un-defer) | Deferred on BLOCKERS on purpose |
| AUD-048 | P3 | Tracker and playbook statements now wrong | S11.14 | |
| AUD-049 | P3 | Silent failures on user writes | S11.24 (Home re-check add, DiffReviewSheet), S11.38 (Settings), S11.45 (Assistant), S11.48 (launch seeding) | |

**Coverage check:** all 50 IDs appear above. Every P0 and P1 maps to at least one session, or to an owner action plus
the session that verifies it.

## By session

| Session | Findings |
|---|---|
| S11.8 (existing) | AUD-036 |
| S11.12 (existing) | AUD-038 (the file edit), AUD-022 (the claims diff from S11.39) |
| S11.14 | AUD-034, AUD-048; asks the owner about AUD-001, AUD-002, AUD-022, AUD-038 |
| S11.15 | AUD-025 |
| S11.16 | AUD-050, AUD-018 (disclosure) |
| S11.17 | AUD-023 |
| S11.18 | AUD-019 (the R1 foundation for AUD-013) |
| S11.19 | AUD-013, the AUD-045 seam |
| S11.20 | AUD-020, AUD-044 (ProfilesScreen) |
| S11.21 | AUD-021, AUD-039 |
| S11.22 | AUD-015 |
| S11.23 | AUD-014 (late response) |
| S11.24 | AUD-017, AUD-029, AUD-049 (re-check) |
| S11.25 | AUD-004 (geometry) |
| S11.26 | AUD-004 (body size), AUD-035 (input caps), AUD-024 (server) |
| S11.27 | AUD-003, AUD-006, AUD-043 |
| S11.28 | AUD-005, AUD-011 |
| S11.29 | AUD-035 (timeouts, deadlines) |
| S11.30 | AUD-016 (server), AUD-007 |
| S11.31 | AUD-010, AUD-042, AUD-037 (`/health` commit) |
| S11.32 | AUD-016 (client), AUD-007 (client) |
| S11.33 | AUD-024 (client) |
| S11.34 | AUD-026 (server) |
| S11.35 | AUD-026 (app) |
| S11.36 | AUD-028 |
| S11.37 | AUD-032, AUD-046, AUD-014 (classifier) |
| S11.38 | AUD-027, AUD-049 (Settings) |
| S11.39 | AUD-022, AUD-044 (Analyze client) |
| S11.40 | AUD-008 |
| S11.41 | AUD-012 |
| S11.42 | AUD-009 (and AUD-001's effect on installs) |
| S11.43 | AUD-031 |
| S11.44 | AUD-030 |
| S11.45 | AUD-033, AUD-049 (Assistant) |
| S11.46 | AUD-037 |
| S11.47 | AUD-040, AUD-041, AUD-044 (dead code), AUD-038 (`improved_prompt.md`) |
| S11.48 | AUD-047, AUD-049 (seeding) |
| S11.49 | AUD-002 (verification); live checks of AUD-022, AUD-024, AUD-030, AUD-035 |

## Not converted into a task, and why

These parts of findings were considered and deliberately left out. Re-open any of them with a dated
`docs/decisions.md` row.

| Finding part | Why it is not a session |
|---|---|
| AUD-008: move internal stores from Documents to Application Support with a migration | S11.40 turns off file sharing in Release, so Documents is no longer user-visible. A storage move risks existing users' homes (it needs a migration and upgrade tests) for no user-facing benefit before Oct 24. It becomes necessary only if file sharing must stay on in Release. S11.40 records this in decisions.md. |
| AUD-018: sync checklist state, the drill log and chats across devices | A product decision with real cost (a sidecar on `StoredHomeModel`, conflict rules, privacy copy). The audit's cheapest honest fix, telling the user, is S11.16. Accounts are demoted and absent from the pitch (scope lock), so cross-device parity is not on the critical path. |
| AUD-021: JSON export/import UI for homes | No spec, pitch or judge-path requirement found (`01-product-spec.md` has none). `HomeDocumentStore.export/importDocument` stay as internal API. Delete and duplicate, the parts users need, are S11.21. |
| AUD-045: decompose `HouseScreen.swift` | BLOCKERS lists it as "Deferred on purpose (do not do in a fix session): split during the upcoming House redesign". S11.19 extracts only the load/autosave/registration seam that AUD-013 needs. |
| AUD-003: per-install tokens with App Attest / DeviceCheck | The real fix for a public client credential, but it touches the backend, the app, provisioning and demo-preflight, and needs device testing. S11.27 bounds the damage instead (server-side daily budget, trusted client key) and records the decision. |
| AUD-001, AUD-002 (the fix itself) | Owner-only: the Render dashboard and billing. Sessions ask, record and verify (S11.14, S11.42, S11.49), and never read secrets. |
| "Not audited in depth" areas (renderer internals, gait animation, PDF layout, routing algorithms) | No findings to convert. They carry their own tests and are owned by S11.9/S11.10 (device passes). |
