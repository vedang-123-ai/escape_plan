// swift-tools-version: 6.0
//
//  EditorCore — a TEST HARNESS, not a shipping module.
//
//  Why this exists: no iOS simulator runtime is installed on the CI/dev machine this lane runs
//  on, so `xcodebuild test` cannot execute a single test. The S2.1 editor core is deliberately
//  pure (Foundation only — no SceneKit, no SwiftUI), which means it compiles and tests fine as
//  a macOS package.
//
//  There is NO source duplication: `Sources/EditorCore/{Core,Generated}` and
//  `Tests/EditorCoreTests/Shared` are symlinks to the real files under `escape_plan/` and
//  `escape_planTests/`. The Xcode app target compiles those same files through its
//  fileSystemSynchronized groups. One source of truth, two runners:
//
//      swift test --package-path tools/editorcore     # runs here, today
//      xcodebuild test -scheme escape_plan …          # runs on P2's machine, with a simulator
//
//  The shared test files switch their import with `#if SWIFT_PACKAGE` (module is `EditorCore`
//  here, `escape_plan` in the app). See docs/decisions.md.

import PackageDescription

let package = Package(
    name: "EditorCore",
    platforms: [.macOS(.v14)],  // Observation (@Observable HomeModelStore/UndoStack) needs 14
    products: [
        .library(name: "EditorCore", targets: ["EditorCore"])
    ],
    targets: [
        .target(
            name: "EditorCore",
            path: "Sources/EditorCore",
            // `Fixtures` is a symlink to escape_plan/Fixtures — the SAME bytes the app bundles
            // (byte-equality with schema/fixtures is enforced by a backend test). `.process`
            // flattens the JSON into the bundle root, which is where the app's copy-resources
            // phase puts them too, so FixtureLoader's lookup is identical in both runners; the
            // loader switches `Bundle(for:)` → `Bundle.module` under SWIFT_PACKAGE.
            resources: [.process("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]  // matches the Xcode target's SWIFT_VERSION
        ),
        .testTarget(
            name: "EditorCoreTests",
            dependencies: ["EditorCore"],
            path: "Tests/EditorCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
