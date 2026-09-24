"""S8.2 — the user and home repositories, against the in-memory fake.

The fake enforces the unique index, so the duplicate-email race is genuinely
exercised here rather than assumed. What these do NOT prove is that a real
MongoDB creates that index — that needs a `mongo`-marked test and a server.
"""

from __future__ import annotations

import pytest

from app.cloud_models import StoredHomeModel, User
from app.cloud_repo import (
    EmailAlreadyRegistered,
    HomeNotOwned,
    HomeRepository,
    UserRepository,
    ensure_indexes,
)
from app.models import HomeModel
from tests.fake_mongo import FakeDatabase


@pytest.fixture
async def db() -> FakeDatabase:
    database = FakeDatabase()
    await ensure_indexes(database)
    return database


class TestUserRepository:
    @pytest.mark.anyio
    async def test_create_then_find_by_email(self, db):
        repo = UserRepository(db)
        user = await repo.create(User(email="a@b.com", hashed_password="h"))

        found = await repo.find_by_email("a@b.com")
        assert found is not None
        assert found.id == user.id
        assert found.hashed_password == "h"

    @pytest.mark.anyio
    async def test_duplicate_email_raises_the_domain_error(self, db):
        """The index is what stops this, not an application-level check — two
        concurrent registrations can both pass a check before either inserts."""
        repo = UserRepository(db)
        await repo.create(User(email="a@b.com", hashed_password="h"))

        with pytest.raises(EmailAlreadyRegistered):
            await repo.create(User(email="a@b.com", hashed_password="other"))

    @pytest.mark.anyio
    async def test_differently_cased_duplicate_is_also_rejected(self, db):
        """User normalises on validation, so these collide at the index."""
        repo = UserRepository(db)
        await repo.create(User(email="a@b.com", hashed_password="h"))

        with pytest.raises(EmailAlreadyRegistered):
            await repo.create(User(email="A@B.COM", hashed_password="h"))

    @pytest.mark.anyio
    async def test_missing_email_returns_none_not_an_error(self, db):
        assert await UserRepository(db).find_by_email("nobody@x.com") is None

    @pytest.mark.anyio
    async def test_find_by_id_round_trips(self, db):
        repo = UserRepository(db)
        user = await repo.create(User(email="a@b.com", hashed_password="h"))
        assert (await repo.find_by_id(user.id)).email == "a@b.com"

    @pytest.mark.anyio
    async def test_a_non_duplicate_error_is_not_swallowed(self, db):
        """Only DuplicateKeyError becomes EmailAlreadyRegistered."""

        class Boom(Exception):
            pass

        async def explode(_doc):
            raise Boom()

        db["users"].insert_one = explode
        with pytest.raises(Boom):
            await UserRepository(db).create(User(email="a@b.com"))


class TestHomeRepository:
    @pytest.mark.anyio
    async def test_upsert_then_list(self, db, bungalow):
        repo = HomeRepository(db)
        stored = StoredHomeModel(
            user_id="u1", home=HomeModel.model_validate(bungalow)
        )
        await repo.upsert(stored)

        homes = await repo.list_for_user("u1")
        assert len(homes) == 1
        assert homes[0].home == stored.home

    @pytest.mark.anyio
    async def test_list_is_scoped_to_the_owner(self, db, bungalow):
        repo = HomeRepository(db)
        home = HomeModel.model_validate(bungalow)
        await repo.upsert(StoredHomeModel(user_id="u1", home=home))
        await repo.upsert(StoredHomeModel(user_id="u2", home=home))

        assert len(await repo.list_for_user("u1")) == 1

    @pytest.mark.anyio
    async def test_another_user_cannot_overwrite_by_guessing_the_id(self, db, bungalow):
        """Ownership is enforced in the query, not only in the route."""
        repo = HomeRepository(db)
        home = HomeModel.model_validate(bungalow)
        mine = StoredHomeModel(id="h1", user_id="u1", home=home, revision=1)
        await repo.upsert(mine)

        attacker = StoredHomeModel(id="h1", user_id="u2", home=home, revision=99)
        with pytest.raises(HomeNotOwned):
            await repo.upsert(attacker)

        still_mine = await repo.find_for_user("h1", "u1")
        assert still_mine is not None
        assert still_mine.revision == 1, "another user's write reached my document"
        assert still_mine.user_id == "u1"

    @pytest.mark.anyio
    async def test_find_for_user_misses_across_owners(self, db, bungalow):
        repo = HomeRepository(db)
        await repo.upsert(
            StoredHomeModel(id="h1", user_id="u1", home=HomeModel.model_validate(bungalow))
        )
        assert await repo.find_for_user("h1", "u2") is None

    @pytest.mark.anyio
    async def test_upsert_replaces_rather_than_duplicating(self, db, bungalow):
        repo = HomeRepository(db)
        home = HomeModel.model_validate(bungalow)
        await repo.upsert(StoredHomeModel(id="h1", user_id="u1", home=home, revision=1))
        await repo.upsert(StoredHomeModel(id="h1", user_id="u1", home=home, revision=2))

        homes = await repo.list_for_user("u1")
        assert len(homes) == 1
        assert homes[0].revision == 2


class TestDeletion:
    """S11.7 — the storage half of delete-my-data. The route tests assert the
    status codes; these assert that documents actually leave the collection,
    which a route test reading `GET /homes` cannot distinguish from a filter."""

    @pytest.mark.anyio
    async def test_delete_for_user_removes_the_document(self, db, bungalow):
        repo = HomeRepository(db)
        await repo.upsert(
            StoredHomeModel(id="h1", user_id="u1", home=HomeModel.model_validate(bungalow))
        )
        assert await repo.delete_for_user("h1", "u1") is True
        assert await repo.find_for_user("h1", "u1") is None

    @pytest.mark.anyio
    async def test_delete_for_user_refuses_across_owners(self, db, bungalow):
        """The ownership check is IN THE FILTER. A read-then-delete has a window
        in which ownership changes, and this is the assertion that would fail if
        someone 'simplified' it to `delete_one({"_id": home_id})`."""
        repo = HomeRepository(db)
        await repo.upsert(
            StoredHomeModel(id="h1", user_id="u1", home=HomeModel.model_validate(bungalow))
        )
        assert await repo.delete_for_user("h1", "u2") is False
        assert await repo.find_for_user("h1", "u1") is not None

    @pytest.mark.anyio
    async def test_delete_for_user_is_false_for_an_unknown_home(self, db):
        assert await HomeRepository(db).delete_for_user("nope", "u1") is False

    @pytest.mark.anyio
    async def test_delete_all_for_user_takes_only_that_users_homes(self, db, bungalow):
        repo = HomeRepository(db)
        home = HomeModel.model_validate(bungalow)
        await repo.upsert(StoredHomeModel(id="h1", user_id="u1", home=home))
        await repo.upsert(StoredHomeModel(id="h2", user_id="u1", home=home))
        await repo.upsert(StoredHomeModel(id="h3", user_id="u2", home=home))

        assert await repo.delete_all_for_user("u1") == 2
        assert await repo.list_for_user("u1") == []
        assert len(await repo.list_for_user("u2")) == 1

    @pytest.mark.anyio
    async def test_delete_all_for_user_is_zero_when_there_is_nothing(self, db):
        assert await HomeRepository(db).delete_all_for_user("u1") == 0

    @pytest.mark.anyio
    async def test_delete_user_removes_the_account(self, db):
        repo = UserRepository(db)
        user = await repo.create(User(email="a@b.com", hashed_password="h"))

        assert await repo.delete(user.id) is True
        assert await repo.find_by_id(user.id) is None
        assert await repo.find_by_email("a@b.com") is None

    @pytest.mark.anyio
    async def test_delete_user_frees_the_unique_email(self, db):
        """Nothing is soft-deleted, so the address is genuinely available again
        — and a re-registration must not trip the unique index."""
        repo = UserRepository(db)
        user = await repo.create(User(email="a@b.com", hashed_password="h"))
        await repo.delete(user.id)

        again = await repo.create(User(email="a@b.com", hashed_password="h2"))
        assert again.id != user.id

    @pytest.mark.anyio
    async def test_delete_user_is_false_for_an_unknown_id(self, db):
        assert await UserRepository(db).delete("u-nobody") is False
