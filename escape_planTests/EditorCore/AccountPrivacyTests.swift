//  AccountPrivacyTests.swift — the privacy copy is checked against the wire, not proofread.
//
//  A privacy disclosure is the one piece of user-facing text that goes stale silently: the
//  schema gains a field, the sync layer uploads it because it uploads the whole document, and
//  the screen keeps saying what used to be true. These tests encode a real fixture home the
//  way `CloudHomesClient.push` does, and real compute requests the way `APIClient` does
//  (S11.16), and compare the result against what the screen claims.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class AccountPrivacyTests: XCTestCase {

    /// Every top-level key an encoded HomeModel actually carries.
    private func encodedKeys(of name: String) throws -> Set<String> {
        let model = try Fixtures.load(name)
        let data = try HomeModel.encoder().encode(model)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    /// THE test. `POST /homes` sends the whole document, so anything the encoder emits is
    /// uploaded — and if this set grows, the disclosure below is incomplete until someone
    /// says what the new field is.
    func testTheDisclosedKeysAreExactlyWhatIsEncoded() throws {
        for name in Fixtures.validNames {
            let encoded = try encodedKeys(of: name)
            XCTAssertTrue(
                encoded.isSubset(of: AccountPrivacy.uploadedHomeKeys),
                "\(name) encodes \(encoded.subtracting(AccountPrivacy.uploadedHomeKeys)), "
                + "which the account privacy copy does not mention.")
        }
    }

    /// The other direction: a key listed here that the encoder never emits means the copy
    /// describes something that does not exist, which is its own kind of dishonest.
    func testEveryDisclosedKeyIsReallyInTheDocument() throws {
        // `twostory` is the richest fixture; the union across all three is what a user's
        // document can contain.
        var everyKey = Set<String>()
        for name in Fixtures.validNames { everyKey.formUnion(try encodedKeys(of: name)) }
        XCTAssertEqual(AccountPrivacy.uploadedHomeKeys, everyKey)
    }

    /// Each uploaded key must be accounted for by at least one line of user-facing text.
    /// Without this the set above could stay correct while the prose covered half of it.
    func testEveryUploadedKeyIsCoveredByALineOfCopy() {
        let covered = Set(AccountPrivacy.uploaded.flatMap(\.keys))
        XCTAssertEqual(
            AccountPrivacy.uploadedHomeKeys.subtracting(covered), [],
            "these uploaded fields have no plain-language line describing them")
    }

    func testNoDisclosureClaimsAKeyThatIsNotUploaded() {
        for disclosure in AccountPrivacy.uploaded {
            for key in disclosure.keys {
                XCTAssertTrue(AccountPrivacy.uploadedHomeKeys.contains(key),
                              "\(key) is described to the user but is not uploaded")
            }
        }
    }

    // MARK: - Sent to compute (S11.16, AUD-050)

    /// Top-level keys of any encodable request body, encoded the way the APIClient does.
    private func topLevelKeys<T: Encodable>(of request: T) throws -> Set<String> {
        let data = try HomeModel.encoder().encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    /// The `home` inside a compute request, as the server receives it.
    private func encodedHome<T: Encodable>(in request: T) throws -> Set<String> {
        let data = try HomeModel.encoder().encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        let home = try XCTUnwrap(object["home"] as? [String: Any])
        return Set(home.keys)
    }

    private func assertDisclosed(_ keys: Set<String>, _ endpoint: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let covered = Set(AccountPrivacy.sentToCompute.flatMap(\.keys))
        XCTAssertEqual(keys.subtracting(covered), [],
                       "\(endpoint) sends fields the privacy copy does not describe",
                       file: file, line: line)
    }

    /// THE AUD-050 test. `/score` runs signed out, on the Home tab's first load, and carries
    /// the whole home plus the checklist. Every field of it must be named by a line of copy.
    func testEveryFieldOfARealScoreRequestIsDisclosed() throws {
        let home = try Fixtures.load("twostory")
        let request = ScoreRequest(home: home, checklist_state: ["smoke.alarm.bedrooms": true])
        let keys = try topLevelKeys(of: request)
        XCTAssertEqual(keys, ["home", "checklist_state"])
        assertDisclosed(keys, "/score")
    }

    /// `/routes` with every optional field set, so a field that is omitted when nil is still
    /// checked. `constraints` and `profile_id` are exclusive server-side; the encoder does not
    /// care, and this is about what CAN be sent.
    func testEveryFieldOfARealRoutesRequestIsDisclosed() throws {
        let home = try Fixtures.load("twostory")
        let request = RoutesRequest(home: home, peril: "fire",
                                    constraints: RoutingConstraints(avoid_stairs: true),
                                    profile_id: "p1")
        let keys = try topLevelKeys(of: request)
        XCTAssertEqual(keys, ["home", "peril", "constraints", "profile_id"])
        assertDisclosed(keys, "/routes")
    }

    /// The line that says "the whole home" has to mean it: the `home` a compute request carries
    /// is the same document an account saves, household names and tags included. If that ever
    /// stops being true the copy is over-disclosing, which is the cheaper failure, but it
    /// should still be a deliberate edit.
    func testTheHomeSentToComputeIsTheWholeDocument() throws {
        let home = try Fixtures.load("twostory")
        let keys = try encodedHome(in: ScoreRequest(home: home, checklist_state: [:]))
        XCTAssertEqual(keys, try encodedKeys(of: "twostory"))
        XCTAssertTrue(keys.contains("profiles"), "the copy says names and tags are sent")
    }

    #if !SWIFT_PACKAGE
    /// The request types that live in `Networking/`, which the EditorCore package does not
    /// compile. Checked in the app runner only.
    func testEveryFieldOfTheOtherComputeRequestsIsDisclosed() throws {
        let home = try Fixtures.load("twostory")
        let room = try XCTUnwrap(home.floors.first?.rooms.first?.id)

        assertDisclosed(try topLevelKeys(of: EvacuateRequest(
            home: home, origin_room_id: room, profile_set_id: "p1")), "/evacuate")
        assertDisclosed(try topLevelKeys(of: DiffRequest(
            stored_model: home, scan_model: home, target_room_id: room)), "/diff_obstructions")
        assertDisclosed(try topLevelKeys(of: ChatRequest(
            home: home, messages: [ChatMessage(role: .user, content: "hi")])), "/chat")
        assertDisclosed(try topLevelKeys(of: BuildRequest(
            description: "a bungalow", image_b64: "AA==", image_media_type: "image/png")),
            "/build")
    }
    #endif

    /// The other direction: a compute key the copy claims that no request sends.
    func testEveryComputeKeyInTheCopyIsInTheDeclaredSet() {
        let covered = Set(AccountPrivacy.sentToCompute.flatMap(\.keys))
        XCTAssertEqual(covered, AccountPrivacy.computeRequestKeys)
    }

    // MARK: - The claims that are not about keys

    /// The soft gate's paragraph. Asserted on substance rather than wording so a copy edit does
    /// not fail the build, but removing a fact does. It must say: homes are saved only here,
    /// no account is needed, the server is sent the home and does not keep it, and Anthropic
    /// gets what the assistant and Import Plan are given.
    func testTheSignedOutClaimSeparatesSavedFromSent() {
        let text = AccountPrivacy.signedOutSummary.lowercased()
        XCTAssertTrue(text.contains("saved only on this iphone"))
        XCTAssertTrue(text.contains("account"))
        XCTAssertTrue(text.contains("sends the whole home"))
        XCTAssertTrue(text.contains("household names"))
        XCTAssertTrue(text.contains("does not keep"))
        XCTAssertTrue(text.contains("anthropic"))
    }

    /// AUD-050 regression guard. Both phrases were false the day they shipped: signed out, the
    /// whole home goes to `/score` on the first Home-tab load, and Import Plan sends a photo.
    func testNoCopyClaimsNothingIsUploadedOrNoPhotoIsSent() {
        let every = [AccountPrivacy.signedOutSummary]
            + AccountPrivacy.sentToCompute.map(\.text) + AccountPrivacy.sentToAnthropic
            + AccountPrivacy.uploaded.map(\.text) + AccountPrivacy.notSynced
            + AccountPrivacy.notUploaded
        for line in every.map({ $0.lowercased() }) {
            XCTAssertFalse(line.contains("uploads nothing"), line)
            XCTAssertFalse(line.contains("ever sent"), line)
            XCTAssertFalse(line.contains("works on this iphone with no account"), line)
        }
    }

    /// AUD-018, the disclosure half: the per-device state sync does not carry is named.
    func testTheSyncDisclosureSaysWhatStaysOnTheDevice() {
        let text = AccountPrivacy.notSynced.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("checklist"))
        XCTAssertTrue(text.contains("drill"))
        XCTAssertTrue(text.contains("chat"))
        XCTAssertTrue(text.contains("not copied to your account"))
    }

    /// Those three really are outside the synced document, so the claim above is true by
    /// construction rather than by proofreading.
    func testNothingTheCopyCallsUnsyncedIsInTheSyncedDocument() {
        for key in AccountPrivacy.uploadedHomeKeys {
            XCTAssertFalse(key.contains("checklist") || key.contains("drill")
                           || key.contains("conversation") || key.contains("chat"), key)
        }
    }

    func testTheDeletionClaimCoversBothTheServerAndThisDevice() {
        let text = AccountPrivacy.deletionSummary.lowercased()
        XCTAssertTrue(text.contains("server"), "must say what is erased")
        XCTAssertTrue(text.contains("this iphone"), "must say what is NOT erased")
        XCTAssertTrue(text.contains("permanently"))
    }

    func testTheConfirmationSaysItCannotBeUndone() {
        XCTAssertTrue(AccountPrivacy.deletionConfirmation.lowercased()
            .contains("cannot be undone"))
    }

    /// Nothing in the disclosure may be empty — a blank line renders as a bullet with no text
    /// and reads as a redaction.
    func testNoDisclosureLineIsEmpty() {
        for disclosure in AccountPrivacy.uploaded {
            XCTAssertFalse(disclosure.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        for disclosure in AccountPrivacy.sentToCompute {
            XCTAssertFalse(disclosure.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        for line in AccountPrivacy.notUploaded + AccountPrivacy.sentToAnthropic
            + AccountPrivacy.notSynced {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
