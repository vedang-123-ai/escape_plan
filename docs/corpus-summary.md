# What guidance we ground on

One-page summary of the grounding corpus in `backend/corpus/`. The AI layer cites **only** these sources;
the deterministic engines read the threshold files. Validate anytime with
`python3 backend/corpus/validate.py` (offline, stdlib-only).

_Last verified 2026-10-11 on `audit-review`: **35 sources, 13 corpus files, 2 threshold files,
44 prevention tips, 0 orphan exceptions.**_

## The corpus at a glance

### Fire — code-quantified

| File | Grounds | Primary source |
|---|---|---|
| `escape-planning-nfpa.md` | Two ways out of every room, meeting point, practice 2×/year, during-fire behavior | NFPA escape planning guidance |
| `egress-windows-irc.md` | Window/door egress code numbers + where escape openings are required | 2021 IRC §R310 / §R311 (ICC) |
| `smoke-alarms-usfa.md` | Alarm placement (every bedroom, outside sleeping areas, every level), testing, 10-year replacement | USFA/FEMA |
| `home-fire-escape-redcross.md` | Escape plan steps, the 2-minute drill loop the app's drill mode mirrors | American Red Cross |
| `fire-facts-stats.md` | Approved statistics for AI + pitch (3-in-5 deaths, ~2 minutes to escape, 26% practiced) | NFPA research / Red Cross |
| `special-considerations.md` | Profile guidance: mobility-limited, children, older adults, pets + deterministic tag→constraint mappings | USFA / NFPA disability evacuation guides |
| `heating-electrical-fire-safety.md` | Space-heater clearance, cooking, extension cords and outlets, dryer lint | NFPA heating/cooking/electrical, USFA dryer report |

### Earthquake — guidance-based (expanded S11.1)

| File | Grounds | Primary source |
|---|---|---|
| `earthquake-preparedness.md` | Drop/Cover/Hold On by situation (in bed, walker or wheelchair, no shelter), the doorway myth, the Triangle of Life | ShakeOut Step 5, USGS FAQ, Ready.gov |
| `earthquake-securing-home.md` | Securing furniture and TVs to studs, two-strap water heaters, cabinet latches, what renters can actually do | ShakeOut Step 1, Ready.gov, CA H&S Code §19211 |
| `earthquake-after-shaking.md` | The conditional gas-shutoff trigger, never restoring gas yourself, aftershocks, masonry, when to evacuate | ShakeOut Step 6, USGS FAQ |

### Tornado / severe weather — guidance-based (expanded S11.1)

| File | Grounds | Primary source |
|---|---|---|
| `severe-weather-tornado.md` | The shelter hierarchy and the "as many walls as possible" rule the engine's objective encodes | NWS, Ready.gov, Red Cross |
| `tornado-safe-rooms.md` | What a rated safe room is, FEMA P-361 / P-320 / ICC 500, and why a basement is not one | FEMA Safe Rooms, FEMA RA2 |
| `tornado-warnings-and-mobile-homes.md` | Watch vs warning vs emergency, alert channels, accessible alerting, manufactured homes | NWS, NWR accessibility, Red Cross |

## The numbers the engines use

**`egress_thresholds.json`** — 2021 IRC baseline, imperial as codified plus meters for the HomeModel:
window egress ≥5.7 sq ft net clear opening (5.0 grade-floor), ≥24 in height, ≥20 in width, sill ≤44 in;
egress door ≥32×78 in; every sleeping room requires an escape opening. Each value carries `source_doc_id`
and `code_ref`, with the jurisdiction-variance caveat included.

**`object_hazard_thresholds.json`** — one `cited` value (NFPA's 3 ft / 0.9144 m heater clearance) and five
`engineering_constants` that are labelled in the file as our own geometric judgement, **not** codified
standards (topple height and slenderness, overhead elevation, door approach radius, registration
tolerance).

**Earthquake and tornado contribute no new numeric thresholds, and that is a finding, not a gap.** See
`docs/decisions.md`, 2026-09-21. The two numbers that exist are not app-checkable: "two metal straps" on a
water heater is a practice, not a dimensioned code value, and the 200–250 mph safe-room design wind speed
is a construction criterion no resident or phone can measure. California H&S §19211 makes water-heater
strapping legally mandatory but delegates the method to the (paywalled) California Plumbing Code, so the
strap positions are not codified here. This asymmetry is exactly what S11.2's `basis` field —
`code_quantified` for fire, `guidance_based` for the others — has to express.

## `prevention_tips.json`

44 tips (`fire` 20, `earthquake` 13, `tornado` 11), each with `id`, `peril`, `topic`, `text`, `cite`,
`audience`. Every `cite` resolves in `sources.json` and is enforced by `validate.py` check 7. The iOS app
bundles a byte-identical copy; `scripts/check-tips-sync.py` (S11.5) is what keeps the two from drifting.

## Grounding rules

- Every citable source has an id in `sources.json` (35); inline citations are `[cite: source-id]`, and
  `validate.py` rejects unresolvable or undeclared ones.
- **No orphan sources** (`validate.py` check 8): every source id must be cited by a corpus doc or named in
  a threshold file. An id the AI may cite but was never shown a document for is a hole it can invent
  guidance through. No exceptions remain: `usgs-earthquake`, the last one, was removed 2026-10-11 once its
  only caller (the drill aftershock card) had been deleted.
- Compilation docs (`fire-facts-stats.md`, `special-considerations.md`, and the four new peril docs) have
  non-source primary ids and only ever cite underlying external sources.
- Statistics outside `fire-facts-stats.md` are off-limits; uncovered topics get honest deferral.
- No source, it doesn't ship. Two earthquake claims and all candle guidance were **removed** in S11.1 for
  exactly this reason rather than re-attributed to an adjacent page.

## Verifying sources against the live web

`python3 backend/corpus/check_urls.py` (network, opt-in, **not** part of the gate) re-fetches every source
URL, confirms 200, and greps for that source's `verify_keywords`. It is how a `retrieved` date gets
stamped. Known limits, all reported as BLOCKED or NO-TEXT rather than as failures:

- **fema.gov** rejects every scripted fetch (urllib and curl alike, full browser headers included) —
  verify by hand.
- **nfpa.org** returns a ~40-character JS shell to any script; status is meaningful, content is not.
- **PDF sources** serve 200 with no extractable text by this route.

## Known gaps

- IRC citations point at ICC's online code pages; jurisdictions amend values — the corpus says so.
- **19 of 36 sources have no `verify_keywords`** and cannot be content-checked by script: the 8 NFPA
  sources (JS shell), 2 FEMA (bot-walled), 2 PDFs, and the remaining fire sources, which S11.1 did not
  reach. Last full run 2026-09-21: **36 checked, 0 hard failures, 17 content-verified**.
- No fire-extinguisher *product* guidance or escape-ladder guidance; the extinguisher **decision rule** is
  covered by `usfa-extinguishers`.
- Earthquake guidance leans on Californian sources (ShakeOut, CA statute). A user elsewhere gets sound
  general practice, but the legal mandate section is explicitly labelled California-only.
