---
description: The Foundation-only EditorCore SwiftPM package and the files symlinked into it
globs: ["tools/editorcore/**", "escape_plan/Editor/Core/**", "escape_plan/Auth/**", "escape_plan/Sync/**", "escape_plan/Drill/SemanticMatcher.swift"]
alwaysApply: false
---

# EditorCore rules (tools/editorcore and what is symlinked into it)

`tools/editorcore` is a Foundation-only SwiftPM package that lets `swift test` run on a machine with no simulator.
Several app directories are symlinked into it, so their code is compiled and tested twice: by the app and by the
package. The package is the fastest real test signal on this project.

- **Symlinked in:** `Editor/Core/` (including `CameraRigModel`), `Auth/`, `Sync/`, `Drill/SemanticMatcher.swift`, and the
  test folder `escape_planTests/EditorCore/` (`Tests/EditorCoreTests/Shared`). Check `ls -la tools/editorcore/Sources/EditorCore`.
- **No SwiftUI, UIKit, SceneKit or ARKit import** in any symlinked source file. It builds in the app but fails the package,
  and silently removes test coverage. Keep pure logic in these files and platform code in `Screens/` or `Renderer/`.
- **Tests compile for both targets.** Shared tests use `#if SWIFT_PACKAGE @testable import EditorCore #else @testable
  import escape_plan #endif`. A test-only helper defined in a shared test file (for example `MockLiveRoom`) must satisfy
  every protocol requirement in both builds, so changing a protocol in a symlinked file breaks the package build.
- Run it after any change here: `swift test --package-path tools/editorcore`. It takes seconds and is the right place
  for new pure logic (freshness rules, snapshot builders, matcher geometry).
- A known-answer test beats a self-consistent one. A 90 degree rotation test cannot tell the direction apart when the
  matcher also tries angle + 180; use a non-right angle (see `SemanticMatcherRotTests`).
