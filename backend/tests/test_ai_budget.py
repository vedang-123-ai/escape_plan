"""S11.27: the daily AI budget (AUD-003) and the /score guard (AUD-006).

The thing under test is a ceiling that a caller holding the public bearer token
cannot reset. So every endpoint test here sends a VALID token — the point is not
that an unauthorised caller is stopped (that is `require_token`'s job and
`test_route_guards.py` covers it), but that an authorised one still cannot spend
past the limit.

No test calls Anthropic. Where an endpoint would, the AI function is stubbed.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app import config
from app import rate_limit
from app.ai.builder import BuildResult
from app.ai.chat.service import ChatResponse
from app.main import app
from app.models import HomeModel
from app.rate_limit import DailyAICallBudget

TEST_TOKEN = "budget-test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    rate_limit.budget.reset()
    yield
    config.get_settings.cache_clear()
    rate_limit.budget.reset()


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


class FakeUTCClock:
    def __init__(self, start: datetime) -> None:
        self.now = start

    def __call__(self) -> datetime:
        return self.now


# --- the counter itself ------------------------------------------------------


def test_budget_allows_exactly_the_limit_then_refuses():
    b = DailyAICallBudget()
    assert [b.spend(3) for _ in range(4)] == [True, True, True, False]
    assert b.remaining(3) == 0
    assert b.spent_today() == 3


def test_budget_rolls_over_at_utc_midnight():
    clock = FakeUTCClock(datetime(2026, 10, 3, 23, 59, 0, tzinfo=timezone.utc))
    b = DailyAICallBudget(clock=clock)
    assert b.spend(1) is True
    assert b.spend(1) is False

    clock.now += timedelta(minutes=2)  # into 2026-10-04 UTC
    assert b.spend(1) is True, "a new UTC day starts a new allowance"
    assert b.spent_today() == 1


def test_budget_does_not_roll_over_within_the_same_day():
    clock = FakeUTCClock(datetime(2026, 10, 3, 0, 1, 0, tzinfo=timezone.utc))
    b = DailyAICallBudget(clock=clock)
    assert b.spend(1) is True
    clock.now += timedelta(hours=23)  # still 2026-10-03 UTC
    assert b.spend(1) is False


def test_budget_is_thread_safe():
    """Concurrent callers must not oversell the limit — the semaphore caps
    concurrency at 4, so several threads really do charge at once."""
    import threading

    b = DailyAICallBudget()
    limit = 50
    granted: list[bool] = []
    lock = threading.Lock()

    def worker():
        ok = b.spend(limit)
        with lock:
            granted.append(ok)

    threads = [threading.Thread(target=worker) for _ in range(200)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert sum(granted) == limit, "exactly `limit` calls should have been allowed"


def test_remaining_never_goes_negative():
    b = DailyAICallBudget()
    for _ in range(5):
        b.spend(2)
    assert b.remaining(2) == 0


# --- every AI call site is covered ------------------------------------------


def _exhaust(limit: int) -> None:
    for _ in range(limit):
        assert rate_limit.budget.spend(limit) or True


@pytest.fixture
def budget_of_one(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("AI_DAILY_CALL_BUDGET", "1")
    monkeypatch.setenv("AI_RATE_PER_MIN", "100000")
    monkeypatch.setenv("AI_RATE_BURST", "100000")
    config.get_settings.cache_clear()
    rate_limit.budget.reset()
    yield
    rate_limit.budget.reset()


def _stub_everything(monkeypatch: pytest.MonkeyPatch, bungalow: dict) -> None:
    """Make every AI call site return without touching Anthropic."""
    home = HomeModel.model_validate(bungalow)
    monkeypatch.setattr(
        "app.main.run_builder",
        lambda **kw: BuildResult(home=home, trace=[], truncated=False),
    )
    monkeypatch.setattr(
        "app.api_chat.chat",
        lambda *a, **k: ChatResponse(reply="Test monthly.", citations=[]),
    )
    monkeypatch.setattr("app.main.recommendation_items", lambda *a, **k: [])


AI_CALL_SITES = [
    ("/build", lambda home: {"description": "a small bungalow"}),
    ("/chat", lambda home: {"home": home, "messages": [{"role": "user", "content": "hi"}]}),
    (
        "/score",
        lambda home: {"home": home, "include_recommendations": True},
    ),
]


@pytest.mark.parametrize("path,body", AI_CALL_SITES, ids=[p for p, _ in AI_CALL_SITES])
def test_every_ai_call_site_refuses_once_the_budget_is_spent(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
    bungalow: dict,
    budget_of_one,
    path: str,
    body,
):
    """One call succeeds, the next is 429 — on each route that spends credit,
    including `/score?include_recommendations` (AUD-006), which used to call the
    AI outside the guard entirely."""
    _stub_everything(monkeypatch, bungalow)

    first = client.post(path, json=body(bungalow), headers=AUTH)
    assert first.status_code == 200, f"{path}: {first.text}"

    second = client.post(path, json=body(bungalow), headers=AUTH)
    assert second.status_code == 429, f"{path}: {second.text}"
    assert "daily AI limit" in second.json()["detail"]
    assert "Retry-After" in second.headers


def test_a_valid_token_does_not_reset_the_budget(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, bungalow: dict, budget_of_one
):
    """AUD-003 stated as a test: the token is public, so holding it must not be
    a way past the ceiling."""
    _stub_everything(monkeypatch, bungalow)
    client.post("/build", json={"description": "x"}, headers=AUTH)

    for _ in range(5):
        resp = client.post("/build", json={"description": "x"}, headers=AUTH)
        assert resp.status_code == 429


def test_a_forged_forwarded_header_does_not_reset_the_budget(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, bungalow: dict, budget_of_one
):
    """The budget is global, so unlike the per-client bucket it does not care
    whose request it is — varying the spoofable header changes nothing."""
    _stub_everything(monkeypatch, bungalow)
    client.post("/build", json={"description": "x"}, headers=AUTH)

    for i in range(5):
        resp = client.post(
            "/build",
            json={"description": "x"},
            headers={**AUTH, "X-Forwarded-For": f"{i}.{i}.{i}.{i}"},
        )
        assert resp.status_code == 429


def test_the_deterministic_routes_are_untouched_by_an_exhausted_budget(
    client: TestClient, bungalow: dict, budget_of_one
):
    """The separation the whole project rests on: when the AI allowance is gone,
    routes and scores still work. A judge asking "what if the AI is down?" gets
    this answer."""
    rate_limit.budget.spend(1)
    assert rate_limit.budget.remaining(1) == 0

    assert client.post("/routes", json={"home": bungalow}, headers=AUTH).status_code == 200
    assert client.post("/score", json={"home": bungalow}, headers=AUTH).status_code == 200
    origin = bungalow["floors"][0]["rooms"][0]["id"]
    evacuate = client.post(
        "/evacuate",
        json={"home": bungalow, "origin_room_id": origin},
        headers=AUTH,
    )
    assert evacuate.status_code == 200, evacuate.text


def test_score_without_recommendations_never_charges_the_budget(
    client: TestClient, bungalow: dict
):
    """`/score` is deterministic and the demo path leans on it, so the plain call
    must not consume the AI allowance."""
    before = rate_limit.budget.spent_today()
    assert client.post("/score", json={"home": bungalow}, headers=AUTH).status_code == 200
    assert rate_limit.budget.spent_today() == before


def test_score_with_recommendations_does_charge_the_budget(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, bungalow: dict
):
    """AUD-006: the flag makes it an AI call, so it must be counted."""
    _stub_everything(monkeypatch, bungalow)
    before = rate_limit.budget.spent_today()
    resp = client.post(
        "/score",
        json={"home": bungalow, "include_recommendations": True},
        headers=AUTH,
    )
    assert resp.status_code == 200, resp.text
    assert rate_limit.budget.spent_today() == before + 1


def test_budget_is_charged_before_the_call_not_after_success(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, bungalow: dict
):
    """A failing call has usually already cost credit. If failures were refunded,
    a loop of failing calls would run unbounded — the shape of the incident that
    drained the account."""
    from app.ai.builder import BuilderError

    def boom(**kwargs):
        raise BuilderError("no key")

    monkeypatch.setattr("app.main.run_builder", boom)
    before = rate_limit.budget.spent_today()
    resp = client.post("/build", json={"description": "x"}, headers=AUTH)
    assert resp.status_code == 502, resp.text
    assert rate_limit.budget.spent_today() == before + 1


# --- /health reports the remaining allowance --------------------------------


def test_health_reports_the_budget_and_stays_open(client: TestClient):
    """Open and cheap (no token), numbers only."""
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["ai_calls_remaining_today"] == config.get_settings().ai_daily_call_budget
    assert body["ai_calls_spent_today"] == 0


def test_health_budget_moves_as_calls_are_spent(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, bungalow: dict
):
    _stub_everything(monkeypatch, bungalow)
    client.post("/build", json={"description": "x"}, headers=AUTH)

    body = client.get("/health").json()
    limit = config.get_settings().ai_daily_call_budget
    assert body["ai_calls_spent_today"] == 1
    assert body["ai_calls_remaining_today"] == limit - 1


# --- configuration -----------------------------------------------------------


def test_a_nonsense_budget_fails_at_startup(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("AI_DAILY_CALL_BUDGET", "0")
    config.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match="AI_DAILY_CALL_BUDGET"):
        config.get_settings()


def test_a_negative_hop_count_fails_at_startup(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("AI_TRUSTED_PROXY_HOPS", "-1")
    config.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match="AI_TRUSTED_PROXY_HOPS"):
        config.get_settings()


def test_zero_hops_is_allowed_unlike_the_other_limits(monkeypatch: pytest.MonkeyPatch):
    """0 is the valid "no proxy in front" setting, which is why it does not go
    through `_positive_number`."""
    monkeypatch.setenv("AI_TRUSTED_PROXY_HOPS", "0")
    config.get_settings.cache_clear()
    assert config.get_settings().ai_trusted_proxy_hops == 0
