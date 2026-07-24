//
//  SchemaMigrator.swift
//  escape_plan — S2.4 persistence
//

import Foundation

/// Checks `schema_version` on load and, when a document predates this build,
/// runs it forward through the registered migrations.
///
/// Migration stub, per S2.4: no older schema versions exist yet (1.0 is the
/// first), so `migrations` is empty. The shape is here so that the first real
/// `schema_version` bump is a one-entry addition rather than a redesign.
enum SchemaMigrator {
    /// The version this build reads and writes. Must track
    /// `schema/homemodel.schema.json`'s `schema_version` const.
    static let currentVersion = "1.1"

    /// Ordered one-step migrations, keyed by the version they upgrade *from*.
    /// Add an entry alongside any schema_version bump.
    static let migrations: [String: (HomeDocument) throws -> HomeDocument] = [
        // 1.0 → 1.1: adds `floor.objects` (defaults to [] — decoders tolerate its absence,
        // so only the version stamp needs rewriting) and the 'ai_plan' source (new documents
        // only; nothing existing to rewrite).
        "1.0": { document in
            guard case .object(var root) = document.body else {
                throw PersistenceError.missingSchemaVersion
            }
            root["schema_version"] = .string("1.1")
            return HomeDocument(body: .object(root))
        }
    ]

    /// Brings `document` up to `currentVersion`.
    ///
    /// - Newer than this build → `PersistenceError.documentTooNew`. We refuse
    ///   rather than guess: a document written by a future build may carry
    ///   fields whose meaning we would silently mangle.
    /// - Older → applied step by step; an unregistered step fails loudly.
    static func migrate(_ document: HomeDocument) throws -> HomeDocument {
        guard let version = document.schemaVersion else {
            throw PersistenceError.missingSchemaVersion
        }

        switch compare(version, currentVersion) {
        case .orderedSame:
            return document
        case .orderedDescending:
            throw PersistenceError.documentTooNew(
                documentVersion: version,
                supportedVersion: currentVersion
            )
        case .orderedAscending:
            break
        }

        var migrated = document
        var current = version
        var steps = 0
        while compare(current, currentVersion) == .orderedAscending {
            // No registered step, a step that didn't advance the version, or more
            // steps than exist: all mean we can't finish the upgrade. Fail before
            // handing the caller a half-migrated document.
            guard let step = migrations[current], steps < migrations.count else {
                throw PersistenceError.migrationUnavailable(
                    fromVersion: current,
                    toVersion: currentVersion
                )
            }
            migrated = try step(migrated)
            guard let next = migrated.schemaVersion, next != current else {
                throw PersistenceError.migrationUnavailable(
                    fromVersion: current,
                    toVersion: currentVersion
                )
            }
            current = next
            steps += 1
        }
        return migrated
    }

    /// Numeric, component-wise comparison — "1.10" is newer than "1.2".
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
