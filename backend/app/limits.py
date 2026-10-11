"""Request size limits and input caps (S11.26; AUD-004 body half, AUD-035 caps
half, AUD-024 server half).

Before this module nothing limited a request body, so the server parsed whatever
arrived, and the AI inputs were unbounded: a description or chat thread of any
length, and an image of any size labelled with any media type, forwarded to
Anthropic unchecked.

Every limit lives here as a named constant because other sessions read them:
S11.33 (the client transcodes photos to JPEG) and S11.45 (the client trims chat
history) have to agree with the server, and the editor already mirrors the
geometry bounds in `EditorValidation.swift`. One module means one place to change.

HOW THE BODY LIMITS WERE CHOSEN (measured 2026-10-03, not guessed)
-----------------------------------------------------------------
The binding question is not "how big is a fixture" (the largest committed one is
14 KB) but "how big can a request the server MUST accept be". That ceiling is
already set by the S11.25 geometry bounds in `app.models`, so the maximum legal
home was constructed at every bound simultaneously -- MAX_ROOMS rooms of
MAX_POLYGON_VERTICES vertices, MAX_OPENINGS_PER_FLOOR x MAX_FLOORS openings,
MAX_OBJECTS_TOTAL objects, MAX_SAFETY_POINTS_PER_FLOOR x MAX_FLOORS points,
MAX_STAIRS stairs, MAX_PROFILES profiles, with long converter-style decimals and
full-length ids -- and measured:

    maximum bounds-valid home, compact JSON : 1,649,482 bytes (1.65 MB)
    maximum bounds-valid home, pretty JSON  : 1,780,354 bytes (1.78 MB)

(MAX_TOTAL_GRID_CELLS is the bound that binds first: 200 rooms only fit if each
is small. A home one byte larger than this is rejected by `HomeModel` anyway, so
it never reaches the body limit.)

A home is NOT the whole body, though, and an earlier draft of this comment quoted
the home-only figure as if it were. `/explain` and `/chat` send `home` plus a
`route_plan` plus `profiles`, so the worst case had to be measured on the real
combination rather than extrapolated from one term:

    that home's route_plan                 :   273,048 bytes
    its profiles, sent again separately    :    10,340 bytes
    --> /chat worst case                   : 2,063,742 bytes (2.06 MB)
        vs MAX_BODY_BYTES_DEFAULT          : 4.06x headroom

Extrapolating would have been wrong in an interesting direction: on the small
fixtures a route_plan runs ~1.9x the home it describes, which predicts a ~5.3 MB
body, but at the maximum it is 0.17x. The ratio inverts because a maximal home is
dominated by 200 room polygons and 3,200 openings while its route plan still
describes only a handful of paths. Vary each input independently, then measure the
combination.

`RoutePlan`'s lists carry explicit length caps matching the style of `models.py`
(see `app/routing/plan.py` and `MAX_ROUTE_*` below): `MAX_ROUTE_ROOMS` (200),
`MAX_ROUTE_WAYPOINTS` (1000), `MAX_ROUTE_BOTTLENECKS` (200), and `MAX_ROUTE_FINDINGS_PER_ROOM` (50).
A hand-written or corrupted `route_plan` payload cannot allocate unbounded lists.

The remaining headroom is deliberate: this session ships BEFORE the client-side
trimming (S11.45) and transcoding (S11.33), so a limit chosen tight against
today's measurement would reject real requests in the gap between sessions.

WHY 413 AND 422 RATHER THAN TRUNCATION
--------------------------------------
Both are refusals the client can act on and show a person. Silently truncating a
chat history or an image would make the model answer about something other than
what the user sent, which on a safety app is worse than an error: the reply would
look authoritative and be about the wrong house. S11.45 trims client-side, where
the user can see what was dropped.

Note on ordering: the body limit is middleware, so an oversized body is refused
with 413 BEFORE the bearer-token dependency runs, and an unauthenticated caller
sees 413 rather than 401. That is the point -- refuse early, before parsing or
paying -- and it discloses nothing, since the limit is the same for every caller.
"""

from __future__ import annotations

import base64
import binascii
from typing import Awaitable, Callable, Literal, Optional

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

# --------------------------------------------------------------------------
# Body size
# --------------------------------------------------------------------------

MAX_BODY_BYTES_DEFAULT = 8 * 1024 * 1024
"""8 MiB: every route except /build. ~4.5x the 1.78 MB maximum legal home."""

MAX_BODY_BYTES_BUILD = 16 * 1024 * 1024
"""16 MiB: /build alone, which carries a base64 image. Has to hold
MAX_IMAGE_B64_CHARS (10 MB) plus a description plus JSON overhead."""

BODY_LIMIT_OVERRIDES: dict[str, int] = {"/build": MAX_BODY_BYTES_BUILD}
"""Per-path exceptions to MAX_BODY_BYTES_DEFAULT, keyed by exact path."""

BODYLESS_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})
"""Never measured, so /health stays open and cheap (a RULE of this session)."""

# --------------------------------------------------------------------------
# /build inputs (AUD-024, AUD-035)
# --------------------------------------------------------------------------

MAX_BUILD_DESCRIPTION_CHARS = 20_000
"""A typed description of a home. Generous on purpose: the text builder is the
accessibility fallback for phones without LiDAR, so a person who describes their
house in detail must not be cut off."""

ALLOWED_IMAGE_MEDIA_TYPES: tuple[str, ...] = (
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
)
"""Exactly the types the Anthropic Messages API accepts, confirmed against
https://platform.claude.com/docs/en/build-with-claude/vision on 2026-10-03.

HEIC is deliberately absent: it is what an iPhone camera produces and what the
photo path used to send while labelling it image/png (AUD-024). Anthropic answers
400, which the app turned into "AI unavailable", so the user blamed the AI. The
server now names the real problem; S11.33 makes the client send real JPEG."""

ImageMediaType = Literal["image/jpeg", "image/png", "image/gif", "image/webp"]
"""Pydantic form of ALLOWED_IMAGE_MEDIA_TYPES. Keep the two in step."""

MAX_IMAGE_B64_CHARS = 10_000_000
"""Anthropic's documented per-image maximum is 10 MB *base64-encoded*, so the cap
belongs on the encoded string, which is what we forward and what they measure.
(Their 5 MB figure is Amazon Bedrock and Google Cloud; the audit quoted that one
from memory. We call the API directly.)"""

MAX_IMAGE_DECODED_BYTES = MAX_IMAGE_B64_CHARS // 4 * 3
"""~7.5 MB, the decoded size of MAX_IMAGE_B64_CHARS. Derived, not independent:
checked only so a string that is within the encoded cap but decodes to something
larger than it claims cannot slip through."""

# --------------------------------------------------------------------------
# /chat inputs (AUD-035)
# --------------------------------------------------------------------------

MAX_CHAT_MESSAGES = 40
"""Turns in one request. The whole corpus is in the system prompt, so history is
what grows; 40 is a long conversation about one house."""

MAX_CHAT_MESSAGE_CHARS = 8_000
"""One message. Longer than anyone types and shorter than a pasted document."""

# --------------------------------------------------------------------------
# RoutePlan nested collection bounds (A06-05)
# --------------------------------------------------------------------------

MAX_ROUTE_WAYPOINTS = 1000
"""Maximum waypoints on a single Route. Real smoothed routes across multi-floor
homes have dozens of waypoints; 1,000 provides ample headroom while bounding memory."""

MAX_ROUTE_FINDINGS_PER_ROOM = 50
"""Maximum RouteFinding entries per RoomRoutePlan."""

MAX_ROUTE_FINDING_OBJECTS = 50
"""Maximum blaming object IDs attached to a single RouteFinding."""

MAX_ROUTE_BOTTLENECK_DISCONNECTED_ROOMS = 200
"""Maximum disconnected room IDs per Bottleneck, matching MAX_ROOMS."""

MAX_ROUTE_BOTTLENECKS = 200
"""Maximum Bottleneck entries on a RoutePlan."""

MAX_ROUTE_ROOMS = 200
"""Maximum RoomRoutePlan entries on a RoutePlan, matching MAX_ROOMS."""

MAX_CHAT_TOTAL_CHARS = 100_000
"""Every message summed (~25k tokens). MAX_CHAT_MESSAGES x MAX_CHAT_MESSAGE_CHARS
would be 320k, so this binds first and is the real cost ceiling."""


def body_limit_for_path(path: str) -> int:
    """The limit that applies to `path`."""
    return BODY_LIMIT_OVERRIDES.get(path, MAX_BODY_BYTES_DEFAULT)


def decoded_image_bytes(image_b64: str) -> int:
    """Decoded length of `image_b64`, or raise ValueError if it is not base64.

    `validate=True` so a mislabelled or truncated payload is caught here rather
    than being forwarded and paid for.
    """
    try:
        return len(base64.b64decode(image_b64, validate=True))
    except (binascii.Error, ValueError) as exc:
        raise ValueError(
            "image_b64 is not valid base64. Encode the image bytes as standard "
            "base64 with no data: prefix and no newlines."
        ) from exc


def _too_large_response(limit: int) -> JSONResponse:
    """413 naming the limit, so a client can tell the user what to do."""
    return JSONResponse(
        status_code=413,
        content={
            "detail": (
                f"Request body too large. This endpoint accepts at most "
                f"{limit:,} bytes."
            )
        },
    )


class BodySizeLimitMiddleware:
    """Refuse an oversized body with 413 before anything parses it.

    Written as raw ASGI rather than `BaseHTTPMiddleware` on purpose: the
    BaseHTTPMiddleware route would have to `await request.body()` to measure,
    which buffers the entire body into memory and so does the very thing the
    limit exists to prevent.

    Two cases:

    * `Content-Length` present -- the common one. Compare and reject without
      reading a byte; otherwise hand the request straight through, so a normal
      request pays nothing at all for this middleware.
    * `Content-Length` absent (`Transfer-Encoding: chunked`) -- a body can arrive
      without ever declaring its size, which is the hole a declared-length check
      alone leaves open. Read it here, but never more than `limit + 1` bytes:
      enough to know the limit is broken, and bounded by the limit itself. If it
      fits, the buffered body is replayed to the app unchanged.
    """

    def __init__(
        self,
        app: ASGIApp,
        *,
        default_max_bytes: int = MAX_BODY_BYTES_DEFAULT,
        overrides: Optional[dict[str, int]] = None,
    ) -> None:
        self.app = app
        self.default_max_bytes = default_max_bytes
        self.overrides = dict(BODY_LIMIT_OVERRIDES if overrides is None else overrides)

    def _limit_for(self, path: str) -> int:
        return self.overrides.get(path, self.default_max_bytes)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope.get("method", "").upper() in BODYLESS_METHODS:
            await self.app(scope, receive, send)
            return

        limit = self._limit_for(scope.get("path", ""))

        declared = _declared_length(scope)
        if declared is not None:
            if declared > limit:
                await _too_large_response(limit)(scope, receive, send)
                return
            # Trustworthy: the ASGI server stops reading at Content-Length, so a
            # client cannot smuggle extra bytes past a length it declared itself.
            await self.app(scope, receive, send)
            return

        chunks: list[bytes] = []
        total = 0
        more = True
        while more:
            message = await receive()
            if message["type"] == "http.disconnect":
                # Nothing to answer; let the app observe the disconnect.
                await self.app(scope, _replay(chunks, trailing=message), send)
                return
            body = message.get("body", b"")
            if body:
                total += len(body)
                if total > limit:
                    await _too_large_response(limit)(scope, receive, send)
                    return
                chunks.append(body)
            more = bool(message.get("more_body", False))

        await self.app(scope, _replay(chunks), send)


def _declared_length(scope: Scope) -> Optional[int]:
    """The request's trustworthy `Content-Length`, or None to count instead.

    None is returned — meaning "measure it yourself" — in every case where the
    header cannot be relied on, so an attacker can never use a header to skip the
    check. That matters more than it looks: a declared length short-circuits the
    counting path, so anything that makes the declaration a lie is a bypass of the
    whole limit, not a cosmetic issue.

    * `Transfer-Encoding: chunked` present. RFC 9112 s6.1 says chunked framing
      wins and Content-Length must be ignored. Measured 2026-10-03 against this
      middleware: `Content-Length: 10` plus a 12 MB chunked body sailed past the
      8 MiB cap when the header was trusted.

      This was directly exploitable on our own stack -- an earlier version of this
      comment wrongly said h11 rejected the pair and that the reach was limited to
      a deployment behind a permissive proxy. Verified on the installed
      h11 0.16.0, with `httptools` absent so uvicorn uses the h11 implementation:
      `h11._headers.normalize_and_validate` accepts `Content-Length` and
      `Transfer-Encoding: chunked` together and keeps both, and
      `h11._connection._body_framing` returns `("chunked", ())` at its own
      "Step 2: check for Transfer-Encoding (T-E beats C-L)" before it ever reads
      Content-Length. uvicorn then puts every raw header into `scope["headers"]`,
      including the one h11 ignored. So the bypass needed no proxy at all.
    * Two `Content-Length` headers that disagree: the classic smuggling pair,
      where each hop believes a different one.
    * A value that is not a non-negative integer.
    """
    lengths: list[int] = []
    for name, value in scope.get("headers", []):
        if name == b"transfer-encoding" and b"chunked" in value.lower():
            return None
        if name == b"content-length":
            try:
                parsed = int(value)
            except ValueError:
                return None
            if parsed < 0:
                return None
            lengths.append(parsed)

    if not lengths:
        return None
    if len(set(lengths)) > 1:
        return None
    return lengths[0]


def _replay(
    chunks: list[bytes], trailing: Optional[Message] = None
) -> Callable[[], Awaitable[Message]]:
    """A `receive` that yields the already-read body, then the trailing message.

    After the body is exhausted this keeps returning `http.disconnect`, which is
    what an ASGI server sends once a request is complete, so an app that polls
    for more cannot hang here.
    """
    pending: list[Message] = [
        {"type": "http.request", "body": chunk, "more_body": True} for chunk in chunks
    ]
    pending.append({"type": "http.request", "body": b"", "more_body": False})
    if trailing is not None:
        pending.append(trailing)

    async def receive() -> Message:
        if pending:
            return pending.pop(0)
        return {"type": "http.disconnect"}

    return receive
