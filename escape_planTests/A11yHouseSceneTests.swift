//  A11yHouseSceneTests.swift
//  escape_planTests
//
//  The accessibility guarantees the House screen makes, as measurements and strings rather
//  than as comments claiming they hold.
//
//  Three things are asserted here:
//
//  1. **The exit marker does not depend on hue.** `exitGreen` versus the reserved `hazardCore`
//     was ΔL 0.056 / 1.18:1 — a green-versus-orange pair deuteranopia collapses, and the two
//     are on screen together the moment the fire simulation runs. The pad was darkened to open
//     a real luminance gap AND given a white rim plus a white outward chevron, so it is still
//     identifiable with colour removed entirely.
//
//  2. **A VoiceOver user can hear their route as an ordered list of steps** — the explicit
//     acceptance criterion. The steps come from `RouteNarration` (the same narrator the
//     printable PDF uses, never a second copy) and are numbered by `RouteGeometry.numberedStops`
//     (the same function that produces the chips drawn on the model), so "step 3" spoken is the
//     circled 3 on screen.
//
//  3. **The 3D scene says what it is showing**, including the honest hazard language when a
//     simulation is running — the same "hazard reaches them first" vocabulary as the finding
//     cards, never softened for being spoken.

import SceneKit
import Testing
import UIKit

@testable import escape_plan

// MARK: - Exit marker: the deuteranopia collision

@Suite("Exit markers — legible with colour removed")
struct ExitMarkerAccessibilityTests {

    private let exit = DollhousePalette.exitGreen
    private let hazard = DollhousePalette.hazardCore
    private let wall = DollhousePalette.wallWhite
    private let primary = DollhousePalette.routePrimary

    /// The bug, stated as the number that used to be true. #16A34A sat 0.056 from `hazardCore`
    /// — one 8-bit gray level of separation per 4.6 — and the only thing keeping an exit
    /// distinguishable from the fire was the pads' shape.
    @Test("The retired exit green really was indistinguishable from the hazard")
    func retiredGreenCollidedWithHazard() {
        let retired = UIColor(hex: 0x16A34A)
        let gap = abs(retired.relativeLuminance - hazard.relativeLuminance)
        #expect(gap < 0.08,
                "the retired #16A34A measured \(gap) from hazardCore — the whole reason it moved")
        #expect(retired.contrastRatio(to: hazard) < 1.3)
    }

    /// The fix, as the number that must stay true. 0.15 is the floor: below it the exit and the
    /// fire are the same gray on a printout and near-identical to a deuteranope.
    @Test("Exit green and the hazard are separated in luminance")
    func exitAndHazardAreSeparated() {
        let gap = abs(exit.relativeLuminance - hazard.relativeLuminance)
        #expect(gap >= 0.15,
                "exit vs hazard luminance gap is only \(gap) — a green pad and an orange fire must not collapse onto each other for a deuteranopic viewer")
        #expect(abs(exit.printedGrayLevel - hazard.printedGrayLevel) >= 40,
                "printed at 8-bit gray the exit is \(exit.printedGrayLevel) and the hazard is \(hazard.printedGrayLevel)")
    }

    /// Darkening for the hazard's sake must not push the exit onto the route it terminates in.
    /// 0.08 is the palette's own floor (see `RouteEncodingTests.luminanceGaps`).
    @Test("Darkening the exit did not collide it with the primary route")
    func exitStillClearsThePrimaryRoute() {
        let gap = abs(exit.relativeLuminance - primary.relativeLuminance)
        #expect(gap >= 0.08,
                "exit vs primary route luminance gap is only \(gap) — the pad the route ends in must not read as more route")
    }

    /// The pad is a filled marker on the white model, so it takes the 3:1 non-text bar. It was
    /// 3.05:1 and is now 4.59:1 — the darkening improved this rather than costing it.
    @Test("The exit pad contrasts against the white model wall")
    func exitContrastsAgainstTheWall() {
        let ratio = exit.contrastRatio(to: wall)
        #expect(ratio >= 3.0, "exit pad measures \(ratio):1 on the wall white")
    }

    /// The cue that makes hue irrelevant: a white rim and a white chevron inside the marker.
    /// 4.5:1 is the bar because this is the only separation left once colour is gone.
    @Test("The non-colour cue carries a real luminance step inside the marker")
    func cueInkStepsAwayFromThePad() {
        let ratio = ExitMarkerFixture.cueInk.contrastRatio(to: exit)
        #expect(ratio >= 4.5,
                "the marker's own rim and chevron measure \(ratio):1 against the pad — below 4.5 the shape cue stops reading in greyscale")
    }

    @Test("Every exit marker carries the rim and the outward chevron, not just colour")
    func markerBuildsTheNonColourCue() throws {
        let node = ExitMarkerFixture.node(wallThickness: 0.12, sillY: 1.0,
                                          outwardZ: 1, animated: false)
        var names: [String] = []
        node.enumerateHierarchy { child, _ in
            if let name = child.name { names.append(name) }
        }
        #expect(names.contains(ExitMarkerFixture.NodeName.pad))
        #expect(names.contains(ExitMarkerFixture.NodeName.rim),
                "the white rim is the marker's luminance frame; without it the pad is hue only")
        #expect(names.contains(ExitMarkerFixture.NodeName.cueChevron),
                "the white chevron is what makes the marker DIRECTIONAL without colour")
        #expect(names.filter { $0.hasPrefix(ExitMarkerFixture.NodeName.chevron + ":") }.count == 3)
    }

    /// The cue is drawn in constant lighting, so its measured step survives every orbit angle
    /// and the shadowed side of the house instead of drifting with the key light.
    @Test("The cue is unlit signage, so its contrast cannot drift with the lighting")
    func cueIsConstantLit() throws {
        let node = ExitMarkerFixture.node(wallThickness: 0.12, sillY: 1.0,
                                          outwardZ: -1, animated: false)
        var rimMaterials: [SCNMaterial] = []
        node.enumerateHierarchy { child, _ in
            guard child.name == ExitMarkerFixture.NodeName.rim,
                  let material = child.geometry?.firstMaterial else { return }
            rimMaterials.append(material)
        }
        let material = try #require(rimMaterials.first)
        #expect(material.lightingModel == .constant)
        #expect((material.diffuse.contents as? UIColor) == ExitMarkerFixture.cueInk)
    }

    /// The whole point of the fixture: an exit reads from any angle without hue. Animated or
    /// not, the cue is present — a Reduce Motion user loses the pulse, never the marker.
    @Test("The cue survives the non-animated (editor) marker too")
    func cueIsPresentWithoutAnimation() {
        for animated in [true, false] {
            let node = ExitMarkerFixture.node(wallThickness: 0.1, sillY: 0.9,
                                              outwardZ: 1, animated: animated)
            var found = false
            node.enumerateHierarchy { child, _ in
                if child.name == ExitMarkerFixture.NodeName.cueChevron { found = true }
            }
            #expect(found, "animated=\(animated) lost the non-colour cue")
        }
    }
}

// MARK: - The route, as an ordered list of steps

@Suite("House scene — the VoiceOver alternative to the 3D")
struct HouseSceneStepsTests {

    private func waypoint(_ kind: String, _ x: Double, floor: String = "f1",
                          node: String) -> String {
        """
        {"x": \(x), "y": 1.0, "floor_id": "\(floor)", "node_id": "\(node)", "kind": "\(kind)"}
        """
    }

    /// Decode-only, like the app gets it.
    private func roomPlan(roomID: String, floorID: String, openingID: String,
                          exitID: String) throws -> RoomRoutePlan {
        let json = """
        {
          "room_id": "\(roomID)", "room_name": "Bedroom", "floor_id": "\(floorID)",
          "primary": {
            "waypoints": [
              \(waypoint("room", 0, floor: floorID, node: roomID)),
              \(waypoint("path", 1, floor: floorID, node: openingID)),
              \(waypoint("opening", 4, floor: floorID, node: openingID)),
              \(waypoint("opening", 8, floor: floorID, node: exitID)),
              \(waypoint("exterior", 8, floor: floorID, node: "EXTERIOR"))
            ],
            "length_m": 8.0, "uses_stairs": false, "uses_window": false,
            "exit_id": "\(exitID)"
          },
          "findings": []
        }
        """
        return try JSONDecoder().decode(RoomRoutePlan.self, from: Data(json.utf8))
    }

    private func bed() throws -> (HomeModel, RoomRoutePlan) {
        let home = try FixtureLoader.load(.bungalow)
        let floor = try #require(home.floors.first)
        let room = try #require(floor.rooms.first)
        let interior = floor.openings.first { !$0.isExit }
        let exit = try #require(floor.openings.first { $0.isExit })
        let plan = try roomPlan(roomID: room.id, floorID: floor.id,
                                openingID: interior?.id ?? exit.id, exitID: exit.id)
        return (home, plan)
    }

    /// THE acceptance criterion: an ordered list, numbered 1…n with no gaps.
    @Test("The route comes back as an ordered list of numbered steps")
    func stepsAreOrderedAndDense() throws {
        let (home, plan) = try bed()
        let steps = HouseSceneAccessibility.steps(for: plan, in: home, drawn: nil)

        #expect(!steps.isEmpty, "a route the engine returned must produce steps")
        #expect(steps.map(\.number) == Array(1...steps.count), "numbering must stay dense")
        #expect(steps.first?.title == "Start here")
        #expect(steps.last?.title == "Out to safety")
    }

    /// The unification requirement: the numbers spoken ARE the numbers drawn. Both come from
    /// `RouteGeometry.numberedStops`, so this cannot drift without the test noticing.
    @Test("Spoken step numbers match the numbered chips drawn on the model")
    func spokenNumbersMatchTheDrawnChips() throws {
        let (home, plan) = try bed()
        let primary = try #require(plan.primary)
        let chips = RouteGeometry.numberedStops(for: primary)
        let steps = HouseSceneAccessibility.steps(for: plan, in: home, drawn: chips)

        #expect(steps.map(\.number) == chips.map(\.number))
        #expect(steps.map(\.title) == chips.map(\.kind.title))
        for (step, chip) in zip(steps, chips) {
            #expect(step.spoken.hasPrefix(chip.caption),
                    "spoken '\(step.spoken)' must start with the drawn chip '\(chip.caption)'")
        }
    }

    /// Passing the overlay's real `drawnSteps` and passing nil must give the same answer, or
    /// the affordance would read differently depending on whether a rebuild happened to be in
    /// flight.
    @Test("Drawn chips and the fallback numbering agree")
    func drawnAndDerivedNumberingAgree() throws {
        let (home, plan) = try bed()
        let primary = try #require(plan.primary)
        let fromOverlay = HouseSceneAccessibility.steps(
            for: plan, in: home, drawn: RouteGeometry.numberedStops(for: primary))
        let derived = HouseSceneAccessibility.steps(for: plan, in: home, drawn: nil)
        #expect(fromOverlay == derived)
    }

    /// The narration is the SHARED narrator, not a second copy: every detail line this produces
    /// must be a sentence `RouteNarration` produced for the same route.
    @Test("Step detail comes from RouteNarration, never from a second narrator")
    func detailComesFromTheSharedNarrator() throws {
        let (home, plan) = try bed()
        let primary = try #require(plan.primary)
        let sentences = Set(RouteNarration.sentences(for: primary, from: plan.room_id, in: home))
        let steps = HouseSceneAccessibility.steps(for: plan, in: home, drawn: nil)
        let details = steps.compactMap(\.detail)

        #expect(!details.isEmpty, "the steps must carry the narrated instructions")
        for detail in details {
            #expect(sentences.contains(detail), "'\(detail)' is not a RouteNarration sentence")
        }
    }

    /// Standing still is not an instruction, so the start chip has no narrated detail — but it
    /// still gets a step, because "you are here" is orientation a blind user cannot get from the
    /// model.
    @Test("The start stop is listed, without inventing an instruction for it")
    func startIsListedWithoutAnInstruction() throws {
        let (home, plan) = try bed()
        let steps = HouseSceneAccessibility.steps(for: plan, in: home, drawn: nil)
        let start = try #require(steps.first)
        #expect(start.title == "Start here")
        #expect(start.detail == nil)
        #expect(start.spoken == "1. Start here")
    }

    /// The user's own meeting point is the last thing a household needs to hear. It has no chip
    /// (it is outside the building and off the drawing), so it must be appended rather than
    /// dropped by the "one line per chip" rule.
    @Test("The meeting point is appended as a final step, never dropped")
    func meetingPointBecomesTheLastStep() throws {
        let (home, plan) = try bed()
        let steps = HouseSceneAccessibility.steps(for: plan, in: home, drawn: nil,
                                                  meetingPoint: "the big oak across the street")
        let last = try #require(steps.last)
        #expect(last.title.contains("the big oak across the street"))
        #expect(steps.map(\.number) == Array(1...steps.count))
    }

    /// A route the engine did not compute produces no steps and says so — it never fabricates
    /// a way out.
    @Test("No engine route means no invented steps")
    func noRouteMeansNoSteps() throws {
        let home = try FixtureLoader.load(.bungalow)
        let json = """
        {"room_id": "r1", "room_name": "Box Room", "floor_id": "f1", "findings": []}
        """
        let plan = try JSONDecoder().decode(RoomRoutePlan.self, from: Data(json.utf8))
        #expect(HouseSceneAccessibility.steps(for: plan, in: home, drawn: nil).isEmpty)
        #expect(HouseSceneAccessibility.spokenSteps(for: plan, in: home, drawn: nil)
                == "The routing engine returned no route for the Box Room.")
    }

    @Test("The whole route reads as one utterance for the custom action")
    func spokenDescriptionIsOneOrderedUtterance() throws {
        let (home, plan) = try bed()
        let spoken = HouseSceneAccessibility.spokenSteps(for: plan, in: home, drawn: nil)
        let steps = HouseSceneAccessibility.steps(for: plan, in: home, drawn: nil)
        #expect(spoken.hasPrefix("Route from the Bedroom, \(steps.count) steps."))
        for step in steps {
            #expect(spoken.contains(step.spoken))
        }
    }
}

// MARK: - The scene summary

@Suite("House scene — what VoiceOver reads for the 3D surface")
struct HouseSceneSummaryTests {

    private func label(person: String? = nil,
                       room: String? = nil,
                       hasRoutes: Bool = true,
                       floors: Int = 2,
                       simulation: HouseSceneAccessibility.SimulationState? = nil) -> String {
        HouseSceneAccessibility.sceneLabel(homeName: "Maple Street",
                                           floorName: "Ground Floor",
                                           floorNumber: 1,
                                           floorCount: floors,
                                           roomCount: 5,
                                           personName: person,
                                           roomName: room,
                                           hasRoutes: hasRoutes,
                                           simulation: simulation)
    }

    @Test("The scene names the home, the floor and the room count")
    func summaryOrientsTheUser() {
        let text = label()
        #expect(text.hasPrefix("3D model of Maple Street."))
        #expect(text.contains("Showing Ground Floor, floor 1 of 2, 5 rooms."))
    }

    @Test("A single-floor home does not claim to be floor 1 of 1")
    func singleFloorHomeReadsNaturally() {
        #expect(label(floors: 1).contains("Ground Floor, 5 rooms."))
        #expect(!label(floors: 1).contains("floor 1 of 1"))
    }

    @Test("The selected person and room are both announced")
    func selectionIsAnnounced() {
        #expect(label(person: "Ada", room: "Bedroom 1")
            .contains("Showing the escape route for Ada, starting in the Bedroom 1."))
        #expect(label(room: "Bedroom 1")
            .contains("Showing the escape route from the Bedroom 1."))
        #expect(label().contains("Showing the primary escape route for everyone."))
    }

    /// Honest about the absence of routes: the app never implies a plan it does not have.
    @Test("With no plan fetched, the scene says so rather than implying one")
    func missingRoutesAreStated() {
        #expect(label(hasRoutes: false).contains("No escape routes are drawn yet."))
    }

    @Test("With no simulation the summary says nothing about a fire")
    func quietWhenNothingIsSimulated() {
        let text = label()
        #expect(!text.lowercased().contains("fire"))
        #expect(!text.lowercased().contains("untenable"))
    }

    @Test("A running simulation announces the origin, the clock and the hazard state")
    func simulationStateIsAnnounced() {
        let text = label(simulation: .init(originRoomName: "Kitchen",
                                           isPlaying: true,
                                           elapsedSpoken: "12 seconds",
                                           durationSpoken: "1 minute 30 seconds",
                                           untenableRoomNames: ["Hall", "Kitchen"]))
        #expect(text.contains("Fire simulation loaded. The fire starts in the Kitchen."))
        #expect(text.contains("12 seconds of 1 minute 30 seconds, playing."))
        #expect(text.contains("The engine models 2 rooms as untenable at this point: "
                              + "Hall and Kitchen."))
    }

    @Test("Before the hazard spreads, the summary says so rather than staying silent")
    func noUntenableRoomsIsStatedExplicitly() {
        let text = label(simulation: .init(originRoomName: "Kitchen",
                                           isPlaying: false,
                                           elapsedSpoken: "0 seconds",
                                           durationSpoken: "1 minute",
                                           untenableRoomNames: []))
        #expect(text.contains("No rooms are untenable yet at this point in the simulation."))
        #expect(text.contains("0 seconds of 1 minute, paused."))
    }

    /// `overtaken_by_hazard` is an honest negative result. A screen-reader user gets the SAME
    /// sentence a sighted user reads on the finding card — same vocabulary, same tier, not
    /// softened for being spoken and not withheld until the animation ends.
    @Test("overtaken_by_hazard is spoken in the finding cards' own language")
    func overtakenIsNeverSoftened() {
        let one = label(simulation: .init(originRoomName: "Kitchen",
                                          isPlaying: true,
                                          elapsedSpoken: "20 seconds",
                                          durationSpoken: "1 minute",
                                          untenableRoomNames: ["Kitchen"],
                                          overtakenPeopleNames: ["Ada"]))
        #expect(one.contains("Hazard reaches them first"),
                "the spoken summary must use the finding card's own title")
        #expect(one.contains("reaches a room on Ada's way out before they clear it."))

        let many = label(simulation: .init(originRoomName: "Kitchen",
                                           isPlaying: false,
                                           elapsedSpoken: "20 seconds",
                                           durationSpoken: "1 minute",
                                           untenableRoomNames: ["Kitchen"],
                                           overtakenPeopleNames: ["Ada", "Bo"]))
        #expect(many.contains("Hazard reaches them first"))
        #expect(many.contains("Ada and Bo"))
    }

    @Test("Lists read as speech, not as comma soup")
    func listsAreSpoken() {
        #expect(HouseSceneAccessibility.list([]) == "")
        #expect(HouseSceneAccessibility.list(["Hall"]) == "Hall")
        #expect(HouseSceneAccessibility.list(["Hall", "Kitchen"]) == "Hall and Kitchen")
        #expect(HouseSceneAccessibility.list(["Hall", "Kitchen", "Landing"])
                == "Hall, Kitchen and Landing")
    }
}
