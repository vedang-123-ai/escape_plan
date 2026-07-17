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
from pydantic import BaseModel, ConfigDict, Field

from app.ai.agent import AgentError, AnalysisResult, run_agent_analysis
from app.ai.grounded import ExplainResponse, GroundingError, explain_routes
from app.api_chat import router as chat_router
from app.config import get_settings, get_thresholds
from app.convert.converter import convert_scan
from app.models import HomeModel, Profile
from app.routing.engine import compute_route_plan
from app.routing.plan import RoutePlan, RoutingConstraints
from app.routing.profiles import find_profile
from app.scoring.findings import Finding
from app.scoring.recommend import recommendation_items
from app.scoring.score import ScoreBreakdown, compute_score

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
    profile_id: Optional[str] = None
    """Route for one household member: their tags derive `constraints` via the
    S3.4 mapping table. Mutually exclusive with an explicit `constraints`."""


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
    profile = None
    if request.profile_id is not None:
        if request.constraints is not None:
            raise HTTPException(
                status_code=422,
                detail="pass either profile_id or constraints, not both",
            )
        profile = find_profile(request.home.profiles, request.profile_id)
        if profile is None:
            raise HTTPException(
                status_code=404,
                detail=f"no profile '{request.profile_id}' in this home",
            )
    return compute_route_plan(
        request.home,
        get_thresholds(),
        constraints=request.constraints,
        profile=profile,
    )


class ConvertRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    scan: dict[str, Any]
    home_name: str = "Scanned Home"


@app.post(
    "/convert",
    response_model=HomeModel,
    # Optional fields the converter never sets (egress, confidence on manual items)
    # serialize as explicit nulls by default, which additionalProperties/nullability
    # in the JSON Schema rejects — e.g. "egress": null. Omit them instead.
    response_model_exclude_none=True,
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


class AnalyzeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home: HomeModel


@app.post(
    "/analyze",
    response_model=AnalysisResult,
    dependencies=[Depends(require_token)],
)
def analyze(request: AnalyzeRequest) -> AnalysisResult:
    """Agentic safety inspection: tool-use loop over the home, evidence-linked
    findings only (S3.2). The agent never computes routes or egress itself —
    it calls the same deterministic engines /routes and /explain use."""
    try:
        return run_agent_analysis(request.home, get_thresholds())
    except AgentError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


class ScoreRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home: HomeModel
    constraints: Optional[RoutingConstraints] = None
    findings: list[Finding] = Field(
        default_factory=list,
        description="Findings from /analyze (S3.2). Omit for a routes-and-checklist "
        "score; the findings component then sits at full marks.",
    )
    checklist_state: dict[str, bool] = Field(
        default_factory=dict,
        description="item id -> done, as persisted on the home document.",
    )
    include_recommendations: bool = Field(
        default=False,
        description="Append grounded AI recommendations (S3.1) to the checklist. "
        "They are advisory only and never change the score.",
    )
    profile: Optional[Profile] = None


@app.post(
    "/score",
    response_model=ScoreBreakdown,
    dependencies=[Depends(require_token)],
)
def score(request: ScoreRequest) -> ScoreBreakdown:
    """Explainable 0-100 preparedness score + checklist (S3.5).

    The score itself is deterministic — weights in
    docs/preparedness-score-weights.md. `include_recommendations` is the only
    part that calls the AI, and only to add non-scoring checklist items.
    """
    plan = compute_route_plan(
        request.home, get_thresholds(), constraints=request.constraints
    )
    breakdown = compute_score(
        request.home, plan, request.findings, request.checklist_state
    )
    if request.include_recommendations:
        try:
            breakdown.checklist.extend(
                recommendation_items(
                    request.home, plan, request.checklist_state, request.profile
                )
            )
        except GroundingError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
    return breakdown
