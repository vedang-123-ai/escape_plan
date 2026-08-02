"""Shared test fixtures. Test homes come from schema/fixtures/ — the project-wide test bed."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES_DIR = REPO_ROOT / "schema" / "fixtures"
SCHEMA_PATH = REPO_ROOT / "schema" / "homemodel.schema.json"


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
