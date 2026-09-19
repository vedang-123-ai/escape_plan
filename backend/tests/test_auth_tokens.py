"""S8.2 — JWT issue and verify.

Expiry is tested by signing a token with a past `exp` rather than by sleeping or
freezing the clock: the token is just data, so nothing needs to elapse and there
is no global clock to mutate.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
import pytest

from app import config
from app.auth.tokens import (
    ALGORITHM,
    AuthNotConfigured,
    AuthTokenError,
    create_access_token,
    decode_access_token,
)

SECRET = "test-jwt-secret-not-a-real-one-padded-to-32-bytes"


@pytest.fixture(autouse=True)
def _configured(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", "test-token")
    monkeypatch.setenv("JWT_SECRET_KEY", SECRET)
    monkeypatch.setenv("JWT_ACCESS_TTL_MINUTES", "60")
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


class TestRoundTrip:
    def test_a_fresh_token_decodes_to_its_subject(self):
        assert decode_access_token(create_access_token("user-123")) == "user-123"

    def test_the_subject_is_not_readable_as_plaintext_state(self):
        """A JWT is signed, not encrypted — this documents that we know the
        payload is readable, which is why nothing secret goes in it."""
        token = create_access_token("user-123")
        payload = jwt.decode(token, SECRET, algorithms=[ALGORITHM])
        assert set(payload) == {"sub", "iat", "exp"}

    def test_tokens_carry_no_password_material(self):
        token = create_access_token("user-123")
        payload = jwt.decode(token, SECRET, algorithms=[ALGORITHM])
        assert not any("pass" in k.lower() or "hash" in k.lower() for k in payload)


class TestRejection:
    def test_an_expired_token_is_rejected(self):
        expired = create_access_token("u1", expires_in=timedelta(seconds=-1))
        with pytest.raises(AuthTokenError):
            decode_access_token(expired)

    def test_a_token_signed_with_another_secret_is_rejected(self):
        forged = jwt.encode(
            {
                "sub": "u1",
                "iat": datetime.now(timezone.utc),
                "exp": datetime.now(timezone.utc) + timedelta(hours=1),
            },
            "a-different-secret-also-padded-to-32-bytes",
            algorithm=ALGORITHM,
        )
        with pytest.raises(AuthTokenError):
            decode_access_token(forged)

    def test_a_token_without_exp_is_rejected(self):
        """PyJWT's `verify_exp` only checks `exp` IF PRESENT, so without an
        explicit `require` this token would never expire. This is the easiest
        real vulnerability to ship in a JWT layer."""
        never_expires = jwt.encode(
            {"sub": "u1", "iat": datetime.now(timezone.utc)}, SECRET,
            algorithm=ALGORITHM,
        )
        with pytest.raises(AuthTokenError):
            decode_access_token(never_expires)

    def test_an_alg_none_token_is_rejected(self):
        """The classic algorithm-confusion attack: an unsigned token claiming
        it needs no signature."""
        unsigned = jwt.encode({"sub": "u1"}, key="", algorithm="none")
        with pytest.raises(AuthTokenError):
            decode_access_token(unsigned)

    def test_a_token_with_no_subject_is_rejected(self):
        no_sub = jwt.encode(
            {
                "iat": datetime.now(timezone.utc),
                "exp": datetime.now(timezone.utc) + timedelta(hours=1),
            },
            SECRET,
            algorithm=ALGORITHM,
        )
        with pytest.raises(AuthTokenError):
            decode_access_token(no_sub)

    def test_a_non_string_subject_is_rejected(self):
        """Otherwise the subject flows into a database query as whatever type
        the attacker chose."""
        weird = jwt.encode(
            {
                "sub": {"$ne": None},
                "iat": datetime.now(timezone.utc),
                "exp": datetime.now(timezone.utc) + timedelta(hours=1),
            },
            SECRET,
            algorithm=ALGORITHM,
        )
        with pytest.raises(AuthTokenError):
            decode_access_token(weird)

    @pytest.mark.parametrize("junk", ["", "not.a.token", "a.b.c", "....."])
    def test_malformed_tokens_raise_the_domain_error_not_a_library_error(self, junk):
        with pytest.raises(AuthTokenError):
            decode_access_token(junk)

    def test_failures_do_not_disclose_which_check_failed(self):
        """Distinguishing 'expired' from 'forged' helps an attacker, and the
        client re-authenticates either way."""
        expired = create_access_token("u1", expires_in=timedelta(seconds=-1))
        forged = jwt.encode(
            {
                "sub": "u1",
                "iat": datetime.now(timezone.utc),
                "exp": datetime.now(timezone.utc) + timedelta(hours=1),
            },
            "other-secret-padded-out-to-thirty-two-bytes",
            algorithm=ALGORITHM,
        )
        # Both raise the same type; the endpoint turns both into one 401.
        for token in (expired, forged):
            with pytest.raises(AuthTokenError):
                decode_access_token(token)


class TestUnconfigured:
    def test_issuing_without_a_secret_raises_a_distinct_error(
        self, monkeypatch: pytest.MonkeyPatch
    ):
        """Not AuthTokenError: a missing secret is an operator problem, not a
        bad credential, and must not read as 'your login failed'."""
        monkeypatch.delenv("JWT_SECRET_KEY", raising=False)
        config.get_settings.cache_clear()
        with pytest.raises(AuthNotConfigured):
            create_access_token("u1")

    def test_verifying_without_a_secret_raises_too(
        self, monkeypatch: pytest.MonkeyPatch
    ):
        token = create_access_token("u1")
        monkeypatch.delenv("JWT_SECRET_KEY", raising=False)
        config.get_settings.cache_clear()
        with pytest.raises(AuthNotConfigured):
            decode_access_token(token)


class TestSecretStrength:
    """A short signing secret is brute-forceable. PyJWT only warns; we refuse."""

    def test_a_short_secret_is_rejected_at_startup(
        self, monkeypatch: pytest.MonkeyPatch
    ):
        monkeypatch.setenv("JWT_SECRET_KEY", "secret")
        config.get_settings.cache_clear()
        with pytest.raises(RuntimeError, match="too short"):
            config.get_settings()

    def test_the_error_says_how_to_generate_one(
        self, monkeypatch: pytest.MonkeyPatch
    ):
        monkeypatch.setenv("JWT_SECRET_KEY", "x" * 31)
        config.get_settings.cache_clear()
        with pytest.raises(RuntimeError, match="token_urlsafe"):
            config.get_settings()

    def test_exactly_the_minimum_is_accepted(self, monkeypatch: pytest.MonkeyPatch):
        monkeypatch.setenv("JWT_SECRET_KEY", "x" * config.MIN_JWT_SECRET_BYTES)
        config.get_settings.cache_clear()
        assert config.get_settings().jwt_secret is not None

    def test_a_missing_secret_is_not_an_error(self, monkeypatch: pytest.MonkeyPatch):
        """Absent means 'auth off'; too-short means misconfigured. Different."""
        monkeypatch.delenv("JWT_SECRET_KEY", raising=False)
        config.get_settings.cache_clear()
        assert config.get_settings().jwt_secret is None
