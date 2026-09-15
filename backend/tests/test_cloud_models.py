"""S8.1 — the cloud-sync storage models.

These run with no database: the models are deliberately free of any driver
import, so everything here is pure validation. Connection-level behaviour is
covered in test_database.py.
"""

from __future__ import annotations

from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.cloud_models import StoredHomeModel, User
from app.models import HomeModel


class TestUser:
    def test_email_is_lowercased_and_trimmed(self):
        """Un-normalised addresses are how duplicate accounts happen."""
        assert User(email="  Vedang@Example.COM  ").email == "vedang@example.com"

    @pytest.mark.parametrize(
        "bad", ["", "nope", "no@domain", "two@@at.com", "has space@x.com", "@x.com"]
    )
    def test_obvious_junk_is_rejected(self, bad):
        with pytest.raises(ValidationError):
            User(email=bad)

    def test_ids_are_unique_per_instance(self):
        assert User(email="a@b.com").id != User(email="a@b.com").id

    def test_timestamps_are_timezone_aware(self):
        """Naive datetimes order incorrectly across a sync."""
        user = User(email="a@b.com")
        assert user.created_at.tzinfo is not None
        assert user.created_at.utcoffset() == timezone.utc.utcoffset(None)

    def test_no_plaintext_password_field_exists(self):
        """The model must have no shape that can hold a raw credential."""
        assert "password" not in User.model_fields
        assert "hashed_password" in User.model_fields
        with pytest.raises(ValidationError):
            User(email="a@b.com", password="hunter2")

    def test_hashed_password_defaults_to_none(self):
        """S8.1 defines the shape; S8.2 owns filling it."""
        assert User(email="a@b.com").hashed_password is None


class TestStoredHomeModel:
    def test_wraps_a_real_fixture(self, bungalow):
        stored = StoredHomeModel(user_id="u1", home=HomeModel.model_validate(bungalow))
        assert stored.home.home_id == bungalow["home_id"]
        assert stored.revision == 1

    def test_rejects_a_home_that_violates_the_contract(self):
        """The embedded HomeModel keeps its own validation — wrapping must not
        become a way to smuggle an invalid home into storage."""
        with pytest.raises(ValidationError):
            StoredHomeModel(user_id="u1", home={"id": "broken"})

    def test_revision_must_stay_positive(self, bungalow):
        with pytest.raises(ValidationError):
            StoredHomeModel(
                user_id="u1", home=HomeModel.model_validate(bungalow), revision=0
            )

    def test_document_uses_mongo_id_key(self, bungalow):
        doc = StoredHomeModel(
            user_id="u1", home=HomeModel.model_validate(bungalow)
        ).to_document()
        assert "_id" in doc and "id" not in doc

    def test_document_round_trips_through_the_alias(self, bungalow):
        """A document read back from Mongo must rebuild the same model."""
        original = StoredHomeModel(user_id="u1", home=HomeModel.model_validate(bungalow))
        restored = StoredHomeModel.model_validate(original.to_document())
        assert restored.id == original.id
        assert restored.user_id == original.user_id
        assert restored.home == original.home

    def test_accepts_either_id_or_underscore_id(self, bungalow):
        """populate_by_name: API-shaped and Mongo-shaped input both load."""
        home = HomeModel.model_validate(bungalow)
        by_field = StoredHomeModel(id="s1", user_id="u1", home=home)
        by_alias = StoredHomeModel.model_validate(
            {"_id": "s1", "user_id": "u1", "home": bungalow}
        )
        assert by_field.id == by_alias.id == "s1"

    def test_document_keeps_native_datetimes(self, bungalow):
        """Mongo stores BSON dates; serialising to a string here would make
        every stored timestamp a string field that cannot be range-queried."""
        doc = StoredHomeModel(
            user_id="u1", home=HomeModel.model_validate(bungalow)
        ).to_document()
        assert isinstance(doc["created_at"], datetime)
