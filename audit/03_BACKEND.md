# 03 · Backend

Canonical home for AUD-035, AUD-042, AUD-043. Security findings for the backend are in `06_AUTH_SECURITY.md`
(AUD-003 … AUD-012); scoring-contract issues in `05_API_INTEGRATION.md` (AUD-026).

## Overview (verified 2026-09-28)

- `backend/.venv/bin/python -m pytest backend/tests/ -m "not live"` → **893 passed, 1 skipped, 29 deselected, 4 warnings**
  (29.7 s, CPython **3.13.5** locally; Render and CI use 3.12 — AUD-041).
- `python3 backend/corpus/validate.py` → **valid: 36 sources, 13 corpus files, 2 threshold files, 44 prevention tips,
  1 orphan exception**.
- Warnings: 3 × `PytestRemovedIn10Warning` (class-scoped fixture defined as an instance method in
  `tests/test_convert.py` — `TestBungalow`, `TestMessy`, `TestSharedDoorGeometric`), 1 × starlette `_PortalFactoryType`
  deprecation. Harmless today; the pytest one becomes an error in pytest 10.

### Layering

| Layer | Files | Purity | Assessment |
|---|---|---|---|
| HTTP | `main.py`, `api_chat.py`, `api_auth.py` | thin | Mostly thin. `/score` orchestrates three plans + optional AI; `/convert` catch-all (AUD-010) |
| Domain models | `models.py` (471), `cloud_models.py` | pure | Strong topology validation; no magnitude bounds (AUD-004) |
| Routing | `routing/*` | pure, deterministic | Solid; Python grid is the hot path (AUD-004, 08) |
| Scoring | `scoring/checklist.py` (1,225), `score.py` | pure except `recommend.py` | Recurrence unreachable via HTTP (AUD-026) |
| AI | `ai/grounded.py`, `agent.py`, `builder.py`, `chat/` | I/O | No client timeouts; unbounded inputs (AUD-035) |
| Storage | `database.py`, `cloud_repo.py` | I/O | Ownership in filters (good); no revision precondition (AUD-016) |
| Config | `config.py` | env | Fails closed on missing bearer, short JWT secret, unsupported model — good |

### Error handling map

| Failure | Handler | Client sees |
|---|---|---|
| `anthropic.APIError` retryable (429/5xx/connection) | `main.anthropic_error` | 503 + detail |
| `anthropic.APIError` other (credit, bad key, 400) | same | 502 + detail |
| Domain `GroundingError`/`AgentError`/`BuilderError` | per route | 502 |
| `CloudSyncDisabled` | `cloud_sync_disabled` | 503 |
| pymongo `ConnectionFailure` | `cloud_sync_unreachable` | 503 |
| pydantic validation | FastAPI default | 422 with field errors |
| Anything in `/convert` | `except Exception` | 422 with the Python message (AUD-010) |
| Rate limit | `rate_limit._too_many` | 429 + `Retry-After` |

---

### [AUD-035] AI calls have no timeout and no input caps; server work outlives the client

**Severity:** P2
**Location:**
- `backend/app/ai/grounded.py:225-229`, `agent.py:565-569`, `builder.py:372-376`, `chat/service.py:153-157` — each
  builds `anthropic.Anthropic(api_key=…)` per request with SDK defaults (**600 s timeout, 2 retries**)
- `backend/app/ai/builder.py:37-38` (`MAX_TOKENS = 4096`, `MAX_ITERATIONS = 40`), `:398-404` (image included in the
  first user turn, so re-sent on every iteration as history grows)
- `backend/app/api_chat.py:45-51` (`messages: list[ChatMessage]` — no max length), `chat/service.py:85-89`
  (`content: str` — no max length)
- `backend/app/main.py:430-435` (`BuildRequest.description` / `image_b64` unbounded)
- iOS timeouts: `/build` 180 s, `/chat` 60 s, `/analyze` 90 s

**Category:** backend / cost / reliability
**What I found:** The endpoints are synchronous (`def`), so each runs in a threadpool thread and holds one of the
`AI_MAX_CONCURRENT` (4) semaphore slots until it returns. Nothing stops a long agent/builder loop when the phone gives up.
**Current behavior:** A `/build` that takes longer than 180 s keeps iterating (up to 40 model calls) after iOS shows a
timeout; the user taps Retry and a second loop starts. Two such users fill half the global AI capacity. A long chat
history or a large description is sent in full every turn.
**Expected behavior:** `anthropic.Anthropic(timeout=…, max_retries=1)` shared per process; an overall wall-clock budget
per request (e.g. builder 150 s, agent 60 s — the documented "<60 s" acceptance); caps on `messages` (count and total
characters), `description` length and `image_b64` size.
**Why this matters:** Cost and availability, on an account that has already run dry once.
**Evidence:** Code reading; `grep -n "timeout\|max_retries" backend/app/ai` finds none.
**Affected systems:** `/build`, `/analyze`, `/chat`, `/explain`, `/score?include_recommendations`.
**Potential fix direction:** One module-level client factory with `timeout` and `max_retries`; a deadline passed into
the loops (they already have iteration caps — add a time check); pydantic `max_length` on request fields.
**Dependencies / considerations:** Tests inject stub clients — keep the injection seam. Coordinate timeouts with iOS so
the server gives up slightly before the client does.

---

### [AUD-042] If Mongo index creation fails at startup it is never retried

**Severity:** P3
**Location:** `backend/app/database.py:130-144`, `backend/app/cloud_repo.py:65-77`
**Category:** backend / database reliability
**What I found:** `ensure_indexes` runs once in `connect()`; failure is logged ("registration is NOT safe against
concurrent duplicate emails until this succeeds") and never retried.
**Current behavior:** On a boot where Atlas is briefly unreachable, the process serves registrations with no unique
index guarantee until the next restart. On the existing cluster the index almost certainly already exists (created on
earlier boots), which is why this is P3.
**Expected behavior:** Retry lazily on first cloud request, or make `/health/db` report "indexes missing".
**Evidence:** Code reading. **Potential fix direction:** a `_indexes_ready` flag checked in `_users()`.

---

### [AUD-043] `require_token` is duplicated between `main.py` and `api_chat.py`

**Severity:** P3
**Location:** `backend/app/main.py:214-223`, `backend/app/api_chat.py:27-42`
**Category:** backend / maintainability
**What I found:** Two copies "to avoid a circular import". A future change (e.g. AUD-003's per-install token) must be
made twice; `test_route_guards.py` would catch a missing guard but not a divergent one.
**Potential fix direction:** Move `require_token` and `AI_GUARDS` into a small `app/deps.py` imported by both.

---

## Other backend observations (not separately indexed)

- `/score` accepts `profile` but uses it only for AI recommendations; routes are scored household-wide with optional
  `constraints` (documented as deliberate: "the score is household-level by design", BLOCKERS deferred list).
- `app/routing/diff.py` aligns a partial scan to the stored room by centroid + four right-angle rotations
  ("Simplified alignment") — adequate for RoomPlan's axis-aligned output; untested against real partial scans
  (device-gated, see BLOCKERS §2).
- `pytest` and `jsonschema` are in `requirements.txt` / `requirements.lock`, so they are installed in production (AUD-041).
- `health()` reports `version="1.0"` hard-coded — it cannot tell you which commit is deployed; a `GIT_SHA` env var in
  the response would make post-deploy smoke checks meaningful (see 10_DEPLOYMENT).
