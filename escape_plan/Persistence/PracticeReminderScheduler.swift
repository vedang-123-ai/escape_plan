//  PracticeReminderScheduler.swift
//  escape_plan — S4.2 drill mode, practice reminders
//
//  Local notifications (UNUserNotificationCenter) that remind a household to run their fire
//  drill again. Entirely on-device: no server, no network, no account.
//
//  GROUNDING RULE, which shapes this whole file: the app may only put a practice *frequency*
//  in front of the user when the corpus says it. It does — twice a year, from two independent
//  sources (see DrillInstructions.practiceFrequencyGuidance). So the recommended cadence here
//  is exactly `twiceAYear`, presented next to its citation chips. The other cadences are
//  offered as the user's own preference and are labelled as carrying no safety claim; nothing
//  in this file rounds, estimates, or invents an interval.
//
//  The notification text itself deliberately states NO frequency — a banner has no room for a
//  citation, so the cited claim stays in the app where the chip pattern works.
//
//  The cadence preference is a couple of bytes per home, so it lives in UserDefaults exactly
//  like ChecklistStateStore, not in a document. The notification centre is behind a protocol
//  so tests never touch the real one.

import Foundation
import UserNotifications

/// How often the household wants to be reminded.
///
/// `twiceAYear` is the only case the corpus supports; `isCorpusBacked` is what the UI keys
/// off to decide whether a citation must be shown beside it.
enum PracticeCadence: String, Codable, Equatable, CaseIterable, Identifiable {
    case off
    case monthly
    case everyThreeMonths
    case twiceAYear
    case yearly

    var id: String { rawValue }

    /// Plain interval label. Never phrased as advice — the recommendation lives in the cited
    /// guidance text, not in a picker row.
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .monthly: return "Every month"
        case .everyThreeMonths: return "Every 3 months"
        case .twiceAYear: return "Twice a year"
        case .yearly: return "Once a year"
        }
    }

    /// True only for the interval published fire-safety guidance actually states.
    var isCorpusBacked: Bool { self == .twiceAYear }

    /// Months between reminders. nil for `.off`. `twiceAYear` is 6 months by arithmetic on
    /// the corpus number, not by an added judgement about frequency.
    var months: Int? {
        switch self {
        case .off: return nil
        case .monthly: return 1
        case .everyThreeMonths: return 3
        case .twiceAYear: return 6
        case .yearly: return 12
        }
    }
}

/// What happened when the user asked for reminders.
enum PracticeReminderOutcome: Equatable {
    case scheduled(Date)
    case cancelled
    /// Notification permission was refused (now or previously). The feature degrades to the
    /// in-app "last practised" nudge; nothing breaks.
    case permissionDenied
    case failed(String)
}

/// The slice of UNUserNotificationCenter this feature needs. Domain-shaped rather than
/// UN-shaped so tests can fake it without constructing notification objects.
protocol PracticeNotificationScheduling: Sendable {
    func isAuthorized() async -> Bool
    /// Prompts if the user has not decided yet; returns the resulting grant.
    func requestAuthorization() async -> Bool
    func schedule(identifier: String, title: String, body: String, at date: Date) async throws
    func cancel(identifiers: [String]) async
    func pendingIdentifiers() async -> [String]
}

/// The real thing.
struct SystemPracticeNotificationCenter: PracticeNotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            // Re-asking is a no-op once denied; the caller shows the degrade path instead.
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge]))
                ?? false
        }
    }

    func schedule(identifier: String, title: String, body: String, at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // A specific calendar date, not a repeating trigger: no UNCalendarNotificationTrigger
        // can express "every six months", and the app re-arms the next one every time a drill
        // is logged or the cadence changes.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier,
                                                   content: content,
                                                   trigger: trigger))
    }

    func cancel(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }
}

/// Schedules (and re-schedules) one pending reminder per home.
///
/// Pure parts — `nextReminderDate`, `cadence` persistence — are static or UserDefaults-backed
/// and testable on their own; the scheduling side goes through an injected
/// `PracticeNotificationScheduling`.
struct PracticeReminderScheduler {
    private let center: PracticeNotificationScheduling
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(center: PracticeNotificationScheduling = SystemPracticeNotificationCenter(),
         defaults: UserDefaults = .standard,
         calendar: Calendar = .current) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
    }

    // MARK: - Preference

    private func key(for homeID: String) -> String { "practiceReminderCadence.\(homeID)" }

    /// Defaults to `.off`: the app never turns on notifications a household did not ask for.
    func cadence(homeID: String) -> PracticeCadence {
        guard let raw = defaults.string(forKey: key(for: homeID)),
              let cadence = PracticeCadence(rawValue: raw) else { return .off }
        return cadence
    }

    func setCadence(_ cadence: PracticeCadence, homeID: String) {
        defaults.set(cadence.rawValue, forKey: key(for: homeID))
    }

    // MARK: - Scheduling

    func notificationIdentifier(homeID: String) -> String { "practice-reminder.\(homeID)" }

    /// Persists the choice, asks for permission if needed, and (re)arms the single pending
    /// reminder for this home.
    ///
    /// Denial is not an error: the preference is still stored, the reminder is simply not
    /// scheduled, and the caller falls back to the in-app nudge.
    @discardableResult
    func apply(_ cadence: PracticeCadence,
               homeID: String,
               homeName: String,
               lastPracticed: Date?,
               now: Date = Date()) async -> PracticeReminderOutcome {
        setCadence(cadence, homeID: homeID)
        let identifier = notificationIdentifier(homeID: homeID)
        await center.cancel(identifiers: [identifier])

        guard cadence != .off else { return .cancelled }
        guard await center.requestAuthorization() else { return .permissionDenied }
        guard let fireDate = Self.nextReminderDate(cadence: cadence,
                                                   lastPracticed: lastPracticed,
                                                   now: now,
                                                   calendar: calendar) else {
            return .cancelled
        }
        do {
            try await center.schedule(
                identifier: identifier,
                title: "Time to practise your fire drill",
                // No interval and no safety claim in the banner — see the file header.
                body: "Open Escape Plan to walk \(homeName)'s escape routes again.",
                at: fireDate
            )
            return .scheduled(fireDate)
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// Re-arms the reminder from a new "last practised" date. Called after a drill is logged.
    /// A no-op when the household has reminders off.
    @discardableResult
    func reschedule(homeID: String,
                    homeName: String,
                    lastPracticed: Date?,
                    now: Date = Date()) async -> PracticeReminderOutcome {
        let current = cadence(homeID: homeID)
        guard current != .off else { return .cancelled }
        return await apply(current, homeID: homeID, homeName: homeName,
                           lastPracticed: lastPracticed, now: now)
    }

    func cancel(homeID: String) async {
        setCadence(.off, homeID: homeID)
        await center.cancel(identifiers: [notificationIdentifier(homeID: homeID)])
    }

    func hasPendingReminder(homeID: String) async -> Bool {
        await center.pendingIdentifiers().contains(notificationIdentifier(homeID: homeID))
    }

    func isAuthorized() async -> Bool { await center.isAuthorized() }

    // MARK: - Pure date maths

    /// When the next reminder should fire.
    ///
    /// - Anchored on the last drill, so a household that just practised is not nagged.
    /// - Never in the past: a household already overdue gets a reminder the next day rather
    ///   than waiting a whole further cycle. That is scheduling hygiene, not a frequency
    ///   claim — it states no interval to the user.
    static func nextReminderDate(cadence: PracticeCadence,
                                 lastPracticed: Date?,
                                 now: Date = Date(),
                                 calendar: Calendar = .current) -> Date? {
        guard let months = cadence.months else { return nil }
        let anchor = lastPracticed ?? now
        guard let candidate = calendar.date(byAdding: .month, value: months, to: anchor) else {
            return nil
        }
        if candidate > now { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
    }

    /// Whole days since the household last practised, for the in-app nudge. nil when they
    /// never have.
    static func daysSince(_ lastPracticed: Date?,
                          now: Date = Date(),
                          calendar: Calendar = .current) -> Int? {
        guard let lastPracticed else { return nil }
        return calendar.dateComponents([.day], from: lastPracticed, to: now).day.map { max(0, $0) }
    }

    /// True when the household is past the interval they chose. Used only to phrase the
    /// in-app nudge — the app states the overdue-ness of *their own* setting, and attaches a
    /// safety claim only when that setting is the corpus-backed one.
    static func isOverdue(cadence: PracticeCadence,
                          lastPracticed: Date?,
                          now: Date = Date(),
                          calendar: Calendar = .current) -> Bool {
        guard let months = cadence.months, let lastPracticed else { return false }
        guard let due = calendar.date(byAdding: .month, value: months, to: lastPracticed) else {
            return false
        }
        return due <= now
    }
}
