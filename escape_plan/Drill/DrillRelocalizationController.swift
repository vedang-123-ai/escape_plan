import Foundation
import simd
#if canImport(RoomPlan)
import RoomPlan
#endif
import Combine
import SwiftUI

@available(iOS 17.0, *)
@Observable
final class DrillRelocalizationController: NSObject {
    enum State: Equatable {
        case scanning
        case analyzing
        case localized(roomId: String, transform: simd_float4x4)
        case failed(reason: String)
    }
    
    var state: State = .scanning
    let homeModel: HomeModel
    
    private let matcher = SemanticMatcher()
    
#if canImport(RoomPlan)
    var captureSession: RoomCaptureSession?
    private var scanTask: Task<Void, Never>?
    private var latestRoom: CapturedRoom?
#endif

    init(homeModel: HomeModel) {
        self.homeModel = homeModel
        super.init()
    }
    
#if canImport(RoomPlan)
    func startScan(with session: RoomCaptureSession) {
        state = .scanning
        latestRoom = nil
        self.captureSession = session
        session.delegate = self
        
        let config = RoomCaptureSession.Configuration()
        session.run(configuration: config)
        
        startTimer()
    }
    
    func retryScan() {
        if let session = self.captureSession {
            startScan(with: session)
        } else {
            state = .failed(reason: "Camera not ready.")
        }
    }
    
    private func startTimer() {
        scanTask?.cancel()
        scanTask = Task { @MainActor [weak self] in
            // Max 8 seconds before giving up and failing, per user requirement.
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self = self else { return }
            if !Task.isCancelled {
                if self.state == .scanning || self.state == .analyzing {
                    self.captureSession?.stop()
                    // Force a final evaluation
                    if let room = self.latestRoom {
                        let result = self.matcher.match(liveRoom: room, against: self.homeModel)
                        switch result {
                        case .match(let matrix, let roomId):
                            self.state = .localized(roomId: roomId, transform: matrix)
                        default:
                            self.state = .failed(reason: "Could not find a match within 8 seconds. Try again.")
                        }
                    } else {
                        self.state = .failed(reason: "Could not scan the room. Try again.")
                    }
                }
            }
        }
    }
#else
    func startScan() {
        state = .failed(reason: "RoomPlan is not supported on this device.")
    }
    
    func retryScan() {}
#endif
    
    func stopScan() {
#if canImport(RoomPlan)
        scanTask?.cancel()
        captureSession?.stop()
        captureSession = nil
#endif
    }
    
#if canImport(RoomPlan)
    private func evaluate(room: CapturedRoom) {
        if case .localized = state { return }
        if case .failed = state { return }
        
        state = .analyzing
        let result = matcher.match(liveRoom: room, against: homeModel)
        
        switch result {
        case .match(let matrix, let roomId):
            self.stopScan()
            self.state = .localized(roomId: roomId, transform: matrix)
        case .ambiguous(let ids):
            // Could prompt the user, but for now fallback to try again
            self.stopScan()
            self.state = .failed(reason: "Room is ambiguous: \(ids.joined(separator: ", ")). Try again.")
        case .noMatch:
            // Keep scanning
            self.state = .scanning
        }
    }
#endif
}

#if canImport(RoomPlan)
@available(iOS 17.0, *)
extension DrillRelocalizationController: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        DispatchQueue.main.async {
            self.latestRoom = room
            self.evaluate(room: room)
        }
    }
    
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.state = .failed(reason: error.localizedDescription)
            }
        }
    }
}
#endif
