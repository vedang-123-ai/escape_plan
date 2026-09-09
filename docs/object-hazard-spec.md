# Object hazard detection — the spec

**Status: APPROVED 2026-09-08 by the owner. Governs the S7 arc (`docs/playbook/07-object-hazard-intro.md`).**
Written against the merged tree at `388cf37` (post-S6.9). Every "already exists" claim below was
re-verified on that tree, not copied from older notes.

This document is the rule book: what the feature claims, what it deliberately does not claim,
the exact deterministic rules with thresholds and citations, and where each rule's output
surfaces. Session prompts reference this file instead of restating it. If a session and this
spec disagree, this spec wins — fix the session file.

---

## 1. What this feature is

The app already builds a structured, metrically accurate 3D model of the home and computes
deterministic escape routes and shelter choices on it. Object hazard detection extends the same
engine to the *contents* of the home: furniture and equipment that can block an escape, fall on
someone in an earthquake, or start/feed a fire.

Three sources feed the object layer:

1. **The LiDAR scan.** RoomPlan already classifies ~16 categories of household object (beds,
   sofas, tables, storage, stoves, ovens, fireplaces, televisions, refrigerators…) with full 3D
   oriented bounding boxes. The app captures these today and throws them away —
   `apple-raw.json` on device contains them; the wire format and `/convert` drop them. S7.3
   stops the throwing-away.
2. **The hazard hunt.** A guided, skippable, room-by-room editor flow where the user tags the
   things no scan can see: the space heater, the water heater in the garage, the mirror over
   the bed, whether the bookcase is strapped. Zero network calls.
3. **Vision photo-assist (optional arc tail).** On-device Vision classification *suggests* tags
   from a photo; the user confirms every one. Suggestions never become model objects on their
   own.

On top of that data, a deterministic rules engine (§4) measures each object against
corpus-cited thresholds and emits findings that carry **a number, a threshold, a citation, and
an action** — every finding, no exceptions.

## 2. The honesty section — read before pitching or extending this

**"Can't the user just see the bookcase?"** Yes. They cannot see that it is an unsecured 1.9 m
bookcase whose topple arc covers the pillow end of the bed, or that the hallway squeezes to
0.62 m against the 0.813 m the IRC requires of an egress door, or that the heater sits 0.4 m
from the sofa against NFPA's 0.9 m rule. The feature's value is *measurement and judgment
against codified standards*, not perception. Consequently: an output like "there is a sofa in
your living room" is banned. If a rule cannot state a measured value, the threshold it
violates, and a cited reason someone should care, the rule does not ship.

**RoomPlan will never see a backpack, a power strip, or a tower fan.** Do not promise
"clutter detection." Transient clutter is handled three ways, honestly: (a) the recurring
"keep exits clear" checklist mechanics that already exist (`recurrence_days`); (b) the hazard
hunt, for semi-permanent items the user can tag; (c) as stretch, S7.8's exit-path re-check —
a fresh partial scan diffed against the stored model, which detects that *something new* is in
the corridor without pretending to know what it is.

**A scan is a moment in time.** `meta.last_scanned` and the rescan nudge exist (schema 2.0).
Object findings inherit that caveat and never claim to describe the home *now*.

**No corpus source → no rule.** Electrical/ignition guidance has zero corpus coverage today
(verified by grep: nothing on cords, outlets, heaters, cooking clearance). S7.2 adds real,
named sources before S7.4 writes the rule that cites them. This ordering is a hard dependency,
not a preference.

**The geometry prioritizes; it never excuses.** ShakeOut says secure tall/heavy furniture,
full stop. The topple rule (R1) tells you *which* item to strap first because its arc reaches
your bed — but an unsecured wardrobe far from everything still gets the generic
`mitigation.secure.<id>` item that ships today. Distance from a bed is never presented as a
reason not to secure.

**No custom ML.** Considered and rejected for this product cycle: training or embedding a
custom detector for small objects. Accuracy failures in a safety app are worse than absence,
and the deadline is Oct 24. The optional Vision sessions use only Apple's built-in on-device
classifiers, as suggestions requiring confirmation.

## 3. Data model (schema 2.1 — S7.1)

`FloorObject` today: `id`, `category` (7 values; read by the renderer, by `mitigation_items`'
heavy-categories filter, and by the S6.3 earthquake cover search — no hazard semantics beyond
those two filters), `center` [x,y], `size_m`
[w,d], `height_m` (prism height from the floor), `rotation_deg`, `source`, `confidence`,
`secured` (default false; exactly one reader today: `checklist.mitigation_items`).

2.1 adds, all optional/defaulted so every 2.0 document remains valid:

| Field | Type | Meaning |
|---|---|---|
| `elevation_m` | number ≥ 0, default 0 | Height of the object's *base* above the floor. 0 = floor-standing (today's implicit value). A wall-mounted TV or shelf gets its real base height — RoomPlan's bounding box carries it; the converter maps it. |
| `mounted` | boolean, default false | Attached to a wall/ceiling rather than resting on something. Distinct from `secured` (anti-topple strapping of a floor-standing object). |
| `category` additions | enum | `bookcase`, `tv`, `water_heater`, `heat_source` (fixed stove/oven/fireplace and portable heaters alike). Existing seven values unchanged. |

Rules for the bump: `schema_version` becomes `"2.1"`; migrators accept 1.0/1.1/2.0; JSON
Schema, pydantic, and Swift Codable move in lockstep with the round-trip test; Swift's
exhaustive `FurnitureFixture` switch must gain arms for the new categories in the *same*
session (placeholder geometry is fine; S7.6 makes it good) or the app stops compiling.

## 4. The rules

Two kinds of constants appear below. **Cited thresholds** come from the corpus
(`egress_thresholds.json`, and S7.2's new `object_hazard_thresholds.json`) and are never
hardcoded in engine code. **ENGINEERING CONSTANTs** are our own geometric judgment calls —
labeled as such in code and docs, tunable, and never presented to the user as a safety
standard.

Severity vocabulary is the existing one: `high` caps the composite score while unresolved
(S6.7 behavior); `info` does not.

### R1 — `topple` (earthquake)

- **Trigger.** `secured == false` and `elevation_m == 0` and the object is topple-prone:
  `category ∈ {wardrobe, bookcase, storage, water_heater}` OR
  (`height_m ≥ 1.2` and `height_m / min(size_m) ≥ 2.0`) — both ENGINEERING CONSTANTs, stored
  in `object_hazard_thresholds.json` under an `engineering_constants` key so they are tunable
  without touching engine code. `appliance` is *not* in the always-topple set (a dishwasher is
  not a wardrobe); slender appliances still qualify via the ratio test.
- **Target zones.** The topple band: the object's footprint extended outward by `height_m` on
  each face (a falling cabinet sweeps roughly its own height). Hazard fires when the band
  intersects (a) a `bed` or `sofa` footprint in the same room, (b) the approach disc of any
  door on the room's computed escape route, or (c) — when route data is available to the
  caller — the route corridor itself.
- **Severity.** `high` when the band reaches a bed or the room's *only* egress approach;
  `info` otherwise.
- **Cites.** `shakeout-guidance` (secure tall/heavy furniture; drywall anchors insufficient;
  renter options), `usgs-earthquake` (falling objects are the most common earthquake injury).
- **Detail sentence pattern.** "The bookcase (1.9 m tall, unsecured) can reach the bed 1.1 m
  away if it topples. Strap it to wall studs — adhesive strap kits work for renters."
- **`secured == true` suppresses R1 entirely.**

### R2 — `overhead` (earthquake)

- **Trigger.** `elevation_m ≥ 0.9` (ENGINEERING CONSTANT — above a lying person) and the
  object's footprint, projected straight down, intersects a `bed` or `sofa` footprint.
- **Severity.** `high` over a bed; `info` over seating. `mounted == true` *with*
  `secured == true` downgrades to `info` (properly anchored, but contents/glass can still
  fall — the sentence says so).
- **Cites.** `shakeout-guidance` ("Heavy items should be moved to bottom shelves or placed far
  away from beds and seating areas").
- **Detail pattern.** "The shelf mounted 1.6 m up overlaps the head of the bed. Move heavy
  items to lower shelves or relocate them away from where people sleep."

### R3 — `heat_clearance` (fire)

- **Trigger.** A `heat_source` object with any *other* object whose horizontal footprint
  distance is under the cited clearance (0.9 m / 3 ft — NFPA portable-heater rule, from
  S7.2's new corpus source). Only movable objects trigger it; walls and counters do not
  (RoomPlan doesn't model counters, and telling someone to move their kitchen wall is noise).
- **Severity.** `high` when the encroaching object is a `bed` or `sofa` (bedding and
  upholstery are the classic heater-fire fuels — cited); `info` otherwise.
- **Cites.** S7.2's heating-fire source (NFPA/USFA). No rule text ships until that source is
  in `sources.json`.
- **Detail pattern.** "The sofa sits 0.4 m from the heater — under the 0.9 m (3 ft)
  clearance NFPA recommends. Move it at least 0.5 m farther away."

### R4 — egress-window blockage (fire) — extends the existing obstruction engine

- **What changes.** `analyze_obstructions` today probes only door approaches. R4 widens it to
  egress-qualifying windows (the qualification logic exists: sill ≤ 1.118 m and R310
  dimensions, from `egress_thresholds.json`). Same grid-reachability probe, same
  counterfactual culprit attribution, same `suggested_move_m`.
- **Output.** The *existing* kinds — `blocked_opening` / `narrows_route` — with the window's
  `opening_id`. No new `FindingKind`: iOS already decodes, styles, and narrates both. The
  narration/detail sentences must not say "door" for a window; audit
  `Obstruction.detail`, `RouteNarration.findingSentence`, and `route_items` wording.
- **Severity.** Existing agent mapping already treats a sleeping room's only egress as high.
- **Cites.** `irc-2021-r310` (what makes the window an egress path), `usfa-escape-plans` /
  `redcross-escape-plan` (keep escape paths clear).

### R5 — `water_heater_unsecured` (earthquake → fire)

- **Trigger.** `category == water_heater` and `secured == false`. No geometry.
- **Severity.** `high`.
- **Cites.** `fema-earthquake` (already in corpus: strap to wall studs; tipping ruptures gas
  lines).
- **Detail pattern.** "The water heater isn't strapped. An earthquake can tip it and rupture
  the gas line — strap it to wall studs at the top and bottom."

### R6 — exit-path obstruction (fire) — already shipped, documented here as part of the feature

`blocks_opening` / `narrows_route` with counterfactual attribution and measured
`suggested_move_m` landed pre-S7 (`backend/app/routing/obstructions.py`). S7 changes nothing
about it except R4's widening. It is listed so the demo and the docs describe one coherent
feature, not two.

### Deliberately not rules (and why)

- **Cord/outlet/overload detection** — nothing can sense it; the hazard hunt asks instead,
  and the checklist carries the cited reminder.
- **"Clutter" as a category** — unmeasurable, unfalsifiable, patronizing. The recurring
  keep-exits-clear item plus S7.8's re-scan diff are the honest versions.
- **Glass/window proximity to tornado shelter** — the S6.3 shelter search already scores
  exterior openings; double-counting via objects adds noise.
- **Chairs, sinks, toilets, bathtubs, stairs (RoomPlan categories)** — dropped at conversion.
  A chair is light and moves daily; fixtures can't move. Mapping them would flood the editor
  with objects nobody will curate.

## 5. Where outputs surface (S7.5)

**Contract cost is deliberately near zero.** No new `ItemCategory` (the existing `mitigation`
category — "secure your stuff" — is exactly what R1/R2/R3/R5 are). No new `FindingKind` (R4
reuses `blocked_opening`/`narrows_route`). The only contract change in the arc is schema 2.1
itself.

- **Checklist.** New generator `object_hazard_items(...)` in `scoring/checklist.py`, category
  `mitigation`, ids `hazard.<rule>.<obj_id>` (e.g. `hazard.topple.obj_wardrobe1`), per-peril
  `HazardTag`s, `scoring=False` (advisory — but `severity="high"` still caps the composite,
  which is S6.7's documented behavior and exactly what a high hazard should do).
  **Supersession:** when `hazard.topple.<id>` (or `hazard.water_heater_unsecured.<id>`)
  exists for an object, the generic strap-it item for the same object is suppressed — in BOTH
  its forms: `mitigation.secure.<id>` and the renter variant `mitigation.secure.<id>.renter`
  (`mitigation_items` emits one or the other by tenure). One object, one strap-it item, the
  specific one. A checkmark already recorded under either generic id carries forward to the
  specific item.
- **Route findings.** R4 flows through the existing engine path untouched.
- **Score.** No weight changes by default; S6.7's severity cap does the work. If S7.5 decides
  hazards should deduct points, that is a weights-doc + worked-examples change and is called
  out, not slipped in.
- **Agent.** New tool `check_object_hazards` mirroring `check_obstructions` exactly: returns
  the engine's fields verbatim, prompt forbids the model estimating any distance or severity
  itself, deterministic tests only (live tests remain credit-blocked).
- **3D view (S7.7).** Culprit objects get an advisory emphasis inside `Theme.swift`'s existing
  semantic scale — **no new colours, and route orange stays reserved for routes/exits**.
  Tapping a finding focuses the camera on the object (`highlightPlacement` pattern).

## 6. Detection-source matrix

| Rule | Scan (S7.3) | Hazard hunt (S7.6) | Vision assist (S7.9/10, optional) |
|---|---|---|---|
| R1 topple | wardrobes/storage/TVs from RoomPlan; `secured` always asked, never assumed | bookcase, anything scan missed; the secured toggle itself | suggests "bookcase" from photo |
| R2 overhead | mounted TVs (bbox elevation) | shelves, mirrors, art over beds | suggests "shelf/mirror" |
| R3 heat_clearance | stove/oven/fireplace → `heat_source` | space heaters (the big one — portable, invisible to scan) | suggests "space heater" |
| R4 window blockage | scan objects + existing model geometry | any manually placed object | — |
| R5 water heater | sometimes scanned as appliance; needs re-categorizing | usually tagged here (garage/closet) | suggests "water heater" |
| R6 exit paths | already works on any object | any object | — |

## 7. RoomPlan → schema category map (S7.3)

| RoomPlan | Schema 2.1 | Note |
|---|---|---|
| bed | `bed` | |
| sofa | `sofa` | |
| table | `table` | earthquake cover candidate (S6.3 logic unchanged) |
| storage | `storage` | wardrobe vs. bookcase indistinguishable to RoomPlan; slenderness test in R1 covers both |
| television | `tv` | wall-mounted gets real `elevation_m` from the bbox |
| stove, oven, fireplace | `heat_source` | |
| refrigerator, dishwasher, washerDryer | `appliance` | |
| chair, sink, toilet, bathtub, stairs | *dropped* | see §4 "deliberately not rules" |

Confidence maps through the existing `high/medium/low → 0.9/0.6/0.3`. Low-confidence objects
are **flagged for editor review, never silently dropped** — that invariant is schema law and
applies to objects exactly as it does to walls.

## 8. Cut order (mirrors the charter)

S7.10 → S7.9 → S7.8 → S7.7's visual-emphasis half. Never cut S7.1–S7.5: the engine *is* the
feature. If only S7.1–S7.5 land, the product still gains every rule above, surfaced through
the checklist and score, on scan + fixture data.
