"""FastAPI service (S1.6): thin HTTP wrappers over the pure engines.

Endpoints stay skinny — all domain logic lives in app.routing (and app.ai from
S3.1 on). /health is open for platform health checks; everything else requires
the shared bearer token.
"""

from __future__ import annotations

import logging
from app.routing.diff import compute_diff, DiffRequest, DiffResult
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any, AsyncIterator, Optional, Literal

import anthropic
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, model_validator
from app.models import HomeModel, FloorObject
from app.routing.obstructions import Obstruction
from app.routing.egress import EgressThresholds

from app.ai.agent import AgentError, AnalysisResult, run_agent_analysis
from app.ai.builder import BuilderError, BuildResult, run_builder
from app.ai.grounded import ExplainResponse, GroundingError, explain_routes
from app.api_auth import router as cloud_router
from app.api_chat import router as chat_router
from app.config import get_settings, get_thresholds, get_object_hazard_thresholds
from app.convert.converter import ConversionError, convert_scan
from app.database import CloudSyncDisabled, database
from app.limits import (
    BodySizeLimitMiddleware,
    ImageMediaType,
    MAX_BUILD_DESCRIPTION_CHARS,
    MAX_IMAGE_B64_CHARS,
    MAX_IMAGE_DECODED_BYTES,
    decoded_image_bytes,
)
from app.deps import AI_GUARDS, ai_guards_for_optional_call, require_token
from app.rate_limit import (
    BUDGET_COST_ANALYZE,
    BUDGET_COST_BUILD,
    BUDGET_COST_SINGLE_CALL,
    budget,
    enforce_budget,
)
from app.models import HomeModel, Profile
from app.routing.engine import compute_route_plan
from app.routing.hazard import EvacuationTimeline, compute_evacuation_timeline
from app.routing.plan import RoutePlan, RoutingConstraints
from app.routing.profiles import find_profile
from app.scoring.findings import Finding
from app.scoring.recommend import recommendation_items
from app.scoring.score import ScoreBreakdown, compute_score

logging.basicConfig(level=logging.INFO)

# Pin pymongo's command logger to INFO, whatever the root level is.
#
# pymongo logs every command it issues — including the full document — at DEBUG. Since S8.4
# that means users' home layouts: floor polygons, room names, `meta.address_optional` and the
# household composition, written into the process log on every sync. Raising the root logger to
# DEBUG is a thing people do while chasing an unrelated bug, and on a hosted service those logs
# are retained and readable by anyone with dashboard access.
#
# So the protection cannot be "we happen to run at INFO" — it has to survive someone turning
# the root level up. `propagate` is left alone: these loggers still reach the root handler, they
# just will not emit below INFO. Anyone who genuinely needs wire-level pymongo output can set
# this logger explicitly, which is a deliberate act rather than a side effect.
for _pymongo_logger in ("pymongo", "pymongo.command", "pymongo.connection", "pymongo.serverSelection"):
    logging.getLogger(_pymongo_logger).setLevel(logging.INFO)

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Own the MongoDB pool for the process lifetime (S8.1).

    `lifespan` rather than `@app.on_event`, which FastAPI documents as
    deprecated. Connecting here — not per request — is what keeps a single
    connection pool; `database.connect()` is a no-op when MONGODB_URI is unset,
    so this is inert for anyone not using cloud sync.
    """
    await database.connect()
    try:
        yield
    finally:
        await database.close()


app = FastAPI(
    title="Escape Plan backend",
    description=(
        "Deterministic fire-escape routing over HomeModel documents, plus the "
        "grounded AI explanation layer. Routing is never done by AI."
    ),
    version="1.0",
    lifespan=lifespan,
)
app.include_router(chat_router)
app.include_router(cloud_router)

# S11.26 (AUD-004): refuse an oversized body with 413 before anything parses it.
# Added last so it runs outermost — the check has to happen before routing, the
# bearer-token dependency, and pydantic, which is the whole point of it.
app.add_middleware(BodySizeLimitMiddleware)

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


@app.exception_handler(CloudSyncDisabled)
def cloud_sync_disabled(_request: Request, exc: CloudSyncDisabled) -> JSONResponse:
    """503, not the bare 500 a RuntimeError would otherwise produce.

    Cloud sync is optional, so "no database configured" is a deployment state, not
    a bug. 503 tells the client the feature is unavailable rather than that the
    request was malformed or the server broke.

    Routes must raise this at the top rather than branching on `database.enabled`
    — a branch would silently skip a write and report success.
    """
    logging.warning("cloud-sync route reached with no database: %s", exc)
    return JSONResponse(
        status_code=503,
        content={"detail": "Cloud sync is not configured on this server."},
    )


# `CloudSyncDisabled` covers "no database CONFIGURED". It does not cover "database
# configured but UNREACHABLE" — a different state with the same right answer.
# Found 2026-09-15 against the deployed service: `MONGODB_URI` was set but Atlas
# was not allow-listing Render's IPs, so `/health/db` reported "unreachable" while
# `POST /auth/register` returned a bare **500 Internal Server Error** with no body.
# That is the worst possible answer for S8.3/S8.4: the iOS client cannot tell a
# transient outage it should retry from a malformed request it must not.
#
# `ConnectionFailure` is the precise seam. It is the base of
# ServerSelectionTimeoutError, NetworkTimeout, AutoReconnect and
# WaitQueueTimeoutError, and is NOT a base of OperationFailure — so a genuine bug
# in one of our queries still surfaces as a 500 rather than being dressed up as a
# transient blip. The import is guarded to preserve the property `database.py`
# relies on: the app must still import when the driver is absent.
try:  # pragma: no cover - exercised by whether the handler below registers
    from pymongo.errors import ConnectionFailure as _ConnectionFailure
except ImportError:  # pragma: no cover - driver-absent deployments
    _ConnectionFailure = None

if _ConnectionFailure is not None:

    @app.exception_handler(_ConnectionFailure)
    def cloud_sync_unreachable(
        _request: Request, exc: Exception
    ) -> JSONResponse:
        """503 with a retryable message when the database cannot be reached.

        Mirrors the Anthropic handler's split above: 503 means "the same request
        may work shortly", which is exactly true of a network partition, an Atlas
        IP allow-list that has not caught up, or a paused free-tier cluster.
        """
        logging.error(
            "cloud-sync route could not reach the database (%s): %s",
            exc.__class__.__name__,
            exc,
            exc_info=True,
        )
        return JSONResponse(
            status_code=503,
            content={
                "detail": "Cloud sync is temporarily unavailable. Please try again."
            },
        )


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
    """Numbers only, deliberately.

    /health is open so a platform probe can reach it, so everything here is
    readable by anyone. The AI budget fields are counts, not configuration and
    not identities: they say how much of today's allowance is left, which is what
    the owner needs to see before filming and what tells us whether a 429 is the
    budget or the rate limiter. They reveal nothing about who spent it.
    """

    status: str
    version: str
    commit: str
    """The deployed git commit (Render sets RENDER_GIT_COMMIT), so a smoke check can
    tell which build is live. A public commit hash, not a secret."""
    ai_calls_remaining_today: int
    ai_calls_spent_today: int


def _deployed_commit() -> str:
    import os

    return os.environ.get("RENDER_GIT_COMMIT", "").strip() or "unknown"


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    settings = get_settings()
    return HealthResponse(
        status="ok",
        version=app.version,
        commit=_deployed_commit(),
        ai_calls_remaining_today=budget.remaining(settings.ai_daily_call_budget),
        ai_calls_spent_today=budget.spent_today(),
    )


class DatabaseHealthResponse(BaseModel):
    """`database` is one of: disabled (no MONGODB_URI), ok, unreachable."""

    database: Literal["disabled", "ok", "unreachable"]
    db_name: str | None


@app.get("/health/db", response_model=DatabaseHealthResponse)
async def health_db() -> DatabaseHealthResponse:
    """Cloud-sync connectivity (S8.1).

    Open, like /health, so a platform probe can reach it. It reveals only
    whether a database is configured and reachable — never the URI, which
    carries credentials.

    Returns 200 even when the database is unreachable: the endpoint's job is to
    report that fact, and a 5xx here would be indistinguishable from the whole
    service being down.
    """
    status = await database.status()
    # Both fields come from the live client state, never from the environment.
    # Reading `db_name` from settings let the body contradict itself — a bad
    # MONGODB_URI reports "disabled" while settings still names a database.
    return DatabaseHealthResponse(
        database=status,
        db_name=get_settings().mongodb_db_name if database.enabled else None,
    )


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
    except ConversionError as exc:
        # Malformed export: the client's fault. The message is curated, never the
        # exception text, so no Python internals or field paths reach the phone.
        logging.warning("convert_scan rejected a scan: %s", exc.__class__.__name__)
        raise HTTPException(
            status_code=422,
            detail="This scan could not be converted. Re-scan the home and try again.",
        ) from exc
    except Exception as exc:
        # Anything else is a server bug: log the traceback and say so honestly.
        logging.error("convert_scan failed unexpectedly", exc_info=True)
        raise HTTPException(
            status_code=500, detail="The server failed to convert this scan."
        ) from exc


class ExplainRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home: HomeModel
    route_plan: RoutePlan
    profile: Optional[Profile] = None


@app.post(
    "/explain",
    response_model=ExplainResponse,
    dependencies=AI_GUARDS,
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
    dependencies=AI_GUARDS,
)
def analyze(request: AnalyzeRequest) -> AnalysisResult:
    """Agentic safety inspection: tool-use loop over the home, evidence-linked
    findings only (S3.2). The agent never computes routes or egress itself —
    it calls the same deterministic engines /routes and /explain use."""
    # S11.27: the agent loop makes up to MAX_ITERATIONS model calls plus submit
    # retries; charge the remainder over the base cost AI_GUARDS already took.
    enforce_budget(BUDGET_COST_ANALYZE - BUDGET_COST_SINGLE_CALL)
    try:
        return run_agent_analysis(request.home, get_thresholds())
    except AgentError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


class BuildRequest(BaseModel):
    """S11.26 (AUD-024, AUD-035): every field is bounded, and the media type is an
    allow-list rather than a string forwarded to Anthropic unchecked.

    `image_media_type` keeps its "image/png" default: the PDF path really does
    render a PNG, and the photo path is fixed client-side in S11.33.

    Read the allow-list narrowly. It refuses a CORRECTLY LABELLED unsupported
    type, so a caller that honestly says `image/heic` now gets a 422 naming the
    problem instead of paying for a model call that returns "AI unavailable".
    It does NOT fix AUD-024's user-visible symptom: `APIClient+Build.swift`
    hardcodes `image_media_type = "image/png"` at both the struct and function
    defaults and `BuildFromPlanView` omits the argument, so real HEIC camera bytes
    still arrive labelled `image/png`, still pass this allow-list and the base64
    decode, and still reach Anthropic. The mislabel is a client bug and S11.33
    owns it; this is the server half only.
    """

    model_config = ConfigDict(extra="forbid")

    description: Optional[str] = Field(
        default=None, max_length=MAX_BUILD_DESCRIPTION_CHARS
    )
    image_b64: Optional[str] = Field(default=None, max_length=MAX_IMAGE_B64_CHARS)
    image_media_type: ImageMediaType = "image/png"

    @model_validator(mode="after")
    def _image_is_decodable(self) -> "BuildRequest":
        """Reject a payload that is not really base64, or that decodes larger than
        Anthropic accepts, before any model call is made."""
        if self.image_b64 is None:
            return self
        decoded = decoded_image_bytes(self.image_b64)  # ValueError -> 422
        if decoded > MAX_IMAGE_DECODED_BYTES:
            raise ValueError(
                f"image is {decoded:,} bytes decoded, over the maximum of "
                f"{MAX_IMAGE_DECODED_BYTES:,}. Downscale it (long edge 1568 px) "
                f"and re-encode as JPEG."
            )
        return self


@app.post(
    "/build",
    response_model=BuildResult,
    # BuildResult contains a HomeModel. As with /convert, omit optional model
    # fields rather than serializing schema-invalid nulls into that document.
    response_model_exclude_none=True,
    dependencies=AI_GUARDS,
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
    # S11.27: the builder is a LOOP of up to MAX_ITERATIONS model calls, so the
    # base cost the guard already charged is not what this request can spend.
    # Charged here rather than in AI_GUARDS because the guard runs before body
    # validation, and a malformed request must not cost a full loop's budget.
    enforce_budget(BUDGET_COST_BUILD - BUDGET_COST_SINGLE_CALL)
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
def score(request: ScoreRequest, http_request: Request) -> ScoreBreakdown:
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
        # S11.27 (AUD-006): this is an AI call and must obey the AI guards, but
        # /score itself must NOT — it is deterministic and the demo path leans on
        # it, so rate-limiting the whole route would throttle the thing that works
        # when the AI is down. The guards cannot be route-level dependencies for a
        # flag that is per-request, so they are applied here instead, in the same
        # order and from the same module as AI_GUARDS.
        with ai_guards_for_optional_call(http_request):
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
    # Was the one compute route left open (audit 2026-09-25). The iOS caller
    # already sends the token (APIClient+Convert.swift); tests/test_route_guards.py
    # now fails any future route that forgets this.
    dependencies=[Depends(require_token)],
)
def diff_obstructions(
    req: DiffRequest,
    thresholds: EgressThresholds = Depends(get_thresholds)
) -> DiffResult:
    tol = get_object_hazard_thresholds().engineering_constants.registration_tolerance_m.value
    return compute_diff(req.stored_model, req.scan_model, req.target_room_id, thresholds, tol)
