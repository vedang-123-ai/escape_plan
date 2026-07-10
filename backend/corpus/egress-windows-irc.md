---
id: irc-2021-r310
org: ICC (International Code Council)
doc_title: 2021 International Residential Code, Section R310 — Emergency Escape and Rescue Openings
url: https://codes.iccsafe.org/s/IRC2021P2/chapter-3-building-planning/IRC2021P2-Pt03-Ch03-SecR310.1
retrieved: 2026-07-10
topics: [egress, windows, code-requirements, thresholds]
additional_source_ids: [irc-2021-r311]
---

# Emergency escape and rescue openings (2021 IRC §R310)

These are the code numbers behind `egress_thresholds.json` — the values the app's deterministic egress checker uses to decide whether a window can count as a viable escape route. All values from the 2021 International Residential Code [cite: irc-2021-r310].

> **Jurisdiction note:** the IRC is a model code. States and municipalities adopt different editions and amend values. These are the widely-adopted 2021 IRC baseline numbers; the app presents them as general guidance, not a substitute for the locally adopted code.

## Where an escape opening is required

Basements, habitable attics, and **every sleeping room** must have at least one operable emergency escape and rescue opening. [cite: irc-2021-r310]

## Dimensional requirements (R310.2)

| Requirement | Imperial (as codified) | Metric |
|---|---|---|
| Minimum net clear opening area | 5.7 sq ft | 0.530 m² |
| Minimum net clear opening area — grade-floor or below-grade opening | 5.0 sq ft | 0.465 m² |
| Minimum net clear opening height | 24 in | 610 mm |
| Minimum net clear opening width | 20 in | 508 mm |
| Maximum sill height above floor | 44 in | 1118 mm |

All from [cite: irc-2021-r310].

Important subtleties:

- **"Net clear opening" is the actual open, passable area** when the window is open — not the glass size or rough opening. A window can meet the 24"×20" minimums and still fail the 5.7 sq ft area requirement (24in × 20in ≈ 3.3 sq ft), so area must be checked independently of height/width. [cite: irc-2021-r310]
- The opening must be **operational from inside the room without keys, tools, or special knowledge**. [cite: irc-2021-r310]
- Bars, grilles, covers, or screens are allowed only if releasable/removable from the inside without tools or keys. [cite: irc-2021-r310]
- Below-grade openings (basement windows) require a window well with minimum dimensions; wells deeper than 44 in need a permanently affixed ladder or steps. [cite: irc-2021-r310]

## Egress doors (2021 IRC §R311, reference values)

At least one side-hinged egress door of **minimum 32 in clear width** and **minimum 78 in clear height** is required per dwelling. [cite: irc-2021-r311] The app treats any code-sized exterior door as a preferred exit over window egress.

## How the app uses these numbers (editorial note)

The routing engine (S1.1/S1.2) reads `egress_thresholds.json` and marks each window opening `egress.viable = true/false` with reasons (e.g. `sill_too_high`, `opening_too_small`). Non-viable windows are excluded from escape-route computation or labeled last-resort. The AI layer may cite this document when explaining *why* a window doesn't qualify, but viability itself is always computed deterministically.
