//  RouteEncodingTests.swift
//  The route must survive losing its color.
//
//  Two things forced this suite. A hazard visualization now puts a second colored system in a
//  scene that used to have exactly one, and the old pair — orange route, red hazard — is the
//  textbook deuteranopia collision. And a printable black-and-white plan has to carry the same
//  routes onto a laser printer, where hue does not exist at all.
//
//  So the encoding is redundant by construction: cool hues for routes and warm for hazard,
//  solid versus dashed geometry, numbered stops, and a measured luminance step between the
//  three identity colors. These tests hold the measurements. If a color is retuned, the numbers
//  here fail before a judge ever sees an unreadable frame.

import SceneKit
import Testing
import UIKit

@testable import escape_plan

@Suite("Route encoding — color-free legibility")
struct RouteEncodingColorTests {

    private let primary = DollhousePalette.routePrimary
    private let secondary = DollhousePalette.routeSecondary
    private let hazard = DollhousePalette.hazardCore
    private let wall = DollhousePalette.wallWhite

    /// The WCAG formula itself, checked against a value nobody can argue with, so a failure in
    /// the assertions below means the palette moved and not that the math is wrong.
    @Test("Relative luminance matches the WCAG reference points")
    func luminanceFormulaIsCorrect() {
        #expect(abs(UIColor.white.relativeLuminance - 1.0) < 1e-6)
        #expect(abs(UIColor.black.relativeLuminance - 0.0) < 1e-6)
        // Mid gray #777777 → 0.1845 by the sRGB transfer function.
        #expect(abs(UIColor(hex: 0x777777).relativeLuminance - 0.1845) < 5e-4)
        #expect(abs(UIColor.white.contrastRatio(to: .black) - 21.0) < 1e-3)
    }

    @Test("The three identity colors sit where the palette says they do")
    func measuredLuminances() {
        #expect(abs(primary.relativeLuminance - 0.0682) < 5e-4)
        #expect(abs(secondary.relativeLuminance - 0.2132) < 5e-4)
        #expect(abs(hazard.relativeLuminance - 0.3246) < 5e-4)
    }

    /// Requirement (c): a real gap, not a comment claiming one. 0.08 is the floor — it is the
    /// separation that still survives a mid-gray page and a projector, and every measured pair
    /// clears it (0.145, 0.111, 0.256).
    @Test("Primary, secondary and hazard are separated in luminance")
    func luminanceGaps() {
        let pairs: [(String, UIColor, UIColor)] = [
            ("primary↔secondary", primary, secondary),
            ("secondary↔hazard", secondary, hazard),
            ("primary↔hazard", primary, hazard),
        ]
        for (name, a, b) in pairs {
            let gap = abs(a.relativeLuminance - b.relativeLuminance)
            #expect(gap >= 0.08,
                    "\(name) luminance gap is only \(gap); the three systems must stay distinguishable with hue removed")
        }
    }

    /// Routes are thin lines, so they take the stricter 3:1 non-text threshold against the wall
    /// they are drawn on. The hazard is a filled mass, which is a large graphical object; it is
    /// held to 2.5:1 and measures 2.60.
    @Test("Every colored system contrasts against the white model")
    func contrastAgainstTheWallWhite() {
        #expect(primary.contrastRatio(to: wall) >= 3.0,
                "primary route measures \(primary.contrastRatio(to: wall)):1 on the wall white")
        #expect(secondary.contrastRatio(to: wall) >= 3.0,
                "secondary route measures \(secondary.contrastRatio(to: wall)):1 on the wall white")
        #expect(hazard.contrastRatio(to: wall) >= 2.5,
                "hazard fill measures \(hazard.contrastRatio(to: wall)):1 on the wall white")
    }

    /// The two routes are the pair a reader has to tell apart, so they carry a real contrast
    /// step and not merely a measurable one.
    @Test("The primary and secondary routes are a full contrast step apart")
    func routePairIsAContrastStep() {
        let ratio = primary.contrastRatio(to: secondary)
        #expect(ratio >= 2.0,
                "primary vs secondary is \(ratio):1 — too close to read as a hierarchy once the hues are gone")
    }

    /// Requirement: grayscale legibility for the printed plan. Desaturate to luminance and the
    /// routes must still be two different grays — measured 74 and 127 out of 255, with the
    /// hazard a further 27 levels up at 154.
    @Test("Desaturated for a black-and-white printer, the routes stay distinguishable")
    func grayscalePrintLegibility() {
        let p = primary.printedGrayLevel
        let s = secondary.printedGrayLevel
        let h = hazard.printedGrayLevel

        #expect(abs(p - s) >= 40,
                "printed at 8-bit gray the routes are \(p) and \(s) — a laser printer renders them as the same line")
        #expect(abs(s - h) >= 20, "secondary \(s) and hazard \(h) collapse on paper")
        #expect(abs(p - h) >= 20, "primary \(p) and hazard \(h) collapse on paper")

        // And the desaturation helper agrees with the level it reports.
        #expect(primary.luminanceGray.printedGrayLevel == p)
    }

    /// The point of the re-key: routes moved off the warm end so the hazard could have it. Blue
    /// channel dominant for routes, red channel dominant for hazard — checked on the raw
    /// components so "cool" and "warm" are assertions rather than adjectives in a comment.
    @Test("Routes are cool, hazard is warm")
    func hueFamiliesAreReserved() {
        func rgb(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b)
        }
        for (name, color) in [("primary", primary), ("secondary", secondary)] {
            let (r, g, b) = rgb(color)
            #expect(b > r + 0.25 && b > g + 0.15,
                    "\(name) route must be cool (blue-dominant) so it cannot be confused with the hazard family")
        }
        let (hr, hg, hb) = rgb(hazard)
        #expect(hr > hb + 0.4 && hr > hg + 0.2, "hazard must be warm — red-dominant")
    }

    /// The number knocked out of a stop chip has to be readable, not merely present.
    @Test("Stop-chip numerals clear the large-text threshold on their chip")
    func chipNumeralContrast() {
        #expect(UIColor.white.contrastRatio(to: primary) >= 4.5)
    }
}

@Suite("Route encoding — dashes and numbered stops")
struct RouteEncodingGeometryTests {

    // MARK: - Dashes

    private func line(_ length: Float) -> [SCNVector3] {
        [SCNVector3(0, 0, 0), SCNVector3(length, 0, 0)]
    }

    @Test("A long run breaks into marks of the specified physical length")
    func dashesHaveAFixedPhysicalPeriod() throws {
        let dashes = RouteGeometry.dashes(line(10), dashLength: 0.45, gapLength: 0.28)
        // period 0.73 over 10 m → marks starting at 0, 0.73, … 9.49; the one at 9.49 is clipped
        // to 0.51 m, which is long enough to keep.
        #expect(dashes.count == 14)

        for dash in dashes.dropLast() {
            let length = RouteGeometry.arcLengths(dash.points).last ?? 0
            #expect(abs(length - 0.45) < 1e-3, "every full mark is one dash long, got \(length)")
        }
        // Marks are ordered, disjoint, and inside the parent's parameterization.
        var previousEnd: Float = -1
        for dash in dashes {
            #expect(dash.uStart > previousEnd)
            #expect(dash.uEnd > dash.uStart)
            #expect(dash.uEnd <= 1.0 + 1e-5)
            previousEnd = dash.uEnd
        }
        // Ink covers roughly dash/(dash+gap) of the run — visibly broken, not nearly solid.
        let inked = dashes.reduce(Float(0)) { $0 + (RouteGeometry.arcLengths($1.points).last ?? 0) }
        #expect(inked / 10 > 0.5 && inked / 10 < 0.72)
    }

    @Test("A leg shorter than one mark still draws")
    func shortLegDrawsAsOneMark() {
        let dashes = RouteGeometry.dashes(line(0.3))
        #expect(dashes.count == 1, "a 0.3 m leg must not vanish into a gap")
        #expect(dashes[0].uStart == 0 && dashes[0].uEnd == 1)
    }

    @Test("Marks keep the corners of the polyline they came from")
    func dashesFollowCorners() throws {
        // An L: 3 m east, then 3 m north. A mark spanning the corner must include the corner
        // point, or the dashed route would cut across the wall.
        let corner = SCNVector3(3, 0, 0)
        let path = [SCNVector3(0, 0, 0), corner, SCNVector3(3, 0, 3)]
        let dashes = RouteGeometry.dashes(path, dashLength: 2.0, gapLength: 0.5)
        let spanning = dashes.first { dash in
            let arcs = RouteGeometry.arcLengths(dash.points)
            return (arcs.last ?? 0) > 0 && dash.points.contains {
                abs($0.x - corner.x) < 1e-4 && abs($0.z - corner.z) < 1e-4
            }
        }
        #expect(spanning != nil, "no mark carried the corner vertex")
    }

    @Test("Degenerate input yields no marks rather than a crash")
    func degenerateDashInput() {
        #expect(RouteGeometry.dashes([]).isEmpty)
        #expect(RouteGeometry.dashes([SCNVector3(1, 1, 1)]).isEmpty)
        #expect(RouteGeometry.dashes([SCNVector3(1, 1, 1), SCNVector3(1, 1, 1)]).isEmpty)
    }

    /// The dash must not break the animation: the pulse rides the tube's `u`, so the marks have
    /// to carry one continuous parameterization instead of each restarting at zero.
    @Test("Dashed tubes carry their share of the parent's u range")
    func dashedTubesKeepOneParameterization() throws {
        let dashes = RouteGeometry.dashes(line(6))
        let first = try #require(dashes.first)
        let last = try #require(dashes.last)

        let firstMesh = try #require(RouteGeometry.tubeMesh(points: first.points, radius: 0.04,
                                                            uRange: first.uStart...first.uEnd))
        let lastMesh = try #require(RouteGeometry.tubeMesh(points: last.points, radius: 0.04,
                                                           uRange: last.uStart...last.uEnd))
        let firstMaxU = firstMesh.uvs.map(\.x).max() ?? 0
        let lastMinU = lastMesh.uvs.map(\.x).min() ?? 0
        #expect(firstMaxU < 0.2, "the first mark must occupy the START of the route's u span")
        #expect(lastMinU > 0.8, "the last mark must occupy the END of the route's u span")
        #expect(lastMinU > firstMaxU)
    }

    // MARK: - Numbered stops

    private func waypoint(_ kind: WaypointKind, _ x: Double, _ y: Double,
                          floor: String = "f1", node: String = "n") -> Waypoint {
        Waypoint(x: x, y: y, floor_id: floor, node_id: node, kind: kind)
    }

    private func route(_ waypoints: [Waypoint]) -> Route {
        Route(waypoints: waypoints, length_m: 10, uses_stairs: false, uses_window: false,
              exit_id: "op_front")
    }

    @Test("Interpolated path points are not stops")
    func pathPointsAreNotNumbered() {
        let stops = RouteGeometry.numberedStops(for: route([
            waypoint(.room, 0, 0),
            waypoint(.path, 1, 0),
            waypoint(.path, 2, 0),
            waypoint(.opening, 3, 0),
            waypoint(.exterior, 5, 0),
        ]))
        #expect(stops.map(\.kind) == [.start, .doorway, .exit])
        #expect(stops.map(\.number) == [1, 2, 3], "numbering must stay dense")
        #expect(stops.map(\.caption) == ["1. Start here", "2. Through the doorway",
                                         "3. Out to safety"])
    }

    @Test("An exterior waypoint on top of its opening is one stop, labelled as the exit")
    func coincidentExitCollapses() {
        // The engine emits the exterior waypoint at its opening's own coordinates.
        let stops = RouteGeometry.numberedStops(for: route([
            waypoint(.room, 0, 0),
            waypoint(.opening, 4, 0),
            waypoint(.exterior, 4, 0),
        ]))
        #expect(stops.count == 2, "two chips on the same doorway is one chip too many")
        #expect(stops.last?.kind == .exit, "the stronger meaning wins on a shared position")
        #expect(stops.last?.number == 2)
    }

    @Test("A floor crossing is one stop, on the floor you leave")
    func stairCrossingCollapses() {
        let stops = RouteGeometry.numberedStops(for: route([
            waypoint(.room, 0, 0, floor: "f2"),
            waypoint(.stair, 3, 1, floor: "f2", node: "st_1"),
            waypoint(.stair, 3, 1, floor: "f1", node: "st_1"),
            waypoint(.opening, 6, 1, floor: "f1"),
            waypoint(.exterior, 6, 1, floor: "f1"),
        ]))
        #expect(stops.map(\.kind) == [.start, .stairs, .exit])
        #expect(stops[1].waypoint.floor_id == "f2",
                "the stairs chip belongs on the floor being left, not duplicated on both")
    }

    @Test("Unknown waypoint kinds are skipped without breaking the sequence")
    func unknownKindsAreSkipped() {
        let stops = RouteGeometry.numberedStops(for: route([
            waypoint(.room, 0, 0),
            waypoint(.unknown, 2, 0),
            waypoint(.opening, 4, 0),
        ]))
        #expect(stops.map(\.number) == [1, 2])
    }
}

@MainActor
@Suite("Route encoding — what the overlay actually builds")
struct RouteEncodingOverlayTests {

    /// `RoomRoutePlan` is decode-only (it mirrors a server response and defines no memberwise
    /// init), so the test bed is built the way the app gets one: from JSON.
    ///
    /// The route walks a bedroom → interior door → exterior door, with the exterior waypoint
    /// sitting on the exit door's own coordinates exactly as the engine emits it. Coordinates
    /// only have to name a known floor for the overlay to draw them.
    private func plan(roomID: String, floorID: String) throws -> RoomRoutePlan {
        func wp(_ kind: String, _ x: Double) -> String {
            """
            {"x": \(x), "y": 1.0, "floor_id": "\(floorID)", "node_id": "n\(x)", "kind": "\(kind)"}
            """
        }
        let json = """
        {
          "room_id": "\(roomID)", "room_name": "Test Room", "floor_id": "\(floorID)",
          "primary": {
            "waypoints": [\(wp("room", 0)), \(wp("path", 2)), \(wp("opening", 4)),
                          \(wp("path", 6)), \(wp("opening", 8)), \(wp("exterior", 8))],
            "length_m": 8.0, "uses_stairs": false, "uses_window": false, "exit_id": "op_front"
          },
          "secondary": {
            "waypoints": [\(wp("room", 0)), \(wp("path", 2)), \(wp("opening", 9)),
                          \(wp("exterior", 9))],
            "length_m": 9.0, "uses_stairs": false, "uses_window": true, "exit_id": "op_back"
          },
          "findings": []
        }
        """
        return try JSONDecoder().decode(RoomRoutePlan.self, from: Data(json.utf8))
    }

    private func build() throws -> (HomeModel, DollhouseScene, RoomRoutePlan) {
        let home = try FixtureLoader.load(.bungalow)
        let floor = try #require(home.floors.first)
        let room = try #require(floor.rooms.first)
        let built = DollhouseSceneBuilder.build(home)
        let roomPlan = try plan(roomID: room.id, floorID: floor.id)
        return (home, built.dollhouse, roomPlan)
    }

    private func nodeNames(_ scene: DollhouseScene, prefix: String) -> [String] {
        var names: [String] = []
        scene.scene.rootNode.enumerateHierarchy { node, _ in
            if let name = node.name, name.hasPrefix(prefix) { names.append(name) }
        }
        return names
    }

    /// The core non-color claim: with the hues stripped, the secondary is still obviously the
    /// secondary, because it is made of many short tubes and the primary is made of one.
    @Test("The secondary route is drawn as many marks, the primary as one continuous tube")
    func secondaryIsRealDashedGeometry() throws {
        let (home, dollhouse, roomPlan) = try build()
        let overlay = RouteOverlay(dollhouse: dollhouse, reduceMotion: false)
        let issues = overlay.show(rooms: [roomPlan], home: home)
        #expect(issues.isEmpty)

        let dashNodes = nodeNames(dollhouse, prefix: "route:").filter { $0.contains(":dash") }
        let solidNodes = nodeNames(dollhouse, prefix: "route:")
            .filter { !$0.contains(":dash") && !$0.hasSuffix(":occluded") }

        #expect(dashNodes.count >= 6,
                "the 8 m secondary must break into several marks, got \(dashNodes.count)")
        // Each mark is drawn twice (the occluded ghost pass plus the solid pass), and the
        // primary contributes exactly one of each.
        #expect(solidNodes.count == 1,
                "the primary must stay ONE tube so its pulse runs the whole path, got \(solidNodes)")
    }

    @Test("Numbered stop chips appear in walking order for the selected route")
    func numberedStopsAreDrawn() throws {
        let (home, dollhouse, roomPlan) = try build()
        let overlay = RouteOverlay(dollhouse: dollhouse)
        overlay.show(rooms: [roomPlan], home: home)

        let stops = try #require(overlay.drawnSteps[roomPlan.room_id])
        #expect(stops.map(\.kind) == [.start, .doorway, .exit])

        let chips = nodeNames(dollhouse, prefix: "routeStop:").sorted()
        #expect(chips == (1...3).map { "routeStop:\(roomPlan.room_id):\($0)" })

        // The chip a sighted user counts and the label VoiceOver reads are the same string.
        var labels: [String] = []
        dollhouse.scene.rootNode.enumerateHierarchy { node, _ in
            if node.name?.hasPrefix("routeStop:") == true,
               let label = node.accessibilityLabel { labels.append(label) }
        }
        #expect(Set(labels) == Set(stops.map(\.caption)))
    }

    @Test("The whole-house view keeps the spoken steps but drops the chips")
    func multiRoomViewSuppressesChips() throws {
        let (home, dollhouse, roomPlan) = try build()
        let second = try plan(roomID: "other_room", floorID: roomPlan.floor_id)
        let overlay = RouteOverlay(dollhouse: dollhouse)
        overlay.show(rooms: [roomPlan, second], home: home)

        #expect(nodeNames(dollhouse, prefix: "routeStop:").isEmpty,
                "numbering every room at once would bury the model in digits")
        #expect(overlay.drawnSteps.count == 2,
                "the ordered steps are still available to speak, just not drawn")
    }

    @Test("clear() removes the stops it drew, in the graph and in the spoken list")
    func clearRemovesEncoding() throws {
        let (home, dollhouse, roomPlan) = try build()
        var baseline = 0
        dollhouse.scene.rootNode.enumerateHierarchy { _, _ in baseline += 1 }

        let overlay = RouteOverlay(dollhouse: dollhouse)
        overlay.show(rooms: [roomPlan], home: home)
        overlay.clear()

        var after = 0
        dollhouse.scene.rootNode.enumerateHierarchy { _, _ in after += 1 }
        #expect(after == baseline)
        #expect(overlay.drawnSteps.isEmpty)
    }

    // MARK: - Reduce Motion

    @Test("Reduce Motion removes the travelling pulse and the throb, never the route")
    func reduceMotionDegradesToAStaticReveal() throws {
        let (home, dollhouse, roomPlan) = try build()
        let overlay = RouteOverlay(dollhouse: dollhouse, reduceMotion: true)
        overlay.show(rooms: [roomPlan], home: home)

        var pulsing = 0
        var animatedOverlayNodes = 0
        var tubes = 0
        var chips = 0
        // Scoped to what THIS overlay added — the scene builder animates its own fixtures, and
        // those are not this lane's to speak for.
        dollhouse.scene.rootNode.enumerateHierarchy { node, _ in
            guard let name = node.name else { return }
            if name.hasPrefix("route") && node.hasActions { animatedOverlayNodes += 1 }
            if name.hasPrefix("route:") {
                tubes += 1
                let modifier = node.geometry?.firstMaterial?.shaderModifiers?[.fragment] ?? ""
                if modifier.contains("u_time") { pulsing += 1 }
            }
            if name.hasPrefix("routeStop:") { chips += 1 }
        }

        #expect(pulsing == 0, "the pulse is the only animation in the material; it must be gone")
        #expect(animatedOverlayNodes == 0, "the start dot must not throb under Reduce Motion")
        #expect(tubes > 0, "the route itself is never disabled — only its motion")
        #expect(chips == 3, "with the pulse gone, the numbered stops carry the direction")
    }

    @Test("With motion allowed, the primary still pulses and the start dot still throbs")
    func motionIsIntactByDefault() throws {
        let (home, dollhouse, roomPlan) = try build()
        let overlay = RouteOverlay(dollhouse: dollhouse, reduceMotion: false)
        overlay.show(rooms: [roomPlan], home: home)

        var pulsing = 0
        var startDotAnimates = false
        dollhouse.scene.rootNode.enumerateHierarchy { node, _ in
            if node.name == "routeStart", node.hasActions { startDotAnimates = true }
            if node.name?.hasPrefix("route:") == true,
               node.geometry?.firstMaterial?.shaderModifiers?[.fragment]?.contains("u_time") == true {
                pulsing += 1
            }
        }
        #expect(pulsing == 1, "exactly the primary's lit pass carries the travelling band")
        #expect(startDotAnimates, "the start dot throbs when motion is allowed")
    }
}
