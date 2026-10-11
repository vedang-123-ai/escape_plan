"""Tests for A11-04: Memoized route solves in /score endpoint."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app
from app.models import HomeModel
from app.routing.engine import compute_route_plan, compute_score_route_plans
from app.scoring.score import compute_score

AUTH = {"Authorization": "Bearer test-memoize-token"}


@pytest.fixture(autouse=True)
def _auth_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", "test-memoize-token")
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def test_memoized_route_plans_are_byte_identical_to_unmemoized(bungalow: dict, apartment: dict, twostory: dict):
    thresholds = config.get_thresholds()
    for fixture in (bungalow, apartment, twostory):
        home = HomeModel.model_validate(fixture)
        p1 = compute_route_plan(home, thresholds, peril="fire")
        tp1 = compute_route_plan(home, thresholds, peril="tornado")
        ep1 = compute_route_plan(home, thresholds, peril="earthquake")

        p2, tp2, ep2 = compute_score_route_plans(home, thresholds)

        assert p1.model_dump_json() == p2.model_dump_json()
        assert tp1.model_dump_json() == tp2.model_dump_json()
        assert ep1.model_dump_json() == ep2.model_dump_json()

        s1 = compute_score(home, p1, [], {}, thresholds, tornado_plan=tp1, earthquake_plan=ep1)
        s2 = compute_score(home, p2, [], {}, thresholds, tornado_plan=tp2, earthquake_plan=ep2)
        assert s1.model_dump_json() == s2.model_dump_json()


def test_score_endpoint_uses_memoized_computation(bungalow: dict):
    client = TestClient(app)
    req = {"home": bungalow, "findings": [], "checklist_state": {}}
    resp = client.post("/score", json=req, headers=AUTH)
    assert resp.status_code == 200
    data = resp.json()
    assert "score" in data
    assert "sub_scores" in data
    assert "checklist" in data
