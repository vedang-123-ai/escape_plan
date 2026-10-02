//  HouseEditorSessionController.swift — S11.19, AUD-013: the House editor's load/save lifecycle.
//
//  The House tab keeps its editor session alive across tab switches, and other writers change the
//  same home file while it is away: the onboarding interview, the re-scan "Add to Home", sync pulls,
//  Profiles. Before this type, House loaded the home once and every autosave wrote its in-memory copy
//  over whatever was on disk, so those writes were silently lost.
//
//  The rule this type enforces: the session remembers the fingerprint of the file as it last read or
//  wrote it, and never writes over a file that has changed since. A changed file is handed back to the
//  screen to reload instead (the undo history goes with it — its snapshots describe the old document).
//  A file that disappeared closes the session, and nothing here will create it again.
//
//  Pure Foundation: compiled into tools/editorcore, so it reaches disk only through
//  `HouseEditorDocumentAccess` (the app's `HomeDocumentStore` conforms), never by naming the store.

import Foundation

/// The three disk operations the House session needs. `HomeDocumentStore` conforms in the app;
/// tests use an in-memory fake.
protocol HouseEditorDocumentAccess {
    func homeFileExists(_ homeID: String) -> Bool
    func loadHome(_ homeID: String) throws -> HomeModel
    func saveHome(_ home: HomeModel) throws
}

/// How the rest of the app learns that House holds a home: `HomeLibrary.editor` and sync's
/// `openHomeID`, so a sync pull never writes the file House is about to autosave into. The app's
/// conformer lives in Screens/; tests record the calls.
@MainActor
protocol HouseEditorRegistration: AnyObject {
    func registerOpenHome(_ homeID: String)
    /// Must clear only what still names this session's home: two editors can overlap across a
    /// tab switch, and clearing unconditionally would unlock a home the other one holds.
    func unregisterOpenHome(_ homeID: String)
}

@MainActor
final class HouseEditorSessionController {

    /// What `checkDisk()` found, compared with what this session last read or wrote.
    enum DiskState: Equatable {
        /// The file is what this session last saw (or a brand-new home has not been written yet).
        case current
        /// Someone else wrote the file. Reload this model and drop the undo history.
        case changed(HomeModel)
        /// The file is gone. The session is closed for good.
        case deleted
        /// The file exists but cannot be read. Leave it alone; never write over it.
        case unreadable(String)
    }

    enum SaveOutcome: Equatable {
        case saved
        /// The file changed underneath the session, so it was NOT written. Reload this model.
        case reloaded(HomeModel)
        /// The file is gone, so it was NOT written (and never will be by this session).
        case deleted
        case failed(String)
    }

    let homeID: String
    private let disk: HouseEditorDocumentAccess

    /// `HomeFingerprint` of the file as this session last read or wrote it. Nil only for a brand-new
    /// home that has never been on disk; once set it is never cleared, which is how a missing file
    /// is told apart from a home that was simply not saved yet.
    private(set) var knownFingerprint: String?

    /// Set once the home file is found missing. A closed session never saves again.
    private(set) var isClosed = false

    /// Told on every appear and disappear. Set by the screen once its session exists.
    var registration: HouseEditorRegistration?

    init(homeID: String, disk: HouseEditorDocumentAccess) {
        self.homeID = homeID
        self.disk = disk
    }

    /// Reads the home and remembers its fingerprint. Nil when there is no file yet, so the caller
    /// starts a blank home (whose first save creates the file).
    func open() throws -> HomeModel? {
        guard disk.homeFileExists(homeID) else { return nil }
        let home = try disk.loadHome(homeID)
        knownFingerprint = HomeFingerprint.of(home)
        return home
    }

    /// The screen became visible (first load, or back from another tab). Re-arms the open-home
    /// guard BEFORE reading the file, so no sync pull can land between the check and the guard;
    /// then reports whether the file changed while the screen was away.
    ///
    /// Before S11.19 the guard was set once at load and cleared on every disappear, so after the
    /// first tab switch sync was free to write the home House still held.
    func appear() -> DiskState {
        guard !isClosed else { return .deleted }
        registration?.registerOpenHome(homeID)
        return checkDisk()
    }

    /// The screen left (a tab switch). Lifts the guard so sync may write a pulled copy; the next
    /// `appear()` notices it.
    func disappear() {
        registration?.unregisterOpenHome(homeID)
    }

    /// Compares the file with what this session last saw. A changed file is adopted as the new
    /// baseline, so the caller must reload the returned model; a missing one closes the session.
    func checkDisk() -> DiskState {
        if isClosed { return .deleted }
        guard disk.homeFileExists(homeID) else {
            // Never on disk is a new home waiting for its first save. Seen on disk and now gone
            // means someone deleted it.
            if knownFingerprint == nil { return .current }
            isClosed = true
            registration?.unregisterOpenHome(homeID)
            return .deleted
        }
        let home: HomeModel
        do {
            home = try disk.loadHome(homeID)
        } catch {
            return .unreadable(String(describing: error))
        }
        let fingerprint = HomeFingerprint.of(home)
        if fingerprint == knownFingerprint { return .current }
        knownFingerprint = fingerprint
        return .changed(home)
    }

    /// Writes `home` only if the file is still what this session last saw.
    func save(_ home: HomeModel) -> SaveOutcome {
        switch checkDisk() {
        case .current:
            break
        case .changed(let newer):
            return .reloaded(newer)
        case .deleted:
            return .deleted
        case .unreadable(let reason):
            return .failed(reason)
        }
        do {
            try disk.saveHome(home)
            // Fingerprint what actually landed, not `home`: the store stamps `meta.modified` on
            // save, so the file differs from the in-memory model it was written from.
            knownFingerprint = HomeFingerprint.of(try disk.loadHome(homeID))
            return .saved
        } catch {
            return .failed(String(describing: error))
        }
    }
}
