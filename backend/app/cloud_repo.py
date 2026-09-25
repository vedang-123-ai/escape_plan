"""Storage access for the S8 cloud layer: users and their home models.

Kept apart from `database.py` (which owns the connection) and from the route
handlers (which stay thin, per the project's FastAPI convention). Every filter is
built from validated model fields — never from raw request dicts — so a
`{"$ne": null}` style operator cannot reach a query.

Collections are addressed through `Database.db`, which raises `CloudSyncDisabled`
when no database is configured. Routes let that propagate to the 503 handler
rather than branching on `database.enabled`, because a branch silently skips the
write and reports success.
"""

from __future__ import annotations

from typing import Any

from app.cloud_models import StoredHomeModel, User

USERS = "users"
HOMES = "homes"


class HomeNotOwned(Exception):
    """Raised when a write targets a home id that belongs to someone else.

    Found by test 2026-09-14. `replace_one({"_id": id, "user_id": me}, upsert=True)`
    does NOT quietly do nothing when the id belongs to another user: the filter
    misses, so Mongo attempts an INSERT, which collides on the `_id` primary key.
    The data is safe either way, but without this the collision surfaces as an
    unhandled driver error and a 500, when the honest answer is that the caller
    does not own that home.
    """


class EmailAlreadyRegistered(Exception):
    """Raised when a registration loses the race for an email address.

    This is the *database* telling us, via the unique index — not an
    application-level "is it taken?" check, which two concurrent registrations
    can both pass before either inserts.
    """


try:  # pragma: no branch - which arm runs depends on the environment
    from pymongo.errors import DuplicateKeyError as _DuplicateKeyError
except ImportError:  # the driver is optional; the app must still import without it
    _DuplicateKeyError = None  # type: ignore[assignment,misc]


def _is_duplicate_key_error(exc: BaseException) -> bool:
    """True for pymongo's DuplicateKeyError.

    `isinstance` when the driver is installed, so a subclass or a re-export is
    still recognised. The class-name match stays as the fallback: `database.py`
    keeps pymongo out of the import path so the app imports without the driver,
    and the in-memory fake in `tests/fake_mongo.py` raises its own
    `DuplicateKeyError`, which only the name identifies.
    """
    if _DuplicateKeyError is not None and isinstance(exc, _DuplicateKeyError):
        return True
    return type(exc).__name__ == "DuplicateKeyError"


async def ensure_indexes(db: Any) -> None:
    """Create the indexes the auth layer's correctness depends on.

    **The unique index on `email` is not an optimisation.** Without it, two
    concurrent registrations for one address both pass any application-level
    check and both insert; `find_by_email` then returns an arbitrary one of them
    and password reset becomes ambiguous — an account-takeover shape.

    Idempotent: Mongo ignores a create_index call for an index that already
    matches. Called from `Database.connect()`.
    """
    await db[USERS].create_index("email", unique=True, name="uniq_email")
    await db[HOMES].create_index("user_id", name="by_user")


class UserRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    @property
    def _collection(self) -> Any:
        return self._db[USERS]

    async def create(self, user: User) -> User:
        """Insert, converting the index violation into a domain error."""
        try:
            await self._collection.insert_one(user.to_document())
        except Exception as exc:
            if _is_duplicate_key_error(exc):
                raise EmailAlreadyRegistered(user.email) from exc
            raise
        return user

    async def find_by_email(self, email: str) -> User | None:
        """Look up by address. The caller must pass an address already
        normalised by `User`'s validator, or a differently-cased duplicate will
        miss."""
        doc = await self._collection.find_one({"email": email})
        return User.model_validate(doc) if doc else None

    async def find_by_id(self, user_id: str) -> User | None:
        doc = await self._collection.find_one({"_id": user_id})
        return User.model_validate(doc) if doc else None

    async def delete(self, user_id: str) -> bool:
        """Erase the account record. True if a document was actually removed.

        Deleting the user is what revokes every outstanding JWT for it:
        `get_current_user` re-reads the user on every request, so a token for a
        deleted account is rejected immediately rather than at its expiry.
        """
        result = await self._collection.delete_one({"_id": user_id})
        return bool(getattr(result, "deleted_count", 0))


class HomeRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    @property
    def _collection(self) -> Any:
        return self._db[HOMES]

    async def list_for_user(self, user_id: str) -> list[StoredHomeModel]:
        cursor = self._collection.find({"user_id": user_id})
        return [StoredHomeModel.model_validate(doc) async for doc in cursor]

    async def upsert(self, stored: StoredHomeModel) -> StoredHomeModel:
        """Write one home, scoped to its owner.

        The filter includes `user_id` as well as `_id` so a caller cannot
        overwrite another user's document by guessing an id — the ownership
        check is in the query, not only in the route.
        """
        try:
            await self._collection.replace_one(
                {"_id": stored.id, "user_id": stored.user_id},
                stored.to_document(),
                upsert=True,
            )
        except Exception as exc:
            if _is_duplicate_key_error(exc):
                raise HomeNotOwned(stored.id) from exc
            raise
        return stored

    async def find_for_user(
        self, home_id: str, user_id: str
    ) -> StoredHomeModel | None:
        doc = await self._collection.find_one({"_id": home_id, "user_id": user_id})
        return StoredHomeModel.model_validate(doc) if doc else None

    async def delete_for_user(self, home_id: str, user_id: str) -> bool:
        """Remove one home, scoped to its owner. True if it existed and was ours.

        `user_id` is in the FILTER, not checked beforehand, for the same reason
        `upsert`'s is: a read-then-delete has a window in which ownership can
        change, and a caller who forgets the second step deletes anyone's home.
        A miss is indistinguishable from "no such home", which is what lets the
        route answer 404 without leaking that the id belongs to someone else.
        """
        result = await self._collection.delete_one(
            {"_id": home_id, "user_id": user_id}
        )
        return bool(getattr(result, "deleted_count", 0))

    async def delete_all_for_user(self, user_id: str) -> int:
        """Remove every home belonging to one user. Returns how many went.

        Used by account deletion, where "delete my data" has to mean the homes
        as well — the account document alone is an email address, and the homes
        are the floor plan, the household members' names and the optional
        address.
        """
        result = await self._collection.delete_many({"user_id": user_id})
        return int(getattr(result, "deleted_count", 0))
