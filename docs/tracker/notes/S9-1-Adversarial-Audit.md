# Adversarial Audit of S9.1

## Findings

### 1. AABB Area Calculation Failure (CRITICAL)
- **What is wrong:** The `SemanticMatcher` filters candidate rooms by `areaDiff < 0.20`. However, the live area is calculated using the Axis-Aligned Bounding Box (AABB) in the `CapturedRoom` extension (`(maxX - minX) * (maxZ - minZ)`).
- **Why it matters:** The AR session's coordinate axes are arbitrary and depend purely on the user's phone orientation at the start of the scan. If a user starts a scan standing at a 45-degree angle to the room's walls, the AABB area will be up to 2x larger than the true area of the room. The 20% tolerance check will unconditionally reject the correct room, causing total relocalization failure in the real world.
- **Location:** `SemanticMatcher.swift` (lines 147-164).
- **Recommended fix:** Extract the length and depth by aligning the walls to the `longestWall`'s direction before calculating the bounding box, OR sum the lengths of the walls to compare perimeter instead of AABB area.
- **Blocks next session:** Yes. This must be fixed before wiring up the UI, or real-world testing will fail instantly.

### 2. Double Negative Rotation Math (HIGH)
- **What is wrong:** The `simd_float4x4(rotationY:)` extension implements a clockwise rotation matrix. The `match` function calls it with `rotationY(-ang)`.
- **Why it matters:** Two sign errors canceled out, making the unit tests pass perfectly by sheer luck. However, the `rotationY` extension is mathematically incorrect for ARKit's standard right-handed coordinate system and will break any future 3D math that relies on it.
- **Location:** `SemanticMatcher.swift` (lines 102 and 172).
- **Recommended fix:** Fix the rotation matrix to standard right-handed `[cos, 0, sin], [0, 1, 0], [-sin, 0, cos]` and pass `+ang`.
- **Blocks next session:** No, but should be fixed immediately to prevent technical debt.

### 3. No-Door Ambiguity Resolution Failure (HIGH)
- **What is wrong:** If a room has no doors (or the LiDAR scan missed them), the score for both 0° and 180° rotations will be exactly `0`. The ambiguity check uses `!ambiguousIds.contains(e.roomId)`, meaning the room is appended to `ambiguousIds` only once.
- **Why it matters:** The engine will confidently return the 0° rotation without flagging the 180° ambiguity. This gives a 50% chance of mapping the user backwards in AR space without the UI ever knowing it needs to ask for clarification.
- **Location:** `SemanticMatcher.swift` (lines 129-139).
- **Recommended fix:** Change the ambiguity check to look at the number of *evaluations* that are close to the best score, rather than unique room IDs, or explicitly return `ambiguous` if the top two scores for the *same* room are identical.
- **Blocks next session:** No, but should be fixed before S9.3.

### 4. Longest Wall Extraction Brittleness (MEDIUM)
- **What is wrong:** The live scan extracts the longest wall by iterating over `walls` and picking `max(by: dimensions.x)`.
- **Why it matters:** Apple's `RoomPlan` frequently splits long, continuous walls into multiple segments if interrupted by doors, windows, or furniture. A 10m wall broken into three 3m segments will lose to an unbroken 4m perpendicular wall, causing a permanent 90-degree alignment failure.
- **Location:** `SemanticMatcher.swift` (line 186).
- **Recommended fix:** Group walls by their normal vectors (within a tolerance) and sum their lengths to find the dominant axis.
- **Blocks next session:** No.

## Summary Status
- **A. Completed:** Basic matching structure, `LiveRoomExtractable` testability, and 180-degree door ambiguity resolution (when doors exist).
- **B. Incomplete:** Robust area and longest-wall extraction that handles real-world `RoomPlan` quirks.
- **C. Broken:** Area comparison fails for rotated coordinate spaces.
- **E. Immediate Fixes:** The AABB area calculation and rotation matrix sign must be fixed before the UI is built.
