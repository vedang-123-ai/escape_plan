"""Lockstep guard for the two hand-synced Finding classes.

WHY two classes exist at all: `app.ai.agent` imports the `anthropic` SDK at
module scope, and the deterministic scoring path must never depend on the AI
layer or its SDK (the project's division-of-labor rule). So
`app.scoring.findings.Finding` is a deliberate field-for-field copy of
`app.ai.agent.Finding`, kept in sync by hand — and this test is the mechanism
that makes silent drift impossible. If either side gains, loses, retypes, or
re-requires a field, a test here fails and names the divergence.

Do NOT "fix" a failure here by making one module import the other's model:
that would drag the Anthropic SDK into scoring. Change both classes together.
"""

from __future__ import annotations

from app.ai.agent import Finding as AgentFinding
from app.scoring.findings import Finding as ScoringFinding

# The one deliberate requiredness difference: the agent-side model REQUIRES
# `evidence` (schema pressure on the model — every finding must name its tool
# calls), while the scoring-side copy defaults it to [] because /score is a
# lenient consumer and a score request is valid without evidence lists.
REQUIREDNESS_EXCEPTIONS = {"evidence"}


def test_field_names_match_exactly():
    assert set(AgentFinding.model_fields) == set(ScoringFinding.model_fields)


def test_field_types_match_exactly():
    for name, agent_field in AgentFinding.model_fields.items():
        scoring_field = ScoringFinding.model_fields[name]
        assert agent_field.annotation == scoring_field.annotation, (
            f"Finding.{name} type drifted: agent={agent_field.annotation!r} "
            f"scoring={scoring_field.annotation!r}"
        )


def test_requiredness_matches_except_documented_exception():
    for name, agent_field in AgentFinding.model_fields.items():
        scoring_field = ScoringFinding.model_fields[name]
        if name in REQUIREDNESS_EXCEPTIONS:
            # Pin the direction too, so the exception can't silently flip.
            assert agent_field.is_required(), f"{name}: agent side must require it"
            assert not scoring_field.is_required(), f"{name}: scoring side must default it"
        else:
            assert agent_field.is_required() == scoring_field.is_required(), (
                f"Finding.{name} requiredness drifted"
            )


def test_extra_config_is_the_documented_pair():
    # Agent side forbids extras (strict contract with the model's submission);
    # scoring side ignores them (a field added on the agent side must not 422
    # the score endpoint). Both are deliberate — see app/scoring/findings.py.
    assert AgentFinding.model_config.get("extra") == "forbid"
    assert ScoringFinding.model_config.get("extra") == "ignore"
