"""Runtime configuration from environment variables (the only I/O of its kind).

Secrets never live in code or git: `BACKEND_BEARER_TOKEN` gates every endpoint
except /health, and `ANTHROPIC_API_KEY` is consumed by the AI layer (S3.x).
"""

from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path

from pydantic import BaseModel, ConfigDict

from app.routing.egress import EgressThresholds

BACKEND_DIR = Path(__file__).resolve().parents[1]
CORPUS_DIR = BACKEND_DIR / "corpus"


class Settings(BaseModel):
    model_config = ConfigDict(frozen=True)

    bearer_token: str
    anthropic_api_key: str | None
    anthropic_model: str


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Load settings once per process. `BACKEND_BEARER_TOKEN` is required so the
    service can never start unauthenticated by accident."""
    token = os.environ.get("BACKEND_BEARER_TOKEN", "")
    if not token:
        raise RuntimeError(
            "BACKEND_BEARER_TOKEN is not set — refusing to start an open backend."
        )
    return Settings(
        bearer_token=token,
        anthropic_api_key=os.environ.get("ANTHROPIC_API_KEY") or None,
        anthropic_model=os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-5"),
    )


@lru_cache(maxsize=1)
def get_thresholds() -> EgressThresholds:
    """Egress thresholds from the corpus (metric authoritative), loaded once."""
    data = json.loads((CORPUS_DIR / "egress_thresholds.json").read_text())
    return EgressThresholds.from_corpus(data)
