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
import time
from typing import Any, Callable, Literal

from app.config import get_settings

logger = logging.getLogger(__name__)

# The driver default is 30s. On an unreachable host that turns /health/db into a
# 30-second hang, which is useless to a health check and to a human debugging it.
SERVER_SELECTION_TIMEOUT_MS = 3000

# Unset by default, meaning a caller waits forever for a pool connection. /health/db
# is unauthenticated, so without this a flood of health checks could exhaust the pool
# and make authenticated requests queue indefinitely rather than fail fast.
WAIT_QUEUE_TIMEOUT_MS = 5000

# `status()` is reachable without a token, and each call is a real pool checkout.
# Caching collapses N concurrent probes into one ping, so an open endpoint cannot be
# used to amplify load against the database (or to pin request workers for 3s each
# while the database is down).
STATUS_CACHE_TTL_S = 5.0

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
        self._status_cache: tuple[float, DatabaseStatus] | None = None

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
        """Create the client if `MONGODB_URI` is set. **Never raises.**

        A missing URI is the supported 'cloud sync off' configuration, and a
        *malformed* one must behave the same way. `AsyncMongoClient` validates
        eagerly in its constructor, so an Atlas password pasted in with an
        unescaped `@` raises `InvalidURI` here — and an uncaught raise in the
        lifespan handler means uvicorn never serves a single request, `/health`
        included. A credential typo for an unbuilt feature would take down the
        routing engine and the whole demo path. Hence: catch, disable, log.

        Note this does NOT prove the server is reachable: PyMongo connects
        lazily, so a bad *host* surfaces on `ping`, not here.
        """
        if self._client is not None:
            logger.warning("connect() called with a client already open; ignoring")
            return

        settings = get_settings()
        if not settings.cloud_sync_enabled:
            logger.info("MONGODB_URI not set — cloud sync disabled")
            return

        assert settings.mongodb_uri is not None  # implied by cloud_sync_enabled
        factory = client_factory or _default_client_factory
        client: Any | None = None
        try:
            client = factory(settings.mongodb_uri)
            db = client[settings.mongodb_db_name]
        except Exception:
            # exc_info is safe here: pymongo's URI/name errors carry host and
            # port but never the username or password — verified against the
            # driver, including the unescaped-password case. The URI itself is
            # never passed to the logger.
            logger.error(
                "could not initialise the MongoDB client — cloud sync disabled. "
                "Check MONGODB_URI (percent-escape credentials) and MONGODB_DB_NAME",
                exc_info=True,
            )
            if client is not None:
                # The client was built before the failure; its monitor tasks
                # would leak, and lifespan's `finally` will not see it.
                try:
                    await client.close()
                except Exception:
                    logger.warning("could not close a half-built client", exc_info=True)
            return

        self._client = client
        self._db = db
        logger.info("cloud sync enabled, database %r", settings.mongodb_db_name)

    async def close(self) -> None:
        """Release the pool. Idempotent, so shutdown paths need no guards.

        State is cleared *before* the await: if `close()` raises, this object
        must not keep reporting `enabled` for a client that is already gone.
        """
        client = self._client
        self._client = None
        self._db = None
        self._status_cache = None
        if client is not None:
            await client.close()

    async def status(self) -> DatabaseStatus:
        """Connectivity as a health check sees it, cached for STATUS_CACHE_TTL_S.

        Deliberately returns a value for the unreachable case instead of
        raising: a database that is down is a fact the health endpoint should
        report, not a 500 that looks like the service itself is broken.
        """
        if self._client is None:
            return "disabled"

        if self._status_cache is not None:
            cached_at, cached = self._status_cache
            if time.monotonic() - cached_at < STATUS_CACHE_TTL_S:
                return cached

        try:
            await self._client.admin.command("ping")
            result: DatabaseStatus = "ok"
        except Exception:
            logger.warning("MongoDB ping failed", exc_info=True)
            result = "unreachable"

        self._status_cache = (time.monotonic(), result)
        return result


def _default_client_factory(uri: str) -> Any:
    """Imported lazily so the module (and the whole app) still imports when
    pymongo is absent — the pre-S8 backend has no reason to require it."""
    from pymongo import AsyncMongoClient

    return AsyncMongoClient(
        uri,
        # Without this, BSON dates decode naive and every timestamp written by
        # this layer comes back unequal to what was stored — including the
        # `meta.created` inside an embedded HomeModel, which would make a
        # round-tripped home compare unequal to the original.
        tz_aware=True,
        serverSelectionTimeoutMS=SERVER_SELECTION_TIMEOUT_MS,
        waitQueueTimeoutMS=WAIT_QUEUE_TIMEOUT_MS,
    )


database = Database()
