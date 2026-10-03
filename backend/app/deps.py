"""Shared FastAPI dependencies: the bearer-token guard and the AI guard stack.

Why this file exists (S11.27, AUD-043): `require_token` was defined twice, in
`app.main` and in `app.api_chat`, because importing it from `main` into the
router would close an import cycle (`main` includes the router). Two copies of an
auth check is two places to get it wrong, and this session adds a guard to the
stack — which would otherwise have had to be added twice, correctly, by hand.

Putting both in a module that imports neither breaks the cycle: `main` and
`api_chat` each import from here, and nothing here imports either of them.

`tests/test_route_guards.py` walks `app.routes` and fails any route that answers
without credentials, so a route added later that forgets these is caught the day
it lands, whichever guard it was supposed to use.
"""

from __future__ import annotations

import secrets
from contextlib import contextmanager
from typing import Annotated, Iterator, Optional

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.rate_limit import (
    ai_budget,
    ai_concurrency,
    ai_rate_limit,
    busy_exception,
    enforce_budget,
    enforce_rate_limit,
    gate,
)

_bearer_scheme = HTTPBearer(auto_error=False)


def require_token(
    credentials: Annotated[
        Optional[HTTPAuthorizationCredentials], Depends(_bearer_scheme)
    ],
) -> None:
    """The shared bearer token on every compute and AI route.

    Read this narrowly: the token ships inside every app build, so it identifies
    the APP, not the caller, and anyone with the IPA has it (AUD-003). It keeps
    the service from being an open relay for anonymous internet traffic; it is
    not what bounds spend. `AI_GUARDS` is.

    `compare_digest` rather than `==` so a wrong token cannot be recovered a byte
    at a time by timing the comparison.
    """
    expected = get_settings().bearer_token
    if credentials is None or not secrets.compare_digest(
        credentials.credentials, expected
    ):
        raise HTTPException(status_code=401, detail="Invalid or missing bearer token")


# The AI routes spend Anthropic credit, so on top of the token they get the cost
# guard (app/rate_limit.py). ORDER MATTERS, and each step exists for a different
# failure:
#
#   require_token    no token is a 401 that never touches anyone's budget
#   ai_rate_limit    one client flooding — keyed on an IP the client cannot set
#   ai_budget        total spend for the UTC day, whoever is spending it. The
#                    only one of these a caller holding the public token cannot
#                    reset, which is why it was added (S11.27)
#   ai_concurrency   in-flight cap, held until the endpoint returns. LAST, so a
#                    request rejected by a cheaper check never occupies a slot
AI_GUARDS = [
    Depends(require_token),
    Depends(ai_rate_limit),
    Depends(ai_budget),
    Depends(ai_concurrency),
]


@contextmanager
def ai_guards_for_optional_call(request: Request) -> Iterator[None]:
    """The same cost guard, for an AI call a route makes only sometimes.

    `/score?include_recommendations=true` is the one case (AUD-006): the route is
    deterministic and the demo path depends on it, so it must not carry
    `AI_GUARDS` as route dependencies — that would rate-limit and budget every
    plain `/score`, including the ones that run when the AI is dead. But when the
    flag IS set the route spends credit, and before this it spent it outside the
    guard entirely.

    A per-request flag cannot be expressed as a route-level dependency, so the
    checks run here instead. `require_token` is NOT repeated: `/score` already
    declares it, and re-running it would need the credentials threaded through
    for no gain.

    The limiter and budget raise `HTTPException(429)` exactly as the dependency
    versions do, so the client sees one behaviour whichever path spent the call.
    The semaphore is released on the way out, including on an exception.
    """
    enforce_rate_limit(request)
    enforce_budget()
    semaphore = gate.semaphore(get_settings().ai_max_concurrent)
    if not semaphore.acquire(blocking=False):
        raise busy_exception()
    try:
        yield
    finally:
        semaphore.release()
