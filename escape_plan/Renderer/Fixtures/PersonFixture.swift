//  PersonFixture.swift
//  Renderer/Fixtures — procedural, articulated household figures.
//
//  Figures stay inside the White Model vocabulary: their identity is silhouette, scale and
//  articulation rather than skin, clothing or texture.  The selected figure keeps the same
//  green selection treatment the original static capsule used.  Escape-route and hazard
//  colours remain reserved for their respective overlays.

import SceneKit
import UIKit

nonisolated enum PersonFixture {

    /// The legacy adult height, retained for callers that position UI relative to a person.
    static let heightM = 1.5

    /// Renderer-local morphology.  This deliberately does not depend on `GaitKind`: the
    /// playback layer can map any current or future model gait onto a stable figure vocabulary.
    enum FigureKind: CaseIterable {
        case adult
        case child
        case elderly
        case wheelchair
        case pet
    }

    /// A rotation in radians.  Pitch is local x, yaw local y and roll local z.
    ///
    /// All authored figures face local +z.  Positive yaw therefore turns their forward axis
    /// toward +x.  Rotations are applied on top of a figure's bind posture, not accumulated.
    struct Rotation: Equatable {
        var pitch: Float
        var yaw: Float
        var roll: Float

        init(pitch: Float = 0, yaw: Float = 0, roll: Float = 0) {
            self.pitch = pitch
            self.yaw = yaw
            self.roll = roll
        }

        static let zero = Rotation()
    }

    /// Renderer-neutral pose input.  A gait implementation only needs to translate its output
    /// into these scalar joint rotations; `PersonFixture` has no dependency on gait math.
    ///
    /// Pet forelegs use the shoulder/elbow/wrist fields and hind legs use hip/knee/ankle.
    /// Wheelchair legs stay in their seated bind posture; only arms and wheels normally move.
    struct Pose: Equatable {
        var verticalOffset: Float = 0
        var pelvis = Rotation.zero
        var spine = Rotation.zero
        var head = Rotation.zero

        var leftShoulder = Rotation.zero
        var rightShoulder = Rotation.zero
        var leftElbow = Rotation.zero
        var rightElbow = Rotation.zero
        var leftWrist = Rotation.zero
        var rightWrist = Rotation.zero

        var leftHip = Rotation.zero
        var rightHip = Rotation.zero
        var leftKnee = Rotation.zero
        var rightKnee = Rotation.zero
        var leftAnkle = Rotation.zero
        var rightAnkle = Rotation.zero

        /// Locomotion-space wheel angles.  Negative values advance the chair along local +z,
        /// matching `GaitCycle`; the rig converts them to SceneKit's local-x axle rotation.
        var leftWheelRotation: Float = 0
        var rightWheelRotation: Float = 0
        var tail = Rotation.zero

        init() {}

        static let neutral = Pose()
    }

    /// Explicit handles for the nodes a locomotion renderer drives.  Core limb handles are
    /// present for every morphology: on a pet they correspond to fore- and hind-leg joints.
    struct JointHandles {
        let pelvis: SCNNode
        let spine: SCNNode
        let head: SCNNode

        let leftShoulder: SCNNode
        let rightShoulder: SCNNode
        let leftElbow: SCNNode
        let rightElbow: SCNNode
        let leftWrist: SCNNode
        let rightWrist: SCNNode

        let leftHip: SCNNode
        let rightHip: SCNNode
        let leftKnee: SCNNode
        let rightKnee: SCNNode
        let leftAnkle: SCNNode
        let rightAnkle: SCNNode

        /// Non-nil only for a wheelchair figure.
        let leftWheel: SCNNode?
        /// Non-nil only for a wheelchair figure.
        let rightWheel: SCNNode?
        /// Non-nil only for a pet figure.
        let tail: SCNNode?
    }

    /// A retained articulated figure.  The root node remains the `person:<id>` hit-test owner.
    final class Rig {
        let rootNode: SCNNode
        let kind: FigureKind
        let joints: JointHandles

        fileprivate init(rootNode: SCNNode, kind: FigureKind, joints: JointHandles) {
            self.rootNode = rootNode
            self.kind = kind
            self.joints = joints
        }

        /// Absolute-from-bind pose application, suitable for renderer callbacks and scrubbing.
        func apply(_ pose: Pose) {
            PersonFixture.apply(pose, to: joints)
        }

        func reset() {
            apply(.neutral)
        }
    }

    private static let pillHeight = 0.26

    private enum JointName {
        static let pelvis = "figure.joint.pelvis"
        static let spine = "figure.joint.spine"
        static let head = "figure.joint.head"
        static let leftShoulder = "figure.joint.shoulder.left"
        static let rightShoulder = "figure.joint.shoulder.right"
        static let leftElbow = "figure.joint.elbow.left"
        static let rightElbow = "figure.joint.elbow.right"
        static let leftWrist = "figure.joint.wrist.left"
        static let rightWrist = "figure.joint.wrist.right"
        static let leftHip = "figure.joint.hip.left"
        static let rightHip = "figure.joint.hip.right"
        static let leftKnee = "figure.joint.knee.left"
        static let rightKnee = "figure.joint.knee.right"
        static let leftAnkle = "figure.joint.ankle.left"
        static let rightAnkle = "figure.joint.ankle.right"
        static let leftWheel = "figure.joint.wheel.left"
        static let rightWheel = "figure.joint.wheel.right"
        static let tail = "figure.joint.tail"
    }

    // Geometry is shared by every figure with the same selection state.  Nodes and transforms
    // remain independent, while SceneKit only uploads one copy of each mesh/material family.
    @MainActor
    private static let regularGeometry = GeometrySet(
        material: FixtureStyle.white(DollhousePalette.furnitureWhite)
    )
    @MainActor
    private static let selectedGeometry = GeometrySet(
        material: FixtureStyle.white(DollhousePalette.selectionTint, roughness: 0.55)
    )

    /// Backwards-compatible entry point used by `PeopleLayer`.  New playback code should retain
    /// the `Rig` returned by `makeRig` so it can apply poses without hierarchy lookups.
    @MainActor
    static func node(id: String, name: String, highlighted: Bool,
                     kind: FigureKind = .adult) -> SCNNode {
        makeRig(id: id, name: name, highlighted: highlighted, kind: kind).rootNode
    }

    /// Builds one fully procedural rig.  No third-party meshes, textures or motion data are used.
    @MainActor
    static func makeRig(id: String, name: String, highlighted: Bool,
                        kind: FigureKind = .adult) -> Rig {
        let container = SCNNode()
        container.name = "person:\(id)"

        let geometry = highlighted ? selectedGeometry : regularGeometry
        let handles: JointHandles
        switch kind {
        case .adult, .child, .elderly:
            handles = standingFigure(in: container, geometry: geometry, kind: kind)
        case .wheelchair:
            handles = wheelchairFigure(in: container, geometry: geometry)
        case .pet:
            handles = petFigure(in: container, geometry: geometry)
        }

        container.addChildNode(hitTarget(for: kind))
        container.addChildNode(pill(name: name, highlighted: highlighted,
                                    figureHeight: figureHeight(for: kind)))

        let rig = Rig(rootNode: container, kind: kind, joints: handles)
        rig.reset()
        return rig
    }

    /// Recovers handles from a legacy root node.  Hierarchy lookup is intended for setup only;
    /// retain a `Rig` rather than calling this from the per-frame renderer callback.
    static func jointHandles(in rootNode: SCNNode) -> JointHandles? {
        func required(_ name: String) -> SCNNode? {
            rootNode.childNode(withName: name, recursively: true)
        }

        guard let pelvis = required(JointName.pelvis),
              let spine = required(JointName.spine),
              let head = required(JointName.head),
              let leftShoulder = required(JointName.leftShoulder),
              let rightShoulder = required(JointName.rightShoulder),
              let leftElbow = required(JointName.leftElbow),
              let rightElbow = required(JointName.rightElbow),
              let leftWrist = required(JointName.leftWrist),
              let rightWrist = required(JointName.rightWrist),
              let leftHip = required(JointName.leftHip),
              let rightHip = required(JointName.rightHip),
              let leftKnee = required(JointName.leftKnee),
              let rightKnee = required(JointName.rightKnee),
              let leftAnkle = required(JointName.leftAnkle),
              let rightAnkle = required(JointName.rightAnkle) else {
            return nil
        }

        return JointHandles(
            pelvis: pelvis, spine: spine, head: head,
            leftShoulder: leftShoulder, rightShoulder: rightShoulder,
            leftElbow: leftElbow, rightElbow: rightElbow,
            leftWrist: leftWrist, rightWrist: rightWrist,
            leftHip: leftHip, rightHip: rightHip,
            leftKnee: leftKnee, rightKnee: rightKnee,
            leftAnkle: leftAnkle, rightAnkle: rightAnkle,
            leftWheel: required(JointName.leftWheel),
            rightWheel: required(JointName.rightWheel),
            tail: required(JointName.tail)
        )
    }

    /// Applies a pose to a root returned from the backwards-compatible `node` API.
    /// Returns false when the node is not a PersonFixture hierarchy.
    @discardableResult
    static func apply(_ pose: Pose, to rootNode: SCNNode) -> Bool {
        guard let handles = jointHandles(in: rootNode) else { return false }
        apply(pose, to: handles)
        return true
    }

    private static func apply(_ pose: Pose, to handles: JointHandles) {
        // Pose nodes are zeroed children of bind-pose anchors.  Assigning, rather than adding,
        // makes every timestamp deterministic and prevents drift after reverse scrubbing.
        handles.pelvis.position = SCNVector3(0, pose.verticalOffset, 0)
        set(handles.pelvis, pose.pelvis)
        set(handles.spine, pose.spine)
        set(handles.head, pose.head)
        set(handles.leftShoulder, pose.leftShoulder)
        set(handles.rightShoulder, pose.rightShoulder)
        set(handles.leftElbow, pose.leftElbow)
        set(handles.rightElbow, pose.rightElbow)
        set(handles.leftWrist, pose.leftWrist)
        set(handles.rightWrist, pose.rightWrist)
        if handles.leftWheel == nil {
            set(handles.leftHip, pose.leftHip)
            set(handles.rightHip, pose.rightHip)
            set(handles.leftKnee, pose.leftKnee)
            set(handles.rightKnee, pose.rightKnee)
            set(handles.leftAnkle, pose.leftAnkle)
            set(handles.rightAnkle, pose.rightAnkle)
        } else {
            // A wheelchair is always seated.  Ignore accidental generic leg gait rather than
            // letting a stair/window pose pull the occupant's legs through the chair.
            set(handles.leftHip, .zero)
            set(handles.rightHip, .zero)
            set(handles.leftKnee, .zero)
            set(handles.rightKnee, .zero)
            set(handles.leftAnkle, .zero)
            set(handles.rightAnkle, .zero)
        }
        handles.leftWheel?.eulerAngles = SCNVector3(-pose.leftWheelRotation, 0, 0)
        handles.rightWheel?.eulerAngles = SCNVector3(-pose.rightWheelRotation, 0, 0)
        if let tail = handles.tail { set(tail, pose.tail) }
    }

    private static func set(_ node: SCNNode, _ rotation: Rotation) {
        node.eulerAngles = SCNVector3(rotation.pitch, rotation.yaw, rotation.roll)
    }

    // MARK: - Standing humanoids

    @MainActor
    private static func standingFigure(in container: SCNNode, geometry: GeometrySet,
                                       kind: FigureKind) -> JointHandles {
        let bodyRoot = SCNNode()
        bodyRoot.name = "figure.body"
        switch kind {
        case .child:
            bodyRoot.scale = SCNVector3(0.74, 0.74, 0.74)
        case .elderly:
            bodyRoot.scale = SCNVector3(0.96, 0.96, 0.96)
        default:
            break
        }
        container.addChildNode(bodyRoot)

        let pelvis = joint(in: bodyRoot, name: JointName.pelvis,
                           position: SCNVector3(0, 0.80, 0), geometry: geometry.joint)
        addModel(geometry.pelvis, named: "figure.part.pelvis", to: pelvis,
                 position: SCNVector3(0, 0.04, 0))

        let elderly = kind == .elderly
        let spine = joint(in: pelvis, name: JointName.spine,
                          position: SCNVector3(0, 0.10, 0),
                          bind: Rotation(pitch: elderly ? 0.22 : 0),
                          geometry: geometry.joint)
        addModel(geometry.torso, named: "figure.part.torso", to: spine,
                 position: SCNVector3(0, 0.20, 0))

        let head = joint(in: spine, name: JointName.head,
                         position: SCNVector3(0, 0.47, 0),
                         bind: Rotation(pitch: elderly ? -0.17 : 0),
                         geometry: geometry.joint)
        let headShape = addModel(geometry.head, named: "figure.part.head", to: head)
        if kind == .child {
            // A relatively large head keeps the child silhouette legible after overall scaling.
            headShape.scale = SCNVector3(1.18, 1.18, 1.18)
        }

        let leftShoulder = joint(in: spine, name: JointName.leftShoulder,
                                 position: SCNVector3(0.20, 0.34, 0),
                                 bind: Rotation(pitch: elderly ? -0.07 : 0,
                                                roll: elderly ? 0.05 : 0.09),
                                 geometry: geometry.joint)
        addDownwardSegment(geometry.upperArm, length: 0.30,
                           named: "figure.part.upperArm.left", to: leftShoulder)
        let leftElbow = joint(in: leftShoulder, name: JointName.leftElbow,
                              position: SCNVector3(0, -0.30, 0),
                              bind: Rotation(pitch: elderly ? -0.12 : 0),
                              geometry: geometry.joint)
        addDownwardSegment(geometry.forearm, length: 0.27,
                           named: "figure.part.forearm.left", to: leftElbow)
        let leftWrist = joint(in: leftElbow, name: JointName.leftWrist,
                              position: SCNVector3(0, -0.27, 0), geometry: geometry.joint)
        addModel(geometry.hand, named: "figure.part.hand.left", to: leftWrist,
                 position: SCNVector3(0, -0.025, 0))

        let rightShoulder = joint(in: spine, name: JointName.rightShoulder,
                                  position: SCNVector3(-0.20, 0.34, 0),
                                  bind: Rotation(pitch: elderly ? -0.13 : 0,
                                                 roll: elderly ? -0.04 : -0.09),
                                  geometry: geometry.joint)
        addDownwardSegment(geometry.upperArm, length: 0.30,
                           named: "figure.part.upperArm.right", to: rightShoulder)
        let rightElbow = joint(in: rightShoulder, name: JointName.rightElbow,
                               position: SCNVector3(0, -0.30, 0),
                               bind: Rotation(pitch: elderly ? -0.20 : 0),
                               geometry: geometry.joint)
        addDownwardSegment(geometry.forearm, length: 0.27,
                           named: "figure.part.forearm.right", to: rightElbow)
        let rightWrist = joint(in: rightElbow, name: JointName.rightWrist,
                               position: SCNVector3(0, -0.27, 0), geometry: geometry.joint)
        addModel(geometry.hand, named: "figure.part.hand.right", to: rightWrist,
                 position: SCNVector3(0, -0.025, 0))

        let leftHip = joint(in: pelvis, name: JointName.leftHip,
                            position: SCNVector3(0.10, -0.02, 0),
                            bind: Rotation(pitch: elderly ? 0.07 : 0),
                            geometry: geometry.joint)
        addDownwardSegment(geometry.upperLeg, length: 0.37,
                           named: "figure.part.upperLeg.left", to: leftHip)
        let leftKnee = joint(in: leftHip, name: JointName.leftKnee,
                             position: SCNVector3(0, -0.37, 0),
                             bind: Rotation(pitch: elderly ? -0.13 : 0),
                             geometry: geometry.joint)
        addDownwardSegment(geometry.lowerLeg, length: 0.35,
                           named: "figure.part.lowerLeg.left", to: leftKnee)
        let leftAnkle = joint(in: leftKnee, name: JointName.leftAnkle,
                              position: SCNVector3(0, -0.35, 0), geometry: geometry.joint)
        addModel(geometry.foot, named: "figure.part.foot.left", to: leftAnkle,
                 position: SCNVector3(0, -0.025, 0.065))

        let rightHip = joint(in: pelvis, name: JointName.rightHip,
                             position: SCNVector3(-0.10, -0.02, 0),
                             bind: Rotation(pitch: elderly ? 0.07 : 0),
                             geometry: geometry.joint)
        addDownwardSegment(geometry.upperLeg, length: 0.37,
                           named: "figure.part.upperLeg.right", to: rightHip)
        let rightKnee = joint(in: rightHip, name: JointName.rightKnee,
                              position: SCNVector3(0, -0.37, 0),
                              bind: Rotation(pitch: elderly ? -0.13 : 0),
                              geometry: geometry.joint)
        addDownwardSegment(geometry.lowerLeg, length: 0.35,
                           named: "figure.part.lowerLeg.right", to: rightKnee)
        let rightAnkle = joint(in: rightKnee, name: JointName.rightAnkle,
                               position: SCNVector3(0, -0.35, 0), geometry: geometry.joint)
        addModel(geometry.foot, named: "figure.part.foot.right", to: rightAnkle,
                 position: SCNVector3(0, -0.025, 0.065))

        if elderly {
            addCane(to: bodyRoot, geometry: geometry)
        }

        return JointHandles(
            pelvis: pelvis, spine: spine, head: head,
            leftShoulder: leftShoulder, rightShoulder: rightShoulder,
            leftElbow: leftElbow, rightElbow: rightElbow,
            leftWrist: leftWrist, rightWrist: rightWrist,
            leftHip: leftHip, rightHip: rightHip,
            leftKnee: leftKnee, rightKnee: rightKnee,
            leftAnkle: leftAnkle, rightAnkle: rightAnkle,
            leftWheel: nil, rightWheel: nil, tail: nil
        )
    }

    @MainActor
    private static func addCane(to bodyRoot: SCNNode, geometry: GeometrySet) {
        // The cane is intentionally bold enough to survive the dollhouse camera distance.
        let shaft = addModel(geometry.unitRod, named: "figure.accessory.cane", to: bodyRoot,
                             position: SCNVector3(-0.27, 0.34, 0.08))
        shaft.scale.y = 0.68

        let handle = addModel(geometry.unitRod, named: "figure.accessory.caneHandle",
                              to: bodyRoot, position: SCNVector3(-0.225, 0.67, 0.08),
                              eulerAngles: SCNVector3(0, 0, Float.pi / 2))
        handle.scale.y = 0.10
    }

    // MARK: - Wheelchair

    @MainActor
    private static func wheelchairFigure(in container: SCNNode,
                                          geometry: GeometrySet) -> JointHandles {
        let chair = SCNNode()
        chair.name = "figure.wheelchair"
        container.addChildNode(chair)

        addModel(geometry.chairSeat, named: "figure.wheelchair.seat", to: chair,
                 position: SCNVector3(0, 0.60, 0.02))
        addModel(geometry.chairBack, named: "figure.wheelchair.back", to: chair,
                 position: SCNVector3(0, 0.82, -0.18))

        // Axle and side rails make the chair read even when a wheel is edge-on to the camera.
        let axle = addModel(geometry.unitRod, named: "figure.wheelchair.axle", to: chair,
                            position: SCNVector3(0, 0.33, -0.01),
                            eulerAngles: SCNVector3(0, 0, Float.pi / 2))
        axle.scale.y = 0.68
        addChairRails(to: chair, geometry: geometry)

        let leftWheel = joint(in: chair, name: JointName.leftWheel,
                              position: SCNVector3(0.31, 0.33, -0.01))
        addWheelVisuals(to: leftWheel, geometry: geometry, side: "left")
        let rightWheel = joint(in: chair, name: JointName.rightWheel,
                               position: SCNVector3(-0.31, 0.33, -0.01))
        addWheelVisuals(to: rightWheel, geometry: geometry, side: "right")

        // Small front casters and a broad footrest remove any ambiguity with an ordinary chair.
        for x: Float in [-0.20, 0.20] {
            let caster = addModel(geometry.casterWheel,
                                  named: x < 0 ? "figure.wheelchair.caster.right"
                                               : "figure.wheelchair.caster.left",
                                  to: chair, position: SCNVector3(x, 0.10, 0.34),
                                  eulerAngles: SCNVector3(0, 0, Float.pi / 2))
            caster.castsShadow = true
        }
        addModel(geometry.footrest, named: "figure.wheelchair.footrest", to: chair,
                 position: SCNVector3(0, 0.24, 0.38),
                 eulerAngles: SCNVector3(-0.18, 0, 0))

        let pelvis = joint(in: container, name: JointName.pelvis,
                           position: SCNVector3(0, 0.68, -0.03), geometry: geometry.joint)
        let pelvisShape = addModel(geometry.pelvis, named: "figure.part.pelvis", to: pelvis,
                                   position: SCNVector3(0, 0.025, 0))
        pelvisShape.scale = SCNVector3(0.86, 0.78, 0.86)

        let spine = joint(in: pelvis, name: JointName.spine,
                          position: SCNVector3(0, 0.08, 0),
                          bind: Rotation(pitch: -0.05), geometry: geometry.joint)
        let torso = addModel(geometry.torso, named: "figure.part.torso", to: spine,
                             position: SCNVector3(0, 0.17, 0))
        torso.scale = SCNVector3(0.86, 0.85, 0.86)

        let head = joint(in: spine, name: JointName.head,
                         position: SCNVector3(0, 0.40, 0.01), geometry: geometry.joint)
        let headShape = addModel(geometry.head, named: "figure.part.head", to: head)
        headShape.scale = SCNVector3(0.86, 0.86, 0.86)

        let armLengthScale: Float = 0.84
        let upperArmLength = 0.30 * armLengthScale
        let forearmLength = 0.27 * armLengthScale

        let leftShoulder = joint(in: spine, name: JointName.leftShoulder,
                                 position: SCNVector3(0.17, 0.29, 0),
                                 bind: Rotation(pitch: -0.12, roll: 0.06),
                                 geometry: geometry.joint)
        let leftUpperArm = addDownwardSegment(geometry.upperArm, length: upperArmLength,
                                              named: "figure.part.upperArm.left",
                                              to: leftShoulder)
        leftUpperArm.scale.y = armLengthScale
        let leftElbow = joint(in: leftShoulder, name: JointName.leftElbow,
                              position: SCNVector3(0, -upperArmLength, 0),
                              bind: Rotation(pitch: -0.28), geometry: geometry.joint)
        let leftForearm = addDownwardSegment(geometry.forearm, length: forearmLength,
                                             named: "figure.part.forearm.left", to: leftElbow)
        leftForearm.scale.y = armLengthScale
        let leftWrist = joint(in: leftElbow, name: JointName.leftWrist,
                              position: SCNVector3(0, -forearmLength, 0), geometry: geometry.joint)
        addModel(geometry.hand, named: "figure.part.hand.left", to: leftWrist)

        let rightShoulder = joint(in: spine, name: JointName.rightShoulder,
                                  position: SCNVector3(-0.17, 0.29, 0),
                                  bind: Rotation(pitch: -0.12, roll: -0.06),
                                  geometry: geometry.joint)
        let rightUpperArm = addDownwardSegment(geometry.upperArm, length: upperArmLength,
                                               named: "figure.part.upperArm.right",
                                               to: rightShoulder)
        rightUpperArm.scale.y = armLengthScale
        let rightElbow = joint(in: rightShoulder, name: JointName.rightElbow,
                               position: SCNVector3(0, -upperArmLength, 0),
                               bind: Rotation(pitch: -0.28), geometry: geometry.joint)
        let rightForearm = addDownwardSegment(geometry.forearm, length: forearmLength,
                                              named: "figure.part.forearm.right", to: rightElbow)
        rightForearm.scale.y = armLengthScale
        let rightWrist = joint(in: rightElbow, name: JointName.rightWrist,
                               position: SCNVector3(0, -forearmLength, 0), geometry: geometry.joint)
        addModel(geometry.hand, named: "figure.part.hand.right", to: rightWrist)

        let upperLegLength: Float = 0.30
        let lowerLegLength: Float = 0.27
        let leftHip = joint(in: pelvis, name: JointName.leftHip,
                            position: SCNVector3(0.09, -0.01, 0.02),
                            bind: Rotation(pitch: -Float.pi / 2), geometry: geometry.joint)
        let leftUpperLeg = addDownwardSegment(geometry.upperLeg, length: upperLegLength,
                                              named: "figure.part.upperLeg.left", to: leftHip)
        leftUpperLeg.scale.y = upperLegLength / 0.37
        let leftKnee = joint(in: leftHip, name: JointName.leftKnee,
                             position: SCNVector3(0, -upperLegLength, 0),
                             bind: Rotation(pitch: Float.pi / 2), geometry: geometry.joint)
        let leftLowerLeg = addDownwardSegment(geometry.lowerLeg, length: lowerLegLength,
                                              named: "figure.part.lowerLeg.left", to: leftKnee)
        leftLowerLeg.scale.y = lowerLegLength / 0.35
        let leftAnkle = joint(in: leftKnee, name: JointName.leftAnkle,
                              position: SCNVector3(0, -lowerLegLength, 0), geometry: geometry.joint)
        addModel(geometry.foot, named: "figure.part.foot.left", to: leftAnkle,
                 position: SCNVector3(0, -0.02, 0.06))

        let rightHip = joint(in: pelvis, name: JointName.rightHip,
                             position: SCNVector3(-0.09, -0.01, 0.02),
                             bind: Rotation(pitch: -Float.pi / 2), geometry: geometry.joint)
        let rightUpperLeg = addDownwardSegment(geometry.upperLeg, length: upperLegLength,
                                               named: "figure.part.upperLeg.right", to: rightHip)
        rightUpperLeg.scale.y = upperLegLength / 0.37
        let rightKnee = joint(in: rightHip, name: JointName.rightKnee,
                              position: SCNVector3(0, -upperLegLength, 0),
                              bind: Rotation(pitch: Float.pi / 2), geometry: geometry.joint)
        let rightLowerLeg = addDownwardSegment(geometry.lowerLeg, length: lowerLegLength,
                                               named: "figure.part.lowerLeg.right", to: rightKnee)
        rightLowerLeg.scale.y = lowerLegLength / 0.35
        let rightAnkle = joint(in: rightKnee, name: JointName.rightAnkle,
                               position: SCNVector3(0, -lowerLegLength, 0), geometry: geometry.joint)
        addModel(geometry.foot, named: "figure.part.foot.right", to: rightAnkle,
                 position: SCNVector3(0, -0.02, 0.06))

        return JointHandles(
            pelvis: pelvis, spine: spine, head: head,
            leftShoulder: leftShoulder, rightShoulder: rightShoulder,
            leftElbow: leftElbow, rightElbow: rightElbow,
            leftWrist: leftWrist, rightWrist: rightWrist,
            leftHip: leftHip, rightHip: rightHip,
            leftKnee: leftKnee, rightKnee: rightKnee,
            leftAnkle: leftAnkle, rightAnkle: rightAnkle,
            leftWheel: leftWheel, rightWheel: rightWheel, tail: nil
        )
    }

    @MainActor
    private static func addChairRails(to chair: SCNNode, geometry: GeometrySet) {
        for x: Float in [-0.24, 0.24] {
            let armrest = addModel(geometry.unitRod,
                                   named: x < 0 ? "figure.wheelchair.armrest.right"
                                                : "figure.wheelchair.armrest.left",
                                   to: chair, position: SCNVector3(x, 0.77, 0.01),
                                   eulerAngles: SCNVector3(Float.pi / 2, 0, 0))
            armrest.scale.y = 0.36

            let frontPost = addModel(geometry.unitRod,
                                     named: "figure.wheelchair.frame.front", to: chair,
                                     position: SCNVector3(x, 0.43, 0.20))
            frontPost.scale.y = 0.35
            let rearPost = addModel(geometry.unitRod,
                                    named: "figure.wheelchair.frame.rear", to: chair,
                                    position: SCNVector3(x, 0.55, -0.18))
            rearPost.scale.y = 0.58
        }
    }

    @MainActor
    private static func addWheelVisuals(to wheel: SCNNode, geometry: GeometrySet, side: String) {
        addModel(geometry.wheel, named: "figure.wheelchair.wheel.\(side)", to: wheel,
                 eulerAngles: SCNVector3(0, 0, Float.pi / 2))
        addModel(geometry.wheelHub, named: "figure.wheelchair.hub.\(side)", to: wheel,
                 eulerAngles: SCNVector3(0, 0, Float.pi / 2))

        let vertical = addModel(geometry.wheelSpoke, named: "figure.wheelchair.spoke.\(side)",
                                to: wheel)
        vertical.scale.y = 0.52
        let horizontal = addModel(geometry.wheelSpoke,
                                  named: "figure.wheelchair.spoke.\(side)", to: wheel,
                                  eulerAngles: SCNVector3(Float.pi / 2, 0, 0))
        horizontal.scale.y = 0.52
        for angle: Float in [Float.pi / 4, -Float.pi / 4] {
            let diagonal = addModel(geometry.wheelSpoke,
                                    named: "figure.wheelchair.spoke.\(side)", to: wheel,
                                    eulerAngles: SCNVector3(angle, 0, 0))
            diagonal.scale.y = 0.52
        }
    }

    // MARK: - Quadruped pet

    @MainActor
    private static func petFigure(in container: SCNNode,
                                  geometry: GeometrySet) -> JointHandles {
        let pelvis = joint(in: container, name: JointName.pelvis,
                           position: SCNVector3(0, 0.42, 0), geometry: geometry.petJoint)
        addModel(geometry.petBody, named: "figure.pet.body", to: pelvis,
                 eulerAngles: SCNVector3(Float.pi / 2, 0, 0))

        let spine = joint(in: pelvis, name: JointName.spine,
                          position: SCNVector3(0, 0.04, 0.23), geometry: geometry.petJoint)
        let head = joint(in: spine, name: JointName.head,
                         position: SCNVector3(0, 0.11, 0.18),
                         bind: Rotation(pitch: -0.12), geometry: geometry.petJoint)
        addModel(geometry.petHead, named: "figure.pet.head", to: head)
        addModel(geometry.petSnout, named: "figure.pet.snout", to: head,
                 position: SCNVector3(0, -0.015, 0.14),
                 eulerAngles: SCNVector3(Float.pi / 2, 0, 0))
        for x: Float in [-0.075, 0.075] {
            addModel(geometry.petEar, named: "figure.pet.ear", to: head,
                     position: SCNVector3(x, 0.14, -0.015),
                     eulerAngles: SCNVector3(-0.18, 0, x < 0 ? 0.18 : -0.18))
        }

        let leftShoulder = joint(in: spine, name: JointName.leftShoulder,
                                 position: SCNVector3(0.095, -0.05, -0.02),
                                 bind: Rotation(pitch: -0.05), geometry: geometry.petJoint)
        addDownwardSegment(geometry.petUpperLeg, length: 0.17,
                           named: "figure.pet.foreleg.upper.left", to: leftShoulder)
        let leftElbow = joint(in: leftShoulder, name: JointName.leftElbow,
                              position: SCNVector3(0, -0.17, 0),
                              bind: Rotation(pitch: 0.08), geometry: geometry.petJoint)
        addDownwardSegment(geometry.petLowerLeg, length: 0.16,
                           named: "figure.pet.foreleg.lower.left", to: leftElbow)
        let leftWrist = joint(in: leftElbow, name: JointName.leftWrist,
                              position: SCNVector3(0, -0.16, 0), geometry: geometry.petJoint)
        addModel(geometry.petPaw, named: "figure.pet.paw.front.left", to: leftWrist,
                 position: SCNVector3(0, -0.01, 0.025),
                 eulerAngles: SCNVector3(Float.pi / 2, 0, 0))

        let rightShoulder = joint(in: spine, name: JointName.rightShoulder,
                                  position: SCNVector3(-0.095, -0.05, -0.02),
                                  bind: Rotation(pitch: -0.05), geometry: geometry.petJoint)
        addDownwardSegment(geometry.petUpperLeg, length: 0.17,
                           named: "figure.pet.foreleg.upper.right", to: rightShoulder)
        let rightElbow = joint(in: rightShoulder, name: JointName.rightElbow,
                               position: SCNVector3(0, -0.17, 0),
                               bind: Rotation(pitch: 0.08), geometry: geometry.petJoint)
        addDownwardSegment(geometry.petLowerLeg, length: 0.16,
                           named: "figure.pet.foreleg.lower.right", to: rightElbow)
        let rightWrist = joint(in: rightElbow, name: JointName.rightWrist,
                               position: SCNVector3(0, -0.16, 0), geometry: geometry.petJoint)
        addModel(geometry.petPaw, named: "figure.pet.paw.front.right", to: rightWrist,
                 position: SCNVector3(0, -0.01, 0.025),
                 eulerAngles: SCNVector3(Float.pi / 2, 0, 0))

        let leftHip = joint(in: pelvis, name: JointName.leftHip,
                            position: SCNVector3(0.095, -0.03, -0.22),
                            bind: Rotation(pitch: 0.10), geometry: geometry.petJoint)
        addDownwardSegment(geometry.petUpperLeg, length: 0.17,
                           named: "figure.pet.hindleg.upper.left", to: leftHip)
        let leftKnee = joint(in: leftHip, name: JointName.leftKnee,
                             position: SCNVector3(0, -0.17, 0),
                             bind: Rotation(pitch: -0.18), geometry: geometry.petJoint)
        addDownwardSegment(geometry.petLowerLeg, length: 0.16,
                           named: "figure.pet.hindleg.lower.left", to: leftKnee)
        let leftAnkle = joint(in: leftKnee, name: JointName.leftAnkle,
                              position: SCNVector3(0, -0.16, 0), geometry: geometry.petJoint)
        addModel(geometry.petPaw, named: "figure.pet.paw.hind.left", to: leftAnkle,
                 position: SCNVector3(0, -0.01, 0.025),
                 eulerAngles: SCNVector3(Float.pi / 2, 0, 0))

        let rightHip = joint(in: pelvis, name: JointName.rightHip,
                             position: SCNVector3(-0.095, -0.03, -0.22),
                             bind: Rotation(pitch: 0.10), geometry: geometry.petJoint)
        addDownwardSegment(geometry.petUpperLeg, length: 0.17,
                           named: "figure.pet.hindleg.upper.right", to: rightHip)
        let rightKnee = joint(in: rightHip, name: JointName.rightKnee,
                              position: SCNVector3(0, -0.17, 0),
                              bind: Rotation(pitch: -0.18), geometry: geometry.petJoint)
        addDownwardSegment(geometry.petLowerLeg, length: 0.16,
                           named: "figure.pet.hindleg.lower.right", to: rightKnee)
        let rightAnkle = joint(in: rightKnee, name: JointName.rightAnkle,
                               position: SCNVector3(0, -0.16, 0), geometry: geometry.petJoint)
        addModel(geometry.petPaw, named: "figure.pet.paw.hind.right", to: rightAnkle,
                 position: SCNVector3(0, -0.01, 0.025),
                 eulerAngles: SCNVector3(Float.pi / 2, 0, 0))

        let tail = joint(in: pelvis, name: JointName.tail,
                         position: SCNVector3(0, 0.04, -0.29),
                         bind: Rotation(pitch: 2.10), geometry: geometry.petJoint)
        addDownwardSegment(geometry.petTail, length: 0.32,
                           named: "figure.pet.tail", to: tail)

        return JointHandles(
            pelvis: pelvis, spine: spine, head: head,
            leftShoulder: leftShoulder, rightShoulder: rightShoulder,
            leftElbow: leftElbow, rightElbow: rightElbow,
            leftWrist: leftWrist, rightWrist: rightWrist,
            leftHip: leftHip, rightHip: rightHip,
            leftKnee: leftKnee, rightKnee: rightKnee,
            leftAnkle: leftAnkle, rightAnkle: rightAnkle,
            leftWheel: nil, rightWheel: nil, tail: tail
        )
    }

    // MARK: - Hierarchy helpers

    /// Adds a bind anchor followed by a zeroed, named pose node.  The split is what lets pose
    /// rotations be absolute while preserving seated, hunched and quadruped rest postures.
    @discardableResult
    @MainActor
    private static func joint(in parent: SCNNode, name: String,
                              position: SCNVector3 = SCNVector3Zero,
                              bind: Rotation = .zero,
                              geometry: SCNGeometry? = nil) -> SCNNode {
        let anchor = SCNNode()
        anchor.position = position
        anchor.eulerAngles = SCNVector3(bind.pitch, bind.yaw, bind.roll)
        parent.addChildNode(anchor)

        let poseNode = SCNNode()
        poseNode.name = name
        anchor.addChildNode(poseNode)
        if let geometry {
            addModel(geometry, named: "figure.part.joint", to: poseNode)
        }
        return poseNode
    }

    @discardableResult
    @MainActor
    private static func addDownwardSegment(_ geometry: SCNGeometry, length: Float,
                                           named name: String, to parent: SCNNode) -> SCNNode {
        addModel(geometry, named: name, to: parent,
                 position: SCNVector3(0, -length / 2, 0))
    }

    @discardableResult
    @MainActor
    private static func addModel(_ geometry: SCNGeometry, named name: String,
                                 to parent: SCNNode,
                                 position: SCNVector3 = SCNVector3Zero,
                                 eulerAngles: SCNVector3 = SCNVector3Zero) -> SCNNode {
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.position = position
        node.eulerAngles = eulerAngles
        node.castsShadow = true
        node.renderingOrder = RenderOrder.fixtures
        parent.addChildNode(node)
        return node
    }

    // MARK: - Label and hit target

    private static func figureHeight(for kind: FigureKind) -> Double {
        switch kind {
        case .adult: return heightM
        case .child: return 1.17
        case .elderly: return 1.43
        case .wheelchair: return 1.25
        case .pet: return 0.79
        }
    }

    /// Broad invisible geometry keeps thin articulated limbs as easy to select as the original
    /// capsule.  It writes neither colour nor depth and never casts a shadow.
    @MainActor
    private static func hitTarget(for kind: FigureKind) -> SCNNode {
        let size: (width: CGFloat, height: CGFloat, length: CGFloat)
        switch kind {
        case .adult, .elderly:
            size = (0.54, 1.52, 0.42)
        case .child:
            size = (0.45, 1.18, 0.36)
        case .wheelchair:
            size = (0.78, 1.28, 0.88)
        case .pet:
            size = (0.42, 0.82, 0.98)
        }

        let box = SCNBox(width: size.width, height: size.height, length: size.length,
                         chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.clear
        material.lightingModel = .constant
        material.colorBufferWriteMask = []
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        box.materials = [material]

        let node = SCNNode(geometry: box)
        node.name = "figure.hitTarget"
        node.position.y = Float(size.height / 2)
        if kind == .pet { node.position.z = -0.04 }
        node.castsShadow = false
        node.renderingOrder = RenderOrder.fixtures
        return node
    }

    /// Billboarded name chip — the same sprite vocabulary as room labels.
    @MainActor
    private static func pill(name: String, highlighted: Bool,
                             figureHeight: Double) -> SCNNode {
        let sprite = RoomLabelSprite.make(name: name)
        let plane = SCNPlane(width: pillHeight * sprite.aspect, height: pillHeight)
        let material = SCNMaterial()
        material.diffuse.contents = sprite.image
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = false
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.name = "figure.label"
        node.position.y = Float(figureHeight + pillHeight)
        node.renderingOrder = RenderOrder.labels
        node.castsShadow = false
        node.opacity = highlighted ? 1.0 : 0.75
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    // MARK: - Shared mesh catalog

    private final class GeometrySet {
        let joint: SCNGeometry
        let head: SCNGeometry
        let torso: SCNGeometry
        let pelvis: SCNGeometry
        let upperArm: SCNGeometry
        let forearm: SCNGeometry
        let hand: SCNGeometry
        let upperLeg: SCNGeometry
        let lowerLeg: SCNGeometry
        let foot: SCNGeometry
        let unitRod: SCNGeometry

        let wheel: SCNGeometry
        let wheelHub: SCNGeometry
        let wheelSpoke: SCNGeometry
        let casterWheel: SCNGeometry
        let chairSeat: SCNGeometry
        let chairBack: SCNGeometry
        let footrest: SCNGeometry

        let petJoint: SCNGeometry
        let petBody: SCNGeometry
        let petHead: SCNGeometry
        let petSnout: SCNGeometry
        let petEar: SCNGeometry
        let petUpperLeg: SCNGeometry
        let petLowerLeg: SCNGeometry
        let petPaw: SCNGeometry
        let petTail: SCNGeometry

        init(material: SCNMaterial) {
            joint = Self.sphere(radius: 0.052, material: material)
            head = Self.sphere(radius: 0.13, material: material, segments: 20)

            let torsoShape = SCNCone(topRadius: 0.175, bottomRadius: 0.135, height: 0.40)
            torso = Self.prepared(torsoShape, material: material)
            pelvis = Self.prepared(
                SCNBox(width: 0.30, height: 0.16, length: 0.19, chamferRadius: 0.055),
                material: material
            )

            upperArm = Self.capsule(radius: 0.047, height: 0.30, material: material)
            forearm = Self.capsule(radius: 0.041, height: 0.27, material: material)
            hand = Self.sphere(radius: 0.058, material: material)
            upperLeg = Self.capsule(radius: 0.067, height: 0.37, material: material)
            lowerLeg = Self.capsule(radius: 0.056, height: 0.35, material: material)
            foot = Self.prepared(
                SCNBox(width: 0.12, height: 0.07, length: 0.20, chamferRadius: 0.03),
                material: material
            )
            unitRod = Self.prepared(SCNCylinder(radius: 0.023, height: 1.0),
                                    material: material)

            wheel = Self.prepared(SCNTorus(ringRadius: 0.29, pipeRadius: 0.036),
                                  material: material)
            wheelHub = Self.prepared(SCNCylinder(radius: 0.058, height: 0.075),
                                     material: material)
            wheelSpoke = Self.prepared(SCNCylinder(radius: 0.012, height: 1.0),
                                       material: material)
            casterWheel = Self.prepared(SCNTorus(ringRadius: 0.070, pipeRadius: 0.022),
                                        material: material)
            chairSeat = Self.prepared(
                SCNBox(width: 0.50, height: 0.09, length: 0.42, chamferRadius: 0.025),
                material: material
            )
            chairBack = Self.prepared(
                SCNBox(width: 0.50, height: 0.44, length: 0.075, chamferRadius: 0.025),
                material: material
            )
            footrest = Self.prepared(
                SCNBox(width: 0.42, height: 0.045, length: 0.18, chamferRadius: 0.018),
                material: material
            )

            petJoint = Self.sphere(radius: 0.043, material: material)
            petBody = Self.capsule(radius: 0.13, height: 0.58, material: material)
            petHead = Self.sphere(radius: 0.13, material: material, segments: 18)
            petSnout = Self.capsule(radius: 0.065, height: 0.20, material: material)
            petEar = Self.prepared(SCNCone(topRadius: 0, bottomRadius: 0.055, height: 0.14),
                                   material: material)
            petUpperLeg = Self.capsule(radius: 0.040, height: 0.17, material: material)
            petLowerLeg = Self.capsule(radius: 0.034, height: 0.16, material: material)
            petPaw = Self.capsule(radius: 0.043, height: 0.12, material: material)
            petTail = Self.capsule(radius: 0.026, height: 0.32, material: material)
        }

        private static func prepared(_ geometry: SCNGeometry,
                                     material: SCNMaterial) -> SCNGeometry {
            geometry.materials = [material]
            return geometry
        }

        private static func sphere(radius: CGFloat, material: SCNMaterial,
                                   segments: Int = 14) -> SCNGeometry {
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = segments
            return prepared(sphere, material: material)
        }

        private static func capsule(radius: CGFloat, height: CGFloat,
                                    material: SCNMaterial) -> SCNGeometry {
            let capsule = SCNCapsule(capRadius: radius, height: height)
            capsule.radialSegmentCount = 12
            capsule.capSegmentCount = 6
            return prepared(capsule, material: material)
        }
    }
}
