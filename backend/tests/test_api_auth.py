"""S8.2 acceptance: register, login, and JWT-guarded /homes.

Runs against the in-memory Mongo fake — no server. `database` is the module-level
singleton the routes reach through, so the fixture installs a fake handle on it
and restores afterwards.
"""

from __future__ import annotations

from datetime import timedelta

import pytest
from fastapi.testclient import TestClient

from app import config
from app.auth.tokens import create_access_token
from app.database import database
from app.main import app
from tests.fake_mongo import FakeDatabase

JWT_SECRET = "a-test-signing-secret-well-over-32-bytes-long"
EMAIL = "vedang@example.com"
PASSWORD = "a-good-password"


@pytest.fixture(autouse=True)
def cloud(monkeypatch: pytest.MonkeyPatch):
    """Point the singleton at a fake database and configure auth."""
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", "test-token")
    monkeypatch.setenv("JWT_SECRET_KEY", JWT_SECRET)
    monkeypatch.delenv("MONGODB_URI", raising=False)
    config.get_settings.cache_clear()

    from app.cloud_repo import ensure_indexes

    fake = FakeDatabase()
    monkeypatch.setattr(database, "_db", fake, raising=False)
    monkeypatch.setattr(database, "_client", object(), raising=False)

    import asyncio

    # The fake's create_index is async but does no I/O, so a throwaway loop is
    # enough; the TestClient below runs the app on its own.
    asyncio.run(ensure_indexes(fake))

    yield fake
    config.get_settings.cache_clear()


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def register(client: TestClient, email: str = EMAIL, password: str = PASSWORD):
    return client.post("/auth/register", json={"email": email, "password": password})


def login(client: TestClient, email: str = EMAIL, password: str = PASSWORD):
    return client.post(
        "/auth/login", data={"username": email, "password": password}
    )


def auth_header(client: TestClient) -> dict:
    return {"Authorization": f"Bearer {login(client).json()['access_token']}"}


class TestRegister:
    def test_register_returns_201_and_the_public_user(self, client):
        resp = register(client)
        assert resp.status_code == 201
        assert resp.json()["email"] == EMAIL

    def test_the_response_never_contains_the_password_or_its_hash(self, client):
        body = register(client).text
        assert PASSWORD not in body
        assert "hashed_password" not in body
        assert "argon2" not in body

    def test_duplicate_email_is_409(self, client):
        register(client)
        assert register(client).status_code == 409

    def test_duplicate_is_detected_across_case(self, client):
        register(client)
        assert register(client, email="VEDANG@EXAMPLE.COM").status_code == 409

    @pytest.mark.parametrize("bad", ["short", "1234567"])
    def test_a_too_short_password_is_422(self, client, bad):
        assert register(client, password=bad).status_code == 422

    def test_an_invalid_email_is_422(self, client):
        assert register(client, email="not-an-email").status_code == 422


class TestLogin:
    def test_valid_credentials_return_a_bearer_token(self, client):
        register(client)
        resp = login(client)
        assert resp.status_code == 200
        assert resp.json()["token_type"] == "bearer"
        assert resp.json()["access_token"]

    def test_a_wrong_password_is_401(self, client):
        register(client)
        assert login(client, password="wrong-password").status_code == 401

    def test_an_unknown_email_is_401(self, client):
        assert login(client, email="nobody@example.com").status_code == 401

    def test_unknown_email_and_wrong_password_are_indistinguishable(self, client):
        """Different bodies would let an attacker enumerate registered emails."""
        register(client)
        wrong_pw = login(client, password="wrong-password")
        no_user = login(client, email="nobody@example.com")
        assert wrong_pw.status_code == no_user.status_code == 401
        assert wrong_pw.json() == no_user.json()

    def test_a_401_carries_the_www_authenticate_header(self, client):
        """RFC 6750 requires it on a bearer-auth challenge."""
        assert "www-authenticate" in {
            k.lower() for k in login(client, password="nope").headers
        }

    def test_login_is_case_insensitive_on_the_email(self, client):
        register(client)
        assert login(client, email="VEDANG@EXAMPLE.COM").status_code == 200


class TestHomesRequiresAuth:
    """The acceptance criterion: /homes without a valid JWT is 401."""

    def test_no_token_is_401(self, client):
        assert client.get("/homes").status_code == 401

    def test_a_garbage_token_is_401(self, client):
        assert client.get(
            "/homes", headers={"Authorization": "Bearer not-a-token"}
        ).status_code == 401

    def test_an_expired_token_is_401(self, client):
        register(client)
        expired = create_access_token("u1", expires_in=timedelta(seconds=-1))
        assert client.get(
            "/homes", headers={"Authorization": f"Bearer {expired}"}
        ).status_code == 401

    def test_a_token_for_a_deleted_user_is_401(self, client, cloud):
        """The user is re-read per request, so deleting the account revokes
        access immediately rather than when the token expires."""
        register(client)
        headers = auth_header(client)
        assert client.get("/homes", headers=headers).status_code == 200

        cloud["users"].documents.clear()
        assert client.get("/homes", headers=headers).status_code == 401

    def test_posting_a_home_without_a_token_is_401(self, client, bungalow):
        assert client.post("/homes", json={"home": bungalow}).status_code == 401


class TestHomeSync:
    def test_round_trip_create_then_list(self, client, bungalow):
        register(client)
        headers = auth_header(client)

        created = client.post("/homes", json={"home": bungalow}, headers=headers)
        assert created.status_code == 201
        assert created.json()["revision"] == 1

        listed = client.get("/homes", headers=headers).json()
        assert len(listed) == 1
        assert listed[0]["home"]["home_id"] == bungalow["home_id"]

    def test_revision_increments_server_side(self, client, bungalow):
        register(client)
        headers = auth_header(client)
        home_id = client.post(
            "/homes", json={"home": bungalow}, headers=headers
        ).json()["id"]

        updated = client.post(
            "/homes", json={"home": bungalow, "home_id": home_id}, headers=headers
        )
        assert updated.json()["revision"] == 2

    def test_a_client_cannot_set_the_revision(self, client, bungalow):
        """extra='forbid': S8.4's merge must be able to trust the counter."""
        register(client)
        resp = client.post(
            "/homes",
            json={"home": bungalow, "revision": 99},
            headers=auth_header(client),
        )
        assert resp.status_code == 422

    def test_a_home_list_is_scoped_to_the_caller(self, client, bungalow):
        register(client)
        client.post("/homes", json={"home": bungalow}, headers=auth_header(client))

        register(client, email="other@example.com")
        other = {
            "Authorization": "Bearer "
            + login(client, email="other@example.com").json()["access_token"]
        }
        assert client.get("/homes", headers=other).json() == []

    def test_updating_another_users_home_is_404(self, client, bungalow):
        """404, not 403 — confirming the id exists would leak its existence."""
        register(client)
        home_id = client.post(
            "/homes", json={"home": bungalow}, headers=auth_header(client)
        ).json()["id"]

        register(client, email="other@example.com")
        other = {
            "Authorization": "Bearer "
            + login(client, email="other@example.com").json()["access_token"]
        }
        resp = client.post(
            "/homes", json={"home": bungalow, "home_id": home_id}, headers=other
        )
        assert resp.status_code == 404

    def test_an_invalid_home_is_422_not_stored(self, client):
        register(client)
        resp = client.post(
            "/homes", json={"home": {"home_id": "broken"}}, headers=auth_header(client)
        )
        assert resp.status_code == 422


class TestMe:
    def test_me_returns_the_authenticated_user(self, client):
        register(client)
        resp = client.get("/auth/me", headers=auth_header(client))
        assert resp.status_code == 200
        assert resp.json()["email"] == EMAIL
        assert "hashed_password" not in resp.text

    def test_me_without_a_token_is_401(self, client):
        assert client.get("/auth/me").status_code == 401


class TestWireContract:
    """The shape the S8.4 Swift client will decode. Regression tests for two
    defects found against a live Atlas cluster on 2026-09-15."""

    def test_a_stored_home_is_returned_with_id_not_underscore_id(
        self, client, bungalow
    ):
        """`_id` is Mongo's primary key, not part of the public API.

        `StoredHomeModel.id` is aliased to `_id` for `to_document()`, and
        FastAPI serialises response models by alias by default — so this used to
        put a storage detail on the wire, contradicting `/auth/me` (which
        returns a plain `id`) and forcing a `CodingKeys` mapping on the Swift
        side for no reason.
        """
        register(client)
        headers = auth_header(client)

        created = client.post("/homes", json={"home": bungalow}, headers=headers)
        assert created.status_code == 201
        assert "id" in created.json()
        assert "_id" not in created.json()

        listed = client.get("/homes", headers=headers).json()
        assert "id" in listed[0]
        assert "_id" not in listed[0]

    def test_an_id_from_a_response_can_be_sent_straight_back(self, client, bungalow):
        """The round-trip the client actually performs: read `id`, send it as
        `home_id`. Guards against fixing the response shape while leaving the
        request side unable to consume it."""
        register(client)
        headers = auth_header(client)
        home_id = client.post(
            "/homes", json={"home": bungalow}, headers=headers
        ).json()["id"]

        updated = client.post(
            "/homes", json={"home": bungalow, "home_id": home_id}, headers=headers
        )
        assert updated.status_code == 201
        assert updated.json()["id"] == home_id
        assert updated.json()["revision"] == 2

    def test_created_at_survives_an_update(self, client, bungalow):
        """`upsert` is a full `replace_one`, so a freshly defaulted `created_at`
        would overwrite the original on every write and the field would mean
        nothing beyond `updated_at`."""
        register(client)
        headers = auth_header(client)
        created = client.post("/homes", json={"home": bungalow}, headers=headers).json()

        updated = client.post(
            "/homes",
            json={"home": bungalow, "home_id": created["id"]},
            headers=headers,
        ).json()

        assert updated["created_at"] == created["created_at"]


def other_header(client: TestClient, email: str = "other@example.com") -> dict:
    """Register a SECOND account and return its auth header.

    Every cross-account assertion below needs one, and writing it inline three
    times is how one of them quietly ends up reusing the first account's token
    and passing for the wrong reason.
    """
    register(client, email=email)
    token = login(client, email=email).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


class TestDeleteHome:
    """S11.7: `DELETE /homes/{id}`. Before this the backend had no delete
    endpoint at all, which is why the iOS sync layer carries tombstones."""

    def test_deleting_your_own_home_is_204_and_it_is_gone(self, client, bungalow):
        register(client)
        headers = auth_header(client)
        home_id = client.post(
            "/homes", json={"home": bungalow}, headers=headers
        ).json()["id"]

        assert client.delete(f"/homes/{home_id}", headers=headers).status_code == 204
        assert client.get("/homes", headers=headers).json() == []

    def test_deleting_without_a_token_is_401(self, client, bungalow):
        register(client)
        home_id = client.post(
            "/homes", json={"home": bungalow}, headers=auth_header(client)
        ).json()["id"]

        assert client.delete(f"/homes/{home_id}").status_code == 401
        # And the home survived the attempt.
        assert len(client.get("/homes", headers=auth_header(client)).json()) == 1

    def test_deleting_another_users_home_is_404_and_leaves_it_alone(
        self, client, bungalow
    ):
        """404 not 403 — confirming the id exists would leak it. The second
        assertion is the one that matters: the answer must not merely be wrong,
        the home must still be there."""
        register(client)
        mine = auth_header(client)
        home_id = client.post("/homes", json={"home": bungalow}, headers=mine).json()["id"]

        assert client.delete(f"/homes/{home_id}", headers=other_header(client)).status_code == 404
        assert len(client.get("/homes", headers=mine).json()) == 1

    def test_deleting_an_unknown_home_is_404(self, client):
        register(client)
        resp = client.delete("/homes/no-such-home", headers=auth_header(client))
        assert resp.status_code == 404

    def test_deleting_twice_is_404_the_second_time(self, client, bungalow):
        register(client)
        headers = auth_header(client)
        home_id = client.post(
            "/homes", json={"home": bungalow}, headers=headers
        ).json()["id"]

        assert client.delete(f"/homes/{home_id}", headers=headers).status_code == 204
        assert client.delete(f"/homes/{home_id}", headers=headers).status_code == 404


class TestDeleteAccount:
    """S11.7: `DELETE /auth/me`. Apple requires in-app account deletion wherever
    accounts exist, and it has to take the homes with it — a home carries the
    floor plan, the household members' names and the optional address."""

    def test_deleting_the_account_is_204(self, client):
        register(client)
        assert client.delete("/auth/me", headers=auth_header(client)).status_code == 204

    def test_the_token_stops_working_immediately(self, client):
        """`get_current_user` re-reads the user per request, so deletion revokes
        every outstanding JWT rather than waiting for it to expire."""
        register(client)
        headers = auth_header(client)
        client.delete("/auth/me", headers=headers)

        assert client.get("/auth/me", headers=headers).status_code == 401
        assert client.get("/homes", headers=headers).status_code == 401

    def test_the_email_is_free_to_register_again(self, client):
        register(client)
        client.delete("/auth/me", headers=auth_header(client))
        assert register(client).status_code == 201

    def test_every_home_goes_with_the_account(self, client, cloud, bungalow):
        """Asserted against STORAGE, not against `GET /homes` — which answers
        401 after deletion and would pass just as well if the documents were
        still sitting in the collection."""
        register(client)
        headers = auth_header(client)
        client.post("/homes", json={"home": bungalow}, headers=headers)
        client.post("/homes", json={"home": bungalow}, headers=headers)
        assert len(cloud["homes"].documents) == 2

        client.delete("/auth/me", headers=headers)
        assert cloud["homes"].documents == {}
        assert cloud["users"].documents == {}

    def test_another_accounts_homes_survive(self, client, cloud, bungalow):
        """The whole point of `delete_many({"user_id": ...})` being scoped. A
        missing filter would erase the collection and every test above would
        still pass."""
        register(client)
        mine = auth_header(client)
        client.post("/homes", json={"home": bungalow}, headers=mine)

        theirs = other_header(client)
        client.post("/homes", json={"home": bungalow}, headers=theirs)

        client.delete("/auth/me", headers=mine)

        assert len(cloud["homes"].documents) == 1
        assert len(client.get("/homes", headers=theirs).json()) == 1
        assert client.get("/auth/me", headers=theirs).status_code == 200

    def test_deleting_without_a_token_is_401(self, client, cloud):
        register(client)
        assert client.delete("/auth/me").status_code == 401
        assert len(cloud["users"].documents) == 1

    def test_a_second_account_never_sees_the_first_accounts_homes(
        self, client, bungalow
    ):
        """The S8.4 ruling, re-pinned here because deletion is the operation
        most likely to break it: a home belongs to the account that synced it,
        and a different account signing in never receives it."""
        register(client)
        client.post("/homes", json={"home": bungalow}, headers=auth_header(client))

        theirs = other_header(client)
        assert client.get("/homes", headers=theirs).json() == []

        # And after the second account deletes itself, the first still has its home.
        client.delete("/auth/me", headers=theirs)
        assert len(client.get("/homes", headers=auth_header(client)).json()) == 1
