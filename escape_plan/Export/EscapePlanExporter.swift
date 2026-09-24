//  EscapePlanExporter.swift
//  escape_plan — Export module
//
//  Assembles the printable plan from what is on disk and writes it to a share-ready file.
//
//  FULLY OFFLINE BY CONSTRUCTION: it reads the home from `HomeDocumentStore` and the routes
//  from `RoutePlanCache` (S4.1's last-good `/routes` response). It has no `APIClient` and
//  cannot make a request, so "export while offline" is not a code path that might regress —
//  it is the only code path there is. A home with nothing cached exports its geometry and
//  says so on the page.

import Foundation

enum EscapePlanExportError: LocalizedError {
    case homeUnavailable(underlying: String)

    var errorDescription: String? {
        switch self {
        case .homeUnavailable(let underlying):
            return "Couldn't read this home from your device. \(underlying)"
        }
    }
}

struct EscapePlanExporter {
    let store: HomeDocumentStore
    /// Nil only if the cache directory can't be created; then routes are simply unavailable.
    let routeCache: RoutePlanCache?
    let meetingPoints: MeetingPointStore

    init(store: HomeDocumentStore,
         routeCache: RoutePlanCache? = try? RoutePlanCache(),
         meetingPoints: MeetingPointStore = MeetingPointStore()) {
        self.store = store
        self.routeCache = routeCache
        self.meetingPoints = meetingPoints
    }

    /// What the export sheet needs to describe the printout before generating it.
    struct Preview {
        var home: HomeModel
        var plan: RoutePlan?
        var routesComputedAt: Date?
        var meetingPoint: String

        var floorCount: Int { home.floors.count }
        var peopleCount: Int { home.profiles.count }
        var hasRoutes: Bool { plan != nil }
    }

    func preview(homeID: String) throws -> Preview {
        let home: HomeModel
        do {
            home = try store.load(homeID: homeID, as: HomeModel.self)
        } catch {
            throw EscapePlanExportError.homeUnavailable(
                underlying: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
        let cached = routeCache?.load(homeID: homeID)
        return Preview(home: home,
                       plan: cached?.plan,
                       routesComputedAt: cached?.savedAt,
                       meetingPoint: meetingPoints.meetingPoint(forHomeID: homeID))
    }

    /// Renders the PDF and writes it to a temp file named after the home, ready to hand to
    /// the share sheet (Save to Files, Print, AirDrop, Mail).
    func writePDF(preview: Preview,
                  meetingPoint: String,
                  now: Date = Date(),
                  fileManager: FileManager = .default) throws -> URL {
        let document = EscapePlanDocument(home: preview.home,
                                          plan: preview.plan,
                                          routesComputedAt: preview.routesComputedAt,
                                          meetingPoint: meetingPoint,
                                          generatedAt: now)
        let output = EscapePlanPDF.render(document)
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("EscapePlanExports", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.filename(for: preview.home.name))
        try output.data.write(to: url, options: Data.WritingOptions.atomic)
        return url
    }

    /// "Willow Street House escape plan.pdf" — what the share sheet shows and what lands in
    /// Files. Filesystem-hostile characters are replaced, not dropped, so two homes whose
    /// names differ only in punctuation don't collide.
    static func filename(for homeName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(homeName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "Home" : cleaned
        return "\(base) escape plan.pdf"
    }

    /// Renders the Responder Snapshot (PDF + JSON) and writes it to disk. `consent` is the
    /// decision the resident made on THIS share (see `ConsentSheet`) — required, not
    /// defaulted, so a caller cannot generate a snapshot without going through consent.
    func writeResponderSnapshot(preview: Preview,
                                consent: SnapshotConsentDecision,
                                now: Date = Date(),
                                fileManager: FileManager = .default) throws -> [URL] {
        var document = EscapePlanDocument(home: preview.home,
                                          plan: preview.plan,
                                          routesComputedAt: preview.routesComputedAt,
                                          meetingPoint: "",
                                          generatedAt: now)
        document.isResponderSnapshot = true
        if let cache = try? ScoreCache() {
            document.scoreResponse = cache.load(homeID: preview.home.id)
        }

        // Generate PDF
        let output = EscapePlanPDF.render(document)
        let directory = ResponderSnapshotStore(fileManager: fileManager).snapshotDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        
        let pdfURL = directory.appendingPathComponent("ResponderSnapshot.pdf")
        try output.data.write(to: pdfURL, options: Data.WritingOptions.atomic)

        // Generate JSON
        let jsonPayload = ResponderSnapshotExtractor.extract(from: document, consent: consent)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(jsonPayload)
        
        let jsonURL = directory.appendingPathComponent("ResponderSnapshot.json")
        try jsonData.write(to: jsonURL, options: Data.WritingOptions.atomic)

        return [pdfURL, jsonURL]
    }
}
