//  BuildRequestEncodingTests.swift — the /build wire contract from the client side
//  (pattern: ChatRequestEncodingTests). The backend's BuildRequest forbids extra keys, so
//  the encoded shape matters; the response decode must tolerate the trace we don't model.

import XCTest
@testable import escape_plan

final class BuildRequestEncodingTests: XCTestCase {

    func testRequestEncodesDescriptionAndImage() throws {
        let request = BuildRequest(description: "2-bed bungalow",
                                   image_b64: Data("img".utf8).base64EncodedString(),
                                   image_media_type: "image/jpeg")
        let json = try JSONSerialization.jsonObject(
            with: HomeModel.encoder().encode(request)) as? [String: Any]
        XCTAssertEqual(json?["description"] as? String, "2-bed bungalow")
        XCTAssertEqual(json?["image_b64"] as? String, "aW1n")
        XCTAssertEqual(json?["image_media_type"] as? String, "image/jpeg")
    }

    func testResponseDecodesHomeAndIgnoresTrace() throws {
        let fixtureData = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("schema/fixtures/bungalow.json"))
        let homeJSON = String(data: fixtureData, encoding: .utf8)!
        let json = """
        {"home": \(homeJSON), "trace": [{"id": "t1", "tool_name": "start_home",
         "input": {}, "output": {"ok": true}}], "truncated": false, "issues": []}
        """
        let response = try HomeModel.decoder.decode(BuildResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.home?.name, "Bungalow")
        XCTAssertFalse(response.truncated)
    }

    func testFailureResponseDecodesWithNilHomeAndIssues() throws {
        let json = """
        {"home": null, "trace": [], "truncated": true,
         "issues": ["floors: List should have at least 1 item"]}
        """
        let response = try HomeModel.decoder.decode(BuildResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.home)
        XCTAssertTrue(response.truncated)
        XCTAssertEqual(response.issues.count, 1)
    }
}
