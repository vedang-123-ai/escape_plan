"""The one place an Anthropic client is built, and the wall-clock deadline every AI loop obeys.

Why this exists (S11.29, AUD-035): every AI module used to build `anthropic.Anthropic(api_key=...)`
with the SDK defaults, a 600 s timeout and 2 retries. The endpoints are synchronous, so a slow
`/build` kept iterating (up to 40 model calls) after the phone had already given up and thrown the
answer away, and the user's Retry started a second loop on top of it.

A synchronous endpoint cannot be cancelled when the phone disconnects, so "stop when the phone gives
up" is a server-side wall-clock deadline a few seconds UNDER the phone's own timeout. The loops check
it before every model call, citation retries and submit retries included.
"""

from __future__ import annotations

import time
from typing import Any, Callable, Optional

import anthropic

# --- the numbers -------------------------------------------------------------
#
# Each deadline sits under the matching iOS `request.timeoutInterval`
# (escape_plan/Networking, checked 2026-10-04). Change them HERE only.

BUILD_DEADLINE_S = 170.0
"""iOS /build waits 180 s (APIClient+Build.swift)."""

ANALYZE_DEADLINE_S = 80.0
"""iOS /analyze waits 90 s (APIClient+Analyze.swift)."""

CHAT_DEADLINE_S = 110.0
"""iOS /chat waits 120 s (`APIClient.chatTimeout`, APIClient+Chat.swift; raised from 60 s by S11.37,
AUD-032). Keep this about 10 s under that number: change both together."""

EXPLAIN_DEADLINE_S = 60.0
"""No iOS screen calls /explain directly. /score with `include_recommendations` reaches it through
`scoring/recommend.py`, and the phone waits 90 s for /score (APIClient+Score.swift)."""

MAX_RETRIES = 1
"""SDK retries per call (it defaults to 2). One covers a dropped connection or a 429 blip."""

MIN_START_S = 20.0
"""Do not START a model call with less than this left. One attempt gets half the remaining time
and the SDK may retry once, so with 20 s or more left attempt + retry fit inside the budget.
A normal call here (thinking disabled, max_tokens <= 4096) takes well under 10 s."""

CONNECT_TIMEOUT_S = 5.0


class DeadlineExceeded(Exception):
    """The request's wall-clock budget ran out before the next model call could start (or finish).

    The endpoint maps it to a 504 with a plain sentence. It is never a safety answer and never a
    half-built result: the builder raises it instead of returning a partial home.
    """


class Deadline:
    """A monotonic wall-clock budget for one request.

    `clock` is injectable so tests can move time without sleeping.
    """

    def __init__(
        self, seconds: float, *, clock: Callable[[], float] = time.monotonic
    ) -> None:
        self._clock = clock
        self._end = clock() + seconds
        self.seconds = seconds

    def remaining(self) -> float:
        return self._end - self._clock()

    def expired(self) -> bool:
        return self.remaining() <= 0

    def can_start(self) -> bool:
        """True when a model call could usefully start now. The one threshold every loop uses."""
        return self.remaining() >= MIN_START_S

    def require_time(self, what: str) -> None:
        """Raise DeadlineExceeded unless a model call could usefully start now."""
        if not self.can_start():
            raise DeadlineExceeded(
                f"{what} ran out of time ({self.seconds:.0f} s budget) before the "
                "next AI call could start"
            )

    def attempt_timeout(self) -> float:
        """Seconds one HTTP attempt may take: half of what is left.

        The SDK may retry once, and a retry that restarted the full remaining time would double
        the overrun. Callers start only when `can_start()` (>= MIN_START_S left), so with
        MAX_RETRIES = 1 attempt + retry stay inside the budget, plus a sub-second back-off.
        """
        return self.remaining() / 2


def build_client(api_key: str) -> anthropic.Anthropic:
    """The shared factory: explicit timeout and a single retry instead of SDK defaults."""
    return anthropic.Anthropic(
        api_key=api_key,
        timeout=anthropic.Timeout(BUILD_DEADLINE_S, connect=CONNECT_TIMEOUT_S),
        max_retries=MAX_RETRIES,
    )


def create_message(
    client: Any, deadline: Optional[Deadline], what: str, **kwargs: Any
) -> Any:
    """`client.messages.create` bounded by `deadline`.

    Every model call in the AI layer goes through here, so the deadline is checked before every
    call, including citation and submit retries. `client` may be a test stub; it only needs a
    `messages.create(**kwargs)`.
    """
    if deadline is not None:
        deadline.require_time(what)
        # Keep the short connect timeout: a bare float would apply to connect too.
        kwargs["timeout"] = anthropic.Timeout(
            deadline.attempt_timeout(), connect=CONNECT_TIMEOUT_S
        )
    return client.messages.create(**kwargs)
