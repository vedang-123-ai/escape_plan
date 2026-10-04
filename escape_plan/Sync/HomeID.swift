//  HomeID.swift
//  escape_plan — S11.41 (AUD-012)
//
//  The one rule for what a `home_id` may look like before it becomes part of a file name.
//
//  `HomeDocumentStore` names each file `<home_id>.homeplan.json`. Ids reach it from the server
//  (a sync pull) and from documents a user can edit by hand (the Files app, in Debug builds), so
//  an id of `../x` would otherwise write outside the Homes directory. Lives in `Sync/` so the
//  `tools/editorcore` package tests it with no simulator; Foundation only.
//
//  The rule is deliberately wider than "a UUID". Every id in use today has to pass, or a home
//  already on disk would stop loading:
//    - lowercase UUIDs (fixtures, FixtureSeeder, duplicate, import)
//    - UPPER-case UUIDs (HouseScreen.blankHome, HomeModelStore.newHome)
//    - `TEST-DEMO-HOME-1234` (the DEBUG UI-test seed)
//    - `9a5e6d34-2c3f-4a1b-8d70-empty-123` (a fixture id that is not a UUID)
//    - test ids such as `home-1`, `seed-test`, `h_bounds`
//    - `preserved-<uuid>-N` (the sync test double's conflict copies)

import Foundation

nonisolated enum HomeID {
    /// Long enough for `preserved-<36-char uuid>-NNN`, short enough to stay far below any
    /// file-name limit once the extension is added.
    static let maxLength = 64

    /// ASCII letters, digits, `-` and `_`, 1 to 64 of them. No `/`, no `.`, so no path
    /// separators and no `.` or `..` segments; nothing that needs escaping in a file name.
    static func isValid(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= maxLength else { return false }
        return id.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"):
                return true
            default:
                return false
            }
        }
    }

    /// Throws `InvalidHomeID` unless `id` passes `isValid`.
    static func validate(_ id: String) throws {
        guard isValid(id) else { throw InvalidHomeID(homeID: id) }
    }
}

/// A `home_id` that cannot be used as a file name. Refused before anything is read or written.
nonisolated struct InvalidHomeID: LocalizedError, Equatable {
    let homeID: String

    var errorDescription: String? {
        "This home has an id the app can't save under, so it was left alone."
    }
}
