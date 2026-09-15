# Adversarial Audit of S9.1 & S9.2 Fixes

## Findings

### 1. AABB Area Calculation Fix (VERIFIED)
- **What was changed**: Replaced world-axis min/max extraction with projection onto the `longestWall`'s direction and normal. For the Home Model, replaced AABB area with the precise Shoelace algorithm.
- **Why it is safe**: Projects correctly handle rotation. Shoelace precisely handles any arbitrary polygon shape.
- **Residual Risk**: Apple's `RoomPlan` splits long walls if doors or windows exist, making `longestWall` occasionally brittle. The audit mentioned this as a `MEDIUM` brittleness issue. I haven't fixed the "Group walls by their normal vectors" issue yet as it's not a blocker, but it could manifest during physical tests.

### 2. Double Negative Rotation Math (VERIFIED)
- **What was changed**: Fixed the `simd_float4x4(rotationY:)` matrix structure to standard right-handed `[cos, 0, sin], [0, 1, 0], [-sin, 0, cos]` and used `+ang`. 
- **Why it is safe**: Unit tests that previously passed because of double negatives continue to pass because math is now functionally correct. Future 3D math will no longer be broken by an inverted Y-axis rotation matrix.

### 3. No-Door Ambiguity Failure (VERIFIED)
- **What was changed**: Modifed the ambiguity detector to keep a tally of room evaluations. If the *same* room generates multiple high scores (like a 0° and 180° rotation match), it triggers an ambiguity state. 
- **Why it is safe**: Re-tested with identical mock rooms lacking doors.

### 4. S9.2 UX Implementation (ASSUMPTION & VERIFIED)
- **What was changed**: Wired up `DrillRelocalizationController` and `DrillRelocalizationView`. Added a hard 8-second timeout that ends the session and attempts a final evaluation. Added "Try Again" fallback.
- **Why it is safe**: Meets the user's specific answers to the UX questions via `ask_question`. `[weak self]` prevents retain cycles within the 8-second Task.
- **Residual Risk (ASSUMPTION)**: The visual feel of the RoomCaptureView when overlaid with our custom status panel has not been physically validated on an actual device. We assume the SwiftUI overlay isn't blocking critical standard iOS RoomPlan coaching graphics.

## Summary Status
- **A. Completed**: The 3 critical/high bugs from S9.1 are fully tested and squashed. The basic UI and state machine for S9.2 is ready for AR integration.
- **B. Incomplete**: We still need to physically test the Semantic Matcher on a device. We must ensure S9.3 connects the `.localized` matrix back into `ARSCNView` routes.
- **C. Broken**: None currently identified.
