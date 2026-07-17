//
//  RoomCaptureController.swift
//  Capture — S1.4
//
//  Owns the RoomPlan session lifecycle and drives the scan UI's state machine.
//
//  Multi-room strategy (playbook S1.4): continuous multi-room capture, merged
//  through the iOS 17+ `StructureBuilder` → `CapturedStructure` API. Each room is
//  captured by a run/stop cycle on a single `RoomCaptureSession`; stopping with
//  `pauseARSession: false` keeps ARKit's world tracking alive across rooms, which
//  is what lets the merge line rooms up as the user walks the house.
//
//  Fallback (documented in docs/decisions.md): if StructureBuilder is
//  unavailable or throws, the captured rooms are exported unmerged with
//  `capture.mode = "sequentialRooms"`. The wire format is identical, so S1.5's
//  converter still ingests it — it just has to pair shared doors geometrically
//  rather than by identifier.
//

import Foundation
import Observation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(RoomPlan)
import RoomPlan
#endif

/// Where the user is in the scan flow.
enum ScanPhase: Equatable {
    /// Pre-flight instructions (lighting, slow pans, doors open).
    case instructions
    /// Actively scanning a room.
    case scanning
    /// A room finished; user chooses to add another or finish.
    case roomFinished
    /// Merging + writing artifacts.
    case processing
    /// Done — artifacts on disk.
    case finished(ScanArtifacts)
    /// Failed; `retry()` returns to instructions without losing prior rooms.
    case failed(String)
}

@MainActor
@Observable
final class RoomCaptureController {

    private(set) var phase: ScanPhase = .instructions
    /// Rooms captured so far this session (one per run/stop cycle).
    private(set) var capturedRoomCount: Int = 0
    /// Set when the merged-structure path fell back; surfaced in the UI and
    /// recorded in the export's `capture.fallbackReason`.
    private(set) var fallbackReason: String?

    private let store: ScanStore
    private let scanID = UUID()
    /// Injected so tests and previews aren't bound to the wall clock.
    private var now: () -> Date

    #if canImport(RoomPlan)
    @ObservationIgnored
    private var capturedRooms: [CapturedRoom] = []
    /// Retained so the SwiftUI representable and the controller share one session.
    /// Not observed: it's a UIKit view whose identity must never change mid-scan
    /// (RoomPlan binds the AR session to it), and `lazy` is incompatible with the
    /// @Observable macro's generated accessors.
    @ObservationIgnored
    private(set) lazy var roomCaptureView: RoomCaptureView = RoomCaptureView(frame: .zero)
    @ObservationIgnored
    private var delegateBox: CaptureDelegateBox?
    #endif

    init(store: ScanStore = ScanStore(), now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// False on Simulator and on any device without LiDAR — the UI must say so
    /// rather than presenting a scanner that can never start.
    var isSupported: Bool {
        #if canImport(RoomPlan) && !targetEnvironment(simulator)
        return RoomCaptureSession.isSupported
        #else
        return false
        #endif
    }

    // MARK: - Session control

    func startScanningRoom() {
        #if canImport(RoomPlan) && !targetEnvironment(simulator)
        guard isSupported else {
            phase = .failed("This device doesn't have the LiDAR sensor RoomPlan needs.")
            return
        }
        installDelegateIfNeeded()
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        roomCaptureView.captureSession.run(configuration: configuration)
        phase = .scanning
        #else
        phase = .failed("Scanning requires a LiDAR-equipped device.")
        #endif
    }

    /// Finish the current room. Keeps ARKit tracking alive so the next room
    /// shares a world origin — the precondition for a coherent merge.
    func finishCurrentRoom() {
        #if canImport(RoomPlan) && !targetEnvironment(simulator)
        roomCaptureView.captureSession.stop(pauseARSession: false)
        phase = .processing
        #endif
    }

    /// Finish the whole scan: stop the session and fully release ARKit.
    func finishScan() {
        #if canImport(RoomPlan) && !targetEnvironment(simulator)
        roomCaptureView.captureSession.stop(pauseARSession: true)
        phase = .processing
        #endif
    }

    /// Return to instructions after a failure. Previously captured rooms are
    /// intentionally kept — a mid-house failure shouldn't cost the user the
    /// rooms they already walked.
    func retry() {
        fallbackReason = nil
        phase = .instructions
    }

    /// Discard everything and start over.
    func reset() {
        #if canImport(RoomPlan)
        capturedRooms.removeAll()
        #endif
        capturedRoomCount = 0
        fallbackReason = nil
        phase = .instructions
    }

    // MARK: - Room accumulation

    #if canImport(RoomPlan)
    private func installDelegateIfNeeded() {
        guard delegateBox == nil else { return }
        let box = CaptureDelegateBox(controller: self)
        delegateBox = box
        roomCaptureView.captureSession.delegate = box
    }

    /// Called by the delegate when RoomPlan finishes processing a room.
    fileprivate func handleRoomCaptureEnd(room: CapturedRoom?, error: Error?) {
        if let error {
            phase = .failed(Self.userFacingMessage(for: error))
            return
        }
        guard let room else {
            phase = .failed(ScanStoreError.noRoomsCaptured.localizedDescription)
            return
        }
        capturedRooms.append(room)
        capturedRoomCount = capturedRooms.count
        phase = .roomFinished
    }

    /// Merge everything captured so far and write it to disk.
    func exportScan() async {
        phase = .processing
        guard !capturedRooms.isEmpty else {
            phase = .failed(ScanStoreError.noRoomsCaptured.localizedDescription)
            return
        }

        let (structure, mode, reason, appleEncodable) = await buildStructure()
        self.fallbackReason = reason

        do {
            let exportedAt = now()
            let export = ScanExportBuilder.makeExport(
                from: structure,
                mode: mode,
                exportedAt: exportedAt,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                deviceModel: Self.deviceModelIdentifier(),
                fallbackReason: reason
            )
            let directory = try store.makeScanDirectory(exportedAt: exportedAt, scanID: scanID)
            let rawJSON = try store.writeRawJSON(export, to: directory)
            let appleRaw = appleEncodable.flatMap { store.writeAppleRawJSON($0, to: directory) }
            let usdz = await exportUSDZ(to: directory)

            phase = .finished(ScanArtifacts(
                directory: directory,
                rawJSON: rawJSON,
                appleRawJSON: appleRaw,
                usdz: usdz,
                roomCount: export.rooms.count,
                exportedAt: exportedAt
            ))
        } catch {
            phase = .failed(Self.userFacingMessage(for: error))
        }
    }

    /// Merged structure when we can get one, unmerged rooms when we can't.
    private func buildStructure() async
        -> (any ScanStructureConvertible, RawScanCaptureMode, String?, (any Encodable)?) {
        let rooms = capturedRooms
        if #available(iOS 17.0, *) {
            do {
                let builder = StructureBuilder(options: [.beautifyObjects])
                let structure = try await builder.capturedStructure(from: rooms)
                return (structure, .mergedStructure, nil, structure)
            } catch {
                // Not fatal: the playbook's documented fallback. S1.5 merges.
                let reason = "StructureBuilder merge failed (\(error.localizedDescription)); "
                    + "exported \(rooms.count) unmerged room(s)."
                print("[RoomCaptureController] \(reason)")
                return (CapturedRoomCollection(rooms: rooms), .sequentialRooms, reason, rooms)
            }
        }
        let reason = "StructureBuilder needs iOS 17; exported \(rooms.count) unmerged room(s)."
        return (CapturedRoomCollection(rooms: rooms), .sequentialRooms, reason, rooms)
    }

    /// Best-effort USDZ. A failed USDZ must not cost the user the JSON.
    private func exportUSDZ(to directory: URL) async -> URL? {
        let url = directory.appendingPathComponent("scan.usdz")
        do {
            if #available(iOS 17.0, *) {
                let builder = StructureBuilder(options: [.beautifyObjects])
                let structure = try await builder.capturedStructure(from: capturedRooms)
                try structure.export(to: url, exportOptions: .parametric)
            } else {
                guard let room = capturedRooms.first else { return nil }
                try room.export(to: url, exportOptions: .parametric)
            }
            return url
        } catch {
            print("[RoomCaptureController] USDZ export failed: \(error)")
            return nil
        }
    }
    #else
    func exportScan() async {
        phase = .failed("Scanning requires a LiDAR-equipped device.")
    }
    #endif

    // MARK: - Helpers

    static func userFacingMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "The scan couldn't be completed: \(error.localizedDescription)"
    }

    static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier += String(UnicodeScalar(UInt8(value)))
        }
    }
}

#if canImport(RoomPlan)
/// RoomPlan's delegate is a class-bound ObjC-style protocol; the controller is a
/// @MainActor @Observable class, so the delegate lives in its own box that hops
/// back to the main actor.
private final class CaptureDelegateBox: NSObject, RoomCaptureSessionDelegate {
    weak var controller: RoomCaptureController?

    init(controller: RoomCaptureController) {
        self.controller = controller
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData,
                        error: Error?) {
        if let error {
            Task { @MainActor [weak controller] in
                controller?.handleRoomCaptureEnd(room: nil, error: error)
            }
            return
        }
        // RoomPlan hands back raw data; turn it into a CapturedRoom off the main
        // actor, then report the result back on it.
        Task { @MainActor [weak controller] in
            do {
                let room = try await RoomBuilder(options: [.beautifyObjects])
                    .capturedRoom(from: data)
                controller?.handleRoomCaptureEnd(room: room, error: nil)
            } catch {
                controller?.handleRoomCaptureEnd(room: nil, error: error)
            }
        }
    }

    func captureSession(_ session: RoomCaptureSession,
                        didFailWith error: Error) {
        Task { @MainActor [weak controller] in
            controller?.handleRoomCaptureEnd(room: nil, error: error)
        }
    }
}
#endif
