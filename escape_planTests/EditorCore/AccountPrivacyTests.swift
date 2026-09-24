//  AccountPrivacyTests.swift — the privacy copy is checked against the wire, not proofread.
//
//  A privacy disclosure is the one piece of user-facing text that goes stale silently: the
//  schema gains a field, the sync layer uploads it because it uploads the whole document, and
//  the screen keeps saying what used to be true. These tests encode a real fixture home the
//  way `CloudHomesClient.push` does and compare the result against what the screen claims.

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

    // MARK: - The claims that are not about keys

    /// The three facts that make the soft gate honest. Asserted on substance rather than
    /// wording so a copy edit does not fail the build, but a REMOVAL does.
    func testTheSignedOutClaimSaysNothingIsUploaded() {
        let text = AccountPrivacy.signedOutSummary.lowercased()
        XCTAssertTrue(text.contains("uploads nothing"))
        XCTAssertTrue(text.contains("no account"))
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
        for line in AccountPrivacy.notUploaded {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
