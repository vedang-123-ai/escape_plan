# 2026-09-15 · S8.1/S8.2 — first contact with a real MongoDB

**Not a playbook session.** An owner-action pass that cleared the single largest
unverified claim in the S8 arc: that the cloud layer had never met a real database.

## What was stood up

Atlas M0 free tier, cluster `escape-plan`, database `escape_plan`. `MONGODB_URI`,
`BACKEND_BEARER_TOKEN`, `JWT_SECRET_KEY` (64 bytes, generated locally) now live in a
gitignored root `.env` created this session. Nothing was set on Render — the deployed
service is unchanged and still returns 503 from `/auth/*`.

## What is now proven, by hand, against a live server

- `/health/db` → `{"database":"ok","db_name":"escape_plan"}` — the S8.1 acceptance
  criterion, met for the first time since the code merged 2026-09-14.
- `ensure_indexes()` really does create `uniq_email` (`email`, `unique=True`) and
  `by_user` (`user_id`). The account-takeover shape is closed in fact, not just in code.
- register → 201, duplicate → 409. So `DuplicateKeyError` matched **by class name**
  does work against the real driver — the risk flagged in `BLOCKERS.md` is not live.
- login → token; `/auth/me` → `UserPublic`, no hash on the wire; wrong password → 401.
- `bungalow.json` (schema 2.1, 1 floor / 4 rooms / 7 openings) round-tripped through
  BSON **semantically identical**. Test user and home deleted; collections back to 0.

## Two things the in-memory fake does not reproduce

1. **BSON truncates datetimes to milliseconds.** A user created at `…744441Z` reads
   back `…744000Z`. Any `assert written == read_back` passes against the fake and fails
   against Mongo — the same shape as the `tz_aware` bug S8.1 already fixed.
2. **`StoredHomeModel` serialises its id as `_id`, not `id`.** `POST /homes` returns
   `{_id, user_id, home, revision, created_at, updated_at}`. S8.4's Swift `Codable`
   must expect `_id`. Better settled now than mid-sync-merge.

Also confirmed in code (the BLOCKERS line had gone stale): all three "S8.2 landmines"
were already handled — the `CloudSyncDisabled` → 503 handler, `UserPublic`, and
`verify_password` returning False on a `None` hash.

## A trap worth not repeating

The first `.env` written this session was **unsourceable**. `MONGODB_URI` ends in
`?retryWrites=true&w=majority&appName=…`, and `set -a; . ./.env` *sources the file as a
shell script* — the bare `&` is a metacharacter, so parsing died at that line and every
variable below it silently never loaded. The symptom was
`BACKEND_BEARER_TOKEN is not set`, which points at the wrong line entirely.
**Quote any `.env` value containing `&`, `?` or `$`.** The shell strips the quotes.

## NOT done

- **Zero `@pytest.mark.mongo` tests exist.** The marker is declared in `pytest.ini` and
  excluded by default, but nothing carries it, so `pytest -m mongo` collects nothing.
  Everything above was verified once, by hand, and the gate does not re-check any of it.
  This is the next action and it is agent-doable now that a server exists.
- `MONGODB_URI` and `JWT_SECRET_KEY` are **not set on Render**. Owner action.
- Concurrency was not tested — duplicate registration was sequential, not a real race.

---

# Part 2 (same day) — the findings fixed, and the suite that re-checks them

The owner set `MONGODB_URI` and `JWT_SECRET_KEY` on Render (replacing the secret
Render generated at blueprint apply — harmless, no account existed yet), then asked
for the findings fixed and the test gap closed.

## Four defects fixed

1. **BSON truncates datetimes to milliseconds.** `_utc_now()` now generates already
   truncated, so a model is a fixed point of the storage round-trip. Proven
   load-bearing rather than assumed: writing an explicitly microsecond-precision
   timestamp still reads back `…744000Z`, and `test_cloud_mongo.py` asserts that, so
   the workaround fails loudly if a future MongoDB makes it unnecessary.
2. **`_id` was leaking onto the wire.** `response_model_by_alias=False` on both
   `/homes` routes. The alias stays on the model for `to_document()`. This also ends
   an inconsistency with `/auth/me`, which always returned a plain `id`.
3. **`created_at` was overwritten on every update.** `upsert` is a full `replace_one`,
   so a re-defaulted timestamp silently replaced the original and the field meant
   nothing beyond `updated_at`. Now carried forward from the existing document.
4. **An unreachable database returned 500, not 503.** Found on the *deployed* service.
   `CloudSyncDisabled` only covers "not configured"; a guarded `ConnectionFailure`
   handler now covers "configured but unreachable". `ConnectionFailure` is the precise
   seam — it excludes `OperationFailure`, so a real query bug still 500s.

Defects 3 and 4 were **not** on the board when this session started; both surfaced
only because real documents were being written and a real deployment was probed.

## The suite

`backend/tests/test_cloud_mongo.py` — 22 tests, green against live Atlas. The pieces
worth knowing about:

- **A throwaway per-run database**, dropped in the fixture's `finally`. The suite runs
  with the same `MONGODB_URI` a developer uses for real work, so pointing it at
  `MONGODB_DB_NAME` would have it deleting real users.
- **A genuinely concurrent registration race** — 10 simultaneous inserts, exactly one
  winner. The pre-existing sequential duplicate test passes even with *no* unique
  index, because the application-level check has time to see the first write.
- Skips (not fails) when `MONGODB_URI` is unset or the server is unreachable.

Default gate is unchanged in character: **526 pass, 34 deselected** (13 live + 21
mongo), still infrastructure-free. Corpus valid, 24 sources.

## The one remaining owner action

**Atlas is not allow-listing Render's egress IPs.** The deployed `/health/db` reports
`unreachable` — the URI parses, but no connection is made; the local machine works only
because its own IP was allow-listed at cluster setup. Fix is Atlas → Network Access →
`0.0.0.0/0` (Render's free tier has no static outbound IPs). Until then the deployed
auth and sync endpoints are unusable and **S8.3/S8.4 cannot be tested against the real
backend**. Tracked in `BLOCKERS.md` §4.

Not done, deliberately: nothing iOS. `FIRST-PRIORITY.md` still stands — the iOS suite
has not been run since 2026-09-09 and four bodies of Swift remain uncompiled.

---

# Part 3 (same day) — the deployed service works

The owner added `0.0.0.0/0` to the Atlas IP access list, which was the last
blocker. Verified against `https://escape-plan-backend.onrender.com`:

```
/health/db                      {"database":"ok","db_name":"escape_plan"}
POST /auth/register             201
POST /auth/register (dupe)      409
POST /auth/login                token issued
GET  /auth/me                   UserPublic, no hash on the wire
POST /auth/login (wrong pw)     401
```

Test account deleted afterwards; `escape_plan` is back to 0 users / 0 homes.

One detail worth recording, because it is a live sighting of the bug this branch
fixes: the deployed `register` returned `created_at` as `…273085Z` while
`/auth/me` read it back as `…273000Z`. That is the BSON millisecond truncation,
observed on the deployed service **because the deployed code predates the fix**.
Re-check it after this branch reaches `main` — the two should match.

**S8.3 (iOS auth UI) and S8.4 (iOS cloud sync) are now unblocked against a real
backend.** The S8 backend arc is done and proven; what remains of S8 is entirely
iOS, which means it sits behind `FIRST-PRIORITY.md` like everything else Swift.
