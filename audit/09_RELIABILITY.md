# 09 · Reliability

Canonical home for AUD-015, AUD-031. The "what happens when…" matrix below cross-references the rest.

## Failure-mode matrix

| Scenario | What happens today | Finding |
|---|---|---|
| Network down, Home tab | Cached score shown (ScoreCache) + offline banner; checklist toggles saved locally, rescore fails with banner | OK |
| Network down, House/Drill | Last-good route plan per home, with a "cached" banner — but not keyed by peril/profile | AUD-028 |
| Backend cold (free tier) | `/health` measured **51 s**; 90 s timeouts cover most endpoints; **chat (60 s) fails and says "offline"** | AUD-032 |
| Backend CPU pinned by a large home | Every request stalls (single instance, GIL) | AUD-004 |
| Login flood | Event loop blocked by Argon2; `/health` stalls → Render may restart | AUD-005 |
| Anthropic out of credit | 502 "AI rejected" (by design); deterministic endpoints unaffected | AUD-002 |
| Anthropic slow/hung | SDK default 600 s timeout, 2 retries; holds an AI slot | AUD-035 |
| Mongo unreachable | `/homes` → 503 retryable (handled); `/health/db` reports it | OK |
| Mongo index creation fails at boot | Never retried | AUD-042 |
| Documents directory unavailable | Temp fallback + permanent banner at launch; some screens still write the real path | AUD-019 |
| Home file fails to decode | `BackendFailure.localLoad`; sync refuses to overwrite it (good) | OK |
| User switches home mid-request | Stale score may be shown for the new home | AUD-014 |
| User double-taps a checklist item | Two rescore requests; the first cancelled one shows a false "can't reach server" | AUD-014 |
| Two screens edit one home | Last autosave of the stale editor wins | AUD-013 |
| Two devices edit one home | Server LWW without revision precondition | AUD-016 |
| Sync conflict while the home is open in House | A "(this device)" copy is created on every sync attempt | AUD-015 |
| Session older than 60 min | Signed out on next sync/launch; backup silently stops | AUD-031 |
| App killed mid-scan conversion | Raw scan stays on disk (never cleaned); no resume | AUD-008 |
| App killed mid-`/build` | Server keeps building up to 40 iterations; result discarded | AUD-035 |
| User has no homes | Home: "Map your home"; Tasks: "No home yet" + Scan (verified in code) | OK |
| User's home has no profiles | Drill dead-ends ("Add family members in Profiles first") with no Profiles screen | AUD-020 |
| Thousands of homes / huge home | `HomeDocumentStore.list()` decodes every file on the main thread at launch and on every refresh | AUD-047 |

---

### [AUD-015] A sync conflict copies the local home before a pull that can be refused, so copies pile up

**Severity:** P2
**Location:**
- `escape_plan/Sync/SyncManager.swift:358-377` (`.pullRemote`: `preserveLocalCopy` runs, *then* `writePulledHome`)
- `escape_plan/Persistence/HomeDocumentSyncRepository.swift:97-104` (`writePulledHome` throws
  `SyncFailure.editorHasTheHomeOpen` when the home is open in the editor)
- `escape_plan/Persistence/HomeDocumentSyncRepository.swift:122-129` (`preserveLocalCopy` → `store.duplicate` with a new id)

**Category:** reliability / sync
**What I found:** For a conflict the remote wins (`conflictRemoteWins` or `neverSyncedOnThisDevice`), the manager first
duplicates the local home as "<name> (this device)", then tries to write the pulled copy. If the user has that home
open in House, the write is refused; the sync record is not updated, so the next sync plans the same pull and makes
another copy.
**Current behavior (code-traced):** With a conflicting home open in the House tab, every foreground/launch sync adds
one more "(this device)" home. Each copy is a new local home, so the next sync uploads it (`createRemote`) and every
other device downloads it. There is no delete UI (AUD-021) to clean them up.
**Expected behavior:** Check the open-home guard before preserving; preserve at most once per conflict (record the
preserved id in `SyncState`).
**Evidence:** Code reading of the ordering; not reproduced (needs two devices or the in-memory fakes — `SyncManagerTests`
could cover it with `InMemoryHomeRepository` configured to throw on write).
**Affected systems:** Sync, library clutter, cloud storage.
**Potential fix direction:** Move the `openHomeID` check into the plan step (skip with reason `.openInEditor`), or
call a `repository.canWrite(homeID:)` before `preserveLocalCopy`.
**Dependencies / considerations:** AUD-013 changes when `openHomeID` is set; fix them together.

---

### [AUD-031] Accounts expire after 60 minutes with no refresh, so "backup" silently stops

**Severity:** P2
**Location:** `render.yaml` (`JWT_ACCESS_TTL_MINUTES: "60"`), `backend/app/auth/tokens.py:56-67` (access token only),
`escape_plan/Auth/AuthSession.swift:101-131` (`restore`: expired token → `discardStoredSession`), `:220-250`
(`signOut` deliberately does not re-arm the gate), `escape_plan/escape_planApp.swift:101-104` (sync 401 →
`session.signOut()`), `escape_plan/Screens/SyncStatusBadge.swift:101` ("Not syncing")
**Category:** reliability / auth UX
**What I found:** There is no refresh token and no silent re-authentication. The gate is (correctly) not re-shown.
**Current behavior:** One hour after signing in, the next launch or sync signs the user out quietly. The only signal is
the small badge changing to "Not syncing". The gate copy "Back up your homes?" implies an ongoing backup.
**Expected behavior:** A long-lived refresh token (or a much longer access TTL for this low-risk data), plus a visible
"Sign in again to keep backing up" prompt when a session ends by expiry rather than by the user.
**Evidence:** Code + config reading.
**Affected systems:** Sync, Settings account section, privacy copy (AUD-050).
**Potential fix direction:** Add `/auth/refresh` with a rotating refresh token stored in the Keychain, or raise the TTL
(e.g. 30 days) and rely on account deletion re-reading the user per request (already true) for revocation.
**Dependencies / considerations:** `test_route_guards.py` allow-list if a new open route is added.
