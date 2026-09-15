"""Runtime configuration from environment variables (the only I/O of its kind).

Secrets never live in code or git: `BACKEND_BEARER_TOKEN` gates every endpoint
except /health, and `ANTHROPIC_API_KEY` is consumed by the AI layer (S3.x).
"""

from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path
from typing import TYPE_CHECKING

from pydantic import BaseModel, ConfigDict

from app.routing.egress import EgressThresholds

if TYPE_CHECKING:
    from app.routing.object_hazards import ObjectHazardThresholds

BACKEND_DIR = Path(__file__).resolve().parents[1]
CORPUS_DIR = BACKEND_DIR / "corpus"


class Settings(BaseModel):
    model_config = ConfigDict(frozen=True)

    bearer_token: str
    anthropic_api_key: str | None
    anthropic_model: str
    mongodb_uri: str | None
    mongodb_db_name: str

    @property
    def cloud_sync_enabled(self) -> bool:
        """Whether the S8 cloud layer can serve requests.

        Unlike `bearer_token`, a missing `MONGODB_URI` is NOT fatal. The
        deterministic engine, the corpus and every pre-S8 endpoint work with no
        database at all, and the demo path depends on them — so an unconfigured
        Mongo disables cloud sync rather than refusing to start the service.
        """
        return self.mongodb_uri is not None


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
        mongodb_uri=os.environ.get("MONGODB_URI") or None,
        mongodb_db_name=os.environ.get("MONGODB_DB_NAME", "escape_plan"),
    )


@lru_cache(maxsize=1)
def get_thresholds() -> EgressThresholds:
    """Egress thresholds from the corpus (metric authoritative), loaded once."""
    data = json.loads((CORPUS_DIR / "egress_thresholds.json").read_text())
    return EgressThresholds.from_corpus(data)

@lru_cache(maxsize=1)
def get_object_hazard_thresholds() -> ObjectHazardThresholds:
    """Object hazard thresholds from the corpus, loaded once."""
    # Runtime import to break the import cycle (config → object_hazards → models → …).
    # The type annotation uses the TYPE_CHECKING import at module level.
    from app.routing.object_hazards import ObjectHazardThresholds as _OHT
    data = json.loads((CORPUS_DIR / "object_hazard_thresholds.json").read_text())
    return _OHT.model_validate(data)
