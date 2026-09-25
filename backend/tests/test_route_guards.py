"""Every route is guarded unless it is on an explicit, short allow-list.

`/diff_obstructions` shipped without `require_token` and nothing noticed, because
each endpoint's auth test was written by hand next to the endpoint (audit
2026-09-25). This walks `app.routes` instead, so a route added tomorrow without a
guard fails here the day it lands, whichever guard it was supposed to use:

- the shared bearer token (`require_token`) on the compute and AI routes;
- the per-user JWT (`CurrentUser`) on `/auth/me` and `/homes*`.

Both answer 401 with no credentials, before any body validation or database
access, so an empty request is enough to tell a guarded route from an open one.
"""

from __future__ import annotations

import re

import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from app import config
from app.main import app

# Deliberately open. Adding to this list is a decision, not a fix for a red test.
OPEN_PATHS = frozenset(
    {
        "/health",  # Render's health check
        "/health/db",  # reports "disabled" / "ok" only, no data
        "/auth/register",  # how an account comes to exist
        "/auth/login",  # how a JWT comes to exist
    }
)
# FastAPI's own documentation routes are Starlette `Route`s, not `APIRoute`s, so
# they never reach the walk below; listed so the intent is written down.
DOCS_PATHS = frozenset({"/docs", "/docs/oauth2-redirect", "/redoc", "/openapi.json"})


@pytest.fixture(autouse=True)
def _token_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", "route-guard-test-token")
    # Configured as in production, so a wrong JWT is rejected by verification
    # (401) rather than by "auth not configured" (a deliberate loud 500).
    monkeypatch.setenv("JWT_SECRET_KEY", "route-guard-test-signing-secret-over-32-bytes")
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def _api_routes(routes, prefix: str = "") -> list[tuple[str, APIRoute]]:
    """Every APIRoute with its full path, including those from included routers.

    FastAPI flattened `include_router` into `app.routes` for years; 0.14x keeps an
    `_IncludedRouter` wrapper instead (its `original_router` plus a prefix in
    `include_context`). Handle both, and cross-check against the OpenAPI document
    below so a future layout change cannot make the walk silently come up short.
    """
    found: list[tuple[str, APIRoute]] = []
    for route in routes:
        if isinstance(route, APIRoute):
            found.append((prefix + route.path, route))
        elif hasattr(route, "original_router"):
            context = getattr(route, "include_context", None)
            inner_prefix = getattr(context, "prefix", "") or ""
            found.extend(_api_routes(route.original_router.routes, prefix + inner_prefix))
    return found


ALL_API_ROUTES = _api_routes(app.routes)


def _guarded_endpoints() -> list[tuple[str, str]]:
    pairs = []
    for path, route in ALL_API_ROUTES:
        if path in OPEN_PATHS | DOCS_PATHS:
            continue
        for method in sorted(route.methods - {"HEAD", "OPTIONS"}):
            pairs.append((method, path))
    return pairs


GUARDED = _guarded_endpoints()


def test_the_walk_actually_finds_the_routes():
    """Guard the guard: an empty walk would pass every assertion below."""
    paths = {path for _, path in GUARDED}
    for expected in (
        "/routes",
        "/score",
        "/diff_obstructions",
        "/explain",
        "/chat",
        "/auth/me",
        "/homes",
        "/homes/{home_id}",
    ):
        assert expected in paths, f"{expected} missing from the route walk"


def test_every_open_path_still_exists():
    """A renamed route must not leave a stale entry that silently exempts nothing."""
    api_paths = {path for path, _ in ALL_API_ROUTES}
    assert OPEN_PATHS <= api_paths


def test_the_walk_covers_every_documented_endpoint():
    """The OpenAPI document is FastAPI's own list; the walk must not miss any of it."""
    walked = {(m, p) for p, r in ALL_API_ROUTES for m in r.methods}
    documented = {
        (method.upper(), path)
        for path, ops in app.openapi()["paths"].items()
        for method in ops
    }
    assert documented <= walked, f"route walk missed {sorted(documented - walked)}"


@pytest.mark.parametrize(("method", "path"), GUARDED, ids=[f"{m} {p}" for m, p in GUARDED])
def test_route_rejects_a_request_with_no_credentials(method: str, path: str):
    client = TestClient(app, raise_server_exceptions=False)
    url = re.sub(r"\{[^}]+\}", "x", path)
    kwargs = {"json": {}} if method in {"POST", "PUT", "PATCH"} else {}
    resp = client.request(method, url, **kwargs)
    assert resp.status_code == 401, (
        f"{method} {path} answered {resp.status_code} with no credentials. Add "
        "dependencies=[Depends(require_token)] (or CurrentUser for per-user routes), "
        "or — only if it must be public — add it to OPEN_PATHS with a reason."
    )


@pytest.mark.parametrize(("method", "path"), GUARDED, ids=[f"{m} {p}" for m, p in GUARDED])
def test_route_rejects_a_wrong_bearer_token(method: str, path: str):
    client = TestClient(app, raise_server_exceptions=False)
    url = re.sub(r"\{[^}]+\}", "x", path)
    kwargs = {"json": {}} if method in {"POST", "PUT", "PATCH"} else {}
    resp = client.request(
        method, url, headers={"Authorization": "Bearer not-the-token"}, **kwargs
    )
    assert resp.status_code == 401, f"{method} {path} accepted a wrong token"
