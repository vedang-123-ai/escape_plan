# S11.36 — Offline route cache keyed by peril, person and model

- **Who:** P1
- **Date(s):** 2026-10-03
- **Status when I stopped:** Done. Simulator tests passed, typechecks passed.

## What happened
- Replaced the simple `home_id` cache key with `RoutePlanKey(homeID, peril, profileID)` and added `HomeFingerprint` checking.
- Updated `HouseScreen` offline banner to explicitly name the peril and person.
- Updated `EscapePlanExporter` to strictly require household fire plans matching the exact home fingerprint.
- Rewrote caching logic and updated tests.
- Fixed an issue where `FixtureLoader.load` models change fingerprint upon being saved via `HomeDocumentStore`, by using the reloaded model in `EscapePlanExportTests` and `OfflineIntegrityTests`.

## Decisions / surprises
- DrillScreen no longer exists (demo trim 2). The route cache is now used only by `HouseScreen` dock, the fire simulation tab, and the printable plan. This was updated in `docs/decisions.md`.
- S11.23 changes to `ReadinessStore` are preserved (we made sure not to regress score scoping).
- New on-screen words added for Anish to review:
  - `"You're offline — showing your last saved \(peril) routes for " + (personName ?? "everyone") + " from " + savedAt.formatted(date: .abbreviated, time: .shortened) + "."`
  - `"No routes saved on this device match this home as it is now. The plan still prints, and says plainly that the routes are missing — it never invents one."`

## Questions for teammates
None.

## Next steps
- S11.38 (Settings share uses the active home, reports failures).
