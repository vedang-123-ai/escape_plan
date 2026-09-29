# 04 · Database & Data Model

Canonical home for AUD-016, AUD-018. There are two stores: **on-device JSON files** (primary, local-first) and an
**optional MongoDB Atlas** cluster for accounts and cloud copies. There is no SQL database, no ORM and no migration
framework; schema evolution is handled by `schema_version` migrators on both sides.

## Stores and schemas

### MongoDB (`MONGODB_DB_NAME=escape_plan`)

| Collection | Document | Indexes | Written by |
|---|---|---|---|
| `users` | `User {_id: uuid4 str, email (normalised, ≤254), hashed_password (argon2id), created_at, updated_at}` | `uniq_email` (unique), `_id` | `/auth/register`, deleted by `DELETE /auth/me` |
| `homes` | `StoredHomeModel {_id: uuid4 str, user_id, home: HomeModel, revision ≥1, created_at, updated_at}` | `by_user` (`user_id`), `_id` | `POST /homes`, `DELETE /homes/{id}`, `DELETE /auth/me` |

- Relationships: `homes.user_id → users._id` by convention only (Mongo has no FK). Account deletion removes homes first,
  then the user; both steps are idempotent (`api_auth.py:165-184`), so a partial failure is retryable. Good.
- `updated_at` is never updated on an update: `sync_home` builds a fresh `StoredHomeModel` whose `updated_at` defaults to
  now — so it *is* refreshed, by construction; `created_at` is carried forward explicitly. Correct.
- Stored `home` documents migrate on read (`HomeModel._migrate`, `models.py:410-414`), so a schema bump does not break
  `GET /homes` for old documents. A document **newer** than the server (a future client) raises inside validation and
  would 500 the whole `GET /homes` for that user — unlikely while one team controls both sides.
- The deployed cluster was reachable on 2026-09-28 (`/health/db` → `{"database":"ok","db_name":"escape_plan"}`).
- The three `-m mongo` tests have never run against Atlas (BLOCKERS §1, owner-only).

### On-device (see `01_ARCHITECTURE.md` §4 for the full table)

- `Documents/Homes/<home_id>.homeplan.json` — exactly the HomeModel JSON; atomic writes; migrated and rewritten on load.
- `UserDefaults["checklistState.<home_id>"]` — `[String: Bool]`; orphaned on home delete (documented, harmless).
- `Documents/sync-state.json` — sync records (server id, synced revision, synced fingerprint), tombstones with owner,
  ownership claims.
- `Documents/DrillLog`, `Documents/Assistant/conversation.json` (single slot, AUD-033), `Documents/RouteCache`
  (AUD-028), `Documents/Scans` (never cleaned, AUD-008), Caches: `ScoreCache`, responder snapshots.

## Integrity checks done in this audit

- JSON Schema ↔ pydantic ↔ Swift version agreement: ✅ (2.1 everywhere; enum breadth difference is a documented ruling).
- Bundled fixtures identical to `schema/fixtures/`: ✅ (`cmp` on all 7 files).
- Referential validation (stairs/profile/opening → rooms/floors, global id uniqueness): ✅ in pydantic
  (`models.py:416-471`) and mirrored client-side in `EditorValidation` (S6 contract tests).
- Magnitude/size constraints: ❌ none (AUD-004).

---

### [AUD-016] `POST /homes` has no optimistic-concurrency check, so concurrent updates silently overwrite each other

**Severity:** P2
**Location:** `backend/app/api_auth.py:224-263` (read `existing`, compute `revision = existing.revision + 1`, then
`upsert`), `backend/app/cloud_repo.py:132-149` (`replace_one({_id, user_id}, doc, upsert=True)` — no revision in the filter)
**Category:** database / concurrency
**What I found:** The server computes the next revision from a read, then replaces unconditionally. The request carries
no "based on revision N".
**Current behavior:** Two devices that both last synced revision 5 and both push an edit: both handlers read 5, both
write revision 6. The second write wins; the first device records "synced at revision 6" with its own fingerprint, so
it will never pull the other device's version (`remote.revision > record.syncedRevision` is false) until someone edits
again. The reconciler's whole conflict model (01 §4, `SyncReconciler.swift` header) assumes the server revision is
monotonic *per write*, which this breaks under concurrency.
**Expected behavior:** The client sends `base_revision`; the server filters `{_id, user_id, revision: base_revision}` and
answers 409 on a miss; the client re-plans.
**Why this matters:** Silent cross-device data loss in the optional sync feature.
**Evidence:** Code reading. Not reproduced (needs two clients and a live Mongo, or the fake in `tests/fake_mongo.py`).
**Affected systems:** `SyncManager`, `SyncReconciler`, `CloudHomesClient`.
**Potential fix direction:** Add `base_revision: int | None` to `HomeSyncRequest` (API change, not a schema change);
compare-and-set in `upsert`; map 409 to a re-sync in `SyncManager`.
**Dependencies / considerations:** Old clients that omit `base_revision` must keep working (treat None as "force").

---

### [AUD-018] Per-home state that is not in the HomeModel never leaves the device

**Severity:** P3
**Location:** `escape_plan/Persistence/ChecklistStateStore.swift:1-9` (documented trade-off), `DrillLogStore.swift`,
`ConversationStore.swift`; sync uploads only `HomeModel` (`Sync/CloudHomesClient.swift`)
**Category:** database / data model / cross-device consistency
**What I found:** Checklist done-state (which drives the score), the drill log (which drives "last practiced" and the
practice reminder) and the conversation are device-local. Sync copies only the home document.
**Current behavior:** The "same" synced home shows a different readiness score and different "done" tasks on each
device; duplicating a home (`HomeDocumentStore.duplicate`) or a sync conflict copy starts with an empty checklist.
Export/import likewise drops done-state (documented).
**Expected behavior:** Either accept and say so in the sync disclosure ("your checklist progress stays on this
device"), or add the state to the synced payload (as a sidecar field on `StoredHomeModel`, not the HomeModel schema).
**Evidence:** Code reading; the trade-off is recorded in `ChecklistStateStore.swift` and `docs/decisions.md`, but the
account privacy/sync copy (`Auth/AccountPrivacy.swift`) does not tell users their progress won't follow them.
**Potential fix direction:** Product decision; the cheapest honest fix is a sentence in the sync disclosure.
