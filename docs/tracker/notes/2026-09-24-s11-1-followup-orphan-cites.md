# S11.1 follow-up — orphan cites (usgs-earthquake, aftershock card, spec §2)

- **Who:** agent run for the orchestrator (branch `s11-1-followup-orphan-cites`)
- **Date(s):** 2026-09-24
- **Status when I stopped:** spec §2 corrected; validate.py exception text corrected; the aftershock card
  re-point and the `usgs-earthquake` deletion were **deliberately not done**, because the card's copy is not
  supported as worded. Logged in BLOCKERS §S11.1 (follow-up block) and decisions.md 2026-09-24.

## What happened
- Checked the planned swap on `escape_plan/DrillMode/DrillInstructions.swift:74` (`.aftershockEvacuate`) to
  `[cite: shakeout-guidance-after]`. The id exists and `earthquake-after-shaking.md` supports "evaluate your
  surroundings" and "be cautious of aftershocks". It does **not** support "evacuate only if the building is
  damaged **or if you are instructed to do so**": ShakeOut Step 6 says "or the surrounding area is unsafe".
  Re-read the live ShakeOut and Ready.gov pages; neither has an "instructed" condition. Stopped, per the
  brief's rule: no cite change, no rewording.
- So `usgs-earthquake` still has one caller (exact-id grep of backend/, escape_plan/, escape_planTests/,
  schema/, tools/, scripts/). It stays in `sources.json` and `ORPHAN_SOURCE_EXCEPTIONS`; the exception's
  stale owner text (named `checklist.py`/S11.2) now names the one caller, why it is blocked, and S11.10.
- No Swift test pins those cite strings (`DrillModeTests` only checks they resolve), so none changed.
- `docs/object-hazard-spec.md` §2: added a dated correction — the corpus has covered cords, outlets, space
  heaters, cooking and dryers since `2bf41c4` (2026-09-09) via `heating-electrical-fire-safety.md`.
  R1 lines 123-130 were already corrected on 2026-09-22; left alone.
- Verified the S11.2/S11.3 parts of the S11.1 HIGH item are really fixed (grep of the code and tests).

## Decisions / surprises
- Surprise: `ready.gov/earthquakes` **does** say to expect aftershocks, contrary to the BLOCKERS premise
  "neither page mentions aftershocks". The corpus records no after-shaking claim from it, so it still is
  not citable for this card.
- Surprise: R3 (`heat_clearance`) measures RoomPlan stoves and ovens against the 0.9 m heating-equipment
  rule and calls them "the heater". The corpus gives that rule for heating equipment only. Logged for S11.3.

## Questions for teammates
- @owner / S11.10: OK to change the card to "...if the building is damaged or the area around it is unsafe"?
  That is the source's condition; then the tag and the source deletion can land in one commit.

## Next steps
- S11.10: fix the copy + cite together, delete `usgs-earthquake` and its exception entry, re-run validate.py.
- Tick the S11.4-section BLOCKERS line "object-hazard-spec.md §2 is stale" (same item, now fixed here).

Gate run 2026-09-24 on this branch: validate.py green (36 sources, 1 orphan exception); backend 788 passed,
1 skipped, 26 deselected; EditorCore 598 tests, 0 failures; `typecheck-ios.sh` ok on all four targets
(type-check only, not a test run). No `xcodebuild test` run.
