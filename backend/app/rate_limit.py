"""AI cost guard: a per-client token bucket plus a global concurrency cap.

Every `/explain`, `/analyze`, `/build` and `/chat` call spends Anthropic credit,
and the bearer token is shared by every install of the app — so the token alone
cannot stop one misbehaving client (or one leaked token) from draining the
account. Two FastAPI dependencies bound that, with no new dependency and no
external store:

- `ai_rate_limit` — a token bucket per client IP: `AI_RATE_BURST` calls at once,
  refilling at `AI_RATE_PER_MIN`. Over the limit is 429 with `Retry-After`.
- `ai_concurrency` — a process-wide `BoundedSemaphore` of `AI_MAX_CONCURRENT`
  in-flight AI calls, whoever makes them. Full is 429 with `Retry-After`,
  immediately: a request never queues holding a worker thread.

Both are in memory and per process. That is the right size for a single free
Render instance; more instances would each enforce their own limits, which is a
known and acceptable over-allowance, not a bypass. The deterministic routes
(/routes, /score, ...) are deliberately NOT limited — they cost CPU, not credit,
and the demo path depends on them.

Keying on IP honours the first `X-Forwarded-For` hop because Render terminates
TLS at a proxy, so `request.client.host` is the proxy for every caller. The
first hop is client-supplied and can be forged; a forger gets their own bucket
but still cannot get past the global semaphore, which is why both exist.
"""

from __future__ import annotations

import math
import threading
import time
from collections.abc import AsyncIterator, Callable

from fastapi import HTTPException, Request

from app.config import get_settings

CONCURRENCY_RETRY_AFTER_S = 5
"""What to tell a client turned away because every AI slot is busy. An AI call
takes roughly 5-30 s; asking again after a few seconds is a fair first guess."""


class TokenBucketLimiter:
    """Thread-safe token buckets keyed by an arbitrary string (the client IP).

    Pure bookkeeping — the clock is injectable so tests can move time without
    sleeping.
    """

    def __init__(
        self, clock: Callable[[], float] = time.monotonic, max_keys: int = 10_000
    ) -> None:
        self._clock = clock
        self._max_keys = max_keys
        self._lock = threading.Lock()
        # key -> (tokens available, time they were counted)
        self._buckets: dict[str, tuple[float, float]] = {}

    def take(self, key: str, rate_per_min: float, burst: int) -> float | None:
        """Spend one token for `key`. Returns None if allowed, else the seconds
        until a token will be available (for `Retry-After`)."""
        rate_per_s = rate_per_min / 60.0
        now = self._clock()
        with self._lock:
            tokens, then = self._buckets.get(key, (float(burst), now))
            tokens = min(float(burst), tokens + (now - then) * rate_per_s)
            if tokens >= 1.0:
                self._buckets[key] = (tokens - 1.0, now)
                self._prune(now, rate_per_s, burst)
                return None
            self._buckets[key] = (tokens, now)
            return (1.0 - tokens) / rate_per_s

    def _prune(self, now: float, rate_per_s: float, burst: int) -> None:
        """Bound memory: a bucket that has refilled completely is identical to
        an absent one, so drop those once the table grows large."""
        if len(self._buckets) <= self._max_keys:
            return
        full_after = burst / rate_per_s
        self._buckets = {
            k: v for k, v in self._buckets.items() if now - v[1] < full_after
        }

    def reset(self) -> None:
        with self._lock:
            self._buckets.clear()


class ConcurrencyGate:
    """A global cap on in-flight AI calls, sized from settings.

    The semaphore is rebuilt if the configured size changes (tests change it; a
    deploy restarts the process anyway). Each holder releases the exact
    semaphore it acquired, so a rebuild can never over-release the new one.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._size: int | None = None
        self._semaphore: threading.BoundedSemaphore | None = None

    def semaphore(self, size: int) -> threading.BoundedSemaphore:
        with self._lock:
            if self._semaphore is None or self._size != size:
                self._semaphore = threading.BoundedSemaphore(size)
                self._size = size
            return self._semaphore

    def reset(self) -> None:
        with self._lock:
            self._semaphore = None
            self._size = None


limiter = TokenBucketLimiter()
gate = ConcurrencyGate()


def client_key(request: Request) -> str:
    """The client's IP: the first `X-Forwarded-For` hop when present (Render's
    proxy), else the socket peer."""
    forwarded = request.headers.get("x-forwarded-for", "")
    first_hop = forwarded.split(",")[0].strip()
    if first_hop:
        return first_hop
    return request.client.host if request.client else "unknown"


def _too_many(detail: str, retry_after_s: float) -> HTTPException:
    return HTTPException(
        status_code=429,
        detail=detail,
        headers={"Retry-After": str(max(1, math.ceil(retry_after_s)))},
    )


async def ai_rate_limit(request: Request) -> None:
    """Per-client token bucket. Declare AFTER `require_token`, so a request
    without the token is a 401 and never spends anyone's budget."""
    settings = get_settings()
    wait = limiter.take(
        client_key(request), settings.ai_rate_per_min, settings.ai_rate_burst
    )
    if wait is not None:
        raise _too_many(
            "Too many AI requests from this device. Please wait and try again.", wait
        )


async def ai_concurrency() -> AsyncIterator[None]:
    """Global in-flight cap; the slot is held until the endpoint returns."""
    semaphore = gate.semaphore(get_settings().ai_max_concurrent)
    if not semaphore.acquire(blocking=False):
        raise _too_many(
            "The assistant is busy right now. Please try again in a moment.",
            CONCURRENCY_RETRY_AFTER_S,
        )
    try:
        yield
    finally:
        semaphore.release()
