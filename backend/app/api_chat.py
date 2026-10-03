"""S3.3 (prep) chat router: stateless `/chat`, wired into `app.main` via
`app.include_router(chat_router)`.

Kept as its own file (rather than growing `app.main`) so this can land, be
tested, and be reviewed independently of the S3.1 human deploy step it
depends on. See docs/decisions.md for why this session is "prep" not "DONE".
"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.ai.chat.service import ChatGroundingError, ChatMessage, ChatResponse, chat
from app.ai.grounded import GroundingError
from app.deps import AI_GUARDS
from app.limits import MAX_CHAT_MESSAGES, MAX_CHAT_TOTAL_CHARS
from app.models import HomeModel, Profile
from app.routing.plan import RoutePlan

router = APIRouter()

class ChatRequest(BaseModel):
    """S11.26 (AUD-035): the history is bounded by count and by total length.

    A long thread used to grow until the model itself rejected it, which reached
    the user as a 502 "AI unavailable" after they had already waited. Refusing
    with 422 up front lets the client trim and say so (S11.45); the server never
    truncates silently, because answering a question about a conversation the
    user did not send is worse on a safety app than an error they can see.
    """

    model_config = ConfigDict(extra="forbid")

    home: HomeModel
    route_plan: Optional[RoutePlan] = None
    profiles: list[Profile] = Field(default_factory=list)
    messages: list[ChatMessage] = Field(min_length=1, max_length=MAX_CHAT_MESSAGES)

    @model_validator(mode="after")
    def _history_within_total_budget(self) -> "ChatRequest":
        total = sum(len(message.content) for message in self.messages)
        if total > MAX_CHAT_TOTAL_CHARS:
            raise ValueError(
                f"conversation is {total:,} characters, over the maximum of "
                f"{MAX_CHAT_TOTAL_CHARS:,}. Send fewer earlier turns."
            )
        return self


@router.post(
    "/chat",
    response_model=ChatResponse,
    # The one shared guard stack (app/deps.py), identical to the AI routes in
    # app.main — including S11.27's daily budget, which this route used to be
    # able to miss simply by not being edited.
    dependencies=AI_GUARDS,
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
