# 05 · API ↔ Client Integration

Canonical home for AUD-024, AUD-026, AUD-028, AUD-032, AUD-046.

## Endpoint inventory (backend → iOS caller)

| Endpoint | Auth | iOS caller | iOS timeout | Status |
|---|---|---|---|---|
| `GET /health` | open | `APIClient.checkHealth` (launch warm-up, Settings) | default 60 s | ✅ live 200 (51 s cold) |
| `GET /health/db` | open | none | — | live `{"database":"ok"}` |
| `POST /routes` | bearer | `fetchRoutes`/`fetchRoutesCached` (House, Drill) | 90 s | ✅ |
| `POST /score` | bearer | `ReadinessStore` | 90 s | ✅ (AUD-026) |
| `POST /evacuate` | bearer | House ignite, Drill fire origin | 90 s | ✅ |
| `POST /convert` | bearer | scan import, re-check | 90 s | ✅ (AUD-010) |
| `POST /diff_obstructions` | bearer | re-check | 90 s | ✅ live 401 without token |
| `POST /explain` | bearer + AI guard | **none** | — | AUD-022 |
| `POST /analyze` | bearer + AI guard | client exists, **no caller** | 90 s | AUD-022 |
| `POST /build` | bearer + AI guard | `BuildFromPlanView` | 180 s | AUD-024, AUD-023 |
| `POST /chat` | bearer + AI guard | `AssistantScreen` | **60 s** | AUD-032 |
| `POST /auth/register`, `/auth/login` | open | `AuthClient` (form-encoded login, by design) | — | ✅ |
| `GET/DELETE /auth/me` | JWT | `AuthSession.refresh/deleteAccount` | — | ✅ |
| `GET/POST /homes`, `DELETE /homes/{id}` | JWT | `CloudHomesClient` | — | ✅ (delete unreachable, AUD-021) |

---

### [AUD-024] Photo-based `/build` sends the photo's raw bytes labelled `image/png`

**Severity:** P1
**Location:**
- `escape_plan/Screens/BuildFromPlanView.swift:147-155` (`photoItem.loadTransferable(type: Data.self)` → raw asset data)
- `escape_plan/Screens/BuildFromPlanView.swift:196-203` (`apiClient.build(description:, imageData:)` — media type not passed)
- `escape_plan/Networking/APIClient+Build.swift:12-13,42-48` (`image_media_type` defaults to `"image/png"`)
- `backend/app/ai/builder.py:398-404` (forwards `image_media_type` to Anthropic unchecked); `main.py:430-435` (no size or type validation)

**Category:** API integration / functional
**What I found:** `PhotosPicker` data is the asset's original encoding — HEIC for most iPhone camera photos, JPEG for
many others — often several MB. The client labels it PNG; the server passes the label through. The PDF path renders a
real PNG (`importPDF`, `BuildFromPlanView.swift:171-192`), so only the photo path is affected.
**Current behavior (reasoned, not run — no API credits):** Anthropic's Messages API accepts JPEG/PNG/GIF/WebP only and
limits base64 image size (~5 MB); a HEIC payload, a type/label mismatch, or an oversize photo is rejected with a 400,
which `main.anthropic_error` turns into **502 "The AI service rejected the request: …"**, and iOS shows the
"AI unavailable" copy. The user concludes the AI is down.
**Expected behavior:** The client transcodes to JPEG (quality ~0.8) and downsizes (long edge ≤ 1568 px), sending
`image/jpeg`; the server validates the type against an allow-list and the decoded size before calling the model.
**Why this matters:** The photo builder is the accessibility fallback for phones without LiDAR (spec §4 "Keep, own it").
**Evidence:** Code reading of all four locations; the backend has no test with a non-PNG media type
(`grep -rn media_type backend/tests` finds none).
**Affected systems:** `/build`, cost guard (each failed attempt still spends a rate-limit token).
**Potential fix direction:** `UIImage(data:)` → resize → `jpegData(compressionQuality:)`; backend `Literal["image/png",
"image/jpeg", "image/webp", "image/gif"]` for `image_media_type` and a max base64 length.
**Dependencies / considerations:** Verify with a funded key and real camera photos (HEIC, JPEG, Live Photo). Tightening
the backend type is an API contract change for `BuildRequest` (not the HomeModel schema).

---

### [AUD-026] Checklist recurrence is dead on the production path: "twice a year" and "rescan" never go stale, "test monthly" never recurs

**Severity:** P2
**Location:**
- `backend/app/main.py:476-479` (`ScoreRequest.checklist_state: dict[str, bool]`), `:505-513` (`compute_score` called without `now`)
- `backend/app/scoring/checklist.py:60` (`ChecklistState = dict[str, bool | str]`), `:109-135` (`_is_done`: recurring items
  need an ISO timestamp string **and** a clock; with `now=None` any truthy value is "done" forever)
- `backend/app/scoring/checklist.py:210-258` (`practice.drill_recent` and `rescan.home` carry `recurrence_days=183`),
  `:195-199` (`alarm.test_monthly` has no recurrence at all)
- `escape_plan/Persistence/ChecklistStateStore.swift` (`[String: Bool]` only), `escape_plan/DrillMode/DrillScreen.swift:949-952`
  (`markPracticed` stores `true`)

**Category:** API integration / business logic
**What I found:** The backend implements time-based staleness, but the only production caller can express neither the
completion time (the request type forbids strings) nor the current time (never passed).
**Current behavior:** Finishing one drill ticks "Practice the plan (twice a year)" permanently. "Rescan your home"
likewise. "Test every smoke alarm this month" stays done forever after one tick. The client's separate drill reminder
(`PracticeReminderScheduler`) and "Last practiced" line are the only staleness signals, so Home can say "Last practiced:
8 months ago" while the task list says the drill task is done.
**Expected behavior:** iOS stores completion timestamps for recurring items and sends them; `/score` passes
`now=datetime.now(timezone.utc)`; monthly/yearly maintenance items get `recurrence_days`.
**Why this matters:** "Practice twice a year" is the core readiness habit the app is built to drive.
**Evidence:** Code reading of both sides. No backend test exercises recurrence at all (`grep -rn "recurrence\|now=datetime\|fromisoformat" backend/tests`
finds nothing relevant), and iOS does not decode `recurrence_days` (`grep -rn recurrence_days escape_plan` → nothing).
**Affected systems:** `/score`, `ChecklistStateStore`, Drill, Home/Tasks, `docs/preparedness-score-weights.md` (the drill
item is `scoring=False`, so the score itself does not move; the checklist and "done" state do).
**Potential fix direction:** Widen `ScoreRequest.checklist_state` to `dict[str, bool | str]`, pass `now`; iOS stores
`ISO8601` strings for items whose `recurrence_days != nil` (decode that field in `ScoreModels.swift`).
**Dependencies / considerations:** Old stored `true` values must keep meaning "done at an unknown time"; with a clock,
`_is_done` treats bool `True` on a recurring item as **stale** (`checklist.py:134`), so every existing user's drill task
flips to not-done at deploy — decide whether that is desired. Tests: an HTTP-level test through `TestClient`.

---

### [AUD-028] The offline route cache ignores peril, profile and model edits

**Severity:** P2
**Location:** `escape_plan/Networking/APIClient+Cache.swift:37-45` (key = `plan.home_id`), `:77-96` ("matching profile
selection is not tracked"); consumers `HouseScreen.swift:1627-1660`, `DrillScreen.swift:783-821`
**Category:** API integration / safety correctness
**What I found:** One cached plan per home. The last successful `/routes` call wins regardless of peril (fire / tornado /
earthquake) or profile (constraints such as `no_stairs`).
**Current behavior:** Offline, starting a **tornado** drill can load the cached **fire** plan; `DrillSession` then uses
`plan.peril` ("fire"), so the user practises the wrong peril while the picker says tornado. A wheelchair user's drill can
load another person's cached route through stairs. After an edit, a cached plan may reference rooms/openings that no
longer exist (only `home_id` is checked). The banner does say the routes are cached, but not *whose* or *which peril*.
**Expected behavior:** Key the cache by `(home_id, peril, profile_id)` and store the model fingerprint it was computed
from; refuse a cached plan whose fingerprint differs from the current model, or label it clearly.
**Evidence:** Code reading.
**Affected systems:** Drill, House offline mode, onboarding golden path.
**Potential fix direction:** Include peril/profile in the file name; store `HomeFingerprint.of(model)` alongside.
**Dependencies / considerations:** `RoutePlan` carries `peril` — the drill can at least refuse a mismatch today.

---

### [AUD-032] The first chat after the server idles times out, and timeouts are reported as "You're offline"

**Severity:** P2
**Location:** `escape_plan/Networking/APIClient+Chat.swift:68` (`timeoutInterval = 60`),
`escape_plan/Networking/BackendFailure.swift:133-145` (`.timedOut` is in the "offline" set)
**Category:** API integration / reliability / UX
**What I found:** Measured on 2026-09-28: `GET /health` on the deployed free instance took **51.2 s** from cold. A chat
turn is cold start + model time (5–30 s, more with citation retries).
**Current behavior:** The first Assistant message after ~15 minutes of backend idleness likely exceeds 60 s and fails
with "You're offline. Getting the assistant needs a connection" although the phone is online. The launch-time `/health`
ping helps only if the user waits on Home first.
**Expected behavior:** Chat timeout ≥ 120 s (like `/build`'s 180 s), and `.timedOut` classified as "the server is slow
to wake up — try again" rather than offline.
**Evidence:** Live measurement (curl, 51.199 s) + code reading.
**Affected systems:** Assistant; every endpoint's timeout copy (routes/score/convert show the same "offline" text on a
timeout).
**Potential fix direction:** Split `.timedOut` into its own `BackendFailure.Kind` ("server waking up"). Raise the chat
timeout. **Considerations:** Render paid tier removes cold starts; decide before filming.

---

### [AUD-046] Decoding failures and non-network errors are reported as "Couldn't reach the server"

**Severity:** P3
**Location:** `escape_plan/Networking/BackendFailure.swift:133-150`
**Category:** API integration / observability
**What I found:** Any error that is not `APIClientError.unexpectedResponse` and not an offline-class `URLError` becomes
`.server(statusCode: -1)` "Couldn't reach the server. Check your connection, or the server address in Settings." —
including `DecodingError` (a contract drift between app and server) and `URLError.cancelled` (AUD-014).
**Current behavior:** A schema drift after a backend deploy looks like a network problem, and points the user at
Settings.
**Expected behavior:** A distinct "the app and server disagree — update the app" message for `DecodingError`, logged
with the path; cancellations ignored.
**Evidence:** Code reading. **Potential fix direction:** Add cases to the classifier and a test per case in
`BackendFailureTests`.
