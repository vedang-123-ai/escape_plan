"""A minimal in-memory stand-in for the async Mongo collections we use.

Why hand-written: `mongomock` has no Python 3.13 support and no async API, and
`mongomock-motor` targets Motor, which reached end-of-life 2026-05-14 — adopting
it would pull a dead driver back in for tests alone. See docs/decisions.md.

This implements only the operations `cloud_repo` performs, and **enforces the
unique index**, because the duplicate-email race is the single most important
behaviour to pin. It is NOT a Mongo emulator: query support is exact-match on
top-level fields, which is all the repositories use. Anything needing real query
semantics belongs in a `mongo`-marked test against a real server.
"""

from __future__ import annotations

from typing import Any


class DuplicateKeyError(Exception):
    """Named to match pymongo's, since `cloud_repo` identifies it by class name."""


class _Cursor:
    """Async-iterable, matching `collection.find(...)` usage."""

    def __init__(self, docs: list[dict]) -> None:
        self._docs = docs

    def __aiter__(self):
        return self._gen()

    async def _gen(self):
        for doc in self._docs:
            yield dict(doc)


class FakeCollection:
    def __init__(self) -> None:
        self.documents: dict[Any, dict] = {}
        self._unique_fields: list[str] = []

    async def create_index(self, field: str, unique: bool = False, **_kw: Any) -> str:
        if unique and field not in self._unique_fields:
            self._unique_fields.append(field)
        return f"{field}_1"

    def _violates_unique(self, doc: dict, ignoring_id: Any = None) -> bool:
        for field in self._unique_fields:
            if field not in doc:
                continue
            for existing_id, existing in self.documents.items():
                if existing_id == ignoring_id:
                    continue
                if existing.get(field) == doc[field]:
                    return True
        return False

    async def insert_one(self, doc: dict) -> Any:
        # _id is Mongo's primary key and is always unique — modelling that
        # matters, because an upsert whose filter misses will try to INSERT and
        # collide here rather than silently overwriting.
        if doc["_id"] in self.documents or self._violates_unique(doc):
            raise DuplicateKeyError(doc)
        self.documents[doc["_id"]] = dict(doc)
        return type("Result", (), {"inserted_id": doc["_id"]})()

    @staticmethod
    def _matches(doc: dict, query: dict) -> bool:
        return all(doc.get(k) == v for k, v in query.items())

    async def find_one(self, query: dict) -> dict | None:
        for doc in self.documents.values():
            if self._matches(doc, query):
                return dict(doc)
        return None

    def find(self, query: dict) -> _Cursor:
        return _Cursor([d for d in self.documents.values() if self._matches(d, query)])

    async def replace_one(self, query: dict, doc: dict, upsert: bool = False) -> Any:
        for existing_id, existing in list(self.documents.items()):
            if self._matches(existing, query):
                if self._violates_unique(doc, ignoring_id=existing_id):
                    raise DuplicateKeyError(doc)
                self.documents[existing_id] = dict(doc)
                return type("Result", (), {"matched_count": 1})()
        if not upsert:
            return type("Result", (), {"matched_count": 0})()
        if doc["_id"] in self.documents or self._violates_unique(doc):
            raise DuplicateKeyError(doc)
        self.documents[doc["_id"]] = dict(doc)
        return type("Result", (), {"matched_count": 0, "upserted_id": doc["_id"]})()

    async def delete_one(self, query: dict) -> Any:
        for existing_id, existing in list(self.documents.items()):
            if self._matches(existing, query):
                del self.documents[existing_id]
                return type("Result", (), {"deleted_count": 1})()
        return type("Result", (), {"deleted_count": 0})()

    async def delete_many(self, query: dict) -> Any:
        doomed = [i for i, d in self.documents.items() if self._matches(d, query)]
        for existing_id in doomed:
            del self.documents[existing_id]
        return type("Result", (), {"deleted_count": len(doomed)})()

    async def count_documents(self, query: dict) -> int:
        return sum(1 for d in self.documents.values() if self._matches(d, query))


class FakeDatabase:
    """`db["users"]` — collections spring into existence on first access."""

    def __init__(self) -> None:
        self.collections: dict[str, FakeCollection] = {}

    def __getitem__(self, name: str) -> FakeCollection:
        return self.collections.setdefault(name, FakeCollection())
