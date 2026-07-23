---
description: Swift/iOS conventions
globs: ["**/*.swift"]
alwaysApply: false
---

# Swift rules

- SwiftUI, iOS 17+ target (RoomPlan's merged multi-room CapturedStructure API needs it).
- Codable structs mirror `schema/homemodel.schema.json` exactly — field names, enums,
 optionality. A decode → encode → semantic-compare round-trip test on the fixtures is the
 gate for any model change.
- All model mutations flow through a single reducer-style `HomeModelStore` (undo/redo and
 autosave depend on this — don't mutate the model from views).
- Persistence is local JSON documents via FileManager, schema-versioned (`Persistence/`, one
  file per home). Core Data was removed wholesale in S0.3 — do not reintroduce it.
- SceneKit for the 3D dollhouse/editor; parametric wall-segment refs from the schema drive
 opening placement — never position doors/windows by absolute coordinates.
- Never embed API keys or backend tokens in source; base URL and bearer token come from
 configuration.
