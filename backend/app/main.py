"""FastAPI service (S1.6): thin HTTP wrappers over the pure engines.

Endpoints stay skinny — all domain logic lives in app.routing (and app.ai from
S3.1 on). /health is open for platform health checks; everything else requires
the shared bearer token.
"""

from __future__ import annotations

import logging
from app.routing.diff import compute_diff
import secrets
from datetime import datetime, timezone
from typing import Annotated, Any, Optional, Literal

import anthropic
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field
from app.models import HomeModel, FloorObject
from app.routing.obstructions import Obstruction
from app.routing.egress import EgressThresholds

class DiffRequest(BaseModel):
    stored_model: HomeModel
    scan_model: HomeModel
    target_room_id: str

class DiffResult(BaseModel):
    success: bool
    error: str | None = None
    diff_objects: list[FloorObject]
    obstructions: list[Obstruction]


from app.ai.agent import AgentError, AnalysisResult, run_agent_analysis
from app.ai.builder import BuilderError, BuildResult, run_builder
from app.ai.grounded import ExplainResponse, GroundingError, explain_routes
from app.api_chat import router as chat_router
from app.config import get_settings, get_thresholds
from app.convert.converter import convert_scan
from app.models import HomeModel, Profile
from app.routing.engine import compute_route_plan
from app.routing.hazard import EvacuationTimeline, compute_evacuation_timeline
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


# Every AI module raises its own domain error (GroundingError/AgentError/BuilderError)
# for the missing-key case, but the `client.messages.create` calls themselves are
# unguarded — so an exhausted credit balance, a rate limit, or an API outage escaped
# as a bare 500 "Internal Server Error" with nothing the app could show a user.
# Found 2026-08-04 by running the endpoints against a dry account. One app-level
# handler covers every endpoint (including the chat router) and any added later.
def _anthropic_message(exc: anthropic.APIError) -> str:
    """The human-readable half of an SDK error.

    `exc.message` is the full repr ("Error code: 400 - {'type': 'error', ...}"),
    which is fine for a log and useless in a banner. The API puts the sentence a
    person should read at `error.message`, so prefer that.
    """
    for source in (getattr(exc, "body", None), _response_json(exc)):
        if isinstance(source, dict):
            error = source.get("error")
            if isinstance(error, dict) and isinstance(error.get("message"), str):
                return error["message"]
    return getattr(exc, "message", None) or str(exc) or exc.__class__.__name__


def _response_json(exc: anthropic.APIError) -> Any:
    response = getattr(exc, "response", None)
    if response is None:
        return None
    try:
        return response.json()
    except Exception:  # non-JSON error bodies (proxies, gateways) are expected
        return None


@app.exception_handler(anthropic.APIError)
def anthropic_error(_request: Request, exc: anthropic.APIError) -> JSONResponse:
    """Map Anthropic SDK failures to a labelled 502/503 instead of a bare 500.

    503 means "the same request may work shortly" (rate limit, overload, network);
    502 means an operator has to act (no credit, bad key). The app uses the split to
    decide between a retry affordance and an honest "AI is unavailable" banner.
    """
    retryable = isinstance(
        exc, (anthropic.RateLimitError, anthropic.APIConnectionError)
    ) or getattr(exc, "status_code", None) in (500, 502, 503, 529)

    detail = _anthropic_message(exc)
    logging.error(
        "Anthropic API failure (%s): %s", exc.__class__.__name__, exc, exc_info=True
    )

    if retryable:
        return JSONResponse(
            status_code=503,
            content={"detail": f"The AI service is temporarily unavailable: {detail}"},
        )
    return JSONResponse(
        status_code=502,
        content={"detail": f"The AI service rejected the request: {detail}"},
    )


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
    """(S1.2) Compute primary/secondary routes for every room.
    
    If peril is omitted, defaults to fire.
    """

    model_config = ConfigDict(extra="forbid")

    home: HomeModel
    peril: Literal["fire", "tornado", "earthquake"] = "fire"
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
        peril=request.peril,
        profile=profile,
    )


class EvacuateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home: HomeModel
    origin_room_id: str
    """The room the fire starts in — the room the user tapped."""
    profile_set_id: Optional[str] = None


@app.post(
    "/evacuate",
    response_model=EvacuationTimeline,
    dependencies=[Depends(require_token)],
)
def evacuate(request: EvacuateRequest) -> EvacuationTimeline:
    """Ignite a room and re-solve every occupant's escape around the spread.

    Same deterministic engine as /routes — the hazard walks the S1.1 nav graph
    and every path is Dijkstra. No AI is involved, and the timeline is
    explicitly illustrative (see app/routing/hazard.py).
    """
    room_ids = {r.id for f in request.home.floors for r in f.rooms}
    if request.origin_room_id not in room_ids:
        raise HTTPException(
            status_code=404,
            detail=f"no room '{request.origin_room_id}' in this home",
        )
    return compute_evacuation_timeline(
        request.home,
        get_thresholds(),
        request.origin_room_id,
        profile_set_id=request.profile_set_id,
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
        model, warnings = convert_scan(
            request.scan,
            home_name=request.home_name,
            timestamp=datetime.now(timezone.utc),
        )
        for w in warnings:
            logging.warning(f"convert_scan: {w}")
        return model
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


class BuildRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    description: Optional[str] = None
    image_b64: Optional[str] = None
    image_media_type: str = "image/png"


@app.post(
    "/build",
    response_model=BuildResult,
    # BuildResult contains a HomeModel. As with /convert, omit optional model
    # fields rather than serializing schema-invalid nulls into that document.
    response_model_exclude_none=True,
    dependencies=[Depends(require_token)],
)
def build(request: BuildRequest) -> BuildResult:
    """LLM house builder (revamp C1): constructs a DRAFT HomeModel from a text
    description and/or floor-plan image via a capped tool-use loop. Everything
    it emits is source=ai_plan + low confidence — the app forces editor review
    before any routes are computed. The builder has no routing tools; the
    deterministic engine remains the only route authority."""
    if not request.description and not request.image_b64:
        raise HTTPException(
            status_code=422, detail="provide a description, an image, or both"
        )
    try:
        return run_builder(
            description=request.description,
            image_b64=request.image_b64,
            image_media_type=request.image_media_type,
        )
    except BuilderError as exc:
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
    thresholds = get_thresholds()
    plan = compute_route_plan(request.home, thresholds, constraints=request.constraints, peril="fire")
    tornado_plan = compute_route_plan(request.home, thresholds, request.constraints, peril="tornado")
    earthquake_plan = compute_route_plan(request.home, thresholds, request.constraints, peril="earthquake")

    breakdown = compute_score(
        request.home,
        plan,
        request.findings,
        request.checklist_state,
        thresholds,
        tornado_plan=tornado_plan,
        earthquake_plan=earthquake_plan
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

@app.post(
    "/diff_obstructions",
    response_model=DiffResult,
    tags=["Routing"],
    summary="Diff a partial scan against a stored room",
    description="Finds new objects and re-evaluates egress obstructions.",
)
def diff_obstructions(req: DiffRequest):
    thresholds = EgressThresholds(window_min_area_m2=0, window_min_area_grade_m2=0, window_min_height_m=0, window_min_width_m=0, window_max_sill_m=0, door_min_width_m=0.8, door_min_height_m=2.0)
    # Read registration tolerance from object_hazard_thresholds
    with open("corpus/object_hazard_thresholds.json") as f:
        import json
        t_data = json.load(f)
    tol = t_data["engineering_constants"]["registration_tolerance_m"]["value"]
    
    return compute_diff(req.stored_model, req.scan_model, req.target_room_id, thresholds, tol)
