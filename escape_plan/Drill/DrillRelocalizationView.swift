import SwiftUI
#if canImport(RoomPlan)
import RoomPlan
#endif

@available(iOS 17.0, *)
struct DrillRoomCaptureViewRepresentable: UIViewRepresentable {
    let onSessionAvailable: (Any) -> Void
    
#if canImport(RoomPlan)
    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        // Disable default coaching if we want our own text, but default might be fine
        // view.isCoachingEnabled = false 
        DispatchQueue.main.async {
            onSessionAvailable(view.captureSession)
        }
        return view
    }
    
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
    }
#else
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
#endif
}

@available(iOS 17.0, *)
struct DrillRelocalizationView: View {
    @State private var controller: DrillRelocalizationController
    @Environment(\.dismiss) private var dismiss
    
    let homeModel: HomeModel
    let routePlan: RoutePlan
    let profileID: String
    
    init(homeModel: HomeModel, routePlan: RoutePlan, profileID: String) {
        self.homeModel = homeModel
        self.routePlan = routePlan
        self.profileID = profileID
        _controller = State(initialValue: DrillRelocalizationController(homeModel: homeModel))
    }
    
    public var body: some View {
        ZStack {
            if case .localized(_, let transform) = controller.state {
                ARDrillView(transform: transform, homeModel: homeModel, routePlan: routePlan, profileID: profileID)
            } else {
                Color.black.ignoresSafeArea()
                
                DrillRoomCaptureViewRepresentable { session in
#if canImport(RoomPlan)
                    if let roomSession = session as? RoomCaptureSession {
                        controller.startScan(with: roomSession)
                    }
#endif
                }
                .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    // Instructions / Status Panel
                    VStack(spacing: 16) {
                        switch controller.state {
                        case .scanning, .analyzing:
                            Text("Pan your phone around the room to find your location.")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white)
                            
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            
                        case .failed(let reason):
                            Text("Match Failed")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            Text(reason)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white)
                            
                            Button {
                                controller.retryScan()
                            } label: {
                                Text("Try Again")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            
                        case .localized:
                            EmptyView()
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(16)
                    .padding()
                }
            }
        }
        .onDisappear {
            controller.stopScan()
        }
    }
}

