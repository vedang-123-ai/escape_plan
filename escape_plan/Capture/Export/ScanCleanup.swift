//
//  ScanCleanup.swift
//  Capture/Export — S11.40 (AUD-008)
//
//  Raw scans are deleted once they have done their job, so a phone does not slowly fill with
//  copies of every walk-through of the home.
//
//  - After a /convert import, once the converted home is SAVED, its scan directory is removed.
//    Never before: until the home is on disk, the raw scan is the only copy of that walk-through.
//  - At launch, scan directories older than `ScanRetention.staleAge` are removed. That collects
//    scans left by a crash, a kill, or a failed conversion the user dismissed.
//  - Debug builds keep raw scans by default, so the fixture workflow in Capture/README.md (drag
//    a scan off the device via Finder) still works. Release builds always delete.
//
//  Only ever deletes direct children of Scans/ whose name is a scan stamp
//  (`yyyyMMdd-HHmmss-<8 hex>`, as `ScanStore.makeScanDirectory` writes). Nothing else.
//

import Foundation

nonisolated enum ScanRetention {
    /// Debug-only UserDefaults switch. Absent means keep (the fixture workflow); set it to false
    /// to exercise the Release behaviour in a Debug build:
    /// `xcrun simctl spawn booted defaults write cac.Escape-Plan debug.keepRawScans -bool NO`
    static let keepRawScansKey = "debug.keepRawScans"

    /// Scans older than this are swept at launch.
    static let staleAge: TimeInterval = 7 * 24 * 60 * 60

    /// Whether raw scans are kept instead of deleted. Always false in Release.
    static func keepsRawScans(defaults: UserDefaults = .standard) -> Bool {
#if DEBUG
        return defaults.object(forKey: keepRawScansKey) as? Bool ?? true
#else
        return false
#endif
    }
}

nonisolated extension ScanStore {

    /// True for a name `makeScanDirectory` produces: `yyyyMMdd-HHmmss-` plus 8 lowercase hex.
    static func isScanDirectoryName(_ name: String) -> Bool {
        name.wholeMatch(of: #/[0-9]{8}-[0-9]{6}-[0-9a-f]{8}/#) != nil
    }

    /// When the scan in `name` was exported, read from its name stamp (local time, as written).
    /// nil for anything that is not a scan directory name. After a time-zone change the reading
    /// is off by the offset (hours), which a 7-day window absorbs; accepted.
    static func exportDate(fromDirectoryName name: String) -> Date? {
        guard isScanDirectoryName(name) else { return nil }
        return DateFormatter.scanDirectoryStamp.date(from: String(name.prefix(15)))
    }

    /// Removes one scan's directory after its conversion result has been saved. Returns whether
    /// anything was deleted. Refuses (returns false) when raw scans are kept, or when `directory`
    /// is not a scan directory directly inside this store's Scans/ folder.
    @discardableResult
    func discardImportedScan(at directory: URL, keepRawScans: Bool) -> Bool {
        guard !keepRawScans, isOwnedScanDirectory(directory) else { return false }
        do {
            try fileManager.removeItem(at: directory)
            return true
        } catch {
            print("[ScanStore] could not remove imported scan \(directory.lastPathComponent): \(error)")
            return false
        }
    }

    /// Removes every scan directory whose name stamp is more than `maxAge` before `now`, and
    /// returns what it removed. Does nothing when raw scans are kept. A stamp in the future
    /// (the clock moved) counts as recent.
    @discardableResult
    func sweepStaleScans(now: Date, maxAge: TimeInterval, keepRawScans: Bool) -> [URL] {
        guard !keepRawScans, let root = try? scansRoot(),
              let children = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        else { return [] }

        var removed: [URL] = []
        for child in children {
            guard isScanDirectoryEntry(child),
                  let exported = Self.exportDate(fromDirectoryName: child.lastPathComponent),
                  now.timeIntervalSince(exported) > maxAge
            else { continue }
            do {
                try fileManager.removeItem(at: child)
                removed.append(child)
            } catch {
                print("[ScanStore] could not sweep stale scan \(child.lastPathComponent): \(error)")
            }
        }
        return removed
    }

    // MARK: - App hooks (off the main thread)

    /// Called by HomeScreen once the converted home is saved.
    static func discardImportedScanInBackground(at directory: URL) {
        Task.detached(priority: .utility) {
            ScanStore().discardImportedScan(at: directory, keepRawScans: ScanRetention.keepsRawScans())
        }
    }

    /// Called once at launch.
    static func sweepStaleScansInBackground() {
        Task.detached(priority: .utility) {
            ScanStore().sweepStaleScans(now: Date(), maxAge: ScanRetention.staleAge,
                                        keepRawScans: ScanRetention.keepsRawScans())
        }
    }

    // MARK: - Guards

    /// A real (non-symlink) directory, directly inside Scans/, with a scan-stamp name.
    private func isOwnedScanDirectory(_ url: URL) -> Bool {
        guard let root = try? scansRoot() else { return false }
        let parent = url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        return parent.path == root.standardizedFileURL.resolvingSymlinksInPath().path
            && isScanDirectoryEntry(url)
    }

    private func isScanDirectoryEntry(_ url: URL) -> Bool {
        guard Self.isScanDirectoryName(url.lastPathComponent),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}
