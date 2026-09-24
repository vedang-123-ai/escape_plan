//  AccountPrivacy.swift
//  escape_plan — S11.7 accounts demoted
//
//  What leaves this device once you sign in, in the words the user actually reads.
//
//  Copy lives HERE, in Foundation-only code, rather than inline in the three SwiftUI screens
//  that show it, for two reasons. The screens cannot be tested on a machine with no simulator
//  and this file can; and a privacy claim repeated in three places is a privacy claim that
//  will be true in two of them after the next schema change.
//
//  `uploadedHomeKeys` is the load-bearing part. It is the exact set of top-level HomeModel
//  keys that `POST /homes` sends, and `AccountPrivacyTests` encodes a real fixture and
//  asserts the two agree — so adding a field to the schema and saying nothing about it fails
//  a test rather than quietly making this screen a lie.

import Foundation

enum AccountPrivacy {

    // MARK: - What is uploaded

    /// Every top-level key of the `HomeModel` document that `CloudHomesClient.push` sends.
    ///
    /// Pinned by test against a real encode of a fixture home. If this set and the encoder
    /// disagree, one of them is wrong and the disclosure below is incomplete.
    static let uploadedHomeKeys: Set<String> = [
        "schema_version", "home_id", "name", "floors", "stairs", "profiles", "meta", "household",
    ]

    /// Plain-language lines for "what gets uploaded", each tied to the schema keys it covers.
    ///
    /// Ordered most-personal first. Someone skimming should hit "names" and "address" before
    /// they hit "wall measurements", because those are the two that would change their mind.
    static let uploaded: [Disclosure] = [
        Disclosure(
            text: "The names you gave household members and pets, whether you tagged them as a "
                + "child, elderly, mobility-limited, or hearing- or vision-impaired, and which "
                + "room each one sleeps in.",
            keys: ["profiles"]),
        Disclosure(
            text: "Your home's address — only if you typed one in. It is optional everywhere "
                + "in the app and blank until you fill it in.",
            keys: ["meta"]),
        Disclosure(
            text: "Whether you rent or own, and which safety equipment you said you already "
                + "have.",
            keys: ["household"]),
        Disclosure(
            text: "The floor plan itself: room shapes and names, walls, doors, windows, "
                + "stairs, and the objects you tagged or a scan found.",
            keys: ["floors", "stairs"]),
        Disclosure(
            text: "The home's name and its created, edited and last-scanned dates.",
            keys: ["home_id", "name", "schema_version"]),
        Disclosure(
            text: "Your email address, which is what the account is.",
            keys: []),
    ]

    // MARK: - What is not

    /// Claims that must stay checkable. Nothing vague belongs here — "we respect your privacy"
    /// is not a fact, and a judge reading the submission can verify every line below against
    /// the code.
    static let notUploaded: [String] = [
        "Your password. The server stores a one-way hash it cannot reverse, never the password "
            + "itself.",
        "Camera images. A LiDAR scan is converted from room measurements; no photo or video "
            + "frame is ever sent or stored.",
        "Your location. Escape Plan never asks for it and never has it.",
        "Anything about how you use the app. There is no analytics or tracking of any kind.",
    ]

    // MARK: - The headline claims

    /// The one sentence that has to be on the sign-in screen, because it is the fact that
    /// makes the gate soft rather than a wall.
    static let signedOutSummary =
        "Signed out, Escape Plan uploads nothing about your home. Everything — building, "
        + "editing, routes, the drill and exporting — works on this iPhone with no account."

    /// Shown next to the delete button. Both halves matter: people hesitate to delete because
    /// they are afraid of losing the work, and the honest answer is that they will not.
    static let deletionSummary =
        "Deleting your account erases your email address and every home stored in it from the "
        + "server, straight away and permanently. The homes on this iPhone are not touched — "
        + "they stay here and keep working, signed out."

    /// The alert body for the confirmation. Deliberately says "cannot be undone" in the
    /// sentence a user reads at the moment they can still stop.
    static let deletionConfirmation =
        "This permanently deletes your account and every home backed up to it. It cannot be "
        + "undone. The homes on this iPhone stay where they are."

    // MARK: -

    struct Disclosure: Equatable, Sendable {
        let text: String
        /// The `HomeModel` keys this line accounts for. Empty means it describes something
        /// outside the home document (the account's own email address).
        let keys: [String]
    }
}
