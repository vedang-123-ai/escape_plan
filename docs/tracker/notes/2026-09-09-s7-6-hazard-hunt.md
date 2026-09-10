# S7.6 — hazard hunt

- **Who:** P1
- **Date(s):** 2026-09-09
- **Status when I stopped:** Completed. Tests passing.

## What happened
- Added `setObjectSecured`, `setObjectMounted`, `setObjectElevation` to `EditAction` and `HomeModelStore`.
- Added missing `setOpeningWidth` stepper to the opening inspector UI.
- Updated object inspector with new toggles (`Strapped to the wall?`, `Mounted`) and steppers for size and height.
- Included `elevation` stepper that appears only when an object is marked as mounted.
- Updated `FurnitureFixture.swift` geometry in `DollhouseScene.swift` by offsetting the Y position based on `elevation_m`.
- Created a `HazardHuntView` inline within the dock for users to answer contextual questions per room (e.g. portable heater, tall objects, water heater).

## Decisions / surprises
- Put the hazard hunt entry point in `HouseScreen` under the Routes dock mode, as a top-level prompt rather than a forced modal, in line with the "not a modal ambush" requirement.
- Implemented `HazardHuntView` in its own file to iterate over rooms and inject `FloorObject` items into the store.
- Object size checks: `[width, depth]` is strictly enforced as > 0.
- `HomeModelStore` leverages the Observation framework so no `@ObservedObject` is needed. Used `select(_:)` to set active selection.
