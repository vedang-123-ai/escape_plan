//  HomeDeletionReach.swift — S11.21 (AUD-021): what deleting a home on this device actually deletes.
//
//  The delete confirmation must say truthfully whether the account's copy goes too, and the answer
//  is not "signed in or not". A local delete writes a tombstone carrying the home's owner
//  (`SyncState.markDeleted`), and a sync sends `DELETE /homes/{id}` only when that owner is the
//  account signed in at the time (`SyncManager`, docs/decisions.md 2026-09-24). So the owner
//  recorded in `homeOwners` decides it, and this reads it the same way sync will.
//
//  Pure Foundation: compiled into tools/editorcore, where `SyncDeletionTests` checks each answer
//  against what a sync then does to a fake backend.

import Foundation

enum HomeDeletionReach: Equatable, Sendable {
    /// No account has ever synced the home, so it exists only on this device. The tombstone has
    /// no owner and never deletes anything from a server.
    case thisDeviceOnly
    /// The signed-in account owns it: the next sync deletes the account's copy too.
    case deviceAndAccount
    /// An account that is not signed in right now owns it. Its copy is deleted the next time that
    /// account syncs on this device, and not before.
    case deviceNowAccountLater

    /// `signedInUserID` is the subject of the current token, or nil when signed out.
    static func of(_ localHomeID: String, in state: SyncState, signedInUserID: String?) -> HomeDeletionReach {
        // Read raw, not through `ownership(of:)`: that compares against `state.userID`, the account
        // the sidecar last synced as, which is not necessarily the one signed in now.
        guard let owner = state.homeOwners[localHomeID] else { return .thisDeviceOnly }
        return owner == signedInUserID ? .deviceAndAccount : .deviceNowAccountLater
    }

    /// The body of the delete confirmation, under the title `Delete "<name>"?` (wording chosen by
    /// Anish in the simulator, 2026-10-02).
    var confirmationMessage: String {
        switch self {
        case .thisDeviceOnly:
            return "It's removed from this iPhone. You can't undo this."
        case .deviceAndAccount:
            return "It's removed from this iPhone and from your account. You can't undo this."
        case .deviceNowAccountLater:
            return "It's removed from this iPhone now, and from the account it's backed up to the next time that account signs in here. You can't undo this."
        }
    }
}
