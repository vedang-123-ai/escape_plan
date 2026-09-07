# Household → checklist mappings (S6.4)

**Why this document exists:** The S6 readiness checklist is deterministic and reproducible. When household facts (tenure, existing equipment, profile tags) alter the checklist, they do so through fixed, corpus-backed rules. No model decides whether a renter gets a different item than an owner.

- Table implementation: `backend/app/scoring/checklist.py` — pure, total, no I/O.
- Item model: `ChecklistItem` with `hazard` and `recurrence_days` support.
- Grounding: every mapping below traces to a file in `backend/corpus/`. **No mapping exists without a corpus line justifying its inclusion.**

## Three kinds of mapping

| Kind | Effect on the checklist |
|---|---|
| **Variant text** | An item is rewritten to match the household's situation (e.g., renters vs. owners), citing the corresponding guidance. |
| **Pre-satisfaction** | An item is still emitted to show it was considered, but its `done` state is pre-set to `True` based on spatial artefacts or declared equipment. |
| **New items** | A specific profile or combination of facts generates an entirely new item (e.g., strobe alarms for the hearing impaired). |

The distinction matters. Pre-satisfaction (derive first, store only when you must) prevents the user from being nagged to "buy smoke alarms" when they've already declared having them, but keeps the item visible so they know the system recognizes their preparation.

## The table

| Household Fact / Tag | Checklist effect | Corpus justification |
|---|---|---|
| `tenure = "rent"` | Unsecured heavy objects (wardrobes, etc.) generate mitigation items specifying **flexible nylon straps with earthquake-rated adhesives**, rather than wall drilling. | "Renter-friendly furniture straps are available without drilling." (`shakeout-guidance`) |
| `tenure = "own"` | Unsecured heavy objects generate mitigation items specifying bolting to **wall studs**. | "Unsecured furniture is a leading cause of earthquake injuries." (`shakeout-guidance`) |
| `existing_equipment` containing `smoke_alarm` | All smoke alarm placement and maintenance items (bedroom, level, sleeping area) are emitted with `done=True`. | (Implementation choice for UI trust — respect declared equipment rather than nagging). |
| `hearing_impaired` profile tag | Emits a high-severity alerts item to install a **bed-shaker or strobe-light alarm**. (Note: produces *zero* routing constraints). | "Standard audible alarms may not wake a person who is deaf or hard of hearing." (`usfa-smoke-alarms`) |
| `mobility_limited` profile tag | Emits an item to **sleep near an accessible exit**. If their bedroom has `no_viable_route`, severity is elevated to `high`. | "Stairs and window egress are generally not usable for a wheelchair user." (`usfa-disabilities`) |
| `child` profile tag | Emits an item to **assign a specific adult** to assist the child during evacuation. | "Children may not wake independently; an assigned adult ensures they escape." (`nfpa-escape-planning`) |
| `pet` profile tag | Emits an item to **keep a leash/carrier near the exit**. Emphasizes that people escape first, and pets never alter routing. | "People escape first; pets drive phrasing, never route computation." (`redcross-escape-plan`) |

## Items deliberately NOT mapped

- `vision_impaired`: The corpus offers no specific, distinct safety task beyond general preparedness, so this tag remains a no-op on the checklist (just as it is on routing). We do not invent tasks.
- `elderly`: Their soft routing constraints (stair penalty) naturally yield different routes, but they require no distinct checklist item beyond what `mobility_limited` handles when explicitly declared.
- **CO Detectors / Extinguishers**: If declared in `existing_equipment`, they can be marked satisfied, but we do **not** emit "Buy a fire extinguisher" as a to-do item, because our primary NFPA/USFA escape guidance focuses on immediate egress, not firefighting.
