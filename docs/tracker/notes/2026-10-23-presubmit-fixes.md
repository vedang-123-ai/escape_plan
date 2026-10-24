# Pre-submission fixes — live chat with a labelled sample, object hazards in /score, Build-it-myself back button

- **Who:** P3 (vedang), with Claude Code
- **Date(s):** 2026-10-23
- **Status when I stopped:** three fixes merged; gate green except the iOS app suite, which was not run.

## What happened
- Pulled `origin/main` (already current), reread the BLOCKERS board and the 2026-10-11 audit roadmap, and checked each
  must-fix item in the code. Already fixed on `main`: A14-01, A10-03, X-01, X-02, X-03, A12-02, A15-01, A17-02/03.
- Found that `f9b1c9b` ("ai chat improvement") replaced the `/chat` call with a fixed four-turn script for every
  home. Restored the live call; the script is now a labelled fallback for Anish's House only.
- Found that `/score` never passed the object-hazard thresholds, so `hazard.*` items never reached the app. Wired it,
  added `test_score_endpoint_reports_object_hazards` (fails without the fix), pinned Two-Story's endpoint score at 40.
- A02-01/02: Home's "Build it myself" pushed a `HouseScreen` that had its own `NavigationStack`. Added
  `embedsNavigationStack`.
- Preflight: the token in this Mac's `BackendConfig.local.json` gets 401 from Render. Not touched (secret file).

## Decisions / surprises
- The sample chat is more grounded than it first looked: the wardrobe and water-heater findings and A* are real.
  Its fridge "3 ft from the range" line repeats the engine's own R3 rule (spec: stoves count as `heat_source`).
- Gate: backend 1293 passed / 1 skipped / 31 deselected; EditorCore 660 passed; type-check ok on all four targets.

## Questions for teammates
- @Anish: did Superset run GitHub Copilot or another agent that wrote code? `tools-used.md` must list it.
- Does the filmed video show a score of 66 or 64? After the Render redeploy the demo homes show 40.

## Next steps
- Owner: fix the token, redeploy Render, rerun the preflight, and tap through "Build it myself" on a device.
