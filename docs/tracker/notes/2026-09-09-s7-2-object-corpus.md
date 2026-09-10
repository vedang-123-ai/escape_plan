# S7.2 — Object-hazard corpus, thresholds, and validation

- **Who:** P1 (AI)
- **Date(s):** 2026-09-09
- **Status when I stopped:** Phase G complete. Corpus updated, validated, and S7.4 unblocked.

## What happened
- Read the massive set of documentation to internalize all rules, including the S7.1 arc.
- Created `heating-electrical-fire-safety.md` drawing entirely from NFPA to cover space heaters, cooking, electrical, and dryers.
- Stood up the new `object_hazard_thresholds.json` using the explicit separation between "cited" standards and "engineering_constants" (geometric judgments).
- Validated new URLs via `certifi` because `urllib` was failing with `CERTIFICATE_VERIFY_FAILED` (the known TLS issue on this machine). All sources verified HTTP 200.
- Re-ran the S7.1 simulator-gated tests (STEP 0) with `xcodebuild test`. Passed (23 tests). Closed the `testCurrentVersionMatchesTheSchemaContract` defect.
- Re-ran `demo-preflight.py`. Confirmed the deployed schema is 2.1 (9 routes).
- Updated `validate.py` to enforce the structure of `object_hazard_thresholds.json`.
- Established convention for metric rounding: Markdown prose uses approximate rounded values for readability (e.g., "3 feet (0.9 m)"), but the engine (S7.4) must exclusively read the precise metric value (`0.9144` m) directly from `object_hazard_thresholds.json`.

## Decisions / surprises
- We opted to use NFPA sources for all 5 requested topic areas rather than split them with USFA, as the NFPA pages correctly responded to fetch attempts while USFA sub-pages returned 404s when requested via the AI's HTTP tools.
- We bypassed the `CERTIFICATE_VERIFY_FAILED` issue by using `certifi` in the validation script.

## Questions for teammates
None.

## Next steps
- S7.3 (scan objects through the pipeline) or S7.4 (object-hazard engine) are now unblocked.

## Verified Sources (Corrective Cycle)
| Source ID | URL | Retrieved | Status | Verified Claim Text |
|-----------|-----|-----------|--------|---------------------|
| usfa-dryer-safety | https://www.usfa.fema.gov/downloads/pdf/statistics/v13i7.pdf | 2026-09-09 | 200 | "Clean the lint filter before and after each cycle", "Lint is a highly combustible material that can accumulate both in the dryer and in the dryer vent" |
| nfpa-heating-safety | https://www.nfpa.org/education-and-research/home-fire-safety/heating | 2026-09-09 | 200 | "Keep anything that can burn... at least three feet away from all heating equipment", "Turn off portable heaters whenever you leave the room" |
| nfpa-cooking-safety | https://www.nfpa.org/education-and-research/home-fire-safety/cooking | 2026-09-09 | 200 | "Stay in the kitchen when you are frying, grilling, boiling, or broiling" |
| nfpa-electrical-safety | https://www.nfpa.org/education-and-research/home-fire-safety/electrical-safety-in-the-home | 2026-09-09 | 200 | "Extension cords should only be used for temporary purposes", "Do not overload outlets or circuits." |
| nfpa-heating-report | https://www.nfpa.org/education-and-research/research/nfpa-research/fire-statistical-reports/heating-equipment | 2026-09-09 | 200 | "Heating equipment is the second leading cause of home fires", "nearly half (46%) occur... December, January, and February" |
| nfpa-cooking-report | https://www.nfpa.org/education-and-research/research/nfpa-research/fire-statistical-reports/home-cooking-fires | 2026-09-09 | 200 | "Cooking is the leading cause of home fires and home fire injuries", "unattended cooking is the primary contributing factor" |
