"""The agent-findings interface the score consumes (S3.2 → S3.5 boundary).

S3.5 is being built while S3.2 (the agentic home inspector) is still in flight in
a parallel lane, so this module declares the contract explicitly rather than
importing it. The shape is transcribed from the agent contract in
docs/playbook/S3-2.md: each finding is
`{severity: high|med|low, room_ids, finding, evidence: [tool_call_refs],
recommendation, citation}`.

TODO(integration): reconcile with S3.2's actual models on merge. If S3.2 defines
an equivalent model, delete this one and re-export theirs from here so the
scoring engine's import path is unchanged. Points of likely drift:
  - severity spelling ("med" vs "medium") — SEVERITY_DEDUCTIONS keys must follow
  - `evidence` element type (opaque tool_call ref strings assumed here)
  - whether findings carry an id (the checklist synthesizes one; see checklist.py)
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Severity = Literal["high", "med", "low"]


class Finding(BaseModel):
    """One issue reported by the S3.2 agent inspector.

    Findings are *inputs* to scoring: the score never re-derives them, and the
    AI never scores. Evidence links are validated by S3.2 server-side before a
    finding is emitted; scoring trusts that and only reads severity here.
    """

    model_config = ConfigDict(extra="ignore")  # tolerate extra S3.2 fields pre-merge

    severity: Severity
    room_ids: list[str] = Field(default_factory=list)
    finding: str
    evidence: list[str] = Field(default_factory=list)
    recommendation: str
    citation: str
