"""Deterministic navigation graph + routing engine (S1.1/S1.2).

Pure-function modules: no I/O, no globals, same input → same output. The FastAPI
endpoints (S1.6) and the agent tools (S3.2) are thin wrappers over these.
"""

from app.routing.egress import EgressThresholds, annotate_egress, check_egress
from app.routing.graph import NavGraph, build_graph

__all__ = [
    "EgressThresholds",
    "annotate_egress",
    "check_egress",
    "NavGraph",
    "build_graph",
]
