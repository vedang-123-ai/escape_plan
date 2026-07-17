"""FastAPI service (S1.6): thin HTTP wrappers over the pure engines.

Endpoints stay skinny — all domain logic lives in app.routing (and app.ai from
S3.1 on). /health is open for platform health checks; everything else requires
the shared bearer token.
"""

from __future__ import annotations

import logging
import secrets
from datetime import datetime, timezone
from typing import Annotated, Any, Optional

from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict

from app.ai.grounded import ExplainResponse, GroundingError, explain_routes
from app.api_chat import router as chat_router
from app.config import get_settings, get_thresholds
from app.convert.converter import convert_scan
from app.models import HomeModel, Profile
from app.routing.engine import compute_route_plan
from app.routing.plan import RoutePlan, RoutingConstraints

logging.basicConfig(level=logging.INFO)

app = FastAPI(
    title="Escape Plan backend",
    description=(
        "Deterministic fire-escape routing over HomeModel documents, plus the "
        "grounded AI explanation layer. Routing is never done by AI."
    ),
    version="1.0",
)
app.include_router(chat_router)

_bearer_scheme = HTTPBearer(auto_error=False)


def require_token(
    credentials: Annotated[
        Optional[HTTPAuthorizationCredentials], Depends(_bearer_scheme)
    ],
) -> None:
    expected = get_settings().bearer_token
    if credentials is None or not secrets.compare_digest(
        credentials.credentials, expected
    ):
        raise HTTPException(status_code=401, detail="Invalid or missing bearer token")


class RoutesRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home: HomeModel
    constraints: Optional[RoutingConstraints] = None


class HealthResponse(BaseModel):
    status: str
    version: str


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", version=app.version)


@app.post(
    "/routes",
    response_model=RoutePlan,
    dependencies=[Depends(require_token)],
)
def routes(request: RoutesRequest) -> RoutePlan:
    """Compute primary/secondary escape routes for every room (deterministic)."""
    return compute_route_plan(
        request.home, get_thresholds(), constraints=request.constraints
    )


class ConvertRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    scan: dict[str, Any]
    home_name: str = "Scanned Home"


@app.post(
    "/convert",
    response_model=HomeModel,
    dependencies=[Depends(require_token)],
)
def convert(request: ConvertRequest) -> HomeModel:
    """RoomPlan export → validated HomeModel (S1.5 converter, pure)."""
    try:
        return convert_scan(
            request.scan,
            home_name=request.home_name,
            timestamp=datetime.now(timezone.utc),
        )
    except Exception as exc:  # malformed exports are a client error, not a 500
        raise HTTPException(
            status_code=422, detail=f"scan could not be converted: {exc}"
        ) from exc


class ExplainRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home: HomeModel
    route_plan: RoutePlan
    profile: Optional[Profile] = None


@app.post(
    "/explain",
    response_model=ExplainResponse,
    dependencies=[Depends(require_token)],
)
def explain(request: ExplainRequest) -> ExplainResponse:
    """Grounded, cited explanation of an already-computed RoutePlan (S3.1)."""
    try:
        return explain_routes(request.home, request.route_plan, request.profile)
    except GroundingError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
