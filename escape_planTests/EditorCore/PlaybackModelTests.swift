//  PlaybackModelTests.swift — the evacuation timeline wire contract and its playback clock.
//
//  Compiled by BOTH runners (see tools/editorcore/Package.swift): the SwiftPM harness, where
//  the code under test is module `EditorCore`, and the Xcode escape_planTests target, where it
//  is `escape_plan`. Everything exercised here is pure Foundation, which is the whole reason
//  `tick(deltaTime:)` takes its delta as an argument — a full timeline runs in a loop with no
//  run loop, no CADisplayLink, and no waiting.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class PlaybackModelTests: XCTestCase {

    // MARK: - Fixtures

    /// A hand-written timeline: two occupants, one of whom the engine flagged overtaken, and
    /// a hazard that spreads through three rooms.
    private func makeTimeline(duration: Double = 60,
                              is_illustrative: Bool = true) -> EvacuationTimeline {
        EvacuationTimeline(
            home_id: "home-1",
            origin_room_id: "r_kitchen",
            tracks: [
                OccupantTrack(profile_id: "p1", profile_name: "Ana", gait: .adult,
                              start_room_id: "r_bed1", exit_id: "o_front",
                              steps: [TimedStep(x: 0, y: 0, floor_id: "f0", t_s: 0, kind: "room"),
                                      TimedStep(x: 3, y: 0, floor_id: "f0", t_s: 18, kind: "exterior")],
                              distance_m: 6, egress_time_s: 18),
                OccupantTrack(profile_id: "p2", profile_name: "Sam", gait: .child,
                              start_room_id: "r_bed2", exit_id: "o_front",
                              steps: [TimedStep(x: 0, y: 4, floor_id: "f0", t_s: 0, kind: "room"),
                                      TimedStep(x: 3, y: 4, floor_id: "f0", t_s: 41, kind: "exterior")],
                              distance_m: 9, egress_time_s: 41,
                              overtaken_by_hazard: true)
            ],
            hazard: [
                HazardEvent(room_id: "r_kitchen", floor_id: "f0", untenable_at_s: 0),
                HazardEvent(room_id: "r_hall", floor_id: "f0", untenable_at_s: 20),
                HazardEvent(room_id: "r_bed2", floor_id: "f0", untenable_at_s: 35)
            ],
            duration_s: duration,
            is_illustrative: is_illustrative)
    }

    private func loaded(_ timeline: EvacuationTimeline? = nil) -> EvacuationPlaybackModel {
        let model = EvacuationPlaybackModel()
        model.load(timeline ?? makeTimeline())
        return model
    }

    private func decode(_ json: String) throws -> EvacuationTimeline {
        try HomeModel.decoder.decode(EvacuationTimeline.self, from: Data(json.utf8))
    }

    // MARK: - Decoding: the full payload

    func testDecodesFullTimeline() throws {
        let timeline = try decode("""
        {
          "home_id": "home-1",
          "profile_set_id": "ps-1",
          "origin_room_id": "r_kitchen",
          "duration_s": 62.5,
          "is_illustrative": true,
          "tracks": [{
            "profile_id": "p1", "profile_name": "Ana", "gait": "elderly",
            "start_room_id": "r_bed1", "exit_id": "o_front",
            "steps": [
              {"x": 0.0, "y": 0.0, "floor_id": "f0", "t_s": 0.0, "kind": "room"},
              {"x": 2.5, "y": 1.0, "floor_id": "f0", "t_s": 12.0, "kind": "exterior"}
            ],
            "distance_m": 5.5, "egress_time_s": 12.0,
            "uses_stairs": true, "uses_window": false, "overtaken_by_hazard": true
          }],
          "hazard": [
            {"room_id": "r_kitchen", "floor_id": "f0", "untenable_at_s": 0.0},
            {"room_id": "r_hall", "floor_id": "f0", "untenable_at_s": 22.0}
          ],
          "findings": [
            {"kind": "no_secondary_egress", "room_id": "r_bed1", "detail": "Only one way out."}
          ]
        }
        """)

        XCTAssertEqual(timeline.home_id, "home-1")
        XCTAssertEqual(timeline.profile_set_id, "ps-1")
        XCTAssertEqual(timeline.origin_room_id, "r_kitchen")
        XCTAssertEqual(timeline.duration_s, 62.5)
        XCTAssertTrue(timeline.is_illustrative)
        XCTAssertEqual(timeline.tracks.count, 1)
        XCTAssertEqual(timeline.tracks[0].gait, .elderly)
        XCTAssertTrue(timeline.tracks[0].uses_stairs)
        XCTAssertTrue(timeline.tracks[0].overtaken_by_hazard)
        XCTAssertEqual(timeline.tracks[0].steps.count, 2)
        XCTAssertEqual(timeline.hazard.count, 2)
        XCTAssertEqual(timeline.findings.count, 1)
        XCTAssertEqual(timeline.findings[0].kind, .no_secondary_egress)
        XCTAssertEqual(timeline.findings[0].detail, "Only one way out.")
    }

    // MARK: - Decoding: tolerance

    /// The minimum a backend can send. Everything optional is absent, and the whole timeline
    /// must still decode — a missing field never costs the entire simulation.
    func testDecodesMinimalTimelineWithEveryOptionalAbsent() throws {
        let timeline = try decode("""
        {
          "home_id": "h", "origin_room_id": "r1", "duration_s": 30,
          "tracks": [{
            "profile_id": "p1", "profile_name": "Ana",
            "start_room_id": "r1", "exit_id": "o1",
            "steps": [{"x": 0, "y": 0, "floor_id": "f0", "t_s": 0, "kind": "room"}],
            "distance_m": 1, "egress_time_s": 9
          }]
        }
        """)

        XCTAssertNil(timeline.profile_set_id)
        XCTAssertEqual(timeline.hazard, [], "a missing hazard list means nothing goes untenable")
        XCTAssertEqual(timeline.findings, [], "a missing findings list is an empty list")
        XCTAssertTrue(timeline.is_illustrative,
                      "a timeline that forgot to say it is illustrative still gets the disclaimer")
        XCTAssertEqual(timeline.tracks[0].gait, .adult)
        XCTAssertFalse(timeline.tracks[0].uses_stairs)
        XCTAssertFalse(timeline.tracks[0].uses_window)
        XCTAssertFalse(timeline.tracks[0].overtaken_by_hazard)
    }

    /// Fields this build has never heard of — top level, inside a track, inside a step — must
    /// be ignored, not fatal. The backend ships ahead of the app routinely.
    func testUnknownFieldsAndEnumCasesDoNotFailTheDecode() throws {
        let timeline = try decode("""
        {
          "home_id": "h", "origin_room_id": "r1", "duration_s": 30,
          "spread_model": "v2-alpha",
          "smoke_layer": [{"room_id": "r1", "height_m": 1.2}],
          "tracks": [{
            "profile_id": "p1", "profile_name": "Ana", "gait": "hoverboard",
            "start_room_id": "r1", "exit_id": "o1",
            "carry_assist": true,
            "steps": [{"x": 0, "y": 0, "floor_id": "f0", "t_s": 0, "kind": "teleport",
                       "crawl": true}],
            "distance_m": 1, "egress_time_s": 9
          }],
          "hazard": [{"room_id": "r1", "floor_id": "f0", "untenable_at_s": 4, "flashover": true}],
          "findings": [{"kind": "some_future_kind", "room_id": "r1", "detail": "New warning."}]
        }
        """)

        XCTAssertEqual(timeline.tracks[0].gait, .unknown,
                       "an unrecognized gait degrades to a figure, it does not fail the timeline")
        XCTAssertEqual(timeline.tracks[0].steps[0].kind, "teleport",
                       "step kind is a raw String on purpose — it round-trips whatever arrives")
        XCTAssertEqual(timeline.hazard[0].untenable_at_s, 4)
        XCTAssertEqual(timeline.findings[0].kind, .unknown)
        XCTAssertEqual(timeline.findings[0].detail, "New warning.",
                       "the engine's detail still reads, so the finding is still shown")
    }

    func testExplicitNullOptionalsDecode() throws {
        let timeline = try decode("""
        {
          "home_id": "h", "profile_set_id": null, "origin_room_id": "r1",
          "duration_s": 12, "tracks": [], "hazard": null, "findings": null
        }
        """)
        XCTAssertNil(timeline.profile_set_id)
        XCTAssertEqual(timeline.hazard, [])
        XCTAssertEqual(timeline.findings, [])
    }

    func testTimelineRoundTripsThroughEncoding() throws {
        let original = makeTimeline()
        let data = try HomeModel.encoder().encode(original)
        let decoded = try HomeModel.decoder.decode(EvacuationTimeline.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Loading

    func testFreshModelIsEmptyAndSafeToRead() {
        let model = EvacuationPlaybackModel()
        XCTAssertNil(model.timeline)
        XCTAssertFalse(model.hasTimeline)
        XCTAssertEqual(model.duration_s, 0)
        XCTAssertEqual(model.progress, 0, "no timeline must read as 0, never NaN")
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.untenableRoomIDs(at: 999), [])
        XCTAssertEqual(model.overtakenTracks, [])
        XCTAssertFalse(model.isIllustrative)
    }

    func testLoadRewindsAndPausesButKeepsPreferences() {
        let model = loaded()
        model.playbackRate = 2
        model.isSteppedMode = true
        model.play()
        model.tick(deltaTime: 5)
        XCTAssertGreaterThan(model.currentTime_s, 0)

        model.load(makeTimeline(duration: 90))
        XCTAssertEqual(model.currentTime_s, 0, "a new ignition rewinds")
        XCTAssertFalse(model.isPlaying, "a new ignition does not auto-play by itself")
        XCTAssertEqual(model.duration_s, 90)
        XCTAssertEqual(model.playbackRate, 2, "rate is a user preference and survives")
        XCTAssertTrue(model.isSteppedMode, "Reduce Motion is an accessibility state and survives")
    }

    func testLoadNilClearsEverything() {
        let model = loaded()
        model.play()
        model.tick(deltaTime: 3)

        model.load(nil)
        XCTAssertNil(model.timeline)
        XCTAssertFalse(model.hasTimeline)
        XCTAssertEqual(model.currentTime_s, 0)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.overtakenTracks, [])
    }

    // MARK: - tick: clamping and monotonicity

    func testTickDoesNothingWhilePaused() {
        let model = loaded()
        model.tick(deltaTime: 10)
        XCTAssertEqual(model.currentTime_s, 0)
    }

    func testTickAdvancesByDeltaTimesRate() {
        let model = loaded()
        model.play()
        model.tick(deltaTime: 0.5)
        XCTAssertEqual(model.currentTime_s, 0.5, accuracy: 1e-9)

        model.playbackRate = 2
        model.tick(deltaTime: 0.5)
        XCTAssertEqual(model.currentTime_s, 1.5, accuracy: 1e-9)

        model.playbackRate = 0.5
        model.tick(deltaTime: 1.0)
        XCTAssertEqual(model.currentTime_s, 2.0, accuracy: 1e-9)
    }

    func testTickIgnoresNonPositiveAndNonFiniteDeltas() {
        let model = loaded()
        model.play()
        model.tick(deltaTime: 4)
        let mark = model.currentTime_s

        model.tick(deltaTime: 0)
        model.tick(deltaTime: -30)
        model.tick(deltaTime: .nan)
        model.tick(deltaTime: .infinity)
        XCTAssertEqual(model.currentTime_s, mark, "the playhead never moves backwards on a tick")
        XCTAssertTrue(model.currentTime_s.isFinite)
    }

    func testTickIsMonotonicAcrossAWholeTimeline() {
        let model = loaded(makeTimeline(duration: 30))
        model.play()
        var previous = model.currentTime_s
        for _ in 0..<2_000 {
            model.tick(deltaTime: 1.0 / 60.0)
            XCTAssertGreaterThanOrEqual(model.currentTime_s, previous)
            XCTAssertLessThanOrEqual(model.currentTime_s, model.duration_s)
            previous = model.currentTime_s
        }
    }

    func testTickClampsAtDurationAndStops() {
        let model = loaded(makeTimeline(duration: 10))
        model.play()
        model.tick(deltaTime: 9.5)
        XCTAssertTrue(model.isPlaying)

        model.tick(deltaTime: 5)
        XCTAssertEqual(model.currentTime_s, 10, "clamped exactly at duration, never past it")
        XCTAssertFalse(model.isPlaying, "playback stops at the end rather than looping")
        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(model.progress, 1, accuracy: 1e-9)

        model.tick(deltaTime: 5)
        XCTAssertEqual(model.currentTime_s, 10, "a tick after the end is inert")
    }

    func testPlayAfterFinishReplaysFromTheStart() {
        let model = loaded(makeTimeline(duration: 10))
        model.play()
        model.tick(deltaTime: 20)
        XCTAssertTrue(model.isFinished)

        model.play()
        XCTAssertEqual(model.currentTime_s, 0)
        XCTAssertTrue(model.isPlaying)
    }

    func testPlaybackRateIsClampedToASaneRange() {
        let model = loaded()
        model.playbackRate = 0
        XCTAssertEqual(model.playbackRate, EvacuationPlaybackModel.minPlaybackRate,
                       "a zero rate would silently wedge playback")
        model.playbackRate = -3
        XCTAssertEqual(model.playbackRate, EvacuationPlaybackModel.minPlaybackRate)
        model.playbackRate = 1_000
        XCTAssertEqual(model.playbackRate, EvacuationPlaybackModel.maxPlaybackRate)
    }

    // MARK: - tick: stepped (Reduce Motion) mode

    func testSteppedModeAdvancesInWholeStepsOnly() {
        let model = loaded(makeTimeline(duration: 30))
        model.isSteppedMode = true
        model.stepInterval_s = 1
        model.play()

        model.tick(deltaTime: 0.4)
        XCTAssertEqual(model.currentTime_s, 0, "under one step, the playhead does not move")
        model.tick(deltaTime: 0.4)
        XCTAssertEqual(model.currentTime_s, 0)
        model.tick(deltaTime: 0.4)
        XCTAssertEqual(model.currentTime_s, 1, accuracy: 1e-9, "banked time becomes one jump")

        model.tick(deltaTime: 2.5)
        XCTAssertEqual(model.currentTime_s, 3, accuracy: 1e-9)
    }

    func testSteppedModeStillReachesTheEnd() {
        let model = loaded(makeTimeline(duration: 4.5))
        model.isSteppedMode = true
        model.stepInterval_s = 1
        model.play()
        for _ in 0..<200 { model.tick(deltaTime: 0.1) }
        XCTAssertEqual(model.currentTime_s, 4.5, accuracy: 1e-9,
                       "a tail shorter than one step must not strand playback")
        XCTAssertFalse(model.isPlaying)
    }

    func testTogglingSteppedModeDropsBankedTime() {
        let model = loaded()
        model.isSteppedMode = true
        model.stepInterval_s = 2
        model.play()
        model.tick(deltaTime: 1.9)
        XCTAssertEqual(model.currentTime_s, 0)

        model.isSteppedMode = false
        model.tick(deltaTime: 0.5)
        XCTAssertEqual(model.currentTime_s, 0.5, accuracy: 1e-9,
                       "switching modes must not release a hoarded jump")
    }

    // MARK: - Transport

    func testSeekClampsAndDoesNotChangePlayState() {
        let model = loaded(makeTimeline(duration: 60))
        model.seek(to: 25)
        XCTAssertEqual(model.currentTime_s, 25)
        XCTAssertFalse(model.isPlaying, "seeking does not start playback")

        model.seek(to: -100)
        XCTAssertEqual(model.currentTime_s, 0)
        model.seek(to: 10_000)
        XCTAssertEqual(model.currentTime_s, 60)
        model.seek(to: .nan)
        XCTAssertEqual(model.currentTime_s, 0)

        model.play()
        model.seek(to: 30)
        XCTAssertTrue(model.isPlaying, "seeking while playing keeps playing")
    }

    func testSeekOnAnEmptyModelIsInert() {
        let model = EvacuationPlaybackModel()
        model.seek(to: 42)
        XCTAssertEqual(model.currentTime_s, 0)
    }

    func testTogglePlaybackAndPauseAndRestart() {
        let model = loaded()
        XCTAssertFalse(model.isPlaying)
        model.togglePlayback()
        XCTAssertTrue(model.isPlaying)
        model.togglePlayback()
        XCTAssertFalse(model.isPlaying)

        model.seek(to: 40)
        model.restart()
        XCTAssertEqual(model.currentTime_s, 0)
        XCTAssertTrue(model.isPlaying, "restart plays — it is the replay button")

        model.pause()
        XCTAssertFalse(model.isPlaying)
    }

    func testPlayIsInertWithoutATimeline() {
        let model = EvacuationPlaybackModel()
        model.play()
        XCTAssertFalse(model.isPlaying)
        model.restart()
        XCTAssertFalse(model.isPlaying)
    }

    func testProgressTracksThePlayhead() {
        let model = loaded(makeTimeline(duration: 50))
        XCTAssertEqual(model.progress, 0)
        model.seek(to: 25)
        XCTAssertEqual(model.progress, 0.5, accuracy: 1e-9)
        model.seek(to: 50)
        XCTAssertEqual(model.progress, 1, accuracy: 1e-9)
    }

    func testProgressIsZeroRatherThanNaNForAZeroLengthTimeline() {
        let model = loaded(makeTimeline(duration: 0))
        XCTAssertEqual(model.progress, 0)
        XCTAssertFalse(model.progress.isNaN)
    }

    // MARK: - untenableRoomIDs(at:)

    func testUntenableRoomIDsAtSeveralTimes() {
        let model = loaded()

        XCTAssertEqual(model.untenableRoomIDs(at: 0), ["r_kitchen"],
                       "the origin room is untenable from the first frame")
        XCTAssertEqual(model.untenableRoomIDs(at: 19.9), ["r_kitchen"])
        XCTAssertEqual(model.untenableRoomIDs(at: 20), ["r_kitchen", "r_hall"],
                       "an event is inclusive at its own boundary")
        XCTAssertEqual(model.untenableRoomIDs(at: 34.5), ["r_kitchen", "r_hall"])
        XCTAssertEqual(model.untenableRoomIDs(at: 35), ["r_kitchen", "r_hall", "r_bed2"])
        XCTAssertEqual(model.untenableRoomIDs(at: 10_000), ["r_kitchen", "r_hall", "r_bed2"])

        XCTAssertFalse(model.untenableRoomIDs(at: 60).contains("r_bed1"),
                       "a room with no hazard event stays clear for the whole timeline")
    }

    func testNoRoomIsUntenableBeforeIgnition() {
        let model = loaded()
        XCTAssertEqual(model.untenableRoomIDs(at: -5), [],
                       "no room is untenable before t = 0")
    }

    func testUntenableRoomIDsOnlyEverGrows() {
        let model = loaded()
        var previous = Set<String>()
        for tenth in 0...600 {
            let now = model.untenableRoomIDs(at: Double(tenth) / 10)
            XCTAssertTrue(previous.isSubset(of: now), "the hazard set must be monotone in time")
            previous = now
        }
    }

    func testUntenableRoomIDsNowFollowsThePlayhead() {
        let model = loaded()
        XCTAssertEqual(model.untenableRoomIDsNow, ["r_kitchen"])
        model.seek(to: 36)
        XCTAssertEqual(model.untenableRoomIDsNow, ["r_kitchen", "r_hall", "r_bed2"])
    }

    func testUntenableTimeForRoom() {
        let model = loaded()
        XCTAssertEqual(model.untenableTime(forRoom: "r_hall"), 20)
        XCTAssertEqual(model.untenableTime(forRoom: "r_kitchen"), 0)
        XCTAssertNil(model.untenableTime(forRoom: "r_bed1"))
    }

    // MARK: - overtakenTracks

    func testOvertakenTracksIsTheEnginesFlagFiltered() {
        let model = loaded()
        XCTAssertEqual(model.tracks.count, 2)
        XCTAssertEqual(model.overtakenTracks.map(\.profile_id), ["p2"])
        XCTAssertEqual(model.overtakenTracks.first?.profile_name, "Sam")
    }

    func testOvertakenTracksIsEmptyWhenTheEngineFlaggedNobody() throws {
        let clean = try decode("""
        {
          "home_id": "h", "origin_room_id": "r1", "duration_s": 20,
          "tracks": [{
            "profile_id": "p1", "profile_name": "Ana",
            "start_room_id": "r1", "exit_id": "o1",
            "steps": [{"x": 0, "y": 0, "floor_id": "f0", "t_s": 0, "kind": "room"}],
            "distance_m": 1, "egress_time_s": 9, "overtaken_by_hazard": false
          }]
        }
        """)
        let model = loaded(clean)
        XCTAssertEqual(model.overtakenTracks, [])
        XCTAssertEqual(model.tracks.count, 1)
    }

    func testOvertakenTracksSurvivesEveryPlaybackState() {
        // The finding is a property of the ENGINE'S answer, not of where the playhead is: it
        // must be reportable before, during, and after the animation.
        let model = loaded()
        XCTAssertEqual(model.overtakenTracks.count, 1)
        model.play()
        model.tick(deltaTime: 5)
        XCTAssertEqual(model.overtakenTracks.count, 1)
        model.tick(deltaTime: 1_000)
        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(model.overtakenTracks.count, 1)
    }

    // MARK: - Escape state

    func testHasEscapedAndActiveTracks() {
        let model = loaded()
        let ana = model.tracks[0]   // out at 18 s
        let sam = model.tracks[1]   // out at 41 s

        XCTAssertFalse(model.hasEscaped(ana, at: 17.9))
        XCTAssertTrue(model.hasEscaped(ana, at: 18), "egress time is inclusive")
        XCTAssertTrue(model.hasEscaped(ana, at: 25))
        XCTAssertFalse(model.hasEscaped(sam, at: 25))

        XCTAssertEqual(model.activeTracks(at: 0).count, 2)
        XCTAssertEqual(model.activeTracks(at: 25).map(\.profile_id), ["p2"])
        XCTAssertEqual(model.activeTracks(at: 60), [])
    }

    // MARK: - Disclaimer flag

    func testIsIllustrativeFollowsTheTimeline() {
        XCTAssertTrue(loaded().isIllustrative)
        XCTAssertFalse(loaded(makeTimeline(is_illustrative: false)).isIllustrative)
        XCTAssertFalse(EvacuationPlaybackModel().isIllustrative)
    }

    // MARK: - Time labels

    func testTimeLabelFormatting() {
        XCTAssertEqual(EvacuationPlaybackModel.timeLabel(0), "0:00")
        XCTAssertEqual(EvacuationPlaybackModel.timeLabel(-4), "0:00")
        XCTAssertEqual(EvacuationPlaybackModel.timeLabel(.nan), "0:00")
        XCTAssertEqual(EvacuationPlaybackModel.timeLabel(9), "0:09")
        XCTAssertEqual(EvacuationPlaybackModel.timeLabel(65), "1:05")
        XCTAssertEqual(EvacuationPlaybackModel.timeLabel(600), "10:00")
    }

    func testSpokenTimeLabelReadsAsDurationNotClockTime() {
        XCTAssertEqual(EvacuationPlaybackModel.spokenTimeLabel(0), "0 seconds")
        XCTAssertEqual(EvacuationPlaybackModel.spokenTimeLabel(1), "1 second")
        XCTAssertEqual(EvacuationPlaybackModel.spokenTimeLabel(42), "42 seconds")
        XCTAssertEqual(EvacuationPlaybackModel.spokenTimeLabel(60), "1 minute")
        XCTAssertEqual(EvacuationPlaybackModel.spokenTimeLabel(65), "1 minute 5 seconds")
        XCTAssertEqual(EvacuationPlaybackModel.spokenTimeLabel(125), "2 minutes 5 seconds")
    }

    func testElapsedAndDurationLabelsTrackState() {
        let model = loaded(makeTimeline(duration: 95))
        XCTAssertEqual(model.elapsedLabel, "0:00")
        XCTAssertEqual(model.durationLabel, "1:35")
        model.seek(to: 62)
        XCTAssertEqual(model.elapsedLabel, "1:02")
    }
}
