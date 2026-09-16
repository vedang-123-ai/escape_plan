"""S8.2 auth and cloud-sync endpoints: /auth/register, /auth/login, /homes.

Thin, per the project's FastAPI convention — hashing lives in `app.auth`,
storage in `app.cloud_repo`.

These endpoints use a **JWT per user**, which is a different axis from the
shared `BACKEND_BEARER_TOKEN` guarding the deterministic endpoints. The bearer
token says "this build may talk to this server"; a JWT says "this request is
this user". Cloud-sync routes need the second; they do not layer the first,
because a per-user credential is the stronger claim.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.auth.passwords import hash_password, verify_password
from app.auth.tokens import AuthTokenError, create_access_token, decode_access_token
from app.cloud_models import (
    StoredHomeModel,
    User,
    UserPublic,
    normalise_email,
)
from app.cloud_repo import (
    EmailAlreadyRegistered,
    HomeNotOwned,
    HomeRepository,
    UserRepository,
)
from app.database import database
from app.models import HomeModel

router = APIRouter(tags=["cloud"])

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)

# RFC 6750: a 401 must carry WWW-Authenticate. One shared instance so every
# rejection is byte-identical — a difference between them is an oracle.
_UNAUTHORIZED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Could not validate credentials",
    headers={"WWW-Authenticate": "Bearer"},
)

# Verified against a throwaway hash when the email is unknown, so a missing user
# costs the same wall-clock time as a real one. Without it, "no such account"
# returns in microseconds while a real account costs a full Argon2 hash — which
# is a timing oracle for enumerating who has registered.
_DUMMY_HASH = hash_password("a-password-that-is-never-anyone's")


class RegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str
    # 8 is a floor, not a policy. Argon2 has no upper limit, and NIST advises
    # against composition rules, so length is the only constraint imposed.
    password: str = Field(min_length=8, max_length=1024)

    @field_validator("email")
    @classmethod
    def _check_email(cls, value: str) -> str:
        """Validate HERE, not only on User. Without this the address reaches
        User() inside the handler, where a ValidationError is an unhandled 500
        rather than the 422 a malformed request deserves."""
        return normalise_email(value)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class HomeSyncRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home: HomeModel
    home_id: str | None = None
    """Omit to create; supply to update an existing home you own."""


def _users() -> UserRepository:
    """`database.db` raises CloudSyncDisabled when unconfigured, which the
    app-level handler turns into 503. Deliberately not a branch on
    `database.enabled` — a branch would skip the write and report success."""
    return UserRepository(database.db)


def _homes() -> HomeRepository:
    return HomeRepository(database.db)


async def get_current_user(
    token: Annotated[str | None, Depends(oauth2_scheme)],
) -> User:
    """Resolve the bearer JWT to a live user, or 401.

    The user is re-read from the database on every request rather than trusted
    from the token, so a deleted account cannot keep acting until its token
    expires.
    """
    if not token:
        raise _UNAUTHORIZED
    try:
        user_id = decode_access_token(token)
    except AuthTokenError:
        raise _UNAUTHORIZED

    user = await _users().find_by_id(user_id)
    if user is None:
        raise _UNAUTHORIZED
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


@router.post("/auth/register", response_model=UserPublic, status_code=201)
async def register(request: RegisterRequest) -> UserPublic:
    """Create an account. The password is hashed before the User is built, so
    no object in this process ever holds it alongside the stored record."""
    user = User(email=request.email, hashed_password=hash_password(request.password))
    try:
        created = await _users().create(user)
    except EmailAlreadyRegistered:
        # 409, and the same wording regardless — "email already registered" is
        # unavoidable on a register form, but it must not vary by account state.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="That email address is already registered.",
        )
    return UserPublic.from_user(created)


@router.post("/auth/login", response_model=TokenResponse)
async def login(
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
) -> TokenResponse:
    """Exchange credentials for a JWT.

    `OAuth2PasswordRequestForm` names the field `username`; ours is an email.
    """
    email = form_data.username.strip().lower()
    user = await _users().find_by_email(email)

    # Always run a verification, even with no user, so the response time does
    # not reveal whether the address exists.
    hashed = user.hashed_password if user else _DUMMY_HASH
    if not verify_password(form_data.password, hashed) or user is None:
        raise _UNAUTHORIZED

    return TokenResponse(access_token=create_access_token(user.id))


@router.get("/auth/me", response_model=UserPublic)
async def me(user: CurrentUser) -> UserPublic:
    return UserPublic.from_user(user)


@router.get("/homes", response_model=list[StoredHomeModel])
async def list_homes(user: CurrentUser) -> list[StoredHomeModel]:
    """Every home belonging to the authenticated user. The user id comes from
    the verified token, never from a query parameter."""
    return await _homes().list_for_user(user.id)


@router.post("/homes", response_model=StoredHomeModel, status_code=201)
async def sync_home(request: HomeSyncRequest, user: CurrentUser) -> StoredHomeModel:
    """Create or update one home for the authenticated user.

    `revision` increments server-side. S8.4's merge needs a monotonic counter it
    can trust, and a client-supplied one is not trustworthy — so the request
    body has no revision field at all.
    """
    repo = _homes()
    revision = 1
    created_at = None
    if request.home_id is not None:
        existing = await repo.find_for_user(request.home_id, user.id)
        if existing is None:
            # 404 rather than 403: confirming that an id exists but belongs to
            # someone else would leak the existence of other users' homes.
            raise HTTPException(status_code=404, detail="No such home.")
        revision = existing.revision + 1
        # Carry the ORIGINAL creation time forward. `upsert` does a full
        # `replace_one`, so a freshly defaulted `created_at` would silently
        # overwrite it on every update and the field would just mean "last
        # written" — indistinguishable from `updated_at`. Found 2026-09-15.
        created_at = existing.created_at

    stored = StoredHomeModel(
        **({"id": request.home_id} if request.home_id else {}),
        **({"created_at": created_at} if created_at else {}),
        user_id=user.id,
        home=request.home,
        revision=revision,
    )
    try:
        return await repo.upsert(stored)
    except HomeNotOwned:
        raise HTTPException(status_code=404, detail="No such home.")
