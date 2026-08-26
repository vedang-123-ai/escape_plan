# S2.3/revamp — surface `narrows_route` as a RouteFinding

- **Who:** P3
- **Date(s):** 2026-08-25
- **Status when I stopped:** Done. Emitted, decoded, styled, narrated, checklisted, tested.
  Backend 295 → 310, iOS unit suite +3, EditorCore unchanged at 270.

## What happened

The TODO line said "`obstructions.py` computes it and nothing shows it", which reads like a
missing UI case. It wasn't. **The finding was never computed on a request that could have
carried it.** `engine.py` gated the whole obstruction analysis behind
`if graph.blocked_openings`, and a narrowing is a doorway that is still *reachable* — so it is
never in `blocked_openings`, so the analysis that would have produced it never ran. The code
had been computing and discarding this since the B3 revamp.

Fix is three lines of gate plus an emission loop:

- `plan.py` — `narrows_route` added to the `RouteFinding` Literal.
- `engine.py` — gate widened to `graph.blocked_openings or any(floor.objects ...)`, and a
  per-room emission loop after the blockage loop. The performance intent the old gate was
  protecting survives: `analyze_obstructions` already skips rooms with no objects, so a
  furniture-free home costs nothing. Pinned by `test_furniture_free_homes_gain_no_findings`.
- Swift: `case narrows_route` in `FindingKind`, a `RouteFindingStyle` ("Tight squeeze"), a
  `RouteNarration` sentence.

New fixture `schema/fixtures/bungalow-narrow.json` — the blocked bungalow with the wardrobe
pulled back until the door is reachable but tight (0.90 m measured against a 1.11 m comfort
width). A separate file from `bungalow-blocked.json` on purpose: the two kinds are
distinguished by whether a path exists at all, so one fixture cannot exercise both.

## Decisions / surprises

**Two latent bugs fell out of surfacing it. Both would have shipped.**

1. `route_items` in `checklist.py` ended in an `else` that titles anything unrecognised
   "<room> has no usable way out". A squeeze would have been presented as a dead end — a
   graver claim than the engine made, on a doorway that works, with no citation supporting
   it. I verified the trap is real by deleting my branch and watching the test fail with
   `'no usable way out' not in 'Bedroom has...able way out'`, then restored it.
2. `Obstruction.detail` printed "squeezes to 0.90 m — under the 0.81 m a door needs".
   0.90 is not under 0.81. Narrowings are judged against the *comfort* width (code +
   `COMFORT_MARGIN_M` per side = 1.11 m) but the sentence quoted the code width, and
   `suggested_move_m` was measured against it too, so it floored at a meaningless 0.05 m.

For (2) I added `target_width_m` rather than redefining `required_width_m`. Folding the
comfort width into the existing field was the smaller diff and is wrong: the margin is our
judgement, not a code threshold, and any citation attached to it would then be false.
`required_width_m` stays the citable IRC R311.2 number. The agent's `check_obstructions` tool
was being handed the same contradiction and now gets both fields.

**Deliberately NOT done:** a third, milder badge colour. A squeeze currently looks exactly as
grave as "no second way out". That is arguably wrong, but START-HERE forbids new colours and
the White Model overhaul exists to undo exactly this kind of proliferation. Filed in TODO.md
as a UI/UX-pass call instead of decided unilaterally.

**Also updated:** `RoutePlanDecodeErrorTests` used `narrows_route` as its example of an
*unknown* kind. That test would have silently stopped testing anything, so it now uses a kind
the engine genuinely does not emit, with a comment saying it must stay that way.

## Questions for teammates

- **@P1** — the third-tint question above is yours. Same tint, or a milder advisory colour?
- **@P1/@P2** — the contract test still open two lines below this one in TODO.md (diff the
  backend `Literal`s against the Swift cases automatically) would have caught this whole
  class. This is the second time a kind and its client drifted.

## Next steps

Nothing blocking. Whoever picks up the UI/UX pass should decide the tint, and can see the
finding live with:

```bash
cd backend && ./.venv/bin/python -m app.routing plan ../schema/fixtures/bungalow-narrow.json --pretty
```
