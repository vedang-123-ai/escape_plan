"""Run the S11.4 eval set deterministically — no API key, no network.

Four things are asserted:

1. Every grader discriminates. For each case the `good` reply must pass and the
   `bad` reply must fail. A grader that accepts everything (the usual way an eval
   rots into decoration) fails on `bad`; one that accepts nothing fails on `good`.
2. The cases are internally honest: real source ids, no duplicate ids, every
   surface real.
3. The graders survive the real plumbing. The `chat()` service is driven with a
   stub Anthropic client replaying each case's reply, so the citation validator,
   the retry loop and the response shape are exercised exactly as in production.
4. The /build cases discriminate through the real builder loop. /build returns a
   BuildResult and no prose, so those probes are scripted tool calls replayed
   through `run_builder`, and the graders read the BuildResult.

When the account has credits, `test_evals_live.py` runs the same cases against
the real model with the same graders.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from app import config
from app.ai.chat.service import ChatGroundingError, ChatMessage, chat
from app.ai.grounded import valid_source_ids
from app.models import HomeModel
from app.routing.engine import compute_route_plan
from tests.conftest import load_fixture
from tests.evals import graders as g
from tests.evals import cases as cases_module
from tests.evals.cases import CASES, EvalCase

CASE_IDS = [c.id for c in CASES]

TEST_TOKEN = "eval-test-token"


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    """The service reads settings, which fail closed without a bearer token.

    No ANTHROPIC_API_KEY is set or needed: every call in this module goes through
    an injected stub client, which is the point of the suite.
    """
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def _graders(case: EvalCase):
    """Every grader that applies to this case, expectations and prohibitions."""
    expect = list(case.expect)
    if case.allowed_measurements:
        expect.append(g.states_no_measurement_outside(set(case.allowed_measurements)))
    return expect, list(case.forbid)


def _grade(case: EvalCase, reply: str) -> list[str]:
    """Problems with `reply`, or [] if it satisfies the case."""
    expect, forbid = _graders(case)
    problems = [p for grader in expect if (p := grader(reply)) is not None]
    for grader in forbid:
        if grader(reply) is None:
            problems.append(f"forbidden behaviour present: {grader.__name__}")
    return problems


# ---------------------------------------------------------------------------
# 1. The graders discriminate


@pytest.mark.parametrize("case", CASES, ids=CASE_IDS)
def test_the_good_reply_passes_every_grader(case: EvalCase) -> None:
    problems = _grade(case, case.good)
    assert problems == [], f"{case.id}: the passing probe was rejected: {problems}"


@pytest.mark.parametrize("case", CASES, ids=CASE_IDS)
def test_the_bad_reply_is_caught(case: EvalCase) -> None:
    """The half that matters. Without it a grader could return None always."""
    problems = _grade(case, case.bad)
    assert problems, (
        f"{case.id}: the failing probe passed every grader — this case is "
        f"currently decorative"
    )


# ---------------------------------------------------------------------------
# 2. The case set is honest about itself


def test_case_ids_are_unique() -> None:
    assert len(CASE_IDS) == len(set(CASE_IDS))


def test_the_set_covers_the_behaviours_the_session_asked_for() -> None:
    """S11-4.md names five required kinds; this is the receipt."""
    ids = set(CASE_IDS)
    required = {
        "emergency": {"emergency-smoke-now", "emergency-trapped-upstairs"},
        "uncited claim": {
            "fabricated-citation-rejected",
            "uncited-claim-rejected",
            "uncited-safety-claim",
            "mixed-cited-and-uncited",
        },
        "out of corpus": {"out-of-corpus-wiring", "out-of-corpus-flood"},
        "route from the engine": {
            "route-question-must-come-from-the-engine",
            "no-invented-route-timing",
        },
        "honest peril tiering": {
            "which-peril-is-best-quantified",
            "earthquake-advice-is-not-a-measurement",
        },
    }
    for kind, needed in required.items():
        assert needed <= ids, f"no case covers {kind}: missing {sorted(needed - ids)}"
    # S11.4 asked for 12-15; S11.44 added two for AUD-030 on purpose.
    assert 12 <= len(CASES) <= 17, f"expected 12-17 cases; found {len(CASES)}"


@pytest.mark.parametrize("case", CASES, ids=CASE_IDS)
def test_every_case_uses_real_source_ids(case: EvalCase) -> None:
    """A case citing a fake id in its `good` probe would teach the wrong thing."""
    from app.ai.chat.claims import cited_ids

    valid = valid_source_ids()
    bogus = sorted(set(cited_ids(case.good)) - valid)
    assert not bogus, f"{case.id}: `good` cites non-existent source ids {bogus}"


MEASURING_CASES = [c for c in CASES if c.allowed_measurements]


@pytest.mark.parametrize(
    "case", MEASURING_CASES, ids=[c.id for c in MEASURING_CASES]
)
def test_allowed_measurements_come_from_the_engine(case: EvalCase) -> None:
    """The guard for the defect the grounding-auditor found in this file.

    `states_no_measurement_outside` grades real model output against this set, so
    a hand-typed number here INVERTS the case: the model is failed for quoting the
    engine and passed for inventing. Both measuring cases shipped that way in the
    first draft ("8.4 m" for a 14.192 m route; a 0.35 m move on a fixture with no
    obstruction). Every entry must now be reproducible from the engine.
    """
    from tests.evals.cases import obstruction_measurements, route_measurements

    derived: set[str] = set()
    _, plan = cases_module._plan_for(case.fixture)
    for room in plan.rooms:
        derived |= route_measurements(case.fixture, room.room_id)
    try:
        derived |= obstruction_measurements(case.fixture)
    except AssertionError:
        pass  # this fixture has no obstructions; routes alone must cover the case

    unexplained = sorted(set(case.allowed_measurements) - derived)
    assert not unexplained, (
        f"{case.id}: {unexplained} is not a measurement the engine produced for "
        f"{case.fixture} — a literal typed here inverts the grader"
    )
    assert case.allowed_measurements, f"{case.id}: empty allowed set grades nothing"


@pytest.mark.parametrize("case", CASES, ids=CASE_IDS)
def test_the_good_probe_quotes_only_engine_measurements(case: EvalCase) -> None:
    """The probe text and the allowed set must agree, or the case teaches a lie."""
    if not case.allowed_measurements:
        return
    grader = g.states_no_measurement_outside(set(case.allowed_measurements))
    assert grader(case.good) is None, (
        f"{case.id}: the passing probe quotes a number the engine did not produce"
    )


@pytest.mark.parametrize("case", CASES, ids=CASE_IDS)
def test_every_case_says_why_it_exists(case: EvalCase) -> None:
    """An eval nobody can justify is an eval nobody will maintain."""
    assert len(case.why) > 40, f"{case.id}: `why` is too thin to survive a rewrite"


# ---------------------------------------------------------------------------
# 3. The graders run against the real service, with a stub client


class StubAnthropic:
    """Replays scripted text replies through the real `chat()` code path.

    Shaped like the SDK's response object only as far as the service reads it:
    `.content` blocks with `.type`/`.text`, and a `.usage` the cache logger can
    read. Deliberately not a mock of the SDK — it is a stand-in for one call.
    """

    def __init__(self, replies: list[str]):
        self._replies = list(replies)
        self.calls = 0
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs):
        self.calls += 1
        self.last_kwargs = kwargs
        text = self._replies.pop(0)
        return SimpleNamespace(
            content=[SimpleNamespace(type="text", text=text)],
            usage=SimpleNamespace(
                input_tokens=1000,
                output_tokens=120,
                cache_creation_input_tokens=0,
                cache_read_input_tokens=900,
            ),
        )


@pytest.fixture(scope="module")
def home_and_plan():
    home = HomeModel.model_validate(load_fixture("twostory.json"))
    return home, compute_route_plan(home, config.get_thresholds())


CHAT_CASES = [c for c in CASES if c.surface == "chat"]
CHAT_CASE_IDS = [c.id for c in CHAT_CASES]


@pytest.mark.parametrize("case", CHAT_CASES, ids=CHAT_CASE_IDS)
def test_the_good_reply_survives_the_real_chat_service(case: EvalCase, home_and_plan):
    """End to end through `chat()`: citation validation must not reject it."""
    home, plan = home_and_plan
    stub = StubAnthropic([case.good])
    result = chat([ChatMessage(role="user", content=case.question)], home, plan, client=stub)
    assert stub.calls == 1, "a valid reply should not have been retried"
    assert _grade(case, result.reply) == []


@pytest.mark.parametrize(
    "case",
    [c for c in CHAT_CASES if g.cites_only_real_sources in c.expect],
    ids=[c.id for c in CHAT_CASES if g.cites_only_real_sources in c.expect],
)
def test_a_fabricated_citation_is_retried_by_the_service_not_just_graded(
    case: EvalCase, home_and_plan
):
    """The grader and the server-side validator must agree.

    A grader that flags something the service happily ships would be measuring
    nothing; this drives the same text through `chat()` and asserts it is bounced.
    """
    home, plan = home_and_plan
    fabricated = "Test them monthly [cite: totally-invented-source-2026]."
    stub = StubAnthropic([fabricated, case.good])
    result = chat([ChatMessage(role="user", content=case.question)], home, plan, client=stub)
    assert stub.calls == 2, "the fabricated citation was not retried"
    assert g.cites_only_real_sources(result.reply) is None


UNCITED_CASES = [c for c in CHAT_CASES if g.cites_every_safety_claim in c.expect]


@pytest.mark.parametrize("case", UNCITED_CASES, ids=[c.id for c in UNCITED_CASES])
def test_an_uncited_claim_is_retried_then_deferred_by_the_service(case: EvalCase, home_and_plan):
    """S11.44: the grader and the server-side check are one function; prove the service acts on it.

    The `bad` probe is retried once; a cited `good` retry ships, and a second
    uncited reply becomes the deferral rather than reaching the user.
    """
    from app.ai.chat.service import UNCITED_DEFERRAL

    home, plan = home_and_plan
    q = [ChatMessage(role="user", content=case.question)]
    assert g.cites_every_safety_claim(case.bad) is not None, f"{case.id}: bad probe is cited"

    stub = StubAnthropic([case.bad, case.good])
    assert chat(q, home, plan, client=stub).reply == case.good
    assert stub.calls == 2

    stub = StubAnthropic([case.bad, case.bad])
    result = chat(q, home, plan, client=stub)
    assert stub.calls == 2
    assert result.reply == UNCITED_DEFERRAL and result.citations == []


def test_the_service_gives_up_rather_than_shipping_a_fabricated_citation(home_and_plan):
    home, plan = home_and_plan
    bad = "Do it monthly [cite: not-a-real-source]."
    stub = StubAnthropic([bad] * 3)
    with pytest.raises(ChatGroundingError):
        chat([ChatMessage(role="user", content="how often?")], home, plan, client=stub)


def test_the_stub_sees_the_repositioned_system_prompt(home_and_plan):
    """Cheap proof the eval is grading the prompt this session actually shipped."""
    home, plan = home_and_plan
    stub = StubAnthropic(["Fine [cite: nfpa-escape-planning]."])
    chat([ChatMessage(role="user", content="hi")], home, plan, client=stub)
    system_text = " ".join(b["text"] for b in stub.last_kwargs["system"])
    assert "readiness and" in system_text and "prevention app" in system_text
    assert "fire escape planning app" not in system_text


def test_the_corpus_block_is_the_cache_breakpoint(home_and_plan):
    """anthropic.md: 'prompt caching on the corpus block; log cache hits.'"""
    home, plan = home_and_plan
    stub = StubAnthropic(["Fine [cite: nfpa-escape-planning]."])
    chat([ChatMessage(role="user", content="hi")], home, plan, client=stub)
    blocks = stub.last_kwargs["system"]
    cached = [b for b in blocks if b.get("cache_control")]
    assert cached, "no system block carries cache_control"
    assert any("<corpus_doc" in b["text"] for b in cached), (
        "the corpus block is not the cached one"
    )


# ---------------------------------------------------------------------------
# 4. The /build surface, through the real builder loop

from app.ai.builder import BuildResult, run_builder  # noqa: E402
from tests.evals.cases import BUILD_CASES, BuildEvalCase  # noqa: E402

BUILD_IDS = [c.id for c in BUILD_CASES]


class ScriptedBuilder:
    """Replays a BuildEvalCase script as `messages.create` responses.

    Each scripted turn becomes one response: tool calls become `tool_use` blocks
    with fresh ids, a str becomes a text-only turn (which ends the loop).
    """

    def __init__(self, script):
        self._turns = list(script)
        self._n = 0
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs):
        if not self._turns:
            raise AssertionError("the script ran out before the builder stopped")
        turn = self._turns.pop(0)
        if isinstance(turn, str):
            return SimpleNamespace(content=[SimpleNamespace(type="text", text=turn)])
        blocks = []
        for name, tool_input in turn:
            self._n += 1
            blocks.append(
                SimpleNamespace(type="tool_use", id=f"toolu_{self._n}", name=name, input=tool_input)
            )
        return SimpleNamespace(content=blocks)


def _build(case: BuildEvalCase, script) -> BuildResult:
    return run_builder(
        description=case.question,
        client=ScriptedBuilder(script),
        home_id="11111111-2222-3333-4444-555555555555",
        now_iso="2026-09-24T12:00:00Z",
    )


def _grade_build(case: BuildEvalCase, result: BuildResult) -> list[str]:
    return [p for grader in case.expect if (p := grader(result)) is not None]


@pytest.mark.parametrize("case", BUILD_CASES, ids=BUILD_IDS)
def test_the_good_build_script_passes_every_grader(case: BuildEvalCase) -> None:
    problems = _grade_build(case, _build(case, case.good))
    assert problems == [], f"{case.id}: the passing probe was rejected: {problems}"


@pytest.mark.parametrize("case", BUILD_CASES, ids=BUILD_IDS)
def test_the_bad_build_script_is_caught(case: BuildEvalCase) -> None:
    """The bad script must survive the real plumbing and still be failed.

    It is asserted to build a valid home first: a bad probe that only failed
    because the action layer rejected it would be testing the validator, not the
    grader, and the case would be decorative on a model that builds cleanly.
    """
    result = _build(case, case.bad)
    assert result.home is not None and not result.truncated, (
        f"{case.id}: the bad probe did not even build ({result.issues}); fix the script"
    )
    assert _grade_build(case, result), f"{case.id}: the failing probe passed every grader"


@pytest.mark.parametrize("case", BUILD_CASES, ids=BUILD_IDS)
def test_every_build_case_says_why_it_exists(case: BuildEvalCase) -> None:
    assert len(case.why) > 40 and case.expect, case.id


def test_build_case_ids_are_unique_across_the_whole_set() -> None:
    every = CASE_IDS + BUILD_IDS
    assert len(every) == len(set(every))


def test_the_builder_draft_is_still_stamped_ai_plan() -> None:
    """What makes the builder a draft-only fallback: its output cannot skip review."""
    case = next(c for c in BUILD_CASES if c.id == "build-uses-the-stated-dimensions")
    home = _build(case, case.good).home
    assert home is not None
    entities = [e for f in home.floors for e in (*f.rooms, *f.openings, *f.objects)]
    assert entities and all(e.source.value == "ai_plan" for e in entities)


def test_the_size_grader_rejects_an_l_shape_inside_the_stated_box() -> None:
    """Found by the grounding-auditor: bounding box alone passed an L-shaped room."""
    case = next(c for c in BUILD_CASES if c.id == "build-uses-the-stated-dimensions")
    l_shape = [[0, 0], [4, 0], [4, 1.5], [2, 1.5], [2, 3], [0, 3]]
    script = list(case.good)
    script[2] = (("add_room", {
        "floor_id": "floor_1", "name": "Bedroom", "type": "bedroom", "polygon": l_shape,
    }),)
    result = _build(case, script)
    assert result.home is not None, result.issues
    assert g.has_a_room_measuring(4.0, 3.0)(result) is not None
