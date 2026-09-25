"""S3.3 (prep) chat router: stateless `/chat`, wired into `app.main` via
`app.include_router(chat_router)`.

Kept as its own file (rather than growing `app.main`) so this can land, be
tested, and be reviewed independently of the S3.1 human deploy step it
depends on. See docs/decisions.md for why this session is "prep" not "DONE".
"""

from __future__ import annotations

import secrets
from typing import Annotated, Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field

from app.ai.chat.service import ChatGroundingError, ChatMessage, ChatResponse, chat
from app.ai.grounded import GroundingError
from app.config import get_settings
from app.models import HomeModel, Profile
from app.rate_limit import ai_concurrency, ai_rate_limit
from app.routing.plan import RoutePlan

router = APIRouter()

# Duplicated (not imported) from app.main.require_token: importing it here
# would create a main <-> api_chat circular import since main.py includes
# this router. Same bearer-token check, same fail-closed Settings source.
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


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home: HomeModel
    route_plan: Optional[RoutePlan] = None
    profiles: list[Profile] = Field(default_factory=list)
    messages: list[ChatMessage] = Field(min_length=1)


@router.post(
    "/chat",
    response_model=ChatResponse,
    # Token first, then the AI cost guard (app/rate_limit.py), as in app.main.
    dependencies=[Depends(require_token), Depends(ai_rate_limit), Depends(ai_concurrency)],
)
def post_chat(request: ChatRequest) -> ChatResponse:
    """Grounded, house-aware, multi-turn chat (S3.1's corpus + citation rules)."""
    try:
        return chat(
            request.messages,
            request.home,
            request.route_plan,
            request.profiles,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except (ChatGroundingError, GroundingError) as exc:
        # GroundingError covers the unset-ANTHROPIC_API_KEY path — a deliberate
        # 502, matching /explain and /analyze, not an accidental 500.
        raise HTTPException(status_code=502, detail=str(exc)) from exc
