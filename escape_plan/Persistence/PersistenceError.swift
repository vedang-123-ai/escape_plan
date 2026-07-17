//
//  PersistenceError.swift
//  escape_plan — S2.4 persistence
//

import Foundation

enum PersistenceError: Error, Equatable, LocalizedError {
    case homeNotFound(homeID: String)
    case malformedDocument(homeID: String, underlying: String)
    case missingSchemaVersion
    case missingHomeID
    /// Written by a newer build of the app than this one. Refused, not guessed at.
    case documentTooNew(documentVersion: String, supportedVersion: String)
    case migrationUnavailable(fromVersion: String, toVersion: String)

    var errorDescription: String? {
        switch self {
        case .homeNotFound(let homeID):
            return "No saved home with id \(homeID)."
        case .malformedDocument(let homeID, let underlying):
            return "The saved home \(homeID) could not be read: \(underlying)"
        case .missingSchemaVersion:
            return "The document has no schema_version and cannot be read safely."
        case .missingHomeID:
            return "The document has no home_id."
        case .documentTooNew(let documentVersion, let supportedVersion):
            return """
                This home was saved by a newer version of Escape Plan \
                (format \(documentVersion); this app reads \(supportedVersion)). \
                Update the app to open it. The file has not been changed.
                """
        case .migrationUnavailable(let fromVersion, let toVersion):
            return "No upgrade path from home format \(fromVersion) to \(toVersion)."
        }
    }
}
