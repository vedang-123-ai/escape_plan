// EvacuationPlayback.swift
// The clock for an `EvacuationTimeline`, and the ONLY thing that decides what "now" means
// during an evacuation animation.
//
// Division of labor — the same rule the whole project runs on, one level down:
//
//   * The backend decides who goes where and when a room becomes untenable. It ships that
//     as an `EvacuationTimeline`.
//   * THIS file decides what time it is: play/pause, rate, scrubbing, and the derived
//     answers that are a pure function of (timeline, t) — which rooms are untenable, who
//     has already reached the exterior, who the engine says the hazard overtook.
//   * The renderer (PeopleLayer / PathSampler / the hazard layer — a different lane) decides
//     what that instant LOOKS like. It asks this model for `currentTime_s` and derives
//     positions itself.
//
// So this file deliberately has NO position interpolation along a track. `PathSampler` owns
// that. If you find yourself wanting `position(of:at:)` here, it belongs there instead.
//
// `escape_plan/Models/` is symlinked into the `tools/editorcore` SwiftPM package (macOS,
// pure Foundation), so this file may import Foundation and Observation and nothing else.
// That is also why Reduce Motion arrives as a plain `Bool` (`isSteppedMode`) instead of being
// read here: `UIAccessibility` does not exist in the package. The view layer reads the flag
// and sets the property.
//
// Threading: main-actor by convention — SwiftUI owns the instance, drives `tick(deltaTime:)`
// from a `TimelineView`, and reads every property during `body`. The class is NOT annotated
// `@MainActor`, so `tick`/`seek`/`untenableRoomIDs(at:)` stay callable straight from a unit
// test with no run loop and no actor hop. Do not touch an instance from a background task.

import Foundation
import Observation

/// Playback state for one `EvacuationTimeline`. All times are **seconds of modeled time**
/// measured from ignition (t = 0 is the moment the origin room catches), never wall-clock
/// dates and never frame counts.
@Observable
final class EvacuationPlaybackModel {

    // MARK: - Tuning constants

    /// The speed menu offers these (quarter speed to double, trim 2, 2026-10-03). Any write to
    /// `playbackRate` outside `minPlaybackRate...maxPlaybackRate` is clamped.
    static let supportedRates: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    static let minPlaybackRate: Double = 0.25
    static let maxPlaybackRate: Double = 4.0
    /// Default granularity of stepped (Reduce Motion) playback, in seconds of modeled time.
    static let defaultStepInterval_s: Double = 1.0

    // MARK: - Core state

    /// The engine's answer, verbatim. `nil` means nothing is simulated and every derived
    /// value below reads as empty/zero — the renderer can bind unconditionally.
    ///
    /// Only ever set through `load(_:)`, never fabricated client-side.
    private(set) var timeline: EvacuationTimeline?

    /// Where the playhead is, in seconds since ignition. Always within `0...duration_s`.
    /// This is the single value the renderer should read to place figures and hazard.
    private(set) var currentTime_s: Double = 0

    /// Whether `tick(deltaTime:)` advances the playhead. Flips to `false` on its own when the
    /// playhead reaches `duration_s`.
    private(set) var isPlaying: Bool = false

    // MARK: - Playback rate

    private var storedPlaybackRate: Double = 1.0

    /// Multiplier applied to every `tick` delta. 1.0 = one second of animation per second of
    /// modeled time. Writes are clamped to `minPlaybackRate...maxPlaybackRate`, so a UI
    /// binding can never wedge playback at 0 or run it away.
    ///
    /// (Backed by a private stored property rather than a `didSet`, because `@Observable`
    /// rewrites stored properties and property observers on them are a trap.)
    var playbackRate: Double {
        get { storedPlaybackRate }
        set { storedPlaybackRate = min(max(newValue, Self.minPlaybackRate), Self.maxPlaybackRate) }
    }

    // MARK: - Reduce Motion

    /// When `true`, `tick` advances the playhead in whole `stepInterval_s` jumps instead of
    /// continuously — figures teleport between discrete instants rather than gliding.
    ///
    /// This is the Reduce Motion degradation, and degradation is the point: the feature is
    /// never disabled, never hidden, and the same timeline is still fully explorable by
    /// stepping or scrubbing. The view layer sets this from
    /// `\.accessibilityReduceMotion` (i.e. `UIAccessibility.isReduceMotionEnabled`);
    /// this file cannot read it (no UIKit in the package).
    /// (Backed by a private stored property for the same `@Observable` reason as
    /// `playbackRate` — no property observers on stored properties of an `@Observable`.)
    var isSteppedMode: Bool {
        get { storedIsSteppedMode }
        set {
            guard newValue != storedIsSteppedMode else { return }
            storedIsSteppedMode = newValue
            pendingStepTime_s = 0
        }
    }

    private var storedIsSteppedMode: Bool = false

    /// Granularity of stepped mode, in seconds of modeled time. Ignored unless
    /// `isSteppedMode`.
    var stepInterval_s: Double = EvacuationPlaybackModel.defaultStepInterval_s

    /// Sub-step time accumulated but not yet applied in stepped mode. Never observable state
    /// the UI needs; it exists so stepping does not lose time between jumps.
    @ObservationIgnored private var pendingStepTime_s: Double = 0

    // MARK: - Derived scalars

    /// Total modeled length of the loaded timeline, in seconds. `0` when nothing is loaded —
    /// callers dividing by this must guard, which is what `progress` does.
    var duration_s: Double { timeline?.duration_s ?? 0 }

    /// Playhead as a fraction of the whole, clamped to `0...1`. `0` when nothing is loaded or
    /// the timeline has zero duration (rather than NaN, which would poison a `Slider`).
    var progress: Double {
        let total = duration_s
        guard total > 0 else { return 0 }
        return min(max(currentTime_s / total, 0), 1)
    }

    /// Whether there is anything to play.
    var hasTimeline: Bool { timeline != nil }

    /// The playhead has reached the end of a loaded timeline.
    var isFinished: Bool { timeline != nil && currentTime_s >= duration_s }

    /// Drives the mandatory on-screen disclaimer. `EvacuationTimeline` decodes a missing
    /// `is_illustrative` as `true`, so this is the safe direction by construction.
    ///
    /// The UI does not use this to decide *whether* to warn — a timeline on screen always
    /// carries the notice — only how strongly to word it. See `HouseScreen.illustrativeNotice`.
    var isIllustrative: Bool { timeline?.is_illustrative ?? false }

    /// The room the hazard starts in, or `nil` when nothing is loaded.
    var originRoomID: String? { timeline?.origin_room_id }

    // MARK: - Derived collections

    /// Every occupant in the loaded timeline, in the engine's order. Empty when unloaded.
    var tracks: [OccupantTrack] { timeline?.tracks ?? [] }

    /// Occupants the ENGINE flagged `overtaken_by_hazard` — the modeled hazard reaches a room
    /// on their path before they clear it.
    ///
    /// This is an honest negative result, not an error state and not a rendering failure. The
    /// UI surfaces it as a finding in the same vocabulary as the routing engine's findings and
    /// never suppresses it to keep the animation comfortable. Nothing here re-derives the
    /// judgment: it is the server's boolean, filtered.
    var overtakenTracks: [OccupantTrack] { tracks.filter(\.overtaken_by_hazard) }

    /// The engine's warning payload attached to this timeline, if the backend sent one.
    /// Rendered verbatim, like every other `RouteFinding`.
    var findings: [RouteFinding] { timeline?.findings ?? [] }

    // MARK: - Lifecycle

    init() {}

    /// Installs a new timeline (or clears with `nil`) and rewinds to t = 0, paused.
    ///
    /// Always rewinds: keeping the old playhead across a new ignition would show a different
    /// fire at a time that meant something in the previous one. Playback rate, stepped mode,
    /// and step interval are user/accessibility preferences and deliberately survive.
    func load(_ timeline: EvacuationTimeline?) {
        self.timeline = timeline
        currentTime_s = 0
        isPlaying = false
        pendingStepTime_s = 0
    }

    /// Starts (or resumes) advancing. No-op with no timeline. Starting from the end rewinds
    /// first, so the play button after a finished run replays instead of doing nothing.
    func play() {
        guard timeline != nil, duration_s > 0 else { return }
        if currentTime_s >= duration_s { currentTime_s = 0 }
        pendingStepTime_s = 0
        isPlaying = true
    }

    /// Stops advancing and leaves the playhead exactly where it is.
    func pause() {
        isPlaying = false
        pendingStepTime_s = 0
    }

    /// Play if paused, pause if playing — what the one play/pause button calls.
    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Moves the playhead to `time` seconds since ignition, clamped to `0...duration_s`.
    /// Does NOT change `isPlaying`: the scrubber pauses explicitly on drag-begin so the user
    /// decides, rather than the model guessing.
    func seek(to time: Double) {
        guard timeline != nil else { return }
        pendingStepTime_s = 0
        currentTime_s = min(max(time.isFinite ? time : 0, 0), duration_s)
    }

    /// Back to t = 0 and playing. The "replay" button.
    func restart() {
        guard timeline != nil else { return }
        currentTime_s = 0
        pendingStepTime_s = 0
        play()
    }

    // MARK: - The clock

    /// Advances the playhead by `deltaTime` seconds of REAL time, scaled by `playbackRate`.
    ///
    /// Pure in the sense that matters: it takes the elapsed time as an argument instead of
    /// reading a clock, so a unit test can drive a whole timeline in a loop with no run loop,
    /// no `CADisplayLink`, and no waiting. The view supplies the delta from a `TimelineView`
    /// (see `HouseScreen.PlaybackClock`, which also caps a single delta so a resumed-from-
    /// background frame cannot skip the whole animation).
    ///
    /// Guarantees:
    /// - No-op unless `isPlaying` and a timeline is loaded.
    /// - Ignores non-positive and non-finite deltas (a `TimelineView` can hand back both).
    /// - `currentTime_s` is monotonically non-decreasing across ticks.
    /// - Clamps at `duration_s` and sets `isPlaying = false` on arrival — playback stops at
    ///   the end rather than running past it or looping.
    /// - In stepped mode, moves only in whole multiples of `stepInterval_s`, banking the
    ///   remainder so no modeled time is lost.
    func tick(deltaTime: Double) {
        guard isPlaying, timeline != nil, deltaTime.isFinite, deltaTime > 0 else { return }
        let advance = deltaTime * playbackRate

        guard isSteppedMode, stepInterval_s > 0 else {
            setTime(currentTime_s + advance)
            return
        }

        pendingStepTime_s += advance
        let wholeSteps = (pendingStepTime_s / stepInterval_s).rounded(.down)
        guard wholeSteps >= 1 else {
            // Not enough banked for a jump yet — but the end of the timeline must still be
            // reachable, or a long tail shorter than one step would strand playback.
            if currentTime_s + pendingStepTime_s >= duration_s { setTime(duration_s) }
            return
        }
        pendingStepTime_s -= wholeSteps * stepInterval_s
        setTime(currentTime_s + wholeSteps * stepInterval_s)
    }

    /// The one place `currentTime_s` moves during playback, so the end-of-timeline stop
    /// cannot be forgotten on one path and remembered on another.
    private func setTime(_ time: Double) {
        let total = duration_s
        if time >= total {
            currentTime_s = total
            isPlaying = false
            pendingStepTime_s = 0
        } else {
            currentTime_s = max(0, time)
        }
    }

    // MARK: - Derived queries (pure functions of the timeline)

    /// The rooms the engine models as untenable at `time` seconds after ignition.
    ///
    /// A `HazardEvent` is inclusive at its own boundary: a room with `untenable_at_s == 12` is
    /// in the set at exactly t = 12. The origin room has `untenable_at_s == 0` and so is in
    /// the set from the first frame. Rooms with no event never appear — absence from
    /// `timeline.hazard` means "stays clear for the whole timeline", per the contract.
    ///
    /// Monotone in `time` by construction: the set only grows.
    func untenableRoomIDs(at time: Double) -> Set<String> {
        guard let timeline else { return [] }
        var ids = Set<String>()
        for event in timeline.hazard where event.untenable_at_s <= time {
            ids.insert(event.room_id)
        }
        return ids
    }

    /// `untenableRoomIDs(at:)` for the current playhead — what the renderer wants each frame.
    var untenableRoomIDsNow: Set<String> { untenableRoomIDs(at: currentTime_s) }

    /// When the engine models `roomID` as becoming untenable, or `nil` if it never does in
    /// this timeline. Seconds since ignition.
    func untenableTime(forRoom roomID: String) -> Double? {
        timeline?.hazard.first { $0.room_id == roomID }?.untenable_at_s
    }

    /// Whether this occupant has already reached the exterior at `time`. Exposed so the
    /// renderer can retire a figure without re-deriving the rule; the rule is exactly
    /// `time >= track.egress_time_s`, which the contract defines as `steps.last!.t_s`.
    func hasEscaped(_ track: OccupantTrack, at time: Double) -> Bool {
        time >= track.egress_time_s
    }

    /// Occupants still inside at `time`. Order matches the engine's.
    func activeTracks(at time: Double) -> [OccupantTrack] {
        tracks.filter { !hasEscaped($0, at: time) }
    }

    // MARK: - Formatting

    /// `m:ss` for a duration in seconds — for the elapsed/total labels, which must read as
    /// TEXT and not be inferred from a bar's position or colour.
    ///
    /// Lives here rather than in the view so it is unit-testable and so the scrubber's
    /// `accessibilityValue` and its visible label can never word the same instant differently.
    static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// Spoken form of a duration, for VoiceOver — "1 minute 5 seconds" reads far better than
    /// "1:05", which VoiceOver may render as a time of day.
    static func spokenTimeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 seconds" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        let secondsPart = "\(secs) second\(secs == 1 ? "" : "s")"
        guard minutes > 0 else { return secondsPart }
        let minutesPart = "\(minutes) minute\(minutes == 1 ? "" : "s")"
        return secs == 0 ? minutesPart : "\(minutesPart) \(secondsPart)"
    }

    /// A speed as the menu shows it: "0.25×", "1×", "1.25×", "2×". Up to two decimals, no
    /// trailing zeros, and never the locale's decimal comma (the rest of the app is English).
    static func rateLabel(_ rate: Double) -> String {
        guard rate.isFinite else { return "1×" }
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rate)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "×"
    }

    /// A speed as VoiceOver says it. "0.25 times speed" is read digit by digit, so the common
    /// fractions get words.
    static func spokenRateLabel(_ rate: Double) -> String {
        switch rate {
        case 1: return "Normal speed"
        case 0.25: return "Quarter speed"
        case 0.5: return "Half speed"
        case 0.75: return "Three quarter speed"
        case 2: return "Double speed"
        default: return "\(rateLabel(rate).dropLast()) times speed"
        }
    }

    /// Elapsed / total as visible text, e.g. `"0:12 / 1:45"`.
    var elapsedLabel: String { Self.timeLabel(currentTime_s) }
    var durationLabel: String { Self.timeLabel(duration_s) }
}
