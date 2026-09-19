"""Pydantic models for the S8 cloud-sync layer: users and stored home models.

Deliberately NOT in `app/models.py`. That file is the executable half of the
HomeModel contract (`schema/homemodel.schema.json`) and is guarded by
`schema-contract-guardian` — every model in it must stay in lockstep with the
JSON Schema and the Swift Codable structs. These models are server-side storage
concerns with no Swift counterpart and no place in the schema, so mixing them in
would make the contract's own guard ambiguous about what it is guarding.

`StoredHomeModel` *embeds* a `HomeModel` rather than re-describing one: the
contract stays the single source of truth for home geometry, and this layer only
adds ownership, identity and revision metadata around it.

Ids are application-generated UUID strings rather than Mongo `ObjectId`s, mapped
onto Mongo's `_id` by alias. That keeps these models JSON-serialisable and free
of any driver import, so they can be validated in tests with no database and no
bson dependency.
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models import HomeModel


def _utc_now() -> datetime:
    """Timezone-aware UTC, truncated to milliseconds.

    Naive datetimes compare incorrectly across a sync — hence `timezone.utc`.

    The truncation is the less obvious half. **BSON stores datetimes as
    milliseconds since the epoch**, so microseconds do not survive a write: a
    user created at `…744441Z` reads back `…744000Z` (observed against a live
    Atlas cluster, 2026-09-15). Generating them already truncated makes an
    in-memory model compare equal to the same model read back from Mongo.
    Without it, `written == read_back` passes against the in-memory fake and
    fails against a real server — the same class of bug as the `tz_aware` fix in
    S8.1, and exactly the kind S8.4's merge would trip over while comparing a
    local copy against a fetched one.

    Sub-millisecond precision carries no meaning here: these timestamps order
    syncs between devices whose clocks disagree by far more than a microsecond.
    """
    now = datetime.now(timezone.utc)
    return now.replace(microsecond=(now.microsecond // 1000) * 1000)


def _new_id() -> str:
    return str(uuid.uuid4())


# A deliberately permissive check: one "@", something either side, no spaces.
# Real address validation is a rabbit hole (RFC 5322) and the authoritative test
# is S8.2's verification flow, not a regex. This only catches obvious junk.
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def normalise_email(value: str) -> str:
    """Lowercase, trim, and reject obvious junk. Shared by the storage model and
    the register request so a single rule decides what an address is — otherwise
    the request layer accepts something the storage layer then rejects, and the
    mismatch surfaces as a 500 instead of a 422.
    """
    cleaned = value.strip().lower()
    if not _EMAIL_RE.match(cleaned):
        raise ValueError(f"not a usable email address: {value!r}")
    return cleaned


class CloudModel(BaseModel):
    """Base for the cloud layer: reject unknown fields, populate by field name.

    `populate_by_name` lets a document load whether it arrives keyed by `id`
    (from the API) or `_id` (from Mongo), which is what makes the alias below
    transparent to callers.
    """

    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class User(CloudModel):
    """An account owning zero or more stored home models.

    `hashed_password` is Optional here and carries no hashing logic on purpose —
    S8.1 defines the shape, S8.2 owns authentication. The field is named for the
    hash, never the password, so there is no shape in which this model can hold
    a plaintext credential.
    """

    id: str = Field(default_factory=_new_id, alias="_id")
    # 254 is the practical maximum for an address. Unbounded, a multi-megabyte
    # string validates here and is then rejected by Mongo's 1024-byte index key
    # limit at write time — a driver error where a 422 belongs.
    email: str = Field(max_length=254)
    hashed_password: str | None = None
    created_at: datetime = Field(default_factory=_utc_now)
    updated_at: datetime = Field(default_factory=_utc_now)

    def to_document(self) -> dict:
        """Mongo-ready dict: `_id` rather than `id`.

        Exists so the obvious call is the correct one. `insert_one(user.model_dump())`
        would write a field literally named `id` and let Mongo mint its own
        ObjectId `_id`, after which every lookup by id misses.

        NOTE for S8.2: this intentionally INCLUDES `hashed_password`, because it
        is the persistence path. Do not return a `User` from an endpoint — add a
        separate public response model, or the hash goes out over the wire.
        """
        return self.model_dump(by_alias=True, mode="python")

    @field_validator("email")
    @classmethod
    def _normalise_email(cls, value: str) -> str:
        """Addresses are case-insensitive in practice, and storing them
        un-normalised is how duplicate accounts happen."""
        return normalise_email(value)


class StoredHomeModel(CloudModel):
    """A `HomeModel` as persisted for one user, with sync metadata.

    `revision` increments on every server-accepted write. S8.4's merge logic
    needs a monotonic counter to detect a stale client pushing over a newer
    server copy; wall-clock timestamps alone cannot do that safely, because two
    devices' clocks disagree.
    """

    id: str = Field(default_factory=_new_id, alias="_id")
    user_id: str
    home: HomeModel
    revision: int = Field(default=1, ge=1)
    created_at: datetime = Field(default_factory=_utc_now)
    updated_at: datetime = Field(default_factory=_utc_now)

    def to_document(self) -> dict:
        """Mongo-ready dict: `_id` rather than `id`, native datetimes kept."""
        return self.model_dump(by_alias=True, mode="python")


class UserPublic(CloudModel):
    """A `User` as it may be returned to a client.

    Exists because `User` is the *storage* model and `to_document()` deliberately
    includes `hashed_password`. Returning a `User` from an endpoint would put the
    hash on the wire, and FastAPI's `response_model` filtering is easy to forget
    or to bypass with a bare dict. This type simply has nowhere to put a hash.
    """

    id: str
    email: str
    created_at: datetime

    @classmethod
    def from_user(cls, user: User) -> "UserPublic":
        return cls(id=user.id, email=user.email, created_at=user.created_at)
