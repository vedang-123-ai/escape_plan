"""S11.26: request body limits and input caps (AUD-004 body half, AUD-035 caps
half, AUD-024 server half).

Three things are asserted for every limit: a request AT the limit is accepted, a
request over it is refused with the documented status, and a refused request
never constructs an Anthropic client — the caps exist to stop the server paying
for a request it was always going to reject.

The body limits are also tied back to the geometry bounds they were derived from
(`test_default_limit_clears_the_largest_legal_home`), so lowering a limit or
raising a bound without re-deriving the other fails here rather than in
production.
"""

from __future__ import annotations

import base64
import json
import math

import pytest
from fastapi.testclient import TestClient

from app import config
from app import models as M
from app.limits import (
    ALLOWED_IMAGE_MEDIA_TYPES,
    MAX_BODY_BYTES_BUILD,
    MAX_BODY_BYTES_DEFAULT,
    MAX_BUILD_DESCRIPTION_CHARS,
    MAX_CHAT_MESSAGES,
    MAX_CHAT_MESSAGE_CHARS,
    MAX_CHAT_TOTAL_CHARS,
    MAX_IMAGE_B64_CHARS,
)
from app.main import app
from app.models import HomeModel

TEST_TOKEN = "limits-test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(autouse=True)
def _token_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture
def no_anthropic(monkeypatch: pytest.MonkeyPatch) -> list[object]:
    """Record every Anthropic client construction.

    A rejected request must leave this list empty. Both `ai/builder.py` and
    `ai/chat/service.py` build their client with `anthropic.Anthropic(...)`, so
    patching the class catches either path.
    """
    constructed: list[object] = []

    class _Recorded:
        def __init__(self, *args, **kwargs):
            constructed.append(kwargs)
            raise AssertionError(
                "an Anthropic client was constructed for a request that should "
                "have been rejected by a limit"
            )

    monkeypatch.setattr("anthropic.Anthropic", _Recorded)
    return constructed


# --- body size: the middleware (AUD-004) -------------------------------------


def _padded_body(total_bytes: int) -> bytes:
    """Syntactically valid JSON of exactly `total_bytes`, with the padding inside
    a string so the size is the only thing under test."""
    envelope = b'{"home":"' + b'x' * 0 + b'"}'
    pad = total_bytes - len(envelope)
    assert pad >= 0, "requested body smaller than the envelope"
    return b'{"home":"' + b"x" * pad + b'"}'


def test_body_at_the_default_limit_is_not_refused(client: TestClient):
    """Exactly at the limit is accepted by the middleware.

    It still fails validation (the padding is not a home), which is the point:
    the assertion is that 413 is not what comes back.
    """
    resp = client.post(
        "/score",
        content=_padded_body(MAX_BODY_BYTES_DEFAULT),
        headers={**AUTH, "Content-Type": "application/json"},
    )
    assert resp.status_code != 413
    assert resp.status_code == 422


def test_body_one_byte_over_the_default_limit_is_413(client: TestClient):
    resp = client.post(
        "/score",
        content=_padded_body(MAX_BODY_BYTES_DEFAULT + 1),
        headers={**AUTH, "Content-Type": "application/json"},
    )
    assert resp.status_code == 413
    assert f"{MAX_BODY_BYTES_DEFAULT:,}" in resp.json()["detail"]


def test_413_is_returned_before_the_token_is_checked(client: TestClient):
    """An oversized body is refused without credentials — refuse early, before
    parsing or paying. Documented in app/limits.py; asserted so it stays true."""
    resp = client.post(
        "/score",
        content=_padded_body(MAX_BODY_BYTES_DEFAULT + 1),
        headers={"Content-Type": "application/json"},
    )
    assert resp.status_code == 413


def test_build_gets_a_larger_limit_than_the_compute_routes(client: TestClient):
    """The same body that /score refuses is within /build's limit, because /build
    carries a base64 image."""
    body = _padded_body(MAX_BODY_BYTES_DEFAULT + 1)
    assert client.post(
        "/score", content=body, headers={**AUTH, "Content-Type": "application/json"}
    ).status_code == 413
    assert client.post(
        "/build", content=body, headers={**AUTH, "Content-Type": "application/json"}
    ).status_code != 413


def test_body_over_the_build_limit_is_413(client: TestClient):
    resp = client.post(
        "/build",
        content=_padded_body(MAX_BODY_BYTES_BUILD + 1),
        headers={**AUTH, "Content-Type": "application/json"},
    )
    assert resp.status_code == 413


def test_chunked_body_over_the_limit_is_413(client: TestClient):
    """A body with no Content-Length is still measured.

    Passing an iterator makes httpx send `Transfer-Encoding: chunked`, so the
    declared-length check cannot see the size — this is the hole that a
    Content-Length check alone would leave open.
    """
    chunk = b"x" * (1024 * 1024)
    over = MAX_BODY_BYTES_DEFAULT + 1

    def chunks():
        sent = 0
        yield b'{"home":"'
        while sent < over:
            yield chunk
            sent += len(chunk)
        yield b'"}'

    resp = client.post(
        "/score", content=chunks(), headers={**AUTH, "Content-Type": "application/json"}
    )
    assert resp.status_code == 413


def test_chunked_body_under_the_limit_is_passed_through(client: TestClient, bungalow: dict):
    """The replay path must hand the app the same body it buffered — a real home
    sent chunked still routes."""
    body = json.dumps({"home": bungalow}).encode()

    def chunks():
        for i in range(0, len(body), 512):
            yield body[i : i + 512]

    resp = client.post(
        "/score", content=chunks(), headers={**AUTH, "Content-Type": "application/json"}
    )
    assert resp.status_code == 200, resp.text


def test_health_stays_open_and_is_not_measured(client: TestClient):
    """A RULE of this session. GET has no body, so the middleware passes it
    straight through."""
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_unparseable_content_length_does_not_skip_the_limit(client: TestClient):
    """A bad Content-Length falls into the counting path rather than being
    trusted, so it cannot be used to get an oversized body past the check."""
    resp = client.post(
        "/score",
        content=_padded_body(MAX_BODY_BYTES_DEFAULT + 1),
        headers={**AUTH, "Content-Type": "application/json", "Content-Length": "nonsense"},
    )
    assert resp.status_code in (400, 413, 422)


# --- the limits are derived from the geometry bounds, not guessed -------------


def _max_bounds_home() -> dict:
    """A home at every S11.25 bound at once — the largest body the server must
    accept. MAX_TOTAL_GRID_CELLS binds first, so the rooms are sized to fit
    MAX_ROOMS of them inside it."""
    name = "N" * 48
    radius = 1.7320508  # 64-gon bbox ~3.46 m -> ~1,200 cells; x200 rooms < 250,000

    def poly(cx: float) -> list[list[float]]:
        n = M.MAX_POLYGON_VERTICES
        return [
            [
                round(cx + radius * math.cos(2 * math.pi * i / n), 7),
                round(radius * math.sin(2 * math.pi * i / n), 7),
            ]
            for i in range(n)
        ]

    floors, rooms_left, objs_left = [], M.MAX_ROOMS, M.MAX_OBJECTS_TOTAL
    for f in range(M.MAX_FLOORS):
        n_rooms = min(M.MAX_ROOMS // M.MAX_FLOORS, rooms_left)
        rooms_left -= n_rooms
        rooms = [
            {
                "id": f"room-{'x' * 27}-{f}-{i}",
                "name": name,
                "type": "bedroom",
                "polygon": poly(i * 8.0),
                "source": "scan",
                "confidence": 0.8712345,
            }
            for i in range(n_rooms)
        ]
        n_obj = min(M.MAX_OBJECTS_PER_FLOOR, objs_left)
        objs_left -= n_obj
        floors.append(
            {
                "id": f"floor-{f}",
                "level": f,
                "name": name,
                "height_m": 2.7123456,
                "rooms": rooms,
                "openings": [
                    {
                        "id": f"op-{f}-{i}-{'y' * 20}",
                        "kind": "window",
                        "room_ids": [rooms[i % n_rooms]["id"], "EXTERIOR"],
                        "wall_segment": {
                            "room_id": rooms[i % n_rooms]["id"],
                            "edge_index": i % M.MAX_POLYGON_VERTICES,
                            "t0": 0.1234567,
                            "t1": 0.8765432,
                        },
                        "width_m": 1.2345678,
                        "height_m": 1.3456789,
                        "sill_height_m": 0.9876543,
                        "source": "scan",
                        "confidence": 0.7654321,
                    }
                    for i in range(M.MAX_OPENINGS_PER_FLOOR)
                ],
                "safety_points": [
                    {
                        "id": f"sp-{f}-{i}-{'w' * 20}",
                        "kind": "gas_shutoff",
                        "position": [i * 0.4567891, 0.7654321],
                        "source": "manual",
                    }
                    for i in range(M.MAX_SAFETY_POINTS_PER_FLOOR)
                ],
                "objects": [
                    {
                        "id": f"ob-{f}-{i}-{'z' * 20}",
                        "category": "bookcase",
                        "center": [i * 0.3456789, 0.1234567],
                        "size_m": [0.8123456, 0.4123456],
                        "height_m": 1.8123456,
                        "rotation_deg": 37.123456,
                        "source": "scan",
                        "secured": False,
                        "elevation_m": 0.0,
                        "mounted": False,
                        "confidence": 0.654321,
                    }
                    for i in range(n_obj)
                ],
            }
        )

    return {
        "schema_version": "2.1",
        "home_id": "h-" + "q" * 30,
        "name": name,
        "floors": floors,
        "stairs": [
            {
                "id": f"st-{i}-{'v' * 20}",
                "from": {"floor_id": "floor-0", "room_id": floors[0]["rooms"][0]["id"]},
                "to": {"floor_id": "floor-1", "room_id": floors[1]["rooms"][0]["id"]},
                "footprint": poly(0.0),
                "kind": "straight",
                "source": "manual",
            }
            for i in range(M.MAX_STAIRS)
        ],
        "profiles": [
            {
                "id": f"pr-{i}-{'u' * 20}",
                "name": name,
                "tags": ["mobility_limited", "elderly", "child"],
                "bedroom_room_id": floors[0]["rooms"][0]["id"],
            }
            for i in range(M.MAX_PROFILES)
        ],
        "meta": {
            "created": "2026-10-03T00:00:00Z",
            "modified": "2026-10-03T00:00:00Z",
            "address_optional": "A" * 120,
        },
        "household": {"tenure": "own", "existing_equipment": []},
    }


def test_the_max_bounds_home_is_actually_legal():
    """If this stops validating, the measurement below stops being a measurement
    of anything — it would be an over-estimate of an unreachable body."""
    HomeModel.model_validate(_max_bounds_home())


def test_default_limit_clears_the_largest_legal_home():
    """The limit is derived from the geometry bounds, with headroom stated.

    Measured 2026-10-03: 1,649,482 bytes compact / 1,780,354 pretty. The margin
    is deliberate — S11.26 ships before the client-side trimming (S11.45) and
    transcoding (S11.33), so a limit chosen tight against today's number would
    reject real requests in the gap.
    """
    home = _max_bounds_home()
    compact = len(json.dumps(home, separators=(",", ":")))
    pretty = len(json.dumps(home))

    assert compact < 2_000_000, f"max legal home grew to {compact:,} bytes"
    assert MAX_BODY_BYTES_DEFAULT > pretty * 4, (
        f"limit {MAX_BODY_BYTES_DEFAULT:,} leaves under 4x headroom over the "
        f"largest legal home ({pretty:,} bytes pretty-printed)"
    )


def test_build_limit_holds_a_maximum_image_plus_a_maximum_description():
    """/build's limit has to fit what its own field caps allow, or the field caps
    are unreachable and the 413 would fire first."""
    assert MAX_BODY_BYTES_BUILD > MAX_IMAGE_B64_CHARS + MAX_BUILD_DESCRIPTION_CHARS


# --- /build input caps (AUD-024, AUD-035) ------------------------------------


def _jpeg_b64(size: int = 64) -> str:
    return base64.b64encode(b"\xff\xd8\xff" + b"\x00" * size).decode()


def _fake_build_result():
    """A valid BuildResult with no model call. `trace` and `truncated` are
    required fields, so a stub has to supply them."""
    from app.ai.builder import BuildResult

    return BuildResult(
        home=HomeModel.model_validate(_minimal_home()), trace=[], truncated=False
    )


def test_build_accepts_a_description_at_the_limit(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
):
    captured: dict = {}

    def fake_builder(**kwargs):
        captured.update(kwargs)
        return _fake_build_result()

    monkeypatch.setattr("app.main.run_builder", fake_builder)
    resp = client.post(
        "/build",
        json={"description": "d" * MAX_BUILD_DESCRIPTION_CHARS},
        headers=AUTH,
    )
    assert resp.status_code == 200, resp.text
    assert len(captured["description"]) == MAX_BUILD_DESCRIPTION_CHARS


def test_build_rejects_a_description_over_the_limit(
    client: TestClient, no_anthropic: list
):
    resp = client.post(
        "/build",
        json={"description": "d" * (MAX_BUILD_DESCRIPTION_CHARS + 1)},
        headers=AUTH,
    )
    assert resp.status_code == 422
    assert no_anthropic == []


@pytest.mark.parametrize("media_type", ALLOWED_IMAGE_MEDIA_TYPES)
def test_build_accepts_every_media_type_anthropic_accepts(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, media_type: str
):
    monkeypatch.setattr(
        "app.main.run_builder",
        lambda **kw: _fake_build_result(),
    )
    resp = client.post(
        "/build",
        json={"image_b64": _jpeg_b64(), "image_media_type": media_type},
        headers=AUTH,
    )
    assert resp.status_code == 200, resp.text


@pytest.mark.parametrize(
    "media_type",
    ["image/heic", "image/heif", "image/tiff", "application/pdf", "image/jpg", "text/plain", ""],
)
def test_build_rejects_a_media_type_anthropic_does_not_accept(
    client: TestClient, no_anthropic: list, media_type: str
):
    """AUD-024's server half. `image/heic` is the real case: an iPhone photo.
    `image/jpg` is the common typo for `image/jpeg` and is equally not accepted."""
    resp = client.post(
        "/build",
        json={"image_b64": _jpeg_b64(), "image_media_type": media_type},
        headers=AUTH,
    )
    assert resp.status_code == 422
    assert no_anthropic == []


def test_build_rejects_an_image_over_the_base64_cap(
    client: TestClient, no_anthropic: list
):
    """MAX_IMAGE_B64_CHARS is Anthropic's documented 10 MB base64 maximum, so a
    larger image would have cost a model call and come back a 502."""
    resp = client.post(
        "/build",
        json={
            "image_b64": "A" * (MAX_IMAGE_B64_CHARS + 1),
            "image_media_type": "image/jpeg",
        },
        headers=AUTH,
    )
    assert resp.status_code == 422
    assert no_anthropic == []


def test_build_rejects_an_image_that_is_not_base64(
    client: TestClient, no_anthropic: list
):
    resp = client.post(
        "/build",
        json={"image_b64": "not base64 at all !!!", "image_media_type": "image/jpeg"},
        headers=AUTH,
    )
    assert resp.status_code == 422
    assert no_anthropic == []
    assert "base64" in resp.text


def test_build_still_requires_a_description_or_an_image(client: TestClient):
    """The pre-existing 422 is unchanged by the new field constraints."""
    assert client.post("/build", json={}, headers=AUTH).status_code == 422


# --- /chat input caps (AUD-035) ---------------------------------------------


def _minimal_home() -> dict:
    from tests.conftest import load_fixture

    return load_fixture("bungalow.json")


def _chat_body(messages: list[dict], home: dict) -> dict:
    return {"home": home, "messages": messages}


def test_chat_accepts_the_maximum_number_of_messages(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, bungalow: dict
):
    """At MAX_CHAT_MESSAGES with short turns, so the total-length cap (which binds
    first for long turns) is not what is under test here."""
    from app.ai.chat.service import ChatResponse

    monkeypatch.setattr(
        "app.api_chat.chat",
        lambda *a, **k: ChatResponse(reply="Test monthly.", citations=[]),
    )
    messages = [
        {"role": "user" if i % 2 == 0 else "assistant", "content": "ok"}
        for i in range(MAX_CHAT_MESSAGES)
    ]
    resp = client.post("/chat", json=_chat_body(messages, bungalow), headers=AUTH)
    assert resp.status_code == 200, resp.text


def test_chat_rejects_one_message_too_many(
    client: TestClient, no_anthropic: list, bungalow: dict
):
    messages = [
        {"role": "user" if i % 2 == 0 else "assistant", "content": "ok"}
        for i in range(MAX_CHAT_MESSAGES + 1)
    ]
    resp = client.post("/chat", json=_chat_body(messages, bungalow), headers=AUTH)
    assert resp.status_code == 422
    assert no_anthropic == []


def test_chat_accepts_a_message_at_the_per_message_limit(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, bungalow: dict
):
    from app.ai.chat.service import ChatResponse

    monkeypatch.setattr(
        "app.api_chat.chat",
        lambda *a, **k: ChatResponse(reply="Test monthly.", citations=[]),
    )
    body = _chat_body([{"role": "user", "content": "c" * MAX_CHAT_MESSAGE_CHARS}], bungalow)
    resp = client.post("/chat", json=body, headers=AUTH)
    assert resp.status_code == 200, resp.text


def test_chat_rejects_a_message_over_the_per_message_limit(
    client: TestClient, no_anthropic: list, bungalow: dict
):
    body = _chat_body(
        [{"role": "user", "content": "c" * (MAX_CHAT_MESSAGE_CHARS + 1)}], bungalow
    )
    resp = client.post("/chat", json=body, headers=AUTH)
    assert resp.status_code == 422
    assert no_anthropic == []


def test_chat_rejects_a_history_over_the_total_budget(
    client: TestClient, no_anthropic: list, bungalow: dict
):
    """Each message is legal on its own; summed they are not. This is the cap
    that actually bounds cost, since count x per-message would be 320k."""
    per = MAX_CHAT_MESSAGE_CHARS
    needed = MAX_CHAT_TOTAL_CHARS // per + 1
    assert needed <= MAX_CHAT_MESSAGES, "fixture would trip the count cap first"
    messages = [
        {"role": "user" if i % 2 == 0 else "assistant", "content": "c" * per}
        for i in range(needed)
    ]
    total = sum(len(m["content"]) for m in messages)
    assert total > MAX_CHAT_TOTAL_CHARS

    resp = client.post("/chat", json=_chat_body(messages, bungalow), headers=AUTH)
    assert resp.status_code == 422
    assert no_anthropic == []
    assert str(f"{MAX_CHAT_TOTAL_CHARS:,}") in resp.text


def test_chat_total_budget_binds_before_the_count_product():
    """Documents why both caps exist: the product of the other two is larger, so
    the total is the real ceiling."""
    assert MAX_CHAT_TOTAL_CHARS < MAX_CHAT_MESSAGES * MAX_CHAT_MESSAGE_CHARS


# --- framing: the declared length must never be a way past the limit ---------
#
# Found 2026-10-03 while reviewing this session's own middleware. A declared
# Content-Length short-circuits the counting path, so anything that makes the
# declaration a lie bypasses the limit entirely rather than merely under-counting.
# These drive the middleware at the ASGI layer on purpose: an HTTP client (and
# h11 underneath TestClient) will not emit a contradictory framing pair, which is
# exactly why the hole was invisible to the endpoint-level tests above.


async def _deliver(headers: list[tuple[bytes, bytes]], megabytes: int) -> tuple[list, int]:
    """Push `megabytes` MB through the middleware with `headers`.

    Returns the response statuses and how many body bytes reached the app.
    """
    from app.limits import BodySizeLimitMiddleware

    delivered = 0

    async def fake_app(scope, receive, send):
        nonlocal delivered
        while True:
            message = await receive()
            if message["type"] != "http.request":
                break
            delivered += len(message.get("body", b""))
            if not message.get("more_body"):
                break
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    scope = {"type": "http", "method": "POST", "path": "/score", "headers": headers}
    chunk = b"x" * (1024 * 1024)
    messages = [
        {"type": "http.request", "body": chunk, "more_body": True}
        for _ in range(megabytes)
    ]
    messages.append({"type": "http.request", "body": b"", "more_body": False})
    pending = iter(messages)

    async def receive():
        return next(pending)

    sent: list = []

    async def send(message):
        sent.append(message)

    await BodySizeLimitMiddleware(fake_app)(scope, receive, send)
    statuses = [m.get("status") for m in sent if m["type"] == "http.response.start"]
    return statuses, delivered


@pytest.mark.parametrize(
    "label,headers",
    [
        (
            "content-length plus chunked: RFC 9112 says chunked wins",
            [(b"content-length", b"10"), (b"transfer-encoding", b"chunked")],
        ),
        (
            "chunked as the last of several transfer codings",
            [(b"content-length", b"10"), (b"transfer-encoding", b"gzip, chunked")],
        ),
        (
            "two content-length headers that disagree",
            [(b"content-length", b"10"), (b"content-length", b"99999999")],
        ),
        ("negative content-length", [(b"content-length", b"-1")]),
        ("no content-length at all", []),
    ],
)
def test_a_lying_content_length_cannot_bypass_the_limit(
    label: str, headers: list[tuple[bytes, bytes]]
):
    import asyncio

    over = MAX_BODY_BYTES_DEFAULT // (1024 * 1024) + 4
    statuses, delivered = asyncio.run(_deliver(headers, over))

    assert statuses == [413], f"{label}: expected 413, got {statuses}"
    assert delivered <= MAX_BODY_BYTES_DEFAULT, (
        f"{label}: {delivered:,} bytes reached the app, over the "
        f"{MAX_BODY_BYTES_DEFAULT:,} byte limit"
    )


def test_a_truthful_content_length_still_short_circuits():
    """The fix must not cost the fast path: a plain, honest Content-Length under
    the limit is still trusted and the body is not buffered here."""
    from app.limits import _declared_length

    assert _declared_length(
        {"headers": [(b"content-length", b"1234")]}
    ) == 1234
    assert _declared_length(
        {"headers": [(b"content-length", b"1234"), (b"content-length", b"1234")]}
    ) == 1234
