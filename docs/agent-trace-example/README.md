# S3.2 agent trace example

`apartment-analysis.json` is a full recorded run of the agent loop
(`backend/app/ai/agent.py::run_agent_analysis`) against `schema/fixtures/apartment.json`,
with a **scripted** Anthropic client standing in for the model (no API key was
available in this environment — see `docs/decisions.md`). The tool calls and
their outputs are real: `get_home_summary`, `get_room`, `compute_routes`, and
`search_corpus` all execute against the actual fixture and the actual S1.1/S1.2
engines. Only the sequence of *which* tool the model calls next, and the final
`submit_findings` payload, are scripted rather than model-generated.

This is what the pitch's "here's the agent literally checking each bedroom"
moment will look like once a real key drives the loop: the `trace` array is
the agent's literal work — each entry is one real tool call and its real
result — and `findings[0].evidence: ["toolu_04"]` is the server verifying that
the finding is actually backed by the `compute_routes` call in the trace,
not just an assertion the model made up.

## What it shows

- Single-point-of-failure detection: the agent calls `compute_routes`, sees the
 engine's own bottleneck output (`d_entry` disconnects all 5 rooms), and files
 a `high`-severity finding citing that exact tool call as evidence.
- Server-side enforcement: `run_agent_analysis` would have dropped this finding
 had `evidence` pointed at a nonexistent tool call, or had `citation` not been
 a real `sources.json` id — see `backend/tests/test_agent.py::test_agent_drops_findings_with_bad_evidence`.

## A related, more subtle case (twostory.json)

The playbook expected the twostory fixture's Kids' Bedroom to trip a
`no_secondary_egress` finding from the routing engine itself. It doesn't: the
engine's secondary-route search is house-level (bans the primary's *exit*, not
its first hop), so it happily routes the kids' room's "secondary" back out
through the shared landing door and the back door downstairs — a different
final exit, which satisfies its definition of a secondary route.

## A third tool, for a hazard neither of those can see (2026-08-02)

`compute_routes` and `check_egress` both reason about the *shell* of the home —
doorways, widths, sills. Neither can see a wardrobe standing in front of a
bedroom door. `check_obstructions` is the agent's window into
`app/routing/obstructions.py`, which attributes a blocked doorway to a specific
object by counterfactual re-rasterization (remove it, does the path come back?)
and measures how far it has to move.

The division of labor is the same one that governs routing: the engine decides
*what* is blocked and *by how much*, deterministically; the agent only re-words
that into cited advice. The tool payload carries the engine's own `detail`
sentence for exactly this reason, and the live test
(`test_blocked_bungalow_agent_names_the_wardrobe`) asserts the distance in the
model's recommendation is the one the engine measured — a fluent recommendation
with an invented number fails.

The room's own window (`w_kids`) does fail egress on width and area
(confirmed directly via `check_egress` — see
`test_check_egress_flags_undersized_kids_window`), so the *room* genuinely has
only one physical way out, even though the *house* doesn't. This is exactly
why the agent has `check_egress` as a tool distinct from `compute_routes`: it
can catch a room-level single-exit problem that a whole-house router
considers resolved. See `test_agent_flags_kids_room_undersized_window_via_check_egress`
for the scripted run, and `docs/decisions.md` for the note to P1.
