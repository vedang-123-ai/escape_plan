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

- `ai_budget` (S11.27) — a global ceiling on AI calls per UTC day, whoever makes
  them. Exhausted is 429. This is the one limit a client cannot reset: see below.

All three are in memory and per process. That is the right size for a single free
Render instance; more instances would each enforce their own limits, which is a
known and acceptable over-allowance, not a bypass. The deterministic routes
(/routes, /score without recommendations, ...) are deliberately NOT limited —
they cost CPU, not credit, and the demo path depends on them.

WHY A DAILY BUDGET AND NOT JUST THE PER-CLIENT BUCKET (S11.27, AUD-003)
-----------------------------------------------------------------------
The bearer token ships inside every app build, so it is public: it identifies the
app, not the caller. The per-client bucket was therefore the only thing standing
between a leaked token and the credit balance, and it keyed on a value the caller
sets. Both halves of that are fixed here — the key is no longer client-supplied
(below), and the daily budget bounds total spend even if the key is defeated,
because it counts every AI call regardless of who makes it. The account has run
dry once already.

A restart resets the counter. That is accepted and not hidden: on one free Render
instance a restart is rare, and the alternative (persisting in Mongo) would attach
spend control to a database the demo trim is switching off. If the service is ever
run as several instances, each enforces its own budget and the effective ceiling
multiplies by the instance count.

CHOOSING THE CLIENT KEY (S11.27)
--------------------------------
The previous key was the FIRST `X-Forwarded-For` hop, which a caller controls
outright: Render's own FastAPI guidance calls trusting that "a critical
vulnerability, allowing bad actors to spoof their IP address", so a script got a
fresh bucket per request simply by varying the header. Confirmed from Render's
documentation 2026-10-03: "All inbound traffic to Render web services passes
through Cloudflare's global network before reaching your application", and
proxies APPEND to `X-Forwarded-For` — so the trustworthy hops are at the RIGHT
end of the list and the left end is whatever the caller invented.

`client_key` therefore prefers a header the infrastructure overwrites
(`CF-Connecting-IP`, which Cloudflare sets on every proxied request), and falls
back to counting in from the right of `X-Forwarded-For` by the number of proxy
hops in front of the app. Both are configurable, so nothing here depends on a
vendor detail staying true: set `AI_TRUSTED_PROXY_HOPS=0` for a local run with no
proxy and the socket peer is used instead.
"""

from __future__ import annotations

import math
import threading
import time
from collections.abc import AsyncIterator, Callable
from datetime import date, datetime, time as dt_time, timedelta, timezone

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
    """The client's IP, from a source the client cannot choose.

    In order:

    1. The trusted header (`AI_CLIENT_IP_HEADER`, default `cf-connecting-ip`).
       Cloudflare writes it on every proxied request and overwrites whatever the
       caller sent, so it is both accurate and outside the caller's control.
    2. `X-Forwarded-For`, counted from the RIGHT by `AI_TRUSTED_PROXY_HOPS`.
       Proxies append, so with one proxy in front the last entry is the one that
       proxy observed, and everything to its left is caller-supplied. Asking for
       more hops than the list holds falls back to the leftmost entry rather than
       indexing off the end -- that is the most conservative reading available,
       and it is also what a correctly configured deployment never hits.
    3. The socket peer, for a local run with no proxy at all
       (`AI_TRUSTED_PROXY_HOPS=0`).

    Returning the same constant for every unidentifiable caller is deliberate:
    they share one bucket rather than each getting a fresh one.
    """
    settings = get_settings()

    trusted_header = settings.ai_client_ip_header
    if trusted_header:
        value = request.headers.get(trusted_header, "").strip()
        if value:
            return value

    hops = settings.ai_trusted_proxy_hops
    if hops > 0:
        forwarded = request.headers.get("x-forwarded-for", "")
        entries = [part.strip() for part in forwarded.split(",") if part.strip()]
        if entries:
            index = max(0, len(entries) - hops)
            return entries[index]

    return request.client.host if request.client else "unknown"


# How many Anthropic `messages.create` calls one request to each route can make.
#
# THIS IS THE UNIT THE BUDGET COUNTS, and getting it wrong is how the first
# version of this module shipped a ceiling ~40x weaker than its own docstring
# claimed. A budget unit is not one HTTP request: `/build` and `/analyze` are
# tool-use LOOPS, so one request to either makes many model calls, each paying
# full input price (neither loop uses prompt caching). 300 requests to /build
# would have been ~12,000 model calls.
#
# Mirrored from the loops rather than imported, to keep this module free of any
# dependency on `app.ai`. `test_ai_budget.py` asserts they stay in lockstep, so
# raising MAX_ITERATIONS without revisiting the cost fails a test rather than
# quietly multiplying the bill.
BUDGET_COST_BUILD = 40
"""`app.ai.builder.MAX_ITERATIONS`."""

BUDGET_COST_ANALYZE = 17
"""`app.ai.agent.MAX_ITERATIONS` (15) + `MAX_SUBMIT_RETRIES` (2)."""

BUDGET_COST_SINGLE_CALL = 3
"""/explain, /chat and /score's recommendations: one call plus up to two
citation retries. Charged by the dependency as the base cost, because it is
also the floor for the loop routes."""


class DailyAICallBudget:
    """A process-wide ceiling on Anthropic model calls per UTC day (S11.27,
    AUD-003).

    Counts CALLS, not tokens. Debiting real token usage would mean every AI
    module reporting its `response.usage` back here, and `app/ai/` is outside
    this session's owned files -- there is a BLOCKERS line for it. A call count
    bounds spend because every call site caps its own `max_tokens`; what it
    cannot see is that a long call costs more than a short one.

    The day boundary is UTC so the ceiling does not shift with the server's
    timezone, and so "today" means the same thing in a log and in /health. The
    clock is injectable for the same reason the token bucket's is: tests move
    time instead of sleeping.
    """

    def __init__(self, clock: Callable[[], datetime] | None = None) -> None:
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._lock = threading.Lock()
        self._day: date | None = None
        self._spent = 0

    def _roll(self) -> None:
        """Reset the counter when the UTC day changes. Caller holds the lock."""
        today = self._clock().date()
        if self._day != today:
            self._day = today
            self._spent = 0

    def spend(self, limit: int, cost: int = 1) -> bool:
        """Charge `cost` model calls. True if within budget, False if exhausted.

        All-or-nothing under the lock: a charge that would exceed the limit is
        refused outright rather than partially applied, so a caller can never be
        told "no" and billed anyway.
        """
        with self._lock:
            self._roll()
            if self._spent + cost > limit:
                return False
            self._spent += cost
            return True

    def remaining(self, limit: int) -> int:
        with self._lock:
            self._roll()
            return max(0, limit - self._spent)

    def spent_today(self) -> int:
        with self._lock:
            self._roll()
            return self._spent

    def reset(self) -> None:
        with self._lock:
            self._day = None
            self._spent = 0


budget = DailyAICallBudget()


def _seconds_until_utc_midnight(now: datetime) -> float:
    """How long until the budget rolls over, for `Retry-After`.

    Telling a client to come back in 5 s when the budget is spent for the day
    would just produce a retry loop against a wall.
    """
    tomorrow = datetime.combine(
        now.date() + timedelta(days=1), dt_time.min, tzinfo=timezone.utc
    )
    return max(1.0, (tomorrow - now).total_seconds())


def _too_many(detail: str, retry_after_s: float) -> HTTPException:
    return HTTPException(
        status_code=429,
        detail=detail,
        headers={"Retry-After": str(max(1, math.ceil(retry_after_s)))},
    )


def enforce_rate_limit(request: Request) -> None:
    """Charge the per-client bucket, raising 429 if it is empty.

    Sync and separate from the dependency below so `/score`'s conditional AI call
    enforces the SAME limit through the SAME code (app/deps.py). Two
    implementations of one limit is how `/score` came to spend credit outside the
    guard in the first place (AUD-006).
    """
    settings = get_settings()
    wait = limiter.take(
        client_key(request), settings.ai_rate_per_min, settings.ai_rate_burst
    )
    if wait is not None:
        raise _too_many(
            "Too many AI requests from this device. Please wait and try again.", wait
        )


def enforce_budget(cost: int = 1) -> None:
    """Charge `cost` against the daily budget, raising 429 if it will not fit.

    Called twice for the loop routes: once by the `ai_budget` dependency for the
    base cost, and once more inside the handler for the remainder, AFTER the
    request has been validated. That split is deliberate. The dependency runs
    BEFORE body validation (measured 2026-10-03: a malformed `/build` already
    charges), so charging a loop route's full weight there would let eight
    malformed requests switch the AI off for the day. The base cost alone still
    bounds a flood of junk; the expensive part is only charged once the request
    is real.
    """
    settings = get_settings()
    if not budget.spend(settings.ai_daily_call_budget, cost):
        raise _too_many(
            "The daily AI limit for this server has been reached. Routes, "
            "scores and the rest of the app still work; only AI features are "
            "paused until the limit resets.",
            _seconds_until_utc_midnight(datetime.now(timezone.utc)),
        )


def busy_exception() -> HTTPException:
    """The 429 for "every AI slot is in use"."""
    return _too_many(
        "The assistant is busy right now. Please try again in a moment.",
        CONCURRENCY_RETRY_AFTER_S,
    )


async def ai_rate_limit(request: Request) -> None:
    """Per-client token bucket. Declare AFTER `require_token`, so a request
    without the token is a 401 and never spends anyone's budget."""
    enforce_rate_limit(request)


async def ai_budget() -> None:
    """Global daily ceiling on AI calls. Declare AFTER `require_token`, so an
    unauthenticated request never spends the day's budget.

    Charges BUDGET_COST_SINGLE_CALL, the floor every AI route pays. `/build`
    and `/analyze` are loops and charge their remainder in the handler, once the
    request has been validated -- see `enforce_budget`.

    Charged on ENTRY, not on success. A call that reaches Anthropic and then
    fails has usually already cost credit, and a budget that refunded failures
    would let a loop of failing calls run unbounded -- which is the exact shape
    of the incident that drained the account.
    """
    enforce_budget(BUDGET_COST_SINGLE_CALL)


async def ai_concurrency() -> AsyncIterator[None]:
    """Global in-flight cap; the slot is held until the endpoint returns."""
    semaphore = gate.semaphore(get_settings().ai_max_concurrent)
    if not semaphore.acquire(blocking=False):
        raise busy_exception()
    try:
        yield
    finally:
        semaphore.release()
