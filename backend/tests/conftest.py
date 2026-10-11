"""Shared test fixtures. Test homes come from schema/fixtures/ — the project-wide test bed."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES_DIR = REPO_ROOT / "schema" / "fixtures"
SCHEMA_PATH = REPO_ROOT / "schema" / "homemodel.schema.json"


@pytest.fixture(autouse=True)
def _ai_cost_guard_relaxed(monkeypatch: pytest.MonkeyPatch):
    """Keep the AI cost guard (app/rate_limit.py) out of unrelated tests.

    Its production defaults (burst 3) would turn the fourth mocked /explain call
    in any one test into a 429. Tests of the guard itself set their own limits
    with monkeypatch and clear the settings cache; the buckets and the semaphore
    are reset around every test so no state leaks between them.
    """
    from app import rate_limit

    monkeypatch.setenv("AI_RATE_PER_MIN", "100000")
    monkeypatch.setenv("AI_RATE_BURST", "100000")
    monkeypatch.setenv("AI_MAX_CONCURRENT", "1000")
    monkeypatch.setenv("COMPUTE_RATE_PER_MIN", "100000")
    monkeypatch.setenv("COMPUTE_RATE_BURST", "100000")
    # S11.27 added a third piece of guard state. Unlike the bucket and the
    # semaphore it ACCUMULATES, so without a reset the suite's own AI calls
    # exhaust the day's allowance partway through and every later test 429s —
    # a failure that only appears in a full run, never in isolation.
    rate_limit.limiter.reset()
    rate_limit.gate.reset()
    rate_limit.budget.reset()
    yield
    rate_limit.limiter.reset()
    rate_limit.gate.reset()
    rate_limit.budget.reset()


def load_fixture(name: str) -> dict:
    return json.loads((FIXTURES_DIR / name).read_text())


@pytest.fixture
def bungalow() -> dict:
    return load_fixture("bungalow.json")


@pytest.fixture
def apartment() -> dict:
    return load_fixture("apartment.json")


@pytest.fixture
def twostory() -> dict:
    return load_fixture("twostory.json")


@pytest.fixture
def bungalow_blocked() -> dict:
    """The bungalow with a wardrobe planted in front of the bedroom door —
    the obstruction test bed (see app/routing/obstructions.py)."""
    return load_fixture("bungalow-blocked.json")


@pytest.fixture
def bungalow_narrow() -> dict:
    """The same bungalow with the wardrobe pulled back until the bedroom door is
    reachable but tight — the `narrows_route` test bed. Deliberately a separate
    fixture from `bungalow_blocked`: the two kinds are distinguished by whether a
    path exists at all, so one file cannot exercise both."""
    return load_fixture("bungalow-narrow.json")
