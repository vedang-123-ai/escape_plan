//
//  ScanStore.swift
//  Capture/Export — S1.4
//
//  Writes scan artifacts into the app's documents directory.
//
//  Layout (one directory per scan, so a scan is a single unit to copy off the
//  device via Files.app / Finder — that is how S1.4's fixtures reach the repo):
//
//      Documents/Scans/<yyyyMMdd-HHmmss>-<short-id>/
//          raw.roomplan.json   ← the converter's input (our pinned format)
//          apple-raw.json      ← Apple's own CapturedStructure encoding
//          scan.usdz           ← parametric USDZ, for eyeballing the capture
//

import Foundation

/// Everything one scan produced on disk.
nonisolated struct ScanArtifacts: Equatable {
    var directory: URL
    var rawJSON: URL
    /// nil when Apple's encoder threw — never fatal, it is a diagnostic aid.
    var appleRawJSON: URL?
    /// nil when USDZ export failed — also never fatal.
    var usdz: URL?
    var roomCount: Int
    var exportedAt: Date
}

nonisolated enum ScanStoreError: LocalizedError {
    case noRoomsCaptured
    case documentsDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .noRoomsCaptured:
            return "The scan finished without capturing any rooms. Try again, moving slowly around the room's walls."
        case .documentsDirectoryUnavailable:
            return "Couldn't reach the app's documents folder to save the scan."
        }
    }
}

/// File I/O for scans. Kept separate from `ScanExportBuilder` (which is pure) so
/// the format logic stays testable without touching a filesystem.
///
/// `nonisolated` because the cleanup in `ScanCleanup.swift` runs off the main actor
/// (the app target defaults to MainActor isolation).
nonisolated struct ScanStore {
    var fileManager: FileManager = .default
    /// Stands in for the Documents directory, so tests work in a temporary folder and
    /// never touch the real one. nil in the app.
    var rootOverride: URL?

    /// `<root>/Scans`, without creating it.
    func scansRoot() throws -> URL {
        let documents: URL
        if let rootOverride {
            documents = rootOverride
        } else {
            guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw ScanStoreError.documentsDirectoryUnavailable
            }
            documents = url
        }
        return documents.appendingPathComponent("Scans", isDirectory: true)
    }

    /// Root for all scans. Created lazily.
    func scansDirectory() throws -> URL {
        let root = try scansRoot()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Create the per-scan directory, named so scans sort chronologically.
    func makeScanDirectory(exportedAt: Date, scanID: UUID) throws -> URL {
        let stamp = DateFormatter.scanDirectoryStamp.string(from: exportedAt)
        let short = scanID.uuidString.lowercased().prefix(8)
        let directory = try scansDirectory()
            .appendingPathComponent("\(stamp)-\(short)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Write the converter-facing JSON. This is the one artifact S1.5 consumes;
    /// a failure here fails the scan. `@MainActor` because `RawScanExport.encoded()` is
    /// (the target's default isolation); its one caller, RoomCaptureController, is too.
    @MainActor @discardableResult
    func writeRawJSON(_ export: RawScanExport, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("raw.roomplan.json")
        try export.encoded().write(to: url, options: .atomic)
        return url
    }

    /// Write Apple's own encoding beside ours.
    ///
    /// This exists purely to serve S1.5's calibration: the converter is built on
    /// *assumptions* about how RoomPlan encodes (column-major transforms,
    /// `{"high": {}}` confidence). Diffing this file against `raw.roomplan.json`
    /// on a real export is what confirms or kills those assumptions. Best-effort
    /// — Apple's encoder throwing must never cost the user their scan.
    func writeAppleRawJSON(_ encodable: some Encodable, to directory: URL) -> URL? {
        let url = directory.appendingPathComponent("apple-raw.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(encodable).write(to: url, options: .atomic)
            return url
        } catch {
            // Diagnostic only; the scan is still valid without it.
            print("[ScanStore] apple-raw.json export failed: \(error)")
            return nil
        }
    }
}

nonisolated extension DateFormatter {
    static let scanDirectoryStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
