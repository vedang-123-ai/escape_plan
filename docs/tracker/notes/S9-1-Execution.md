# S9.1 — Semantic Relocalization Engine Execution

- **Who:** P1
- **Date(s):** 2026-09-14
- **Status when I stopped:** SemanticMatcher engine built and unit tested.

## What happened
Implemented the `SemanticMatcher` engine to calculate the coordinate transformation matrix aligning an AR `CapturedRoom` scan with a stored `HomeModel`.
Created the algorithm to match dimensions, center alignment, rotate to align longest walls, and finally resolve 180-degree rotation ambiguity using door positions.
Abstracted feature extraction via `LiveRoomExtractable` protocol to allow mocking since `CapturedRoom` is hard to synthesize without real scan data. Tests for perfect match, 180-degree ambiguity, and ambiguous duplicate rooms pass.

## Decisions / surprises
* Decision: Handled ambiguity explicitly by returning an `ambiguous(candidateRoomIds:)` state if multiple rooms share nearly identical dimensions and door positions.
* Surprise: Apple's `RoomPlan` properties on `CapturedRoom.Surface` require carefully parsing `transform.columns` vectors instead of having a direct `normal` property.

## Questions for teammates
None at this time.

## Next steps
S9.2 — Relocalization UI & AR Setup. Start wiring the engine output up to the UI so we can display visual cues in the camera view!
