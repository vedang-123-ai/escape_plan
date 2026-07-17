//  EditorCoreTestSupport.swift — shared plumbing for the S2.1 editor-core tests.
//
//  These test files are compiled by BOTH runners (see tools/editorcore/Package.swift):
//    - the SwiftPM harness, where the code under test is module `EditorCore`
//    - the Xcode escape_planTests target, where it is module `escape_plan`
//  SWIFT_PACKAGE is defined only by SwiftPM, which is what lets one file serve both.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

// MARK: - Fixtures

/// Loads the project-wide fixtures from `schema/fixtures/`.
///
/// They are read from the source tree rather than copied into a test bundle on purpose: the
/// fixtures are the single project-wide test bed (rules/paths/schema.md — "don't invent
/// parallel test homes"), and a bundle copy would silently go stale the moment P1 edits one.
enum Fixtures {

    /// Walks up from this file until it finds the directory holding `schema/fixtures`.
    /// Works from either runner, since both compile this file from a path inside the repo.
    static let repoRoot: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("schema/fixtures").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("could not locate schema/fixtures above \(#filePath)")
    }()

    static var directory: URL { repoRoot.appendingPathComponent("schema/fixtures") }

    /// The three valid test homes built in S0.2.
    static let validNames = ["bungalow", "apartment", "twostory"]

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func load(_ name: String) throws -> HomeModel {
        try HomeModel.decoder.decode(HomeModel.self, from: data(name))
    }

    /// Deliberately broken documents from `schema/fixtures/invalid/`.
    static func invalidNames() throws -> [String] {
        let dir = directory.appendingPathComponent("invalid")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
    }

    static func loadInvalid(_ file: String) throws -> HomeModel {
        let url = directory.appendingPathComponent("invalid").appendingPathComponent(file)
        return try HomeModel.decoder.decode(HomeModel.self, from: Data(contentsOf: url))
    }
}

// MARK: - Store helpers

extension HomeModelStore {

    /// A store with deterministic ids and clock, and snapping off — the default for tests that
    /// assert exact geometry. Tests that exercise snapping opt back in explicitly.
    static func testStore(_ model: HomeModel,
                          snap: SnapSettings = .disabled,
                          idPrefix: String = "gen") throws -> HomeModelStore {
        var counter = 0
        return try HomeModelStore(
            model: model,
            snapSettings: snap,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            makeId: {
                counter += 1
                return "\(idPrefix)_\(counter)"
            })
    }
}

// MARK: - Assertions

/// Asserts the store's central promise at any point in a test: whatever it holds, the backend
/// would accept.
func XCTAssertModelValid(_ model: HomeModel, _ message: String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    let issues = EditorValidation.validate(model)
    XCTAssertTrue(issues.isEmpty,
                  "\(message) — model is invalid:\n" + issues.map(\.description).joined(separator: "\n"),
                  file: file, line: line)
}

func XCTAssertRejected(_ outcome: HomeModelStore.Outcome, _ message: String = "",
                       file: StaticString = #filePath, line: UInt = #line) {
    if case .rejected = outcome { return }
    XCTFail("\(message) — expected rejection, got \(outcome)", file: file, line: line)
}

func XCTAssertApplied(_ outcome: HomeModelStore.Outcome, _ message: String = "",
                      file: StaticString = #filePath, line: UInt = #line) {
    if case .rejected(let issues) = outcome {
        XCTFail("\(message) — expected the action to apply, got rejection:\n"
                + issues.map(\.description).joined(separator: "\n"),
                file: file, line: line)
    }
}

func XCTAssertPointEqual(_ a: Point, _ b: Point, accuracy: Double = 1e-9,
                         _ message: String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.x, b.x, accuracy: accuracy, "\(message) (x)", file: file, line: line)
    XCTAssertEqual(a.y, b.y, accuracy: accuracy, "\(message) (y)", file: file, line: line)
}
