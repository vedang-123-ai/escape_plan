"""Anthropic SDK failures must not surface as bare 500s.

Found 2026-08-04: with the account's credit balance exhausted, /explain, /analyze
and /chat all returned `500 Internal Server Error` with no body the app could act
on. The missing-key path was already handled (a clean 502), so the gap was only in
the unguarded `client.messages.create` calls — which is exactly the failure mode a
live demo hits (rate limit, overload, dry account).

The contract these tests pin:
  502 — an operator has to act (no credit, bad key). Don't bother retrying.
  503 — the same request may work shortly (rate limit, overload, network).
Both carry a human-readable `detail`. Neither is ever a 500.
"""

from __future__ import annotations

import anthropic
import httpx
import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app

TEST_TOKEN = "test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(autouse=True)
def _token_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture
def client() -> TestClient:
    # The handler under test converts the exception to a response, so the
    # TestClient must not re-raise it as a server exception.
    return TestClient(app, raise_server_exceptions=False)


def _status_error(status_code: int, message: str) -> anthropic.APIStatusError:
    """Build a real SDK error the way the SDK builds it from an HTTP response."""
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    response = httpx.Response(
        status_code, request=request, json={"error": {"message": message}}
    )
    return anthropic.APIStatusError(message, response=response, body=None)


def _credit_exhausted() -> anthropic.APIStatusError:
    """The exact error observed on 2026-08-04."""
    return _status_error(
        400,
        "Your credit balance is too low to access the Anthropic API. "
        "Please go to Plans & Billing to upgrade or purchase credits.",
    )


def _rate_limited() -> anthropic.RateLimitError:
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    response = httpx.Response(
        429, request=request, json={"error": {"message": "rate limit exceeded"}}
    )
    return anthropic.RateLimitError("rate limit exceeded", response=response, body=None)


def _explain_body(bungalow: dict, client: TestClient) -> dict:
    plan = client.post("/routes", json={"home": bungalow}, headers=AUTH).json()
    return {"home": bungalow, "route_plan": plan}


def test_credit_exhaustion_is_502_not_500(
    client: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    """The headline regression: a dry account used to produce a bare 500."""
    import app.main as main

    def boom(*_args, **_kwargs):
        raise _credit_exhausted()

    monkeypatch.setattr(main, "run_agent_analysis", boom)

    resp = client.post("/analyze", json={"home": bungalow}, headers=AUTH)
    assert resp.status_code == 502, f"got {resp.status_code}, body={resp.text[:300]}"
    detail = resp.json()["detail"]
    assert "credit balance is too low" in detail
    assert detail != "Internal Server Error"


def test_rate_limit_is_503_so_the_app_can_offer_retry(
    client: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    import app.main as main

    def boom(*_args, **_kwargs):
        raise _rate_limited()

    monkeypatch.setattr(main, "run_agent_analysis", boom)

    resp = client.post("/analyze", json={"home": bungalow}, headers=AUTH)
    assert resp.status_code == 503
    assert "temporarily unavailable" in resp.json()["detail"]


def test_overloaded_529_is_retryable(
    client: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    import app.main as main

    def boom(*_args, **_kwargs):
        raise _status_error(529, "Overloaded")

    monkeypatch.setattr(main, "run_agent_analysis", boom)

    assert (
        client.post("/analyze", json={"home": bungalow}, headers=AUTH).status_code == 503
    )


def test_connection_error_is_retryable(
    client: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    import app.main as main

    def boom(*_args, **_kwargs):
        raise anthropic.APIConnectionError(
            request=httpx.Request("POST", "https://api.anthropic.com/v1/messages")
        )

    monkeypatch.setattr(main, "run_agent_analysis", boom)

    assert (
        client.post("/analyze", json={"home": bungalow}, headers=AUTH).status_code == 503
    )


def test_explain_is_covered_too(
    client: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    """The handler is app-level, so every AI endpoint gets it — not just /analyze."""
    import app.main as main

    body = _explain_body(bungalow, client)

    def boom(*_args, **_kwargs):
        raise _credit_exhausted()

    monkeypatch.setattr(main, "explain_routes", boom)

    resp = client.post("/explain", json=body, headers=AUTH)
    assert resp.status_code == 502
    assert "credit balance is too low" in resp.json()["detail"]


def test_deterministic_endpoints_are_unaffected(client: TestClient, bungalow: dict):
    """The whole architectural point: routing never touches the AI, so an outage
    that kills /explain leaves /routes and /score fully working."""
    assert (
        client.post("/routes", json={"home": bungalow}, headers=AUTH).status_code == 200
    )
    assert (
        client.post("/score", json={"home": bungalow}, headers=AUTH).status_code == 200
    )
