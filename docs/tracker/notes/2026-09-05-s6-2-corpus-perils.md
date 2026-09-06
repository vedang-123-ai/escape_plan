# S6.2 — Corpus: earthquake and severe-weather grounding

- **Who:** Corpus subagent (Lane B)
- **Date(s):** 2026-09-05
- **Status when I stopped:** Done. Corpus valid: 17 sources, 8 corpus files.

## What happened
- Researched USGS, FEMA, NOAA/NWS, and Great ShakeOut for earthquake and tornado guidance.
- Wrote `backend/corpus/earthquake-preparedness.md` with rules on Drop, Cover, Hold On, debunking the Triangle of Life, securing furniture (including renter-friendly strap options), gas shutoff protocol, and post-shaking evacuation.
- Wrote `backend/corpus/severe-weather-tornado.md` detailing safe room hierarchy (basement > interior room on lowest floor), mobile home vulnerability, watch vs. warning differences, and head/neck protection.
- Updated `backend/corpus/sources.json` to include 6 new sources and the 2 new corpus files.
- Ran `validate.py` (exited 0).
- Triggered a review with a grounding-auditor subagent, which found several un-cited claims and missing guidance. Addressed all findings by removing invented guidance, adding required citations, and explicitly detailing the doorway myth (earthquakes) and basement superiority (tornado).
- Re-ran `validate.py` (exited 0).

## Decisions / surprises
- Deliberately did not add any new thresholds to `egress_thresholds.json` because there were no numeric, codified thresholds found that were worth computing on.
- Explicitly put the commentary about tornado guidance being the exact inverse of fire escape guidance into an "Implications for the app" editorial note rather than presenting it as safety guidance, based on the reviewer's feedback.

## Questions for teammates
- None.

## Next steps
- Unblocks S6.3 (peril engine) and S6.4 (checklist rule table).
