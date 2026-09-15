"""JWT issue and verify (S8.2).

PyJWT, pinned `>=2.13.0` as a SECURITY floor — CVE-2026-48522..48526 (algorithm
allow-list bypass, a public JWK accepted as an HMAC secret yielding forged HS256
tokens, JWKS SSRF) are fixed there. Not python-jose: its CVEs *are* patched in
3.5.0, but it went 3.7 years between releases and FastAPI removed it from the
docs. See docs/decisions.md.

Two PyJWT defaults are dangerous and are overridden below:

  * `algorithms=[...]` is mandatory on decode and must never be derived from the
    token's own header — that is the algorithm-confusion attack.
  * **A token with no `exp` claim decodes happily by default.** `verify_exp`
    only checks `exp` if it is present, so a forged or hand-made token that
    simply omits it would never expire. `require` makes its absence an error.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
from jwt.exceptions import InvalidTokenError

from app.config import get_settings

ALGORITHM = "HS256"
"""Symmetric: one server-side secret, no key distribution. Passed explicitly on
every decode so a token cannot nominate its own algorithm."""

REQUIRED_CLAIMS = ["exp", "iat", "sub"]


class AuthTokenError(Exception):
    """Raised when a token is absent, malformed, expired, or unverifiable.

    Deliberately one error for every failure: telling a caller *why* their token
    failed distinguishes "expired" from "forged" for an attacker, and the client
    does the same thing either way — re-authenticate.
    """


class AuthNotConfigured(Exception):
    """No JWT_SECRET_KEY. Distinct from a bad token: an operator must act."""


def _secret() -> str:
    secret = get_settings().jwt_secret
    if not secret:
        raise AuthNotConfigured(
            "JWT_SECRET_KEY is not set — refusing to issue or accept tokens"
        )
    return secret


def create_access_token(
    subject: str, expires_in: timedelta | None = None
) -> str:
    """Sign a token for `subject` (a user id).

    `expires_in` is injectable so tests can produce an already-expired token
    without sleeping or freezing the clock.
    """
    now = datetime.now(timezone.utc)
    ttl = expires_in or timedelta(minutes=get_settings().jwt_access_ttl_minutes)
    payload = {"sub": subject, "iat": now, "exp": now + ttl}
    return jwt.encode(payload, _secret(), algorithm=ALGORITHM)


def decode_access_token(token: str) -> str:
    """Verify a token and return its subject, or raise `AuthTokenError`.

    Returns only the subject: nothing else in the payload is trusted as
    application state, so a token cannot carry, say, a role it was not issued.
    """
    try:
        payload = jwt.decode(
            token,
            _secret(),
            algorithms=[ALGORITHM],
            options={"require": REQUIRED_CLAIMS},
        )
    except InvalidTokenError as exc:
        # ExpiredSignatureError, InvalidSignatureError and
        # MissingRequiredClaimError are all subclasses of this.
        raise AuthTokenError(str(exc)) from exc

    subject = payload.get("sub")
    if not isinstance(subject, str) or not subject:
        raise AuthTokenError("token subject is missing or not a string")
    return subject
