import SwiftUI
import ARKit
import SceneKit
import Combine

@available(iOS 17.0, *)
struct ARDrillViewRepresentable: UIViewRepresentable {
    let transform: simd_float4x4
    let homeModel: HomeModel
    let routePlan: RoutePlan
    let profileID: String
    let onDrillComplete: (TimeInterval) -> Void
    
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        view.session.run(config)
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.autoenablesDefaultLighting = true
        
        let rootNode = SCNNode()
        // `transform` maps AR device space to HomeModel space.
        // We want to place HomeModel coordinates into AR space, so we use `transform.inverse`.
        rootNode.simdTransform = transform.inverse
        view.scene.rootNode.addChildNode(rootNode)
        
        context.coordinator.containerNode = rootNode
        context.coordinator.drawWaypoints(in: rootNode, plan: routePlan, profileID: profileID, homeModel: homeModel)
        
        return view
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        let parent: ARDrillViewRepresentable
        var containerNode: SCNNode?
        var exitPosition: SIMD3<Float>?
        var startTime: Date = Date()
        var completed = false
        
        init(_ parent: ARDrillViewRepresentable) {
            self.parent = parent
        }
        
        /// How far above its own floor a waypoint sphere floats, in metres. Chest height, so
        /// the markers read as signposts rather than as things on the ground.
        static let waypointHoverHeight = 1.0

        func drawWaypoints(in node: SCNNode, plan: RoutePlan, profileID: String, homeModel: HomeModel) {
            guard let profile = homeModel.profiles.first(where: { $0.id == profileID }) else { return }
            guard let room = plan.rooms.first(where: { $0.room_id == profile.bedroom_room_id }) else { return }
            guard let primary = room.primary else { return }

            // Waypoints are FLOOR-LOCAL: `Waypoint` carries x/y in plan metres plus the
            // `floor_id` they belong to, and the type's own doc comment says "height comes from
            // the floor". Until 2026-09-16 this drew every one at a hardcoded 1.0 m, so on
            // `twostory` — a core fixture — a route from an upstairs bedroom down to the front
            // door drew both legs at the same height, and a user standing upstairs saw the
            // ground-floor leg floating at eye level.
            //
            // `DollhouseGeometry.floorBaseHeights` is the SAME stacking the dollhouse uses to
            // place its floors, reused rather than reimplemented: two formulas for where a
            // floor sits would eventually disagree, and the AR view and the 3D view would show
            // the same route at two different heights.
            let floorBases = DollhouseGeometry.floorBaseHeights(of: homeModel)

            // Draw waypoints
            for (index, wp) in primary.waypoints.enumerated() {
                // Floating semi-transparent waypoints
                let sphere = SCNSphere(radius: 0.15)
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.blue.withAlphaComponent(0.6)
                material.emission.contents = UIColor.blue.withAlphaComponent(0.4)
                sphere.materials = [material]
                
                let wpNode = SCNNode(geometry: sphere)
                // An unknown floor_id falls back to 0 rather than being skipped: a waypoint
                // drawn on the ground floor is wrong, but a missing one breaks the path the
                // user is following.
                let y = Float((floorBases[wp.floor_id] ?? 0) + Self.waypointHoverHeight)
                wpNode.position = SCNVector3(Float(wp.x), y, Float(wp.y))
                node.addChildNode(wpNode)
                
                // Track the last waypoint as the exit
                if index == primary.waypoints.count - 1 {
                    exitPosition = SIMD3<Float>(Float(wp.x), y, Float(wp.y))
                    
                    // Make the exit node more distinct
                    material.diffuse.contents = UIColor.green.withAlphaComponent(0.7)
                    material.emission.contents = UIColor.green.withAlphaComponent(0.5)
                    let pulse = CABasicAnimation(keyPath: "opacity")
                    pulse.fromValue = 1.0
                    pulse.toValue = 0.3
                    pulse.duration = 1.0
                    pulse.autoreverses = true
                    pulse.repeatCount = .infinity
                    wpNode.addAnimation(pulse, forKey: "pulse")
                }
            }
        }
        
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard !completed, let exitPos = exitPosition, let view = renderer as? ARSCNView else { return }
            guard let cameraTransform = view.session.currentFrame?.camera.transform else { return }
            
            let cameraPos = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
            
            if let container = containerNode {
                let worldExitPos = container.simdConvertPosition(exitPos, to: nil)
                let distance = simd_distance(cameraPos, worldExitPos)
                
                // User requested 1.5 meters threshold
                if distance < 1.5 {
                    completed = true
                    let elapsed = Date().timeIntervalSince(startTime)
                    DispatchQueue.main.async {
                        self.parent.onDrillComplete(elapsed)
                    }
                }
            }
        }
    }
}

@available(iOS 17.0, *)
struct ARDrillView: View {
    let transform: simd_float4x4
    let homeModel: HomeModel
    let routePlan: RoutePlan
    let profileID: String
    
    @State private var drillComplete = false
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    
    init(transform: simd_float4x4, homeModel: HomeModel, routePlan: RoutePlan, profileID: String) {
        self.transform = transform
        self.homeModel = homeModel
        self.routePlan = routePlan
        self.profileID = profileID
    }
    
    public var body: some View {
        ZStack {
            ARDrillViewRepresentable(
                transform: transform,
                homeModel: homeModel,
                routePlan: routePlan,
                profileID: profileID
            ) { elapsed in
                self.elapsedSeconds = elapsed
                self.recordDrill()
                self.drillComplete = true
            }
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                if drillComplete {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.green)
                        
                        Text("Drill Complete!")
                            .font(.title)
                            .bold()
                            .foregroundColor(.white)
                        
                        Text("Time: \(String(format: "%.1f", elapsedSeconds))s")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        if let err = saveError {
                            Text("Error saving log: \(err)")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Finish")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(16)
                    .padding()
                } else {
                    VStack {
                        Text("Follow the waypoints to the exit")
                            .font(.headline)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding()
                }
            }
        }
    }
    
    private func recordDrill() {
        guard let profile = homeModel.profiles.first(where: { $0.id == profileID }) else { return }
        guard let room = homeModel.locateRoom(profile.bedroom_room_id) else { return }
        
        do {
            let logStore = try DrillLogStore()
            let record = DrillRecord(
                homeID: homeModel.home_id,
                roomID: room.room.id,
                roomName: room.room.name,
                profileID: profile.id,
                profileName: profile.name,
                startedAt: Date().addingTimeInterval(-elapsedSeconds),
                elapsedSeconds: elapsedSeconds,
                outcome: .completed,
                modeledEgressSeconds: nil
            )
            try logStore.append(record)
        } catch {
            self.saveError = error.localizedDescription
        }
    }
}
