import XCTest
@testable import escape_plan

final class BackendConfigTests: XCTestCase {

    func testAbsentConfigReturnsUnconfigured() {
        // In clean test environment or clean Release build without BackendConfig.local.json
        let config = BackendConfig.load(from: Bundle(for: Self.self))
        XCTAssertFalse(config.isConfigured)
        XCTAssertNil(config.bearerToken)
        XCTAssertEqual(config.statusDescription, BackendConfig.unconfiguredMessage)
    }

    func testConfigWithTokenIsConfigured() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let jsonPayload = """
        {
            "bearer_token": "test-mock-token-xyz",
            "base_url": "https://example.com"
        }
        """
        let fileURL = tempDir.appendingPathComponent("BackendConfig.local.json")
        try jsonPayload.write(to: fileURL, atomically: true, encoding: .utf8)

        // Create a bundle pointing to tempDir
        guard let bundle = Bundle(url: tempDir) else {
            XCTFail("Failed to initialize test bundle")
            return
        }

        let config = BackendConfig.load(from: bundle)
        XCTAssertTrue(config.isConfigured)
        XCTAssertEqual(config.bearerToken, "test-mock-token-xyz")
        XCTAssertEqual(config.baseURL, URL(string: "https://example.com"))
        XCTAssertEqual(config.statusDescription, "Backend configured.")
    }

    func testConfigWithEmptyTokenIsUnconfigured() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let jsonPayload = """
        {
            "bearer_token": "   "
        }
        """
        let fileURL = tempDir.appendingPathComponent("BackendConfig.local.json")
        try jsonPayload.write(to: fileURL, atomically: true, encoding: .utf8)

        guard let bundle = Bundle(url: tempDir) else {
            XCTFail("Failed to initialize test bundle")
            return
        }

        let config = BackendConfig.load(from: bundle)
        XCTAssertFalse(config.isConfigured)
        XCTAssertEqual(config.statusDescription, BackendConfig.unconfiguredMessage)
    }
}
