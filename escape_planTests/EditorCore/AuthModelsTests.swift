//  AuthModelsTests.swift — the auth wire shapes, and the timestamp both backend forms produce.
//
//  Lives in escape_planTests/EditorCore/ (symlinked as the SwiftPM package's Shared folder)
//  rather than in the app target, so it RUNS on a machine with no simulator. Everything it
//  covers is pure Foundation for exactly that reason.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class AuthModelsTests: XCTestCase {

    private struct DateBox: Decodable { let at: Date }

    private func decodeDate(_ raw: String) throws -> Date {
        let json = Data("{\"at\":\"\(raw)\"}".utf8)
        return try HomeModel.decoder.decode(DateBox.self, from: json).at
    }

    // MARK: - created_at: the backend emits two different shapes

    /// Both strings below were produced by the REAL backend models (pydantic v2, via
    /// `UserPublic.model_dump_json()`), captured 2026-09-15. Which one you get depends on
    /// whether the microsecond field is zero, so a client must handle both or it works
    /// almost-always — the worst failure mode.
    func testDecodesBackendTimestampWithFractionalSeconds() throws {
        let seconds = try decodeDate("2026-09-16T05:33:58.567000Z").timeIntervalSince1970
        // 567 ms must actually survive: a parser that accepted the string but discarded the
        // fraction would still return a Date here, and S8.4 orders syncs by this field.
        XCTAssertEqual(seconds - seconds.rounded(.down), 0.567, accuracy: 0.001)
    }

    func testDecodesBackendTimestampWithoutFractionalSeconds() throws {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 15
        components.hour = 18; components.minute = 22; components.second = 31
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(try decodeDate("2026-09-15T18:22:31Z"),
                       try XCTUnwrap(calendar.date(from: components)))
    }

    /// Why the auth layer does NOT hand-roll an `ISO8601DateFormatter`: the obvious one
    /// silently fails on the common backend form. `JSONDecoder`'s `.iso8601` strategy and
    /// `ISO8601DateFormatter()` are not the same parser, which is easy to assume and wrong.
    func testBareISO8601FormatterWouldNotHaveWorked() {
        XCTAssertNil(ISO8601DateFormatter().date(from: "2026-09-16T05:33:58.567000Z"))
    }

    // MARK: - Wire shapes

    func testDecodesUserPublicResponse() throws {
        let json = Data(#"""
        {"id":"9c137960-dcd8-4e99-a5b4-6f990294f612","email":"a@b.co",
         "created_at":"2026-09-16T05:33:58.567000Z"}
        """#.utf8)
        let decoded = try HomeModel.decoder.decode(UserPublicResponse.self, from: json)
        XCTAssertEqual(decoded.id, "9c137960-dcd8-4e99-a5b4-6f990294f612")
        XCTAssertEqual(decoded.email, "a@b.co")
        XCTAssertEqual(decoded.asUser.email, "a@b.co")
    }

    /// A hash must never appear in this type — the backend's `UserPublic` has nowhere to put
    /// one, and neither does ours. Extra keys are ignored rather than fatal, which is what
    /// lets the backend add a field without breaking an already-shipped build.
    func testUserPublicIgnoresUnexpectedKeys() throws {
        let json = Data(#"""
        {"id":"u1","email":"a@b.co","created_at":"2026-09-15T18:22:31Z","hashed_password":"$argon2id$x"}
        """#.utf8)
        XCTAssertEqual(try HomeModel.decoder.decode(UserPublicResponse.self, from: json).id, "u1")
    }

    func testDecodesTokenResponse() throws {
        let json = Data(#"{"access_token":"header.payload.sig","token_type":"bearer"}"#.utf8)
        let decoded = try HomeModel.decoder.decode(TokenResponse.self, from: json)
        XCTAssertEqual(decoded.access_token, "header.payload.sig")
        XCTAssertEqual(decoded.token_type, "bearer")
    }

    /// The backend's `RegisterRequest` forbids extra keys, so the encoded shape is exactly
    /// two fields. A stray one is a 422 at runtime.
    func testRegisterBodyEncodesExactlyEmailAndPassword() throws {
        let data = try JSONEncoder().encode(
            RegisterRequestBody(email: "a@b.co", password: "correct horse battery"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["email", "password"])
    }
}
