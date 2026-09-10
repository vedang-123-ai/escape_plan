# S7.4 — The object-hazard engine

- **Who:** P3
- **Date(s):** 2026-09-09
- **Status when I stopped:** S7.4 is complete, fully tested, and cleanly integrated with S7.5 and S7.6.

## What happened
- Implemented `object_hazards.py` handling topple (R1), overhead (R2), heat clearance (R3), and unstrapped water heater (R5) hazards based on physics thresholds.
- Widened `obstructions.py` to identify furniture blocking egress-qualifying windows (R4).
- Added comprehensive testing across `test_object_hazards.py` and `test_obstructions.py`. Tests cover negative scenarios (e.g., secured items, distant heaters), severity assignment rules, explicit measured distances injected into sentences, citation mapping, deterministic sorting, and non-egress window silence.
- Resolved UI issues by strictly pulling `[cite: ...]` out of engine prose. The engine emits raw prose strings to `detail` fields, trusting the higher `checklist.py` and `score.py` surfaces to construct the UI-ready `why=` payload using the `citation` property from `ObjectHazard`.
- Moved geometric magic numbers (like a 0.6m radius approach fallback) into domain configurations via `object_hazard_thresholds.json`. 

## Decisions / surprises
- We discovered that `Obstruction.detail` and `ObjectHazard.detail` cannot contain `[cite: source-id]` tags directly since the UI layers (e.g. `HomeScreen.swift`, `RouteFindingViews.swift`) print those details raw without passing through `DrillCitedText.swift`. Instead, citations are structurally preserved in `ObjectHazard.citation` and used cleanly during checklist/tool composition.

## Questions for teammates
- None right now. 

## Next steps
- **S7.7** — 3D emphasis and device pass.
