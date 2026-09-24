"""S8.1/S8.2 against a REAL MongoDB. Marked `mongo`; deselected by default.

    backend/.venv/bin/python -m pytest backend/tests/ -m mongo

Everything else in the cloud-layer suite runs against `tests/fake_mongo.py`,
which is fast, hermetic, and — this is the point of this file — **not Mongo**.
The fake models `_id` uniqueness and enforces unique indexes, which is how the
cross-owner write bug was found, but it cannot prove anything about the driver
or the wire format. Three classes of defect live in that gap:

  * **BSON is not JSON.** It stores datetimes at millisecond resolution, so a
    microsecond-precision timestamp does not survive a write. A test asserting
    `written == read_back` passes against the fake and fails here.
  * **The driver's exceptions are its own.** `cloud_repo` identifies
    `DuplicateKeyError` **by class name**, to keep pymongo out of the import
    path. Only a real driver proves that string still matches.
  * **Indexes are the server's job.** `ensure_indexes()` can run clean and still
    create nothing if the server disagrees — and the unique email index is the
    account-takeover fix, not an optimisation.

Every test here runs against a **throwaway database**, named per-run and dropped
afterwards, so this suite can never touch real data even when `MONGODB_URI`
points at the production cluster. It skips cleanly when `MONGODB_URI` is unset.
"""

from __future__ import annotations

import asyncio
import os
import uuid
from datetime import datetime, timezone

import pytest

from app.cloud_models import StoredHomeModel, User
from app.cloud_repo import (
    HOMES,
    USERS,
    EmailAlreadyRegistered,
    HomeNotOwned,
    HomeRepository,
    UserRepository,
    ensure_indexes,
)
from app.models import HomeModel

pytestmark = [pytest.mark.mongo, pytest.mark.anyio]

MONGODB_URI = os.environ.get("MONGODB_URI")

pytest.importorskip("pymongo", reason="the mongo suite needs the real driver")

if not MONGODB_URI:
    pytest.skip(
        "set MONGODB_URI to run the mongo suite (Atlas free tier or a local mongod)",
        allow_module_level=True,
    )


@pytest.fixture
async def mongo_db():
    """A throwaway database, dropped on the way out.

    Deliberately NOT `MONGODB_DB_NAME`. Pointing this suite at the real database
    would have it deleting users; a per-run name means the worst case of a
    misconfigured URI is an empty scratch database on someone's cluster.
    """
    from pymongo import AsyncMongoClient

    name = f"escape_plan_test_{uuid.uuid4().hex[:12]}"
    client = AsyncMongoClient(
        MONGODB_URI, serverSelectionTimeoutMS=10_000, tz_aware=True
    )
    try:
        await client.admin.command("ping")
    except Exception as exc:  # pragma: no cover - environment, not logic
        await client.close()
        pytest.skip(f"no reachable MongoDB at MONGODB_URI: {type(exc).__name__}: {exc}")

    db = client[name]
    try:
        await ensure_indexes(db)
        yield db
    finally:
        await client.drop_database(name)
        await client.close()


@pytest.fixture
def users(mongo_db) -> UserRepository:
    return UserRepository(mongo_db)


@pytest.fixture
def homes(mongo_db) -> HomeRepository:
    return HomeRepository(mongo_db)


class TestIndexes:
    """`ensure_indexes()` is called from `Database.connect()` and its failure is
    non-fatal by design — it needs a reachable server. That makes "did it
    actually create anything?" a question only a real server can answer."""

    async def test_the_unique_email_index_exists(self, mongo_db):
        info = await mongo_db[USERS].index_information()
        assert "uniq_email" in info, (
            "without this index two concurrent registrations for one address "
            "both insert — the account-takeover shape S8.2 exists to prevent"
        )
        assert info["uniq_email"]["key"] == [("email", 1)]
        assert info["uniq_email"].get("unique") is True

    async def test_the_home_lookup_index_exists(self, mongo_db):
        info = await mongo_db[HOMES].index_information()
        assert "by_user" in info
        assert info["by_user"]["key"] == [("user_id", 1)]

    async def test_ensure_indexes_is_idempotent(self, mongo_db):
        """It runs on every connect, so a second call must not raise."""
        await ensure_indexes(mongo_db)
        await ensure_indexes(mongo_db)
        assert "uniq_email" in await mongo_db[USERS].index_information()


class TestDuplicateEmail:
    async def test_a_duplicate_registration_raises_the_domain_error(self, users):
        """The real `DuplicateKeyError`, matched by class name.

        `cloud_repo._is_duplicate_key_error` compares `type(exc).__name__`
        rather than importing pymongo. If the driver ever renames that class the
        match silently fails and a 409 becomes a 500 — this test is the only
        thing that would notice.
        """
        await users.create(User(email="dupe@example.com", hashed_password="x"))
        with pytest.raises(EmailAlreadyRegistered):
            await users.create(User(email="dupe@example.com", hashed_password="y"))

    async def test_case_variants_collide(self, users):
        """The index is on the stored value, so normalisation has to happen
        before the write — otherwise `A@b.com` and `a@b.com` are two accounts."""
        await users.create(User(email="Mixed@Example.COM", hashed_password="x"))
        with pytest.raises(EmailAlreadyRegistered):
            await users.create(User(email="mixed@example.com", hashed_password="y"))

    async def test_a_concurrent_race_produces_exactly_one_user(self, users, mongo_db):
        """The race the index exists for, run as an actual race.

        Sequential duplicate-registration tests pass even with no index at all,
        because the application-level check has time to see the first write.
        Ten concurrent inserts do not give it that chance: without a unique
        index several would land, and `find_by_email` would then return an
        arbitrary one of them.
        """
        results = await asyncio.gather(
            *(
                users.create(User(email="race@example.com", hashed_password=f"h{i}"))
                for i in range(10)
            ),
            return_exceptions=True,
        )

        winners = [r for r in results if isinstance(r, User)]
        losers = [r for r in results if isinstance(r, EmailAlreadyRegistered)]
        unexpected = [
            r
            for r in results
            if not isinstance(r, (User, EmailAlreadyRegistered))
        ]

        assert not unexpected, f"unexpected errors from the race: {unexpected!r}"
        assert len(winners) == 1, f"{len(winners)} inserts won; exactly 1 may"
        assert len(losers) == 9
        assert await mongo_db[USERS].count_documents({"email": "race@example.com"}) == 1


class TestTimestamps:
    """BSON's millisecond resolution, proven rather than assumed."""

    async def test_a_user_reads_back_equal_to_what_was_written(self, users):
        """The assertion that fails if `_utc_now()` stops truncating.

        Observed 2026-09-15 before the fix: written `…744441Z`, read back
        `…744000Z`. Nothing in the fake-backed suite can catch that.
        """
        written = User(email="ts@example.com", hashed_password="x")
        await users.create(written)

        read_back = await users.find_by_email("ts@example.com")
        assert read_back is not None
        assert read_back.created_at == written.created_at
        assert read_back.updated_at == written.updated_at
        assert read_back == written

    async def test_the_server_really_does_truncate_to_milliseconds(self, users):
        """Proves the hazard `_utc_now()` exists to avoid, rather than assuming
        it. Writes a deliberately microsecond-precision timestamp — what the
        model produced before 2026-09-15 — and shows the server drops it.

        If a future MongoDB gains microsecond resolution this test fails, which
        is the signal that the truncation in `_utc_now()` can be removed. That
        is worth knowing; a silently unnecessary workaround is how the next
        person concludes the comment is wrong.
        """
        user = User(email="precision@example.com", hashed_password="x")
        user.created_at = user.created_at.replace(microsecond=744_441)
        await users.create(user)

        read_back = await users.find_by_email("precision@example.com")
        assert read_back.created_at.microsecond == 744_000
        assert read_back.created_at != user.created_at

    async def test_timestamps_come_back_timezone_aware(self, users):
        """The S8.1 `tz_aware=True` finding: a naive datetime read back from
        Mongo compares unequal to the aware one that was written, and silently
        misorders a sync between devices in different zones."""
        await users.create(User(email="tz@example.com", hashed_password="x"))
        read_back = await users.find_by_email("tz@example.com")
        assert read_back.created_at.tzinfo is not None
        assert read_back.created_at.utcoffset() == timezone.utc.utcoffset(None)

    async def test_a_stored_home_reads_back_equal(self, homes, bungalow):
        written = StoredHomeModel(
            user_id="u1", home=HomeModel.model_validate(bungalow)
        )
        await homes.upsert(written)
        read_back = await homes.find_for_user(written.id, "u1")
        assert read_back is not None
        assert read_back.created_at == written.created_at
        assert read_back.updated_at == written.updated_at


class TestHomeRoundTrip:
    """A HomeModel is the project's one law. It has to survive BSON intact."""

    @pytest.mark.parametrize(
        "fixture_name", ["bungalow", "apartment", "twostory"]
    )
    async def test_a_home_survives_bson_unchanged(
        self, homes, fixture_name, request
    ):
        """Compared as models, not as raw dicts.

        A dict comparison fails on absent-vs-explicit-null for every optional
        field, which is noise: pydantic materialises them either way and the
        meaning is identical. Model equality is the question that matters — the
        editor and the routing engine both consume the model.
        """
        raw = request.getfixturevalue(fixture_name)
        home = HomeModel.model_validate(raw)
        written = StoredHomeModel(user_id="u1", home=home)

        await homes.upsert(written)
        read_back = await homes.find_for_user(written.id, "u1")

        assert read_back is not None
        assert read_back.home == home
        assert read_back.home.schema_version == home.schema_version

    async def test_nested_geometry_survives_with_full_float_precision(
        self, homes, bungalow
    ):
        """Polygon vertices are the coordinates routes are computed on. A float
        that shifts in storage moves a wall."""
        home = HomeModel.model_validate(bungalow)
        written = StoredHomeModel(user_id="u1", home=home)
        await homes.upsert(written)

        read_back = await homes.find_for_user(written.id, "u1")
        for floor_before, floor_after in zip(home.floors, read_back.home.floors):
            for room_before, room_after in zip(floor_before.rooms, floor_after.rooms):
                assert room_after.polygon == room_before.polygon
                assert room_after.id == room_before.id

    async def test_an_empty_home_list_is_empty_not_an_error(self, homes):
        assert await homes.list_for_user("nobody") == []


class TestOwnership:
    """The ownership check is in the query, not only in the route."""

    async def test_a_write_to_another_users_home_id_is_rejected(
        self, homes, bungalow
    ):
        """`replace_one` with an owner-scoped filter does NOT quietly no-op when
        the id belongs to someone else: the filter misses, Mongo attempts an
        insert, and it collides on `_id`. Found against the fake 2026-09-14;
        this confirms the real driver raises the same way.
        """
        home = HomeModel.model_validate(bungalow)
        mine = StoredHomeModel(user_id="owner", home=home)
        await homes.upsert(mine)

        theirs = StoredHomeModel(id=mine.id, user_id="attacker", home=home)
        with pytest.raises(HomeNotOwned):
            await homes.upsert(theirs)

        still_mine = await homes.find_for_user(mine.id, "owner")
        assert still_mine is not None
        assert still_mine.user_id == "owner"

    async def test_a_listing_is_scoped_to_its_owner(self, homes, bungalow):
        home = HomeModel.model_validate(bungalow)
        await homes.upsert(StoredHomeModel(user_id="a", home=home))
        await homes.upsert(StoredHomeModel(user_id="a", home=home))
        await homes.upsert(StoredHomeModel(user_id="b", home=home))

        assert len(await homes.list_for_user("a")) == 2
        assert len(await homes.list_for_user("b")) == 1

    async def test_another_users_home_is_invisible_not_forbidden(
        self, homes, bungalow
    ):
        """`find_for_user` returning None is what lets the route answer 404
        rather than 403 — a 403 would confirm the id exists."""
        mine = StoredHomeModel(
            user_id="owner", home=HomeModel.model_validate(bungalow)
        )
        await homes.upsert(mine)
        assert await homes.find_for_user(mine.id, "someone-else") is None


class TestDocumentShape:
    """What actually lands in Mongo, as opposed to what the model looks like."""

    async def test_a_user_is_keyed_by_underscore_id(self, users, mongo_db):
        """`insert_one(user.model_dump())` would write a field named `id` and
        let Mongo mint its own ObjectId `_id`, after which every lookup misses.
        `to_document()` exists to prevent that; this proves it worked."""
        user = User(email="shape@example.com", hashed_password="x")
        await users.create(user)

        doc = await mongo_db[USERS].find_one({"_id": user.id})
        assert doc is not None
        assert doc["_id"] == user.id
        assert "id" not in doc

    async def test_the_stored_hash_is_never_the_password(self, users, mongo_db):
        user = User(email="hash@example.com", hashed_password="$argon2id$vsomething")
        await users.create(user)
        doc = await mongo_db[USERS].find_one({"_id": user.id})
        assert doc["hashed_password"] == "$argon2id$vsomething"

    async def test_a_home_document_embeds_the_model_not_a_reference(
        self, homes, mongo_db, bungalow
    ):
        """The home is stored whole. S8.4 fetches one document per home, and a
        reference would make that a second round trip for no benefit."""
        stored = StoredHomeModel(
            user_id="u1", home=HomeModel.model_validate(bungalow)
        )
        await homes.upsert(stored)

        doc = await mongo_db[HOMES].find_one({"_id": stored.id})
        assert isinstance(doc["home"], dict)
        assert doc["home"]["home_id"] == bungalow["home_id"]
        assert doc["revision"] == 1
        assert isinstance(doc["created_at"], datetime)


class TestUnreachableDatabase:
    """A CONFIGURED but UNREACHABLE database is a third state, distinct from
    "not configured" (503 via `CloudSyncDisabled`) and from "working".

    Found 2026-09-15 on the deployed service: `MONGODB_URI` was set but Atlas was
    not allow-listing Render's IPs, and `POST /auth/register` answered a bare 500
    with no body. The iOS client in S8.3/S8.4 has to tell "retry this" from "your
    request was wrong", and a 500 says the wrong one.

    Marked `mongo` because it needs the real driver's exception types, though it
    deliberately never reaches a real server.
    """

    async def test_a_connection_failure_becomes_503_not_500(self, monkeypatch):
        from fastapi.testclient import TestClient

        from app import config
        from app.database import database
        from app.main import app

        monkeypatch.setenv("BACKEND_BEARER_TOKEN", "test-token")
        monkeypatch.setenv(
            "JWT_SECRET_KEY", "a-test-signing-secret-well-over-32-bytes-long"
        )
        config.get_settings.cache_clear()

        from pymongo import AsyncMongoClient

        # A syntactically valid URI pointing at a port nothing listens on. The
        # client constructs fine and fails on first use — which is precisely the
        # deployed failure mode, and is why a constructor-time check cannot
        # substitute for this handler.
        dead = AsyncMongoClient(
            "mongodb://127.0.0.1:1/", serverSelectionTimeoutMS=250
        )
        monkeypatch.setattr(database, "_client", dead, raising=False)
        monkeypatch.setattr(database, "_db", dead["escape_plan_unreachable"], raising=False)

        try:
            with TestClient(app) as client:
                resp = client.post(
                    "/auth/register",
                    json={"email": "unreachable@example.com", "password": "a-good-one"},
                )
            assert resp.status_code == 503, (
                f"expected 503, got {resp.status_code} — a bare 500 tells the iOS "
                "client nothing about whether retrying is worthwhile"
            )
            assert "try again" in resp.json()["detail"].lower()
        finally:
            await dead.close()
            config.get_settings.cache_clear()


class TestDeletionAgainstRealMongo:
    """S11.7 — delete-my-data against the real driver.

    The fake's `delete_one` / `delete_many` are twenty hand-written lines, and
    the one thing they cannot prove is that `delete_many({"user_id": ...})`
    scopes the way `find` does on a real server. Getting that wrong erases every
    account's homes, and the fake would agree with it.
    """

    async def test_delete_all_for_user_leaves_other_owners_alone(
        self, mongo_db, bungalow
    ):
        repo = HomeRepository(mongo_db)
        home = HomeModel.model_validate(bungalow)
        await repo.upsert(StoredHomeModel(id="h1", user_id="u1", home=home))
        await repo.upsert(StoredHomeModel(id="h2", user_id="u1", home=home))
        await repo.upsert(StoredHomeModel(id="h3", user_id="u2", home=home))

        assert await repo.delete_all_for_user("u1") == 2
        assert await repo.list_for_user("u1") == []
        assert len(await repo.list_for_user("u2")) == 1

    async def test_delete_for_user_refuses_across_owners(self, mongo_db, bungalow):
        repo = HomeRepository(mongo_db)
        await repo.upsert(
            StoredHomeModel(
                id="h1", user_id="u1", home=HomeModel.model_validate(bungalow)
            )
        )
        assert await repo.delete_for_user("h1", "u2") is False
        assert await repo.find_for_user("h1", "u1") is not None

    async def test_deleting_a_user_frees_the_unique_email_index(self, mongo_db):
        """The index is the server's, not the fake's. If deletion left a
        tombstone the re-registration below would raise EmailAlreadyRegistered.
        """
        repo = UserRepository(mongo_db)
        user = await repo.create(User(email="a@b.com", hashed_password="h"))
        assert await repo.delete(user.id) is True

        again = await repo.create(User(email="a@b.com", hashed_password="h2"))
        assert again.id != user.id
