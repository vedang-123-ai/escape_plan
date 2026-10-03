//  EvacuationJourneyTests.swift — "Who does what" in the fire simulation (trim 2, 2026-10-03),
//  and the playback speed menu.
//
//  Known-answer tests against the bungalow fixture, whose geometry is simple enough to check by
//  hand: Living Room (0,0)-(5,4), Kitchen (5,0)-(10,4), Bedroom (0,4)-(5,8), Bathroom (5,4)-(10,8);
//  front door `d_front` on the Living Room's y = 0 wall, window `w_bedroom` on the Bedroom's y = 8
//  wall. The tracks are hand-written in the shape the engine sends; nothing here computes a route.
//
//  Compiled by BOTH runners (the SwiftPM EditorCore harness and the Xcode test target).

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class EvacuationJourneyTests: XCTestCase {

    private func step(_ x: Double, _ y: Double, floor: String = "f1", t: Double,
                      kind: String = "path") -> TimedStep {
        TimedStep(x: x, y: y, floor_id: floor, t_s: t, kind: kind)
    }

    private func track(start: String, exit: String, steps: [TimedStep], egress: Double,
                       name: String = "Ana", window: Bool = false,
                       overtaken: Bool = false) -> OccupantTrack {
        OccupantTrack(profile_id: "p.\(name)", profile_name: name, gait: .adult,
                      start_room_id: start, exit_id: exit, steps: steps,
                      distance_m: 8, egress_time_s: egress,
                      uses_window: window, overtaken_by_hazard: overtaken)
    }

    // MARK: - Steps to rooms

    /// Bedroom → through the Living Room → out the front door. The door point on the shared
    /// y = 4 wall falls in the Bedroom (ray casting), the step outside falls in no room.
    func testBedroomThroughLivingRoomToTheFrontDoor() throws {
        let home = try Fixtures.load("bungalow")
        let steps = [step(2.5, 6, t: 0, kind: "room"), step(2.5, 4, t: 2, kind: "opening"),
                     step(2.5, 2, t: 4), step(2.45, 0, t: 6, kind: "opening"),
                     step(2.45, -0.5, t: 7, kind: "exterior")]
        XCTAssertEqual(EvacuationJourneyNarrator.roomIDs(along: steps, in: home),
                       ["r_bedroom", "r_living"])

        let journey = EvacuationJourneyNarrator.journey(
            for: track(start: "r_bedroom", exit: "d_front", steps: steps, egress: 7), in: home)
        XCTAssertEqual(journey.startRoomName, "Bedroom")
        XCTAssertEqual(journey.roomsPassed, ["Living Room"])
        XCTAssertEqual(journey.exitDescription, "the door in the Living Room")
        XCTAssertFalse(journey.leavesThroughWindow)
        XCTAssertEqual(journey.startLine, "Starts in Bedroom")
        XCTAssertEqual(journey.passesLine, "Goes through Living Room")
        XCTAssertEqual(journey.exitLine, "Leaves through the door in the Living Room")
        XCTAssertEqual(journey.timeOutLine, "Outside at 0:07")
    }

    /// Repeated samples in one room fold to one entry, and the start room is not "passed".
    /// The point on the x = 5 wall between Living Room and Kitchen falls in the Kitchen.
    func testRepeatsFoldAndTheStartRoomIsNotPassed() throws {
        let home = try Fixtures.load("bungalow")
        let steps = [step(8, 2, t: 0, kind: "room"), step(7, 2, t: 1), step(5, 1.8, t: 2, kind: "opening"),
                     step(4, 2, t: 3), step(3, 1, t: 4), step(2.45, 0, t: 5, kind: "opening"),
                     step(2.45, -0.5, t: 6, kind: "exterior")]
        XCTAssertEqual(EvacuationJourneyNarrator.roomIDs(along: steps, in: home),
                       ["r_kitchen", "r_living"])
        let journey = EvacuationJourneyNarrator.journey(
            for: track(start: "r_kitchen", exit: "d_front", steps: steps, egress: 6), in: home)
        XCTAssertEqual(journey.roomsPassed, ["Living Room"])
    }

    /// Out through the Bedroom window without crossing another room.
    func testStraightOutThroughAWindow() throws {
        let home = try Fixtures.load("bungalow")
        let steps = [step(2.5, 6, t: 0, kind: "room"), step(2.5, 8, t: 3, kind: "opening"),
                     step(2.5, 8.5, t: 5, kind: "exterior")]
        let journey = EvacuationJourneyNarrator.journey(
            for: track(start: "r_bedroom", exit: "w_bedroom", steps: steps, egress: 65, window: true),
            in: home)
        XCTAssertEqual(journey.roomsPassed, [])
        XCTAssertEqual(journey.passesLine, "Goes straight to the way out")
        XCTAssertTrue(journey.leavesThroughWindow)
        XCTAssertEqual(journey.exitLine, "Climbs out through the window in the Bedroom")
        XCTAssertEqual(journey.timeOutLine, "Outside at 1:05")
    }

    /// A floor this home does not have, and an exit id it does not have: nothing is snapped or
    /// invented. The rooms stay empty and the exit falls back to the track's own flag.
    func testUnknownFloorAndExitAreNotGuessed() throws {
        let home = try Fixtures.load("bungalow")
        let steps = [step(2.5, 6, floor: "f9", t: 0), step(2.5, 2, floor: "f9", t: 3)]
        XCTAssertEqual(EvacuationJourneyNarrator.roomIDs(along: steps, in: home), [])
        let door = EvacuationJourneyNarrator.journey(
            for: track(start: "r_gone", exit: "nope", steps: steps, egress: 3), in: home)
        XCTAssertEqual(door.startRoomName, "r_gone", "an unknown room shows its id, not a made-up name")
        XCTAssertEqual(door.exitLine, "Leaves through an outside door")
        let window = EvacuationJourneyNarrator.journey(
            for: track(start: "r_bedroom", exit: "nope", steps: steps, egress: 3, window: true), in: home)
        XCTAssertEqual(window.exitLine, "Climbs out through a window")
    }

    /// VoiceOver hears one person as one element, warning included when the engine set the flag.
    func testSpokenSummaryAndTheOvertakenWarning() throws {
        let home = try Fixtures.load("bungalow")
        let steps = [step(2.5, 6, t: 0), step(2.5, 2, t: 4), step(2.45, -0.5, t: 18)]
        let safe = EvacuationJourneyNarrator.journey(
            for: track(start: "r_bedroom", exit: "d_front", steps: steps, egress: 18), in: home)
        XCTAssertEqual(safe.spokenSummary,
                       "Ana. Starts in Bedroom. Goes through Living Room. "
                       + "Leaves through the door in the Living Room. Outside after 18 seconds.")
        XCTAssertFalse(safe.overtaken)

        let caught = EvacuationJourneyNarrator.journey(
            for: track(start: "r_bedroom", exit: "d_front", steps: steps, egress: 18, overtaken: true),
            in: home)
        XCTAssertTrue(caught.overtaken)
        XCTAssertTrue(caught.spokenSummary.hasSuffix(
            "Warning. The modeled fire reaches a room on their way out before they clear it."))
    }

    /// One journey per track, in the engine's order.
    func testJourneysFollowTheEngineOrder() throws {
        let home = try Fixtures.load("bungalow")
        let steps = [step(2.5, 6, t: 0), step(2.45, -0.5, t: 9)]
        let timeline = EvacuationTimeline(
            home_id: home.home_id, origin_room_id: "r_kitchen",
            tracks: [track(start: "r_bedroom", exit: "d_front", steps: steps, egress: 9, name: "Zed"),
                     track(start: "r_bedroom", exit: "d_front", steps: steps, egress: 9, name: "Amy")],
            hazard: [], duration_s: 9)
        XCTAssertEqual(EvacuationJourneyNarrator.journeys(for: timeline, in: home).map(\.personName),
                       ["Zed", "Amy"])
    }

    func testListJoinsNamesInPlainEnglish() {
        XCTAssertEqual(EvacuationJourneyNarrator.list([]), "")
        XCTAssertEqual(EvacuationJourneyNarrator.list(["Hall"]), "Hall")
        XCTAssertEqual(EvacuationJourneyNarrator.list(["Hall", "Den"]), "Hall and Den")
        XCTAssertEqual(EvacuationJourneyNarrator.list(["Hall", "Den", "Porch"]), "Hall, Den and Porch")
    }

    // MARK: - Speed menu (trim 2)

    func testTheSpeedMenuOffersQuarterToDouble() {
        XCTAssertEqual(EvacuationPlaybackModel.supportedRates, [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2])
        XCTAssertEqual(EvacuationPlaybackModel.supportedRates.map(EvacuationPlaybackModel.rateLabel),
                       ["0.25×", "0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×"])
        XCTAssertEqual(EvacuationPlaybackModel.supportedRates.map(EvacuationPlaybackModel.spokenRateLabel),
                       ["Quarter speed", "Half speed", "Three quarter speed", "Normal speed",
                        "1.25 times speed", "1.5 times speed", "Double speed"])
    }

    /// Every menu entry is a rate the model keeps as chosen, not one the clamp rewrites.
    func testEverySupportedRateSurvivesTheClamp() {
        let model = EvacuationPlaybackModel()
        for rate in EvacuationPlaybackModel.supportedRates {
            model.playbackRate = rate
            XCTAssertEqual(model.playbackRate, rate)
        }
    }
}
