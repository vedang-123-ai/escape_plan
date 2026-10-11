# Audit-review — review of the 2026-10-11 agent lanes

- **Who:** Anish (with Claude Code)
- **Date(s):** 2026-10-11
- **Status when I stopped:** all ten lanes reviewed, fixed and merged on `audit-review`; merged to `main`.

## What happened
Ten parallel agent lanes (backend, build, content, geometry, net, perf, persist, scoring, ui-a11y, qa) left uncommitted work. Kept what was correct, fixed what did not compile, removed dead or unsafe code:
- build: device-only `let` RoomPlan configuration fixed (device build was broken since 2026-09-10); camera-permission screen; privacy manifest. BackendConfig exclusion removed (would ship no token).
- backend: overlap made non-blocking for existing homes, but new overlaps still rejected (`HomeModelStore.newWarnings`), with a test that fails without it.
- persist: fixed four compile errors (Equatable, `.mismatch` pattern, MainActor, `.equipment`).
- net: `Audit_NetworkFallbackTests` nested under `OfflineIntegrityTests` so the global URLProtocol stub is serialized.
- content: PDF in-fire rules reworded to the corpus text. scoring: CO item and door tip deferred. ui-a11y: double "Selected", dead banner actions, dollhouse red fixed. qa/perf: dead tests and `renderAsync` removed.

Gate 2026-10-11: backend 1275 passed; EditorCore 660 passed; corpus valid (35 sources, 13 files, 44 tips); typecheck 4/4; Release device build succeeded; iOS unit run `unit3.xcresult` (see commit message for counts).

## Decisions / surprises
Three rows in `docs/decisions.md` (overlap policy, keep bundled token, CO deferral). Surprise: the simulator-only gate cannot catch device-only compile errors; CI now has a device-build step.

## Questions for teammates
None.

## Next steps
Deploy the backend to Render, install on the demo iPhone, warm the server, film.
