//  BuildRequestEncodingTests.swift — the /build wire contract from the client side
//  (pattern: ChatRequestEncodingTests). The backend's BuildRequest forbids extra keys, so
//  the encoded shape matters; the response decode must tolerate the trace we don't model.

import XCTest
@testable import escape_plan

/// Records the body of every request on the session it is installed in and answers 503. Installed
/// only on an ephemeral session (pattern: ReadinessStoreTests), never registered globally.
private final class BuildSpyProtocol: URLProtocol {
    nonisolated(unsafe) static var bodies: [Data] = []
    private static let lock = NSLock()

    static func reset() { lock.withLock { bodies = [] } }
    static var recorded: [Data] { lock.withLock { bodies } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession moves httpBody into a stream before a protocol sees it.
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        Self.lock.withLock { Self.bodies.append(body) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class BuildRequestEncodingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BuildSpyProtocol.reset()
    }

    // MARK: - What goes on the wire (S11.33, AUD-024)

    /// A camera photo (HEIC) reaches /build as JPEG bytes labelled image/jpeg.
    func testPhotoIsSentAsJPEGLabelledJPEG() async throws {
        let heic = try encodedFixture(width: 4032, height: 3024, type: "public.heic")
        let body = try await sentBody(image: try ImagePreparation.photo(heic))
        XCTAssertEqual(body["image_media_type"] as? String, "image/jpeg")
        let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(body["image_b64"] as? String)))
        XCTAssertEqual(Array(bytes.prefix(3)), [0xFF, 0xD8, 0xFF], "the bytes must really be JPEG")
        XCTAssertNotEqual(bytes, heic, "the original HEIC must not be what is sent")
    }

    /// The PDF path still sends PNG, labelled PNG.
    func testPDFIsSentAsPNGLabelledPNG() async throws {
        let pdf = try pdfFixture(width: 612, height: 792)
        let body = try await sentBody(image: try ImagePreparation.pdfFirstPage(pdf))
        XCTAssertEqual(body["image_media_type"] as? String, "image/png")
        let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(body["image_b64"] as? String)))
        XCTAssertEqual(Array(bytes.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "the bytes must really be PNG")
    }

    /// Bytes that do not decode never become a `PreparedImage`, and `build` accepts nothing else,
    /// so a build after a failed pick carries neither image bytes nor a media type (the old
    /// client sent "image/png" even with no image). The view half (a failed pick attaches nothing
    /// and shows a message) is not unit-tested; see the S11.33 note.
    func testFailedPhotoLeavesNoImageFieldsOnTheWire() async throws {
        let garbage = Data("definitely not a photo".utf8)
        XCTAssertThrowsError(try ImagePreparation.photo(garbage))
        let attachment = try? ImagePreparation.photo(garbage)
        let body = try await sentBody(description: "2-bed bungalow", image: attachment)
        XCTAssertEqual(body["description"] as? String, "2-bed bungalow")
        XCTAssertNil(body["image_b64"])
        XCTAssertNil(body["image_media_type"])
    }

    /// Calls the real `APIClient.build` on an ephemeral session whose only protocol is the spy,
    /// and returns the one JSON body it sent. The spy answers 503, so `build` throws; expected.
    private func sentBody(description: String? = nil,
                          image: PreparedImage?) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BuildSpyProtocol.self]
        let defaults = UserDefaults(suiteName: "BuildRequestEncodingTests.\(UUID().uuidString)")!
        defaults.set("https://build-tests.invalid", forKey: "APIClient.baseURL")
        let client = APIClient(defaults: defaults, session: URLSession(configuration: configuration))
        _ = try? await client.build(description: description, image: image)
        let bodies = BuildSpyProtocol.recorded
        XCTAssertEqual(bodies.count, 1, "exactly one /build request")
        let data = try XCTUnwrap(bodies.first)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Encoding and decoding

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
