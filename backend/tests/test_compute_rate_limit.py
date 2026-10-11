"""Tests for A06-04: IP rate limiting on deterministic compute endpoints (/routes, /score, /evacuate)."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import config, rate_limit
from app.main import app

AUTH = {"Authorization": "Bearer test-compute-token"}


@pytest.fixture(autouse=True)
def _auth_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", "test-compute-token")
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def test_compute_rate_limit_enforced_on_routes(bungalow: dict, monkeypatch: pytest.MonkeyPatch):
    # Set a tight burst limit for testing
    monkeypatch.setenv("COMPUTE_RATE_PER_MIN", "60")
    monkeypatch.setenv("COMPUTE_RATE_BURST", "2")
    config.get_settings.cache_clear()
    rate_limit.limiter.reset()

    client = TestClient(app)
    req = {"home": bungalow}

    # First request: 200 OK
    r1 = client.post("/routes", json=req, headers=AUTH)
    assert r1.status_code == 200

    # Second request: 200 OK (burst exhausted)
    r2 = client.post("/routes", json=req, headers=AUTH)
    assert r2.status_code == 200

    # Third request: 429 Too Many Requests
    r3 = client.post("/routes", json=req, headers=AUTH)
    assert r3.status_code == 429
    assert "Retry-After" in r3.headers
    assert "Too many compute requests" in r3.json()["detail"]


def test_compute_rate_limit_enforced_on_score(bungalow: dict, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("COMPUTE_RATE_PER_MIN", "60")
    monkeypatch.setenv("COMPUTE_RATE_BURST", "1")
    config.get_settings.cache_clear()
    rate_limit.limiter.reset()

    client = TestClient(app)
    req = {"home": bungalow, "findings": [], "checklist_state": {}}

    r1 = client.post("/score", json=req, headers=AUTH)
    assert r1.status_code == 200

    r2 = client.post("/score", json=req, headers=AUTH)
    assert r2.status_code == 429
    assert "Retry-After" in r2.headers


def test_compute_rate_limit_requires_token_before_rate_limit(bungalow: dict, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("COMPUTE_RATE_PER_MIN", "60")
    monkeypatch.setenv("COMPUTE_RATE_BURST", "1")
    config.get_settings.cache_clear()
    rate_limit.limiter.reset()

    client = TestClient(app)
    req = {"home": bungalow}

    # Request without token fails with 401, not 429, and does not burn bucket
    r_bad = client.post("/routes", json=req)
    assert r_bad.status_code == 401

    # Valid token still has full bucket
    r_good = client.post("/routes", json=req, headers=AUTH)
    assert r_good.status_code == 200
