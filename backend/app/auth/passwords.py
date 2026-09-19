"""Password hashing (S8.2).

**Argon2id via argon2-cffi**, which is OWASP's first choice for new code. Its
defaults (m=65536 KiB, t=3, p=4) exceed every configuration in the OWASP
Password Storage Cheat Sheet's equivalence table, the weakest of which is
m=19456, t=2, p=1.

Deliberately NOT passlib (no release since 2020; hard-fails against bcrypt 5.x)
and NOT bare bcrypt, whose 72-byte input limit is a crash in bcrypt 5 and which
OWASP now files under legacy. Argon2 has no input length cap, so the whole
72-byte pre-hashing minefield simply does not apply here. See docs/decisions.md.
"""

from __future__ import annotations

from argon2 import PasswordHasher
from argon2.exceptions import (
    InvalidHashError,
    VerificationError,
    VerifyMismatchError,
)

_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    """Return an encoded Argon2id hash (algorithm and parameters included)."""
    return _hasher.hash(password)


def verify_password(password: str, hashed: str | None) -> bool:
    """Constant-time-ish verification that never raises.

    `hashed` is Optional because `User.hashed_password` is — a user created by
    seed data or a partial write can have none. Such a user must NEVER
    authenticate, so None returns False here rather than reaching the hasher,
    where it would raise and surface as a 500.

    argon2-cffi raises on mismatch rather than returning False, and takes
    (hash, password) in that order — both easy to get backwards.
    """
    if not hashed:
        return False
    try:
        _hasher.verify(hashed, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False
    return True


def needs_rehash(hashed: str) -> bool:
    """True when a stored hash predates the current parameters.

    Callers re-hash on the next successful login, which is the only moment the
    plaintext is available.
    """
    try:
        return _hasher.check_needs_rehash(hashed)
    except (InvalidHashError, VerificationError):
        return False
