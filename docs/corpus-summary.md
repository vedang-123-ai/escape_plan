# What guidance we ground on (S0.4 handoff)

One-page summary of the fire-safety grounding corpus in `backend/corpus/`. The AI layer cites **only** these sources; the deterministic egress checker reads `egress_thresholds.json`. Validate anytime with `python3 backend/corpus/validate.py`.

## The corpus at a glance

| File | Grounds | Primary source |
|---|---|---|
| `escape-planning-nfpa.md` | Two ways out of every room, meeting point, practice 2×/year, during-fire behavior | NFPA escape planning guidance |
| `egress-windows-irc.md` | Window/door egress code numbers + where escape openings are required | 2021 IRC §R310 / §R311 (ICC) |
| `smoke-alarms-usfa.md` | Alarm placement (every bedroom, outside sleeping areas, every level), testing, 10-year replacement | USFA/FEMA |
| `home-fire-escape-redcross.md` | Escape plan steps, the 2-minute drill loop the app's drill mode mirrors | American Red Cross |
| `fire-facts-stats.md` | Approved statistics for AI + pitch (3-in-5 deaths, ~2 minutes to escape, 26% practiced) | NFPA research / Red Cross |
| `special-considerations.md` | Profile guidance: mobility-limited, children, older adults, pets + deterministic tag→constraint mappings | USFA / NFPA disability evacuation guides |

## The numbers the routing engine uses (`egress_thresholds.json`)

2021 IRC baseline, imperial as codified + meters for the HomeModel: window egress ≥5.7 sq ft net clear opening (5.0 grade-floor), ≥24 in height, ≥20 in width, sill ≤44 in; egress door ≥32×78 in; every sleeping room requires an escape opening. Each value carries `source_doc_id` + `code_ref`. Jurisdiction-variance caveat included.

## Grounding rules encoded for S3.1

- Every citable source has an id in `sources.json` (11 sources); the citation validator checks against it.
- Inline citations use `[cite: source-id]`; `validate.py` rejects unresolvable or undeclared citations.
- Statistics outside `fire-facts-stats.md` are off-limits; uncovered topics → honest deferral (rule stated in the corpus itself).

## Known gaps (flagged for P1 sign-off)

- IRC citations point to ICC's online code pages; jurisdictions amend values — corpus says so explicitly.
- No fire-extinguisher or escape-ladder product guidance yet; add if a feature needs it.
- Corpus is ~8 pages of dense structured guidance vs. the playbook's ~15–25 page target — deliberately dense rather than padded; flag if S3.1 needs more breadth.
