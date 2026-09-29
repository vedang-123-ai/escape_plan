# 06 · Authentication & Security

Canonical home for AUD-003 … AUD-012. Other files reference these by ID only.

## Threat model in one paragraph

The iOS app is distributed to judges and families. Every build carries the shared backend bearer token in its bundle.
So anyone with the app (or its IPA) can call every compute and AI endpoint. The per-user JWT layer for cloud homes is
well built; the anonymous layer around it has almost no abuse controls beyond an in-memory AI rate limiter keyed on a
header the caller controls. The backend runs as **one free Render instance** (51 s cold start measured 2026-09-28),
so anything that pins its CPU or event loop takes the whole demo path down.

---

### [AUD-003] The shared bearer token is shipped in the app, so every "token-gated" endpoint is effectively public

**Severity:** P1
**Location:**
- `escape_plan/Networking/APIClient.swift:67-78` (`bundledBearerToken()` reads `BackendConfig.local.json` from `Bundle.main`)
- `escape_plan/CLAUDE.md` / `APIClient.swift:67-70` ("the synchronized project group bundles it automatically")
- `backend/app/main.py:214-233` (`require_token`, `AI_GUARDS`), `backend/app/api_chat.py:33-42`
- `backend/app/rate_limit.py:119-126` (`client_key` trusts the first `X-Forwarded-For` hop)

**Category:** security / cost
**What I found:** The only credential protecting `/routes`, `/score`, `/evacuate`, `/convert`, `/diff_obstructions`,
`/explain`, `/analyze`, `/build` and `/chat` is one static string that is copied into the app bundle as plain JSON.
The AI cost guard keys its per-client bucket on the first `X-Forwarded-For` value, which the caller sets.

**Current behavior:** Extracting the token from any installed build (or IPA) is trivial. With it, a script can: send a
new `X-Forwarded-For` value per request to get a fresh bucket every time, and keep `AI_MAX_CONCURRENT` (4) AI calls in
flight continuously. The semaphore caps *concurrency*, not *spend*: 4 parallel `/build` loops (up to 40 model calls
each, `builder.py:38`) run all day.

**Expected behavior:** A credential that ships in a client is treated as public; spend is bounded by something the
attacker cannot reset (a daily global budget, a per-install identity issued by the server, App Attest / DeviceCheck,
or keying the bucket on Render's appended last `X-Forwarded-For` hop).

**Why this matters:** The Anthropic account is already out of credits once (BLOCKERS §1). A leaked token drains a
top-up with no alert, and rotating the token breaks every installed build (see AUD-009).

**Evidence:** Code reading of the four locations above. BLOCKERS "Audit remediation Part A" already records the XFF
weakness as an accepted risk; this finding adds that the token itself is not secret, which changes that risk's size.
Not exploited against the live service.

**Affected systems:** Anthropic spend; Render CPU; every endpoint except `/health*` and `/auth/*`.
**Likely root cause:** Shared-secret design chosen for a single-team demo, carried into a distributed app.
**Potential fix direction:** Add a global daily AI budget (count + tokens) enforced server-side and surfaced in
`/health`; key the limiter on the last XFF hop (Render appends the real client IP there); optionally mint per-install
tokens from an unauthenticated `/install` endpoint protected by App Attest. Do not rely on the bearer token for cost
control.
**Dependencies / considerations:** Changing the token model touches `APIClient`, Settings, `demo-preflight.py`,
`render.yaml`. Keep `/health` open for Render's probe. Coordinate with AUD-006 (the unguarded `/score` AI path).

---

### [AUD-004] Unbounded home geometry lets one request pin the backend CPU (measured)

**Severity:** P1
**Location:**
- `backend/app/models.py` — no bounds on coordinate magnitude, polygon vertex count, rooms/floors/objects counts
- `backend/app/routing/nav_grid.py:28` (`CELL_M = 0.1`), `:154-161` (per-cell point-in-polygon loop over the room bbox)
- `backend/app/main.py:500-503` (`/score` computes three full route plans per call)
- No request body size limit anywhere (FastAPI/uvicorn defaults)

**Category:** security (DoS) / performance
**What I found:** The navigation grid is built per room at 10 cm resolution over the room's bounding box, in pure
Python. Cost grows with floor area. Nothing limits area.

**Current behavior (measured 2026-09-28, local M-series Mac, `compute_route_plan(..., peril="fire")`):**
`twostory.json` scaled ×1 → 0.07 s; ×4 → 1.15 s; ×10 → 7.24 s. Growth is ~quadratic in the scale factor, so a single
valid 1 km × 1 km room (10⁸ cells) would run for hours and exhaust the free instance's memory. `/score` does this three
times. Render's free CPU is far slower than the test machine.

**Expected behavior:** Validation rejects homes outside plausible residential bounds (for example: coordinates within
±200 m, room area ≤ 2,000 m², ≤ 200 rooms, ≤ 500 objects, ≤ 64 vertices per polygon), and the server enforces a body
size limit (a few MB) before parsing.

**Why this matters:** With AUD-003, any holder of the app can stall the single backend instance, including during
judging or filming. Synchronous endpoints run in the threadpool but all share the GIL.

**Evidence:** Script in the session scratchpad (`bigroom.py`) scaling every fixture coordinate; timings above.
**Affected systems:** `/routes`, `/score`, `/evacuate`, `/diff_obstructions`, `/analyze` (agent calls the engine), `/homes` storage.
**Likely root cause:** Validators check topology (CCW, self-intersection, references) but not magnitude.
**Potential fix direction:** Add bounds as pydantic `Field` constraints and model validators, mirror them in the JSON
Schema (`maxItems`, `maximum`) and in Swift `EditorValidation` so the editor cannot create a home the server rejects.
Add a body-size middleware.
**Dependencies / considerations:** **This is a schema change** (`schema_version` bump + `schema-contract-guardian`
run) if expressed in the JSON Schema; a server-only limit avoids the bump but then the three layers disagree. Check the
real maximum extents of fixtures and scans first (`schema/fixtures/scans/`).

---

### [AUD-005] Registration and login are unthrottled and hash on the event loop

**Severity:** P1
**Location:**
- `backend/app/api_auth.py:123-157` (`async def register`, `async def login`)
- `backend/app/auth/passwords.py:23-48` (argon2-cffi defaults: 64 MiB, t=3, p=4; synchronous)
- `backend/app/api_auth.py:54` (`_DUMMY_HASH` — timing equalisation, good, but doubles as a cost amplifier)

**Category:** security (brute force, DoS)
**What I found:** Both routes are `async def` and call the synchronous Argon2 hasher directly, so each call blocks the
single asyncio event loop for the full hash. There is no rate limit, lockout, or CAPTCHA on either route, and
registration needs no email verification.

**Current behavior:** Measured 36.5 ms per `verify_password` on the audit Mac; a free Render instance is much slower.
While a hash runs, the loop cannot accept or dispatch any other request (the sync compute routes are dispatched from
the loop too), so a modest stream of login attempts starves `/health` and the demo path. Credential stuffing against
real accounts is unlimited. Anyone can create unlimited accounts for arbitrary email addresses.

**Expected behavior:** Hashing runs in a worker (`await anyio.to_thread.run_sync(...)` or `run_in_threadpool`),
`/auth/*` has its own per-IP and per-email throttle (the existing `TokenBucketLimiter` can be reused), and failed-login
counts back off per account.

**Why this matters:** The auth routes are the only unauthenticated POST surface; they take the whole service down,
not just accounts.
**Evidence:** Code reading plus the timing measurement (session command, 5 iterations).
**Affected systems:** Entire backend availability; account security.
**Likely root cause:** Argon2 was chosen for strength (correctly) without accounting for the async context.
**Potential fix direction:** Thread-offload hash/verify; add `auth_rate_limit` dependency; consider lowering Argon2
parallelism/memory to fit a 512 MB instance (OWASP's `m=19456, t=2, p=1` is acceptable).
**Dependencies / considerations:** `tests/test_route_guards.py` allow-list; keep responses byte-identical for
unknown/known users (enumeration). `needs_rehash` (AUD-011) should be wired at the same time if parameters change.

---

### [AUD-006] `/score?include_recommendations=true` spends AI credit outside the cost guard (known)

**Severity:** P2
**Location:** `backend/app/main.py:480-523`
**Category:** security / cost
**What I found / current behavior:** `/score` is guarded only by `require_token`; with `include_recommendations` it calls
`recommendation_items` → Anthropic. The iOS client never sets the flag, so it is reachable only with the token —
which AUD-003 shows is public.
**Expected behavior:** Either apply `ai_rate_limit` + `ai_concurrency` when the flag is set, or remove the flag.
**Evidence:** Already open in BLOCKERS "Audit remediation Part A"; re-confirmed by reading `main.py:514-522`.
**Affected systems:** Anthropic spend. **Root cause:** Guard added per-route, not per-call-site.
**Potential fix direction:** Move the guard into `recommend.py`'s caller, or split a `/score/recommendations` route
under `AI_GUARDS`. **Considerations:** `test_route_guards.py`.

---

### [AUD-007] No per-user storage quota on `/homes`

**Severity:** P2
**Location:** `backend/app/api_auth.py:224-263` (`sync_home`), `backend/app/cloud_repo.py:132-149`
**Category:** security (resource abuse) / database
**What I found:** Any registered account (registration is open, AUD-005) can POST unlimited homes of unlimited size
(AUD-004). Mongo's 16 MB document cap is the only ceiling; the free Atlas tier is 512 MB total.
**Current behavior:** One script fills the cluster; every user's sync then fails with a driver error (500).
**Expected behavior:** A per-user home count cap (e.g. 20) and a per-document size cap, returning 413/422.
**Evidence:** Code reading; no quota logic exists (`grep -in "quota\|limit" backend/app/api_auth.py backend/app/cloud_repo.py`
matches only a comment about password length).
**Affected systems:** Cloud sync for all users. **Root cause:** Feature built for a demo scale.
**Potential fix direction:** Count on insert (`count_documents({"user_id":…})`) before `upsert` of a new id; cap body size.
**Considerations:** The iOS sync must surface the new error as a per-home failure, not retry forever.

---

### [AUD-008] The app's whole Documents directory is exposed in the Files app in release builds

**Severity:** P2
**Location:**
- `escape_plan.xcodeproj/project.pbxproj:401,405,437,441` (`INFOPLIST_KEY_UIFileSharingEnabled = YES`,
  `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES` in both Debug and Release)
- `escape_plan/Capture/README.md:56` (the reason: pulling raw scans off the device for converter fixtures)
- Contents exposed: `Documents/Homes/*.homeplan.json` (floor plans, household member names, optional street address),
  `Documents/sync-state.json` (account ownership claims), `Documents/Assistant/conversation.json`,
  `Documents/DrillLog/`, `Documents/RouteCache/`, `Documents/Scans/*/` (raw RoomPlan JSON + USDZ, never deleted)

**Category:** security / privacy / data integrity
**What I found:** A development affordance (copying scans off the phone) ships in the release configuration.
**Current behavior:** Any user (or anyone with the unlocked phone, or Finder over USB) can browse, copy, edit or delete
internal state. Deleting a home file here bypasses the sync tombstone, so sync re-downloads it; editing
`sync-state.json` can re-assign ownership claims; a hand-edited home file that fails to decode is listed but cannot be
opened. Raw scans accumulate forever (no cleanup anywhere in `Capture/`), including every partial re-check.
**Expected behavior:** Release builds keep internal state out of the user-visible Documents folder (Application Support),
and scans are deleted after successful conversion unless a debug setting keeps them.
**Why this matters:** The app promises privacy (S11.7 disclosure) about what leaves the device; this exposes more on the
device than the app itself shows.
**Evidence:** `grep -n INFOPLIST_KEY_UIFileSharingEnabled escape_plan.xcodeproj/project.pbxproj` shows both
configurations; `grep -rn removeItem escape_plan/Capture` returns nothing.
**Affected systems:** Persistence, Sync, Capture, privacy copy (`AccountPrivacy.swift`).
**Likely root cause:** S1.4 debugging setting never scoped to Debug.
**Potential fix direction:** Set both keys only in Debug; move stores to Application Support (with a one-time
migration of existing files); add scan cleanup after `/convert` succeeds.
**Dependencies / considerations:** A storage move needs a migration or existing users lose their homes. `demo-preflight`
and the fixture-capture workflow depend on pulling scans; keep a Debug path for it.

---

### [AUD-009] Bearer-token and server-address settings: rotation never reaches existing installs; invalid addresses are accepted

**Severity:** P2
**Location:**
- `escape_plan/Networking/APIClient.swift:42-44,62-64` (stored token in `UserDefaults` takes precedence over the bundled one forever)
- `escape_plan/Screens/SettingsScreen.swift:67-103` (the "Advanced" section is in release builds), `:499-509` (`save()`)

**Category:** security / reliability / UX
**What I found:** Once `apiClient.bearerToken` is assigned (any "Save changes" tap, even one that only edits the URL,
persists the current token), `UserDefaults` wins over the bundled value on every later launch. `save()` accepts any
string `URL(string:)` parses, including `api.example.com` — the field's own placeholder — which has no scheme and
breaks every request. The "Saved" confirmation shows regardless.
**Current behavior:** When the owner fixes the known token mismatch (BLOCKERS §1) by rotating Render's token and
shipping a new build, every tester who ever tapped Save keeps the old token and gets 401 on every request, with the
message "check it in Settings". A user who types a bare host breaks the app until they find the field again.
**Expected behavior:** Only persist the token when the user actually changed it; offer "Reset to default"; validate
that the URL has `https` (or `http://localhost` in Debug) and a host before saving; hide "Advanced" in Release or behind
a gesture.
**Evidence:** Code reading of the two locations.
**Affected systems:** Every backend call; `AuthSession.baseURL`; `SyncManager.baseURL`.
**Potential fix direction:** Store an override flag separately from the value; validate with `URLComponents`.
**Considerations:** `SignedOutPathUITests` passes `-APIClient.baseURL`/`-APIClient.bearerToken` launch arguments that
rely on the current precedence.

---

### [AUD-010] `/convert` turns every exception into a 422 carrying the exception text

**Severity:** P3
**Location:** `backend/app/main.py:371-385`
**Category:** security (information disclosure) / backend correctness
**What I found:** `except Exception as exc: raise HTTPException(422, detail=f"scan could not be converted: {exc}")`.
**Current behavior:** A genuine server bug (KeyError, TypeError, pydantic internal error) is reported to the client as
the client's fault, with Python internals in the message, and is not logged as an error.
**Expected behavior:** Catch the converter's own domain errors (and `ValidationError`) as 422 with a curated message;
let anything else become a logged 500.
**Evidence:** Code reading. **Affected:** iOS `BackendFailure` shows the raw `detail` for 422 (`BackendFailure.swift:162-172`).
**Potential fix direction:** Introduce `ConversionError` in `app/convert`, raise it for malformed input.

---

### [AUD-011] Argon2 parameter upgrades are never applied (`needs_rehash` is dead)

**Severity:** P3
**Location:** `backend/app/auth/passwords.py:51-60`; no caller (`grep -rn needs_rehash backend/app` → definition only)
**Category:** security hygiene
**What I found / current behavior:** The helper exists and its docstring says callers rehash on login; `login()` does not.
**Expected behavior:** After a successful `verify_password`, `if needs_rehash(h): update hash`.
**Why this matters:** If AUD-005's fix lowers or raises Argon2 cost, existing hashes never move.
**Evidence:** grep. **Potential fix direction:** Add a `UserRepository.update_password_hash`.

---

### [AUD-012] Untrusted `home_id` is used verbatim as a filename, and list/load disagree about identity

**Severity:** P3
**Location:** `escape_plan/Persistence/HomeDocumentStore.swift:222-224` (`url(for:)`), `:74-100` (`list()` uses the id
inside the document, not the filename), `escape_plan/Persistence/HomeDocumentSyncRepository.swift:97-121` (pulled homes
are saved by their embedded `home_id`)
**Category:** security (path handling) / data integrity
**What I found:** A `home_id` arriving from the server (sync pull) or a hand-edited file (AUD-008) is appended to the
Homes directory unsanitised; `../` segments would escape it. `list()` reports the embedded id, `load()` looks up the
filename, so a file whose name and embedded id differ is listed but cannot be opened.
**Current behavior:** Exploitable only with control of the user's own cloud account or device files — a self-attack —
hence P3. The mismatch case is reachable through the Files app today.
**Expected behavior:** Validate ids (UUID-ish `[A-Za-z0-9_-]{1,64}`) on every write path; have `list()` skip or repair
name/id mismatches.
**Evidence:** Code reading.
**Potential fix direction:** One `HomeID.isValid` check used by `save`, `writePulledHome`, `importDocument`.
**Considerations:** Fixture ids and the `TEST-DEMO-HOME-1234` launch seed must still pass the rule.

---

### [AUD-050] The privacy disclosure says signed-out use "uploads nothing about your home" and that no photo is ever sent — both are false

**Severity:** P1
**Location:**
- `escape_plan/Auth/AccountPrivacy.swift:83-85` (`signedOutSummary`: "Signed out, Escape Plan uploads nothing about your
  home. Everything — building, editing, routes, the drill and exporting — works on this iPhone with no account.")
- `escape_plan/Auth/AccountPrivacy.swift:70-76` (`notUploaded`: "Camera images. … no photo or video frame is ever sent
  or stored.")
- Shown on: `AuthGateView` (`AccountPrivacyDisclosure`, `Screens/Auth/AuthFormComponents.swift:165-210`) and Settings
  (`SettingsScreen.swift:346-351`)
- What actually leaves the phone signed out: the **entire HomeModel** — room names, household member names, their
  vulnerability tags (child, elderly, mobility-limited, hearing/vision-impaired), which room each sleeps in, and the
  optional street address — on every `/routes`, `/score`, `/evacuate`, `/chat` request (`main.py:236-249,466-485`,
  `api_chat.py:45-51`); the chosen photo or rendered PDF page on `/build` (`BuildFromPlanView.swift:196-203`); and, from
  the server, a floor-plan summary (`ai/chat/summary.py`) and the photo/description to **Anthropic**, a third party

**Category:** security / privacy / truthfulness
**What I found:** The S11.7 disclosure was written about *what an account stores*, but its headline sentence is phrased
about *uploading*, and routes are computed on the server — they cannot work "on this iPhone with no account" offline
except from the last-good cache. The "no photo is ever sent" line is contradicted by Import Plan.
**Current behavior:** A user (or judge) reads that nothing is uploaded while signed out; the app transmits the full home,
including sensitive household data, to the team's server on the first Home-tab load, and some of it to Anthropic.
**Expected behavior:** Accurate copy: e.g. "Signed out, your homes are saved only on this iPhone. To compute routes and
your score, the app sends the floor plan to our server, which does not keep it. The assistant and the plan importer
send what you type or pick to Anthropic's AI service." Plus the App Store privacy label to match.
**Why this matters:** `AccountPrivacy.swift`'s own doc comment says "a judge reading the submission can verify every line
below against the code". This one fails that test, and App Store review checks privacy labels against behaviour.
**Evidence:** Code reading of the strings and of every request body; the server does not persist these requests (no
Mongo writes outside `/homes`, logs contain no bodies — checked `main.py`), so "stores nothing" would be true where
"uploads nothing" is not.
**Affected systems:** Auth gate, Settings, App Store submission metadata, pitch.
**Potential fix direction:** Rewrite the two strings; add a test that pins the copy's key phrases (the file already has
tests pinning `uploadedHomeKeys` against a real encode — extend the same idea to "sent for computation").
**Dependencies / considerations:** `escape_planTests/EditorCore/AccountPrivacyTests.swift:74-75` asserts the phrase
"uploads nothing", and `SignedOutProofTests.swift` proves only the *sync* half (no token → no `/homes` request) — the
tests pin the misleading wording rather than the behaviour. Update both with the copy.

---

## What is solid (verified)

- JWT: HS256 pinned on decode, `exp/iat/sub` required, secret ≥ 32 bytes enforced at startup (`config.py:76-91`),
  user re-read per request so deleted accounts lose access immediately (`api_auth.py:98-117`).
- Ownership: every home query filters on `user_id`; unowned and missing ids are indistinguishable (404).
- Login does a dummy verify for unknown emails (no timing oracle); 401 bodies are byte-identical.
- `Settings` redacts secrets from `repr`; pymongo command logging is pinned at INFO so home documents never hit logs.
- No API keys in tracked files; the AI key is server-only; the Keychain item is `AfterFirstUnlock`, non-synchronizable,
  and purged on first launch after reinstall.
- `/diff_obstructions` requires the token on the deployed service (live check, 401, 2026-09-28).

## Accepted / previously rejected (do not re-open without new evidence)

See `docs/decisions.md` 2026-09-25 "audit (rejected)" rows: password re-entry on `DELETE /auth/me`, splitting
401/403, compound Mongo index, JSON login body. This audit found no new evidence against those rulings.
