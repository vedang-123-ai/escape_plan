//  AccountPrivacy.swift
//  escape_plan — S11.7 accounts demoted; S11.16 rewritten against what actually leaves the phone
//
//  What leaves this device, in the words the user actually reads.
//
//  Copy lives HERE, in Foundation-only code, rather than inline in the three SwiftUI screens
//  that show it, for two reasons. The screens cannot be tested on a machine with no simulator
//  and this file can; and a privacy claim repeated in three places is a privacy claim that
//  will be true in two of them after the next schema change.
//
//  Two different things leave the phone, and the copy keeps them apart (AUD-050):
//
//  - SENT TO COMPUTE, NOT KEPT. Routes, the score, the fire simulation and scan conversion run
//    on our server, signed in or not. Every one of those requests carries the whole HomeModel,
//    household names and vulnerability tags included. The server stores none of them: the only
//    database writes are `/auth/*` and `/homes`, and nothing logs a request body.
//  - SAVED TO AN ACCOUNT. Only when signed in, `POST /homes` stores the same document.
//
//  The S11.7 copy told signed-out users nothing about their home left the phone: the second
//  claim mistaken for the first. Where a claim names Anthropic it is because `/chat` and
//  `/build` are the only endpoints the app calls that reach it (`backend/app/api_chat.py`,
//  `backend/app/ai/builder.py`). `/explain` and `/analyze` also call it, and the app calls
//  neither; `/score` can, but only with `include_recommendations`, which the app never sends.
//
//  The key sets are the load-bearing part. `AccountPrivacyTests` encodes real requests and
//  asserts every top-level field is described by a line of copy, so adding a field to the
//  schema or to a request body and saying nothing about it fails a test rather than quietly
//  making this screen a lie.

import Foundation

enum AccountPrivacy {

    // MARK: - The headline claim

    /// The one paragraph that has to be on the sign-in screen, because it is the fact that
    /// makes the gate soft rather than a wall. Each sentence is one row of the S11.16 inventory
    /// (docs/tracker/notes/2026-10-01-s11-16-privacy-truth.md).
    static let signedOutSummary =
        "Signed out, your homes are saved only on this iPhone, and you never need an account. "
        + "To work out routes, your score and the fire drill, the app sends the whole home — "
        + "household names and tags included — to our server, which uses it and does not store "
        + "it. The assistant sends your messages and your home's room names on to Anthropic's "
        + "AI service, and Import Plan sends it the picture and description you give it."

    // MARK: - Sent to compute, not stored

    /// Every top-level field of the request bodies that carry a home to a compute endpoint:
    /// `/score`, `/routes`, `/evacuate`, `/convert`, `/diff_obstructions`, `/chat`, `/build`.
    /// None of them needs an account and none of them is stored.
    ///
    /// Pinned by test against real encodes of `ScoreRequest` and `RoutesRequest` (in both
    /// runners) and of the Networking-only request types (in the app runner).
    static let computeRequestKeys: Set<String> = [
        "home",                                                 // /score, /routes, /evacuate, /chat
        "checklist_state",                                      // /score
        "peril", "constraints", "profile_id",                   // /routes
        "origin_room_id", "profile_set_id",                     // /evacuate
        "scan", "home_name",                                    // /convert
        "stored_model", "scan_model", "target_room_id",         // /diff_obstructions
        "messages",                                             // /chat
        "description", "image_b64", "image_media_type",         // /build
    ]

    /// What the server is sent to work things out, ordered most-personal first.
    static let sentToCompute: [Disclosure] = [
        Disclosure(
            text: "The whole home, every time the server works something out for you: the "
                + "floor plan and room names, the names you gave household members and pets, "
                + "their tags (child, elderly, pet, mobility-limited, hearing- or "
                + "vision-impaired) and the room each one sleeps in. Re-scanning "
                + "a room sends your saved home and the new scan together, to compare them.",
            keys: ["home", "stored_model", "scan_model"]),
        Disclosure(
            text: "Which checklist items you have ticked, so the score can count them.",
            keys: ["checklist_state"]),
        Disclosure(
            text: "A new scan's measurements and labels (walls, doors, windows, furniture), the "
                + "name you give it, the app version and the model of iPhone that took it, to "
                + "turn them into a floor plan.",
            keys: ["scan", "home_name"]),
        Disclosure(
            text: "Which hazard, household member or starting room you are looking at.",
            keys: ["peril", "constraints", "profile_id", "origin_room_id", "profile_set_id",
                   "target_room_id"]),
        Disclosure(
            text: "Your messages to the assistant, and the photo, PDF page or description you "
                + "give Import Plan. These go on to Anthropic, below.",
            keys: ["messages", "description", "image_b64", "image_media_type"]),
    ]

    /// What our server passes on to Anthropic. Nothing here is keyed: the server builds these
    /// from the request rather than forwarding it. `/chat` sends `summarize_home` (home, floor
    /// and room names, exits, stairs) and the message history; the app sends no `profiles`.
    /// `/build` sends the image and the description. Only the first page of a PDF is rendered
    /// and sent (`BuildFromPlanView`).
    static let sentToAnthropic: [String] = [
        "The assistant: your messages, its earlier replies, and a summary of the floor plan — "
            + "the home's name, its floor and room names and types, its exits and its stairs. "
            + "Not the household members you added.",
        "Import Plan: the photo, or the first page of the PDF, that you pick, and any "
            + "description you type. A photo is sent as it is, including any location your "
            + "camera saved in it.",
        "Anthropic handles what it receives under its own policies, not ours.",
    ]

    // MARK: - Saved to an account

    /// Every top-level key of the `HomeModel` document that `CloudHomesClient.push` sends.
    ///
    /// Pinned by test against a real encode of a fixture home. If this set and the encoder
    /// disagree, one of them is wrong and the disclosure below is incomplete.
    static let uploadedHomeKeys: Set<String> = [
        "schema_version", "home_id", "name", "floors", "stairs", "profiles", "meta", "household",
    ]

    /// Plain-language lines for "what an account saves", each tied to the schema keys it covers.
    ///
    /// Ordered most-personal first. Someone skimming should hit household names and tags before
    /// they hit "wall measurements", because those are what would change their mind.
    static let uploaded: [Disclosure] = [
        Disclosure(
            text: "The names you gave household members and pets, whether you tagged them as a "
                + "child, elderly, pet, mobility-limited, or hearing- or vision-impaired, and "
                + "which room each one sleeps in.",
            keys: ["profiles"]),
        Disclosure(
            // S11.16: the S11.7 line promised an address "only if you typed one in", but no
            // screen sets `meta.address_optional` and nothing on the server does either
            // (pitch-truth-auditor). If a screen ever gains an address field, this line and the
            // `sentToCompute` "whole home" line both need it back.
            text: "The dates the home was created, last edited and last scanned. The app never "
                + "asks for your address.",
            keys: ["meta"]),
        Disclosure(
            text: "Whether you rent or own, and which safety equipment you said you already "
                + "have.",
            keys: ["household"]),
        Disclosure(
            text: "The floor plan itself: room shapes and names, walls, doors, windows, "
                + "stairs, and the objects you tagged or a scan found.",
            keys: ["floors", "stairs"]),
        // The dates belong to `meta` and are described on that line; this one is only the
        // home's name and the two ids that identify the document. Corrected in review — the
        // key-coverage test still passed with the dates claimed here, because `meta` was
        // covered anyway, so the mapping was wrong on its own terms without failing anything.
        Disclosure(
            text: "The home's name, and the identifiers that tell one saved home from another.",
            keys: ["home_id", "name", "schema_version"]),
        Disclosure(
            text: "Your email address, which is what the account is.",
            keys: []),
        // Was under "never uploads" in S11.7, which contradicted itself: the password IS sent,
        // once, to `/auth/register` and `/auth/login`. What is never kept is the password.
        Disclosure(
            text: "A one-way hash of your password, which cannot be turned back into it. The "
                + "password itself is never stored.",
            keys: []),
    ]

    /// AUD-018. Sync copies the home document and nothing else, so the state that lives beside
    /// it — `ChecklistStateStore` (UserDefaults), the drill log and `ConversationStore` — is
    /// not in the account. Said here so a second device showing a different score is expected
    /// rather than a bug. Deliberately "not copied to your account" and not "never leaves this
    /// iPhone": ticks go to `/score` and messages go to `/chat`, they are just not saved there.
    static let notSynced: [String] = [
        "Checklist progress, practice-drill history and assistant chats are kept on this "
            + "iPhone and are not copied to your account, so another device starts without them.",
    ]

    // MARK: - What never leaves this iPhone

    /// Claims that must stay checkable. Nothing vague belongs here — "we respect your privacy"
    /// is not a fact, and a judge reading the submission can verify every line below against
    /// the code.
    static let notUploaded: [String] = [
        "Camera images from a scan. A LiDAR scan sends the measurements and labels listed "
            + "above; no photo or video frame from the camera leaves this iPhone. Import Plan is "
            + "the one exception, and only for the picture you choose.",
        "Your location. Escape Plan never asks for it. The one way it can leave is inside a "
            + "photo you pick for Import Plan, as described above.",
        "Analytics or tracking. There is none. Like any server, ours records when each request "
            + "arrived and from which internet address.",
    ]

    // MARK: - Deleting

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
        /// The keys this line accounts for: `HomeModel` keys in `uploaded`, request-body keys
        /// in `sentToCompute`. Empty means it describes something outside both (the account's
        /// own email address and password hash).
        let keys: [String]
    }
}
