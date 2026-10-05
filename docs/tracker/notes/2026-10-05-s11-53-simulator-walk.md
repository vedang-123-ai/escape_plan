# S11.53 — simulator walk of the demo golden path

- **Who:** agent D (Claude), for Anish
- **Date(s):** 2026-10-05
- **Status when I stopped:** walk done and recorded; six findings in `BLOCKERS.md` under "S11.53 findings"; two new
  always-on UI tests; no app, backend, corpus or schema file changed.

## What happened

- Built `origin/main` `988fe94` (Debug, with the owner's gitignored `BackendConfig.local.json`) and drove it on the
  iPhone 17 Pro simulator with a UI-test walk driver that saves a screenshot and the accessibility tree per step:
  `escape_planUITests/SimulatorWalkUITests.swift`, skipped unless `TEST_RUNNER_WALK_OUT=<dir>` is passed.
- Live server: `/health` reports commit `988fe94` (= `origin/main`), first call 52 s (cold start).
  `scripts/demo-preflight.py`: all PASS except `/explain` 502, "ANTHROPIC_API_KEY is not configured on the server".
- What works and what does not, with screenshots: `BLOCKERS.md` "S11.53 findings", images in
  `docs/tracker/evidence/s11-53/`.
- Added `escape_planUITests/DeadServerUITests.swift`: the assistant and House against a dead server (closed loopback
  port) must say "offline" in words, offer Try again, and stay usable. Mutation-checked: pointed at the live server,
  both fail at their first offline assertion.

## Decisions / surprises

- A fresh install has four homes, and the first one a judge sees is "Jagged Stack", the floor-stacking test model.
- The selected home resets to the first home on every launch. Pick Two-Story House again after each relaunch while filming.
- Earthquake and tornado show up as scores and tasks only. The House screen draws fire routes only.
- The AI 502 on Render comes from a missing key, not only from the credits running out.

## Questions for teammates

- Anish: should the starter library drop Jagged Stack, and should the app remember the last home? (S53-1, S53-2)
- Anish: should there be a peril picker in House, or should the earthquake/tornado route claim be dropped? (S53-3)

## Next steps

- Lane D: S53-1, S53-2, S53-4, S53-5. Owner: set `ANTHROPIC_API_KEY` on Render plus credits (S53-6).
- Re-run the walk: `TEST_RUNNER_WALK_OUT=/tmp/walk xcodebuild test ... -only-testing:escape_planUITests/SimulatorWalkUITests`.
