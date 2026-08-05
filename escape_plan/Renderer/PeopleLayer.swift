//  PeopleLayer.swift
//  Renderer — the household standing in the model.
//
//  Answers the question the dollhouse could not: *who lives here, and where do they sleep?*
//  A profile's whole purpose is that it changes the route — a wheelchair user is not sent down
//  the stairs — but until now a profile was a row in a picker with no presence in the scene, so
//  switching profiles changed a line on screen with no visible reason.
//
//  Managed like `RouteOverlay`: this owns only the nodes it added and can clear them without
//  touching the built scene, so a rebuild never leaves orphans behind.

import SceneKit

@MainActor
final class PeopleLayer {

    private weak var dollhouse: DollhouseScene?
    private var addedNodes: [SCNNode] = []

    init(dollhouse: DollhouseScene) {
        self.dollhouse = dollhouse
    }

    /// Places one figure per profile, standing at the centroid of their bedroom.
    /// `highlighted` is the currently selected profile, if any.
    ///
    /// Returns human-readable issues for profiles whose bedroom can't be located — surfaced
    /// the way `RouteOverlay.show` surfaces unresolvable route references, never swallowed.
    @discardableResult
    func show(profiles: [Profile], home: HomeModel, highlighted: String?) -> [String] {
        clear()
        guard let dollhouse else { return [] }
        var issues: [String] = []
        let baseHeights = DollhouseGeometry.floorBaseHeights(of: home)

        for profile in profiles {
            guard let (floorID, room) = home.locateRoom(profile.bedroom_room_id) else {
                issues.append("\(profile.name)'s bedroom (\(profile.bedroom_room_id)) "
                              + "isn't in this home.")
                continue
            }
            let node = PersonFixture.node(id: profile.id, name: profile.name,
                                          highlighted: profile.id == highlighted)
            node.position = DollhouseGeometry.scenePoint(Geometry.centroid(room.polygon),
                                                         y: baseHeights[floorID] ?? 0)
            dollhouse.scene.rootNode.addChildNode(node)
            addedNodes.append(node)
        }
        return issues
    }

    func clear() {
        for node in addedNodes { node.removeFromParentNode() }
        addedNodes = []
    }

    /// Walks up from a hit-test result to the `person:<id>` container, so a tap that lands on
    /// the head, the body or the name pill all resolve to the same profile.
    static func profileID(forHit node: SCNNode) -> String? {
        var current: SCNNode? = node
        while let candidate = current {
            if let name = candidate.name, name.hasPrefix("person:") {
                return String(name.dropFirst("person:".count))
            }
            current = candidate.parent
        }
        return nil
    }
}
