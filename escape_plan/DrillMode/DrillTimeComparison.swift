//  DrillTimeComparison.swift
//  escape_plan — S4.2 drill mode, time-to-exit
//
//  Compares the stopwatch time of a real practice against the *modeled* walk for that person:
//  `OccupantTrack.egress_time_s` from the evacuation timeline, which is the engine's resampled
//  route at illustrative animation speeds (see Models/EvacuationTimeline.swift — the timeline
//  is flagged `is_illustrative` and the UI is required to say so).
//
//  Two things this file refuses to do:
//
//  1. Invent a modeled number. There is exactly one legitimate source, `egress_time_s`. In
//     particular it does NOT divide `Route.length_m` by an assumed walking speed: that would
//     be the app computing a result it is not allowed to compute, dressed as engine output.
//     No timeline → no comparison, and the UI says so plainly.
//  2. Render a verdict. The wording never says "you would have made it" or anything about
//     surviving. It says how the practice compares to a drawing of the route, in language a
//     family reads with children in the room.
//
//  Pure Foundation, no UI — unit-testable.

import Foundation

struct DrillTimeComparison: Equatable {
    /// Real stopwatch seconds for the practice just finished.
    let elapsed: TimeInterval
    /// `OccupantTrack.egress_time_s`, or nil when no timeline was available.
    let modeled: TimeInterval?
    let personName: String

    init(elapsed: TimeInterval, modeled: TimeInterval?, personName: String) {
        self.elapsed = max(0, elapsed)
        self.modeled = modeled.map { max(0, $0) }
        self.personName = personName
    }

    /// Times within this many seconds of each other read as "about the same" rather than
    /// implying a precision neither number has.
    static let tolerance: TimeInterval = 2

    var isAvailable: Bool { modeled != nil }

    /// Practice minus modeled. Positive means the practice took longer. nil when unavailable.
    var difference: TimeInterval? {
        guard let modeled else { return nil }
        return elapsed - modeled
    }

    // MARK: - Copy

    var headline: String {
        guard let modeled else { return "Your practice: \(Self.clockString(elapsed))" }
        return "Your practice: \(Self.clockString(elapsed)) · Modeled walk: "
            + Self.clockString(modeled)
    }

    var detail: String {
        guard let difference else {
            return "No modeled walk has been worked out for \(personName) yet, so there's "
                + "nothing to compare this against. The time above is just your stopwatch."
        }
        let gap = Self.spokenDuration(abs(difference))
        if abs(difference) <= Self.tolerance {
            return "That's about the same as the modeled walk for \(personName)."
        }
        if difference > 0 {
            return "That's \(gap) longer than the modeled walk for \(personName). The model "
                + "assumes a steady, unobstructed walk, so a real practice usually takes a "
                + "little longer."
        }
        return "That's \(gap) quicker than the modeled walk for \(personName). Keep practising "
            + "so the route stays familiar."
    }

    /// Shown whenever a modeled number is on screen — the same honesty `is_illustrative`
    /// demands of the animation.
    var disclaimer: String? {
        guard isAvailable else { return nil }
        return "The modeled walk comes from the app's illustrative animation speeds. It's a "
            + "drawing of the route, not a prediction of how a real fire would go."
    }

    /// One string for VoiceOver, so the card reads as a sentence instead of three fragments.
    var accessibilitySummary: String {
        var parts = ["Your practice took \(Self.spokenDuration(elapsed))."]
        if let modeled {
            parts.append("The modeled walk for \(personName) is \(Self.spokenDuration(modeled)).")
        }
        parts.append(detail)
        if let disclaimer { parts.append(disclaimer) }
        return parts.joined(separator: " ")
    }

    // MARK: - Sourcing the modeled number

    /// The one legitimate source: this person's track in an evacuation timeline.
    /// nil when there is no timeline, or the timeline has no track for them.
    static func modeledEgressSeconds(forProfileID profileID: String,
                                     in timeline: EvacuationTimeline?) -> TimeInterval? {
        timeline?.tracks.first { $0.profile_id == profileID }?.egress_time_s
    }

    // MARK: - Formatting

    /// "0:48", "1:12", "12:05" — monospaced-digit friendly.
    static func clockString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "48 seconds", "1 minute 12 seconds" — for VoiceOver, which should not read "one colon
    /// twelve".
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        let secondsPart = "\(remainder) second\(remainder == 1 ? "" : "s")"
        guard minutes > 0 else { return secondsPart }
        let minutesPart = "\(minutes) minute\(minutes == 1 ? "" : "s")"
        return remainder == 0 ? minutesPart : "\(minutesPart) \(secondsPart)"
    }

    /// "today", "yesterday", "12 days ago", "never" — for the "last practised" nudge.
    static func lastPracticedPhrase(_ date: Date?,
                                    now: Date = Date(),
                                    calendar: Calendar = .current) -> String {
        guard let days = PracticeReminderScheduler.daysSince(date, now: now, calendar: calendar)
        else { return "This household hasn't practised yet." }
        switch days {
        case 0: return "This household last practised today."
        case 1: return "This household last practised yesterday."
        default: return "This household last practised \(days) days ago."
        }
    }
}
