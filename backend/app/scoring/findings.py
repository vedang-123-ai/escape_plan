"""The agent-findings interface the score consumes (S3.2 → S3.5 boundary).

S3.5 is being built while S3.2 (the agentic home inspector) is still in flight in
a parallel lane, so this module declares the contract explicitly rather than
importing it. The shape is transcribed from the agent contract in
archive/playbook-v1:docs/playbook/S3-2.md: each finding is
`{severity: high|med|low, room_ids, finding, evidence: [tool_call_refs],
recommendation, citation}`.

Reconciled with S3.2 post-merge (2026-07-22): `app.ai.agent.Finding` is
field-for-field identical to this one. The duplication is deliberate and stays —
`app.ai.agent` imports `anthropic` at module level, so re-exporting its model
here would drag the Anthropic SDK into the deterministic scoring path and break
the project's division of labor (scoring never depends on the AI layer).

The cost is that the two must be kept in lockstep by hand. If either changes,
change both; `test_finding_lockstep.py` fails on any field-set drift, and
`test_scoring.py` / `test_agent.py` pin behavior on each side.
Points of drift to watch:
  - severity spelling ("med" vs "medium") — SEVERITY_DEDUCTIONS keys must follow
  - `evidence` element type (opaque tool_call ref strings)
  - `id` semantics: server-stamped content hash (see finding_id below)

`finding_id` lives here rather than in app.ai.agent so the id scheme stays
importable from the deterministic scoring path; the agent imports it from here
(AI may depend on scoring, never the reverse).
"""

from __future__ import annotations

import hashlib
import re
from typing import Literal, Sequence

from pydantic import BaseModel, ConfigDict, Field

Severity = Literal["high", "med", "low"]


def finding_id(severity: str, room_ids: Sequence[str], finding: str) -> str:
    """Deterministic content-derived id for an agent finding.

    Hashes severity + sorted room ids + a normalized slug of the finding text,
    so the same issue keeps the same id across re-analyses regardless of the
    order findings are reported in. Wording changes to the finding text DO
    change the id — that is inherent to content addressing and acceptable: the
    stale checkmark simply orphans, which was already the failure mode of the
    positional ids this replaces.
    """
    slug = " ".join(re.findall(r"[a-z0-9]+", finding.lower()))
    basis = "|".join([severity, ",".join(sorted(room_ids)), slug])
    return hashlib.sha256(basis.encode("utf-8")).hexdigest()[:12]


class Finding(BaseModel):
    """One issue reported by the S3.2 agent inspector.

    Findings are *inputs* to scoring: the score never re-derives them, and the
    AI never scores. Evidence links are validated by S3.2 server-side before a
    finding is emitted; scoring trusts that and only reads severity here.
    """

    # Stays "ignore" (not "forbid", which is what app.ai.agent.Finding uses): scoring is the
    # consumer here, and a field added on the agent side should not 422 the score endpoint.
    model_config = ConfigDict(extra="ignore")

    id: str = ""
    """Stable content-derived id, stamped server-side by /analyze (finding_id).
    Empty when the caller predates ids; the checklist then falls back to
    positional keying (the pre-id status quo)."""

    severity: Severity
    room_ids: list[str] = Field(default_factory=list)
    finding: str
    evidence: list[str] = Field(default_factory=list)
    recommendation: str
    citation: str
