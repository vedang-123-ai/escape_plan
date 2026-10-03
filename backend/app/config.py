"""Runtime configuration from environment variables (the only I/O of its kind).

Secrets never live in code or git: `BACKEND_BEARER_TOKEN` gates every endpoint
except /health, and `ANTHROPIC_API_KEY` is consumed by the AI layer (S3.x).
"""

from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path
from typing import TYPE_CHECKING, Any

from pydantic import BaseModel, ConfigDict, Field

from app.ai.model_support import DEFAULT_MODEL, unsupported_model_reason
from app.routing.egress import EgressThresholds

if TYPE_CHECKING:
    from app.routing.object_hazards import ObjectHazardThresholds

BACKEND_DIR = Path(__file__).resolve().parents[1]
CORPUS_DIR = BACKEND_DIR / "corpus"


class Settings(BaseModel):
    model_config = ConfigDict(frozen=True)

    # repr=False on every secret: one `logger.debug("settings=%s", settings)`
    # would otherwise print the bearer token, the API key and a MongoDB URI
    # complete with its password.
    bearer_token: str = Field(repr=False)
    anthropic_api_key: str | None = Field(default=None, repr=False)
    anthropic_model: str
    mongodb_uri: str | None = Field(default=None, repr=False)
    mongodb_db_name: str
    jwt_secret: str | None = Field(default=None, repr=False)
    jwt_access_ttl_minutes: int
    # AI cost guard (app/rate_limit.py). Every /explain /analyze /build /chat
    # call spends Anthropic credit; these bound what one client, and everyone
    # together, can spend. Defaults suit a one-family demo — tune on Render.
    ai_rate_per_min: float = 6.0
    ai_rate_burst: int = 3
    ai_max_concurrent: int = 4
    # S11.27 (AUD-003). The bearer token ships in every app build and is public,
    # so it bounds nobody's spend. These two do.
    ai_daily_call_budget: int = 1000
    """Anthropic model calls allowed per UTC day, server-wide — MODEL calls, not
    HTTP requests, because /build and /analyze are loops (see BUDGET_COST_* in
    app/rate_limit.py).

    Sized from that unit, not guessed. At BUDGET_COST_BUILD = 40, 1000 is ~25
    photo/text builds a day, or ~333 explain/chat turns, or any mix — roomy for a
    rehearsal day. And it is still a short fuse for abuse: the per-client bucket
    allows 6 requests/min, so a script looping /build spends ~240 units a minute
    and hits the ceiling in about four. 300 would have been only 7 builds, which
    a single filming day could plausibly exhaust."""
    ai_client_ip_header: str = "cf-connecting-ip"
    """A header the infrastructure overwrites, used as the rate-limit key when
    present. Empty string disables it (then the X-Forwarded-For path is used)."""
    ai_trusted_proxy_hops: int = 1
    """How many proxies sit in front of this app, so `client_key` knows how far
    from the RIGHT of X-Forwarded-For the trustworthy entry is. 0 means no proxy:
    use the socket peer, which is correct for a local run."""

    @property
    def auth_enabled(self) -> bool:
        """Whether S8.2 auth can serve requests.

        Auth needs BOTH a database to store users in and a secret to sign with.
        Tracked separately from `cloud_sync_enabled` so a half-configured server
        (database but no JWT secret) fails loudly at the route instead of
        appearing to work and issuing unsigned or unverifiable tokens.
        """
        return self.cloud_sync_enabled and self.jwt_secret is not None

    @property
    def cloud_sync_enabled(self) -> bool:
        """Whether the S8 cloud layer can serve requests.

        Unlike `bearer_token`, a missing `MONGODB_URI` is NOT fatal. The
        deterministic engine, the corpus and every pre-S8 endpoint work with no
        database at all, and the demo path depends on them — so an unconfigured
        Mongo disables cloud sync rather than refusing to start the service.
        """
        return self.mongodb_uri is not None


MIN_JWT_SECRET_BYTES = 32
"""RFC 7518 §3.2: an HMAC key for SHA-256 should be at least the hash output
size. PyJWT warns below this; we refuse, because a short signing secret is
brute-forceable and the warning is easy to miss in a deploy log."""


def _validated_jwt_secret(secret: str | None) -> str | None:
    """Reject a too-short secret loudly at startup rather than signing with it.

    Fails closed on a BAD secret while treating an ABSENT one as "auth off" —
    the same split as MONGODB_URI: not configuring a feature is a choice,
    misconfiguring it is an error.
    """
    if secret is None:
        return None
    if len(secret.encode()) < MIN_JWT_SECRET_BYTES:
        raise RuntimeError(
            f"JWT_SECRET_KEY is too short ({len(secret.encode())} bytes). "
            f"Use at least {MIN_JWT_SECRET_BYTES} bytes of random data, e.g. "
            f"`python3 -c 'import secrets; print(secrets.token_urlsafe(48))'`."
        )
    return secret


def _validated_anthropic_model(model: str) -> str:
    """Refuse a model the AI layer's requests would 400 on, at startup.

    Every not-live test injects a stub client, so `ANTHROPIC_MODEL=claude-fable-5-1`
    used to pass the whole suite and then break /explain on the first real call
    (forced tool_choice is rejected there). The supported set and the reasons live
    next to the code that sends those parameters, in app/ai/model_support.py.
    """
    reason = unsupported_model_reason(model)
    if reason is not None:
        raise RuntimeError(reason)
    return model


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Load settings once per process. `BACKEND_BEARER_TOKEN` is required so the
    service can never start unauthenticated by accident."""
    token = os.environ.get("BACKEND_BEARER_TOKEN", "")
    if not token:
        raise RuntimeError(
            "BACKEND_BEARER_TOKEN is not set — refusing to start an open backend."
        )
    return Settings(
        bearer_token=token,
        anthropic_api_key=os.environ.get("ANTHROPIC_API_KEY") or None,
        anthropic_model=_validated_anthropic_model(
            os.environ.get("ANTHROPIC_MODEL") or DEFAULT_MODEL
        ),
        mongodb_uri=os.environ.get("MONGODB_URI") or None,
        mongodb_db_name=os.environ.get("MONGODB_DB_NAME", "escape_plan"),
        # No default and no generated fallback, on purpose. A per-process random
        # secret would "work" in testing and then invalidate every token on each
        # restart and on every replica — the kind of bug that looks like a
        # flaky login. Absent secret = auth disabled, loudly.
        jwt_secret=_validated_jwt_secret(os.environ.get("JWT_SECRET_KEY") or None),
        jwt_access_ttl_minutes=int(os.environ.get("JWT_ACCESS_TTL_MINUTES", "60")),
        ai_rate_per_min=_positive_number("AI_RATE_PER_MIN", "6", float),
        ai_rate_burst=_positive_number("AI_RATE_BURST", "3", int),
        ai_max_concurrent=_positive_number("AI_MAX_CONCURRENT", "4", int),
        ai_daily_call_budget=_positive_number("AI_DAILY_CALL_BUDGET", "1000", int),
        # Not _positive_number: an empty value is meaningful (disable the header)
        # and lowercased because ASGI header lookups are case-insensitive but the
        # comparison in client_key is not.
        ai_client_ip_header=os.environ.get("AI_CLIENT_IP_HEADER", "cf-connecting-ip")
        .strip()
        .lower(),
        # Not _positive_number either: 0 is the valid "no proxy" setting.
        ai_trusted_proxy_hops=_non_negative_int("AI_TRUSTED_PROXY_HOPS", "1"),
    )


def _non_negative_int(name: str, default: str) -> int:
    """Read an int env var that may legitimately be zero.

    `_positive_number` refuses 0 because a zero rate or semaphore size would brick
    the AI routes. A zero proxy-hop count is not that: it is the correct setting
    for running with no proxy in front, so it needs its own reader rather than a
    relaxation of the other one.
    """
    raw = os.environ.get(name) or default
    try:
        value = int(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name}={raw!r} is not an integer") from exc
    if value < 0:
        raise RuntimeError(f"{name} must be zero or greater, got {raw!r}")
    return value


def _positive_number(name: str, default: str, kind: type[int] | type[float]) -> Any:
    """Read a positive int/float env var, failing at startup on nonsense.

    A zero or negative limit would silently turn every AI route into a 429 (or,
    for the semaphore, a crash on the first request), so refuse it up front the
    way a short JWT secret is refused.
    """
    raw = os.environ.get(name) or default
    try:
        value = kind(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name}={raw!r} is not a number") from exc
    if value <= 0:
        raise RuntimeError(f"{name} must be positive, got {raw!r}")
    return value


@lru_cache(maxsize=1)
def get_thresholds() -> EgressThresholds:
    """Egress thresholds from the corpus (metric authoritative), loaded once."""
    data = json.loads((CORPUS_DIR / "egress_thresholds.json").read_text())
    return EgressThresholds.from_corpus(data)

@lru_cache(maxsize=1)
def get_object_hazard_thresholds() -> ObjectHazardThresholds:
    """Object hazard thresholds from the corpus, loaded once."""
    # Runtime import to break the import cycle (config → object_hazards → models → …).
    # The type annotation uses the TYPE_CHECKING import at module level.
    from app.routing.object_hazards import ObjectHazardThresholds as _OHT
    data = json.loads((CORPUS_DIR / "object_hazard_thresholds.json").read_text())
    return _OHT.model_validate(data)
