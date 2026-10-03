"""The AI cost guard (app/rate_limit.py): per-client token bucket + global cap.

No test here reaches Anthropic. Every AI entry point is monkeypatched to raise
its own "AI unavailable" error, so an allowed request is a 502 and a limited one
is a 429 — the guard is the only thing that differs between them.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import config, rate_limit
from app import main
from app.ai.agent import AgentError
from app.ai.builder import BuilderError
from app.ai.chat.service import ChatGroundingError
from app.ai.grounded import GroundingError
from app.rate_limit import TokenBucketLimiter

TEST_TOKEN = "rate-limit-test-token"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


def _raiser(exc: Exception):
    def boom(*_a, **_k):
        raise exc

    return boom


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    monkeypatch.setattr(main, "run_agent_analysis", _raiser(AgentError("no AI in tests")))
    monkeypatch.setattr(main, "explain_routes", _raiser(GroundingError("no AI in tests")))
    monkeypatch.setattr(main, "run_builder", _raiser(BuilderError("no AI in tests")))
    monkeypatch.setattr(
        "app.api_chat.chat", _raiser(ChatGroundingError("no AI in tests"))
    )
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def _limits(monkeypatch: pytest.MonkeyPatch, *, per_min="1", burst="1", concurrent="4"):
    monkeypatch.setenv("AI_RATE_PER_MIN", per_min)
    monkeypatch.setenv("AI_RATE_BURST", burst)
    monkeypatch.setenv("AI_MAX_CONCURRENT", concurrent)
    config.get_settings.cache_clear()


@pytest.fixture
def client() -> TestClient:
    return TestClient(main.app, raise_server_exceptions=False)


@pytest.fixture
def bodies(client: TestClient, bungalow: dict) -> dict[str, dict]:
    plan = client.post("/routes", json={"home": bungalow}, headers=AUTH).json()
    return {
        "/explain": {"home": bungalow, "route_plan": plan},
        "/analyze": {"home": bungalow},
        "/build": {"description": "a one-bedroom flat"},
        "/chat": {"home": bungalow, "messages": [{"role": "user", "content": "hi"}]},
    }


AI_PATHS = ["/explain", "/analyze", "/build", "/chat"]


# --- the endpoints --------------------------------------------------------------


@pytest.mark.parametrize("path", AI_PATHS)
def test_every_ai_route_is_rate_limited(path, client, bodies, monkeypatch):
    _limits(monkeypatch, per_min="6", burst="2")
    assert client.post(path, json=bodies[path], headers=AUTH).status_code == 502
    assert client.post(path, json=bodies[path], headers=AUTH).status_code == 502
    limited = client.post(path, json=bodies[path], headers=AUTH)
    assert limited.status_code == 429
    # 6/min refills one token every 10 s.
    assert 1 <= int(limited.headers["Retry-After"]) <= 10


def test_the_budget_is_per_client_ip(client, bodies, monkeypatch):
    _limits(monkeypatch, burst="1")
    a = {**AUTH, "X-Forwarded-For": "203.0.113.7, 10.0.0.1"}
    b = {**AUTH, "X-Forwarded-For": "198.51.100.9"}
    assert client.post("/analyze", json=bodies["/analyze"], headers=a).status_code == 502
    assert client.post("/analyze", json=bodies["/analyze"], headers=a).status_code == 429
    assert client.post("/analyze", json=bodies["/analyze"], headers=b).status_code == 502


def test_the_budget_is_shared_across_ai_routes(client, bodies, monkeypatch):
    """One bucket per client, not per route: spreading calls across the four
    endpoints must not multiply the allowance."""
    _limits(monkeypatch, burst="1")
    assert client.post("/explain", json=bodies["/explain"], headers=AUTH).status_code == 502
    assert client.post("/chat", json=bodies["/chat"], headers=AUTH).status_code == 429


def test_a_request_without_the_token_is_401_and_spends_nothing(client, bodies, monkeypatch):
    _limits(monkeypatch, burst="1")
    assert client.post("/analyze", json=bodies["/analyze"]).status_code == 401
    assert client.post("/analyze", json=bodies["/analyze"]).status_code == 401
    assert client.post("/analyze", json=bodies["/analyze"], headers=AUTH).status_code == 502


def test_deterministic_routes_are_never_limited(client, bungalow, monkeypatch):
    _limits(monkeypatch, burst="1")
    for _ in range(4):
        assert client.post("/routes", json={"home": bungalow}, headers=AUTH).status_code == 200


def test_a_full_house_is_429_with_retry_after(client, bodies, monkeypatch):
    _limits(monkeypatch, per_min="1000", burst="1000", concurrent="1")
    held = rate_limit.gate.semaphore(1)
    assert held.acquire(blocking=False)  # someone else's call is in flight
    try:
        busy = client.post("/chat", json=bodies["/chat"], headers=AUTH)
        assert busy.status_code == 429
        assert busy.headers["Retry-After"] == str(rate_limit.CONCURRENCY_RETRY_AFTER_S)
    finally:
        held.release()
    assert client.post("/chat", json=bodies["/chat"], headers=AUTH).status_code == 502


def test_a_failing_call_gives_its_slot_back(client, bodies, monkeypatch):
    """The endpoint raises (502) every time; if the slot leaked, the second call
    would find the only one taken."""
    _limits(monkeypatch, per_min="1000", burst="1000", concurrent="1")
    for path in AI_PATHS:
        assert client.post(path, json=bodies[path], headers=AUTH).status_code == 502


# --- the pieces -----------------------------------------------------------------


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def test_bucket_allows_the_burst_then_refills_at_the_rate():
    clock = FakeClock()
    bucket = TokenBucketLimiter(clock=clock)
    assert [bucket.take("ip", 6, 3) for _ in range(3)] == [None, None, None]
    wait = bucket.take("ip", 6, 3)
    assert wait == pytest.approx(10.0)
    clock.now += 9.9
    assert bucket.take("ip", 6, 3) is not None
    clock.now += 0.2
    assert bucket.take("ip", 6, 3) is None


def test_bucket_never_holds_more_than_the_burst():
    clock = FakeClock()
    bucket = TokenBucketLimiter(clock=clock)
    bucket.take("ip", 6, 2)
    clock.now += 3600  # an hour idle does not bank 360 calls
    assert [bucket.take("ip", 6, 2) for _ in range(3)][-1] is not None


def test_bucket_prunes_refilled_entries_when_large():
    clock = FakeClock()
    bucket = TokenBucketLimiter(clock=clock, max_keys=3)
    for ip in ("a", "b", "c"):
        bucket.take(ip, 60, 1)
    clock.now += 5  # all three have refilled (1 token at 1/s)
    bucket.take("d", 60, 1)
    assert set(bucket._buckets) == {"d"}


# --- client key: the caller must not be able to choose it (S11.27, AUD-003) ---
#
# This replaces `test_client_key_prefers_the_first_forwarded_hop`, which asserted
# the vulnerable behaviour: the first X-Forwarded-For hop is written by the
# caller, so keying on it handed a script a fresh bucket per request just by
# varying a header. Render's own FastAPI guidance calls trusting that "a critical
# vulnerability, allowing bad actors to spoof their IP address".


def _request(headers: list[tuple[bytes, bytes]]):
    from starlette.requests import Request

    return Request({"type": "http", "headers": headers, "client": ("10.0.0.1", 1234)})


def test_client_key_falls_back_to_the_socket_peer():
    assert rate_limit.client_key(_request([])) == "10.0.0.1"


def test_client_key_prefers_the_header_the_proxy_overwrites():
    """CF-Connecting-IP is written by Cloudflare on every proxied request and
    overwrites whatever the caller sent, so it wins over X-Forwarded-For."""
    key = rate_limit.client_key(
        _request(
            [
                (b"x-forwarded-for", b"1.2.3.4, 203.0.113.7"),
                (b"cf-connecting-ip", b"198.51.100.9"),
            ]
        )
    )
    assert key == "198.51.100.9"


def test_client_key_takes_the_forwarded_hop_from_the_right():
    """With one proxy in front, the LAST entry is the one that proxy observed;
    everything left of it is whatever the caller chose to send."""
    key = rate_limit.client_key(
        _request([(b"x-forwarded-for", b" 1.2.3.4 , 203.0.113.7 ")])
    )
    assert key == "203.0.113.7"


def test_a_forged_forwarded_chain_cannot_win_a_fresh_bucket():
    """The point of the change, stated as the attack it stops.

    A caller prepending different addresses gets the SAME key every time, so the
    per-client bucket actually bounds them.
    """
    keys = {
        rate_limit.client_key(
            _request([(b"x-forwarded-for", f"{i}.{i}.{i}.{i}, 203.0.113.7".encode())])
        )
        for i in range(1, 20)
    }
    assert keys == {"203.0.113.7"}


def test_more_hops_than_entries_falls_back_to_the_leftmost(monkeypatch):
    """A misconfiguration must not index off the end; the most conservative
    reading available is the leftmost entry."""
    monkeypatch.setenv("AI_TRUSTED_PROXY_HOPS", "5")
    config.get_settings.cache_clear()
    assert (
        rate_limit.client_key(_request([(b"x-forwarded-for", b"203.0.113.7")]))
        == "203.0.113.7"
    )


def test_zero_hops_ignores_the_header_entirely(monkeypatch):
    """The local-run setting: no proxy in front, so believe only the socket."""
    monkeypatch.setenv("AI_TRUSTED_PROXY_HOPS", "0")
    monkeypatch.setenv("AI_CLIENT_IP_HEADER", "")
    config.get_settings.cache_clear()
    assert (
        rate_limit.client_key(_request([(b"x-forwarded-for", b"1.2.3.4, 203.0.113.7")]))
        == "10.0.0.1"
    )


def test_an_empty_trusted_header_is_skipped_not_used(monkeypatch):
    """A present-but-blank CF-Connecting-IP must not become the key."""
    monkeypatch.setenv("AI_TRUSTED_PROXY_HOPS", "1")
    config.get_settings.cache_clear()
    key = rate_limit.client_key(
        _request(
            [
                (b"cf-connecting-ip", b"   "),
                (b"x-forwarded-for", b"1.2.3.4, 203.0.113.7"),
            ]
        )
    )
    assert key == "203.0.113.7"


@pytest.mark.parametrize(
    ("name", "value"),
    [("AI_RATE_BURST", "0"), ("AI_RATE_PER_MIN", "-1"), ("AI_MAX_CONCURRENT", "lots")],
)
def test_nonsense_limits_fail_at_startup(name, value, monkeypatch):
    monkeypatch.setenv(name, value)
    config.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match=name):
        config.get_settings()


def test_production_defaults(monkeypatch):
    for name in ("AI_RATE_PER_MIN", "AI_RATE_BURST", "AI_MAX_CONCURRENT"):
        monkeypatch.delenv(name, raising=False)
    config.get_settings.cache_clear()
    settings = config.get_settings()
    assert (settings.ai_rate_per_min, settings.ai_rate_burst, settings.ai_max_concurrent) == (
        6.0,
        3,
        4,
    )
