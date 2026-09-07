"""S3.1 deterministic tests: citation validation, prompt construction, retry
loop, and the /explain endpoint — no network, the Anthropic client is faked."""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import config
from app.ai import grounded
from app.ai.grounded import (
    ExplainResponse,
    GroundingError,
    Recommendation,
    RoomExplanation,
    build_system_blocks,
    explain_routes,
    find_invalid_citations,
    valid_source_ids,
)
from app.main import app
from app.models import HomeModel
from app.routing.engine import compute_route_plan

TEST_TOKEN = "test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def _response(citation: str) -> ExplainResponse:
    return ExplainResponse(
        summary="A short overview.",
        room_explanations=[
            RoomExplanation(
                room_id="r1", room_name="Bedroom", primary_explanation="Go out the door."
            )
        ],
        recommendations=[
            Recommendation(
                claim="Everyone needs two ways out of every room.",
                action="Add a secondary route for the bedroom.",
                source_citation=citation,
            )
        ],
    )


# --- citation validator -----------------------------------------------------


def test_valid_source_ids_come_from_sources_json():
    ids = valid_source_ids()
    assert "nfpa-escape-planning" in ids
    assert "irc-2021-r310" in ids
    # compilation-doc primary ids are NOT citable
    assert "fire-facts-stats" not in ids
    assert "special-considerations" not in ids


def test_validator_accepts_real_citation():
    assert find_invalid_citations(_response("nfpa-escape-planning")) == []


def test_validator_rejects_fabricated_source():
    problems = find_invalid_citations(_response("nfpa-totally-made-up-2026"))
    assert len(problems) == 1
    assert "nfpa-totally-made-up-2026" in problems[0]


def test_validator_rejects_empty_recommendations():
    resp = _response("nfpa-escape-planning")
    resp.recommendations = []
    assert find_invalid_citations(resp)


# --- system prompt ----------------------------------------------------------


def test_system_prompt_embeds_full_corpus_with_cache_control():
    blocks = build_system_blocks()
    assert len(blocks) == 2
    assert blocks[1]["cache_control"] == {"type": "ephemeral"}
    for name in grounded.CORPUS_FILE_ORDER + ["egress_thresholds.json"]:
        assert f'<corpus_doc file="{name}">' in blocks[1]["text"]
    # the rules block enumerates the citable ids
    assert "nfpa-escape-planning" in blocks[0]["text"]


# --- retry loop (faked client) ----------------------------------------------


class FakeClient:
    """Returns scripted submit_explanation payloads in order."""

    def __init__(self, payloads: list[dict]):
        self._payloads = list(payloads)
        self.calls = 0
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs):
        self.calls += 1
        payload = self._payloads.pop(0)
        return SimpleNamespace(
            content=[
                SimpleNamespace(
                    type="tool_use", id=f"toolu_{self.calls}", input=payload
                )
            ],
            usage=SimpleNamespace(
                input_tokens=100,
                output_tokens=50,
                cache_creation_input_tokens=0,
                cache_read_input_tokens=0,
            ),
        )


@pytest.fixture
def bungalow_home_and_plan(bungalow: dict):
    home = HomeModel.model_validate(bungalow)
    plan = compute_route_plan(home, config.get_thresholds())
    return home, plan


def test_explain_retries_fabricated_citation_then_succeeds(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    fake = FakeClient(
        [
            _response("made-up-source").model_dump(),
            _response("nfpa-escape-planning").model_dump(),
        ]
    )
    result = explain_routes(home, plan, client=fake)  # type: ignore[arg-type]
    assert fake.calls == 2
    assert result.recommendations[0].source_citation == "nfpa-escape-planning"


def test_explain_gives_up_after_retries(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    fake = FakeClient([_response("made-up-source").model_dump()] * 3)
    with pytest.raises(GroundingError, match="made-up-source"):
        explain_routes(home, plan, client=fake)  # type: ignore[arg-type]
    assert fake.calls == 1 + grounded.MAX_CITATION_RETRIES


# --- /explain endpoint ------------------------------------------------------


def test_explain_endpoint_requires_token(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    body = {
        "home": home.model_dump(mode="json"),
        "route_plan": plan.model_dump(mode="json"),
    }
    assert TestClient(app).post("/explain", json=body).status_code == 401


def test_explain_endpoint_happy_path(bungalow_home_and_plan, monkeypatch):
    home, plan = bungalow_home_and_plan
    canned = _response("nfpa-escape-planning")
    monkeypatch.setattr("app.main.explain_routes", lambda *a, **k: canned)
    resp = TestClient(app).post(
        "/explain",
        json={
            "home": home.model_dump(mode="json"),
            "route_plan": plan.model_dump(mode="json"),
        },
        headers=AUTH,
    )
    assert resp.status_code == 200
    assert ExplainResponse.model_validate(resp.json()) == canned


def test_explain_endpoint_maps_grounding_error_to_502(
    bungalow_home_and_plan, monkeypatch
):
    home, plan = bungalow_home_and_plan

    def boom(*a, **k):
        raise GroundingError("citation validation failed after retries")

    monkeypatch.setattr("app.main.explain_routes", boom)
    resp = TestClient(app).post(
        "/explain",
        json={
            "home": home.model_dump(mode="json"),
            "route_plan": plan.model_dump(mode="json"),
        },
        headers=AUTH,
    )
    assert resp.status_code == 502


def test_corpus_block_matches_sources_json() -> None:
    """The mechanism that keeps citation validation honest.

    `valid_source_ids()` accepts every id in sources.json, so an id is only safe to
    accept if the model was actually shown the document it comes from. S6.2 added two
    corpus files and six source ids while `CORPUS_FILE_ORDER` and `CORPUS_DOC_FILES`
    stayed hardcoded to the six fire documents -- so the server would have validated
    `noaa-tornado` on a tornado claim the model invented, and search_corpus answered
    'tornado safe room' with five fire-escape paragraphs. Both lists are now derived
    from sources.json; this asserts they cannot drift apart again.
    """
    import json as _json
    from app.ai import agent, grounded
    from app.config import CORPUS_DIR

    declared = [cf["file"] for cf in _json.loads((CORPUS_DIR / "sources.json").read_text())["corpus_files"]]
    assert grounded.CORPUS_FILE_ORDER == declared
    assert agent.CORPUS_DOC_FILES == declared

    # Every id the server will accept must appear in the block the model is shown.
    block = grounded.corpus_text()
    unseen = sorted(i for i in grounded.valid_source_ids() if i not in block)
    assert not unseen, f"ids validate but are never shown to the model: {unseen}"
