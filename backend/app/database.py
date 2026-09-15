"""MongoDB connection lifecycle for the S8 cloud-sync layer.

Driver choice (deviation from the S8.1 playbook — see docs/decisions.md):
the playbook says "Motor (async MongoDB driver) or Beanie". **Motor reached
end-of-life on 2026-05-14** and MongoDB now directs new code at PyMongo's
native async API, which went GA in PyMongo 4.13. So this uses
`pymongo.AsyncMongoClient` and the project takes no dependency on a dead driver.

Two behaviours differ from Motor and are easy to get wrong:
  * `AsyncMongoClient.close()` is a coroutine — it must be awaited.
  * The client owns a connection pool and is meant to be one long-lived
    instance for the process, never created per request.

Cloud sync is OPTIONAL. `get_settings()` refuses to start without
`BACKEND_BEARER_TOKEN`, but an unset `MONGODB_URI` only disables this layer:
the routing engine, the corpus and every pre-S8 endpoint work with no database,
and the demo path depends on them. A backend that refused to boot without Mongo
would trade a working product for an unbuilt feature.
"""

from __future__ import annotations

import logging
from typing import Any, Callable, Literal

from app.config import get_settings

logger = logging.getLogger(__name__)

# The driver default is 30s. On an unreachable host that turns /health/db into a
# 30-second hang, which is useless to a health check and to a human debugging it.
SERVER_SELECTION_TIMEOUT_MS = 3000

DatabaseStatus = Literal["disabled", "ok", "unreachable"]


class CloudSyncDisabled(RuntimeError):
    """Raised when cloud-sync code runs with no database configured."""


class Database:
    """Holds the process-wide client. One instance; see the module docstring.

    `client_factory` exists so tests can drive the lifecycle with a stub and
    assert on real behaviour (connect → ping → close) without a live server.
    """

    def __init__(self) -> None:
        self._client: Any | None = None
        self._db: Any | None = None

    @property
    def enabled(self) -> bool:
        return self._client is not None

    @property
    def db(self) -> Any:
        """The database handle. Raises if cloud sync is not configured, rather
        than returning None for a caller to dereference into an AttributeError."""
        if self._db is None:
            raise CloudSyncDisabled(
                "cloud sync is not configured — set MONGODB_URI to enable it"
            )
        return self._db

    async def connect(self, client_factory: Callable[[str], Any] | None = None) -> None:
        """Create the client if `MONGODB_URI` is set. Never raises on a missing
        URI — that is the supported 'cloud sync off' configuration.

        Note this does NOT prove the server is reachable: PyMongo connects
        lazily, so a bad host surfaces on first use (or on `ping`), not here.
        """
        settings = get_settings()
        if not settings.cloud_sync_enabled:
            logger.info("MONGODB_URI not set — cloud sync disabled")
            return

        assert settings.mongodb_uri is not None  # implied by cloud_sync_enabled
        factory = client_factory or _default_client_factory
        self._client = factory(settings.mongodb_uri)
        self._db = self._client[settings.mongodb_db_name]
        logger.info("cloud sync enabled, database %r", settings.mongodb_db_name)

    async def close(self) -> None:
        """Release the pool. Idempotent, so shutdown paths need no guards."""
        if self._client is not None:
            await self._client.close()
        self._client = None
        self._db = None

    async def status(self) -> DatabaseStatus:
        """Connectivity as a health check sees it.

        Deliberately returns a value for the unreachable case instead of
        raising: a database that is down is a fact the health endpoint should
        report, not a 500 that looks like the service itself is broken.
        """
        if self._client is None:
            return "disabled"
        try:
            await self._client.admin.command("ping")
            return "ok"
        except Exception:
            logger.warning("MongoDB ping failed", exc_info=True)
            return "unreachable"


def _default_client_factory(uri: str) -> Any:
    """Imported lazily so the module (and the whole app) still imports when
    pymongo is absent — the pre-S8 backend has no reason to require it."""
    from pymongo import AsyncMongoClient

    return AsyncMongoClient(
        uri, serverSelectionTimeoutMS=SERVER_SELECTION_TIMEOUT_MS
    )


database = Database()
