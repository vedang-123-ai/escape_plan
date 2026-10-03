// APIClient+Convert.swift
// POST /convert (S1.5) — the missing half of the Capture module. `Capture/` has always been
// able to produce a raw RoomPlan export on disk; nothing ever uploaded it. This is the link
// between `ScanArtifacts.rawJSON` and a real HomeModel the editor can open.
//
// The scan body is carried as `JSONValue` rather than a typed struct on purpose: the raw
// export format is the converter's contract (backend/app/convert/README.md), and re-declaring
// it in Swift would create a second copy that drifts. The app's job is to hand the bytes over
// untouched — the backend is the only thing that interprets them.

import Foundation

extension APIClient {
    /// Uploads a raw RoomPlan export and returns the converted `HomeModel`.
    ///
    /// Conversion is entirely server-side (S1.5's pure converter). Low-confidence
    /// scan-derived items come back carrying `source` + `confidence` so the editor can flag
    /// them for review — they are never dropped here, per the schema invariant.
    ///
    /// - Parameters:
    ///   - scanFileURL: `ScanArtifacts.rawJSON` — the converter-facing export, not Apple's
    ///     diagnostic `appleRawJSON`.
    ///   - homeName: name for the resulting home; the backend defaults to "Scanned Home".
    func convertScan(at scanFileURL: URL, homeName: String) async throws -> HomeModel {
        let scanData = try Data(contentsOf: scanFileURL)
        let scan = try HomeModel.decoder.decode(JSONValue.self, from: scanData)

        var request = try authenticatedRequest(path: "convert", method: "POST")
        request.httpBody = try HomeModel.encoder().encode(
            ConvertRequest(scan: scan, home_name: homeName)
        )
        // A scan upload is usually the first request after the phone has been busy scanning
        // for minutes, i.e. against a Render instance that has gone back to sleep. 90 s
        // matches /routes rather than URLSession's 60 s default.
        request.timeoutInterval = 90

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse(statusCode: -1)
        }
        // 422 is the backend's "this export could not be converted" — a real, expected
        // outcome for a partial or malformed scan, not a bug. Surfaced to the caller as the
        // status code so the scan flow can offer a rescan rather than a generic failure.
        guard http.statusCode == 200 else {
            throw APIClientError.unexpectedResponse(statusCode: http.statusCode)
        }
        return try HomeModel.decoder.decode(HomeModel.self, from: data)
    }
}

/// Mirrors `ConvertRequest` in backend/app/main.py (`extra="forbid"` — do not add fields
/// here without adding them there).
private struct ConvertRequest: Encodable {
    let scan: JSONValue
    let home_name: String
}

// `Obstruction`, `DiffRequest`, `DiffResult` and `diffObstructions` (POST /diff_obstructions) left
// with the re-scan review, cut from the demo app 2026-10-02. The backend route is still deployed.
