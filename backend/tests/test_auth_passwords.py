"""S8.2 — password hashing."""

from __future__ import annotations

import pytest

from app.auth.passwords import hash_password, needs_rehash, verify_password


class TestHashing:
    def test_hash_verifies_against_its_own_password(self):
        assert verify_password("correct horse", hash_password("correct horse"))

    def test_wrong_password_fails(self):
        assert not verify_password("wrong", hash_password("correct horse"))

    def test_hash_is_argon2id_with_owasp_compliant_parameters(self):
        """OWASP's weakest accepted config is m=19456, t=2, p=1. argon2-cffi's
        defaults are well above it; this pins that we did not lower them."""
        encoded = hash_password("x")
        assert encoded.startswith("$argon2id$")

        params = encoded.split("$")[3]
        values = dict(p.split("=") for p in params.split(","))
        assert int(values["m"]) >= 19456
        assert int(values["t"]) >= 2
        assert int(values["p"]) >= 1

    def test_the_plaintext_never_appears_in_the_hash(self):
        assert "hunter2" not in hash_password("hunter2")

    def test_the_same_password_hashes_differently_each_time(self):
        """A per-hash salt; identical hashes would leak which users share a
        password."""
        assert hash_password("same") != hash_password("same")


class TestNoPlaintextCredentialCanAuthenticate:
    def test_none_hash_never_verifies(self):
        """A user with no hash — seed data, an invite flow, a partial write —
        must never authenticate. This is the bypass shape S8.2 must not ship."""
        assert not verify_password("anything", None)

    def test_empty_hash_never_verifies(self):
        assert not verify_password("anything", "")

    def test_a_garbage_hash_returns_false_rather_than_raising(self):
        """argon2-cffi raises on a malformed hash; unhandled that is a 500 on a
        corrupted row instead of a failed login."""
        assert not verify_password("anything", "not-a-hash")

    def test_the_empty_password_still_requires_a_matching_hash(self):
        assert verify_password("", hash_password(""))
        assert not verify_password("", hash_password("nonempty"))


class TestLongPasswords:
    """Argon2 has no input length cap. bcrypt's 72-byte limit is a ValueError in
    bcrypt 5.x, i.e. a 500 on long passwords — one reason this is not bcrypt."""

    @pytest.mark.parametrize("length", [72, 73, 100, 1000])
    def test_long_passwords_round_trip(self, length):
        password = "a" * length
        assert verify_password(password, hash_password(password))

    def test_passwords_differing_only_past_72_bytes_are_distinguished(self):
        """Under bcrypt these would be the same password. They must not be."""
        base = "a" * 72
        assert not verify_password(base + "DIFFERENT", hash_password(base + "X"))


class TestRehash:
    def test_a_current_hash_does_not_need_rehashing(self):
        assert needs_rehash(hash_password("x")) is False

    def test_a_weaker_hash_is_flagged(self):
        """A hash stored under lower parameters should be upgraded on next
        login, the only moment the plaintext is available."""
        from argon2 import PasswordHasher

        weak = PasswordHasher(time_cost=1, memory_cost=8, parallelism=1).hash("x")
        assert needs_rehash(weak) is True

    def test_garbage_does_not_raise(self):
        assert needs_rehash("not-a-hash") is False
