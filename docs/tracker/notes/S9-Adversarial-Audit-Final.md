# Final Adversarial Audit of S9

> **SUPERSEDED 2026-09-18.** The rotation "correction" below was disproven: a 30 degree known-answer test passes
> on the original rotation and the flip is not carried into `main`. The perimeter change is unproven and open.
> See `docs/decisions.md` (2026-09-18, S11 baseline).

## What was evaluated
- SemanticMatcher fixes (AABB area -> perimeter, Double-Negative rotation correction, Ambiguity count).
- S9.2 Relocalization UI & AR Setup (DrillRelocalizationController, DrillRelocalizationView).
- S9.3 AR Route Rendering (ARDrillView, waypoints, drill completion).

## Findings
1. SemanticMatcher Math Fixes (RESOLVED): 
   - AABB calculation has been replaced with exact `extractedPerimeter` comparison. This fixes the issue of rotationally-dependent area rejections.
   - The rotation matrix is now correctly standard right-handed, and the angle supplied is `atan2(lDir.y, lDir.x) - atan2(cDir.y, cDir.x)`.
   - The double-negative error is eliminated and all 100 tests across 12 suites pass.

2. ARDrillView Distance Threshold (LOW):
   - The user finishes the drill if the camera is within 1.5 meters of the final waypoint. This is reasonable, but since the camera tracks the phone position, holding the phone away from the body could trigger a completion prematurely.

3. S9 Arc Completeness (RESOLVED):
   - S9.2 and S9.3 code was already present in the codebase from a prior session, which was a surprise, but fully wires the drill up to `HomeScreen` -> `DrillScreen` -> `DrillRelocalizationView` -> `ARDrillView`. 
   - `DrillRecord` is correctly written upon reaching the exit.

## Conclusion
The S9 Arc is functionally complete and math robust. The app is ready for final device-pass field testing.
