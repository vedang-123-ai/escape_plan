//
//  DrillPracticeTests.swift
//  escape_planTests — S4.2 drill mode: practice log, reminders, time-to-exit
//
//  XCTest to match DrillModeTests.swift, which these extend. (The unit target runs both
//  XCTest and Swift Testing — BackendFailureTests and PeopleLayerTests use `import Testing` —
//  but every drill-mode test lives here, in one idiom.)
//

import XCTest
@testable import escape_plan

// MARK: - Practice log

final class DrillLogStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("drilllog-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func store() throws -> DrillLogStore {
        try DrillLogStore(directory: directory)
    }

    private func record(home: String = "home-1",
                        profile: String = "p1",
                        profileName: String = "Maya",
                        room: String = "bed1",
                        roomName: String = "Maya's bedroom",
                        started: Date,
                        elapsed: Double,
                        outcome: DrillOutcome = .completed,
                        modeled: Double? = nil) -> DrillRecord {
        DrillRecord(homeID: home, roomID: room, roomName: roomName,
                    profileID: profile, profileName: profileName,
                    startedAt: started, elapsedSeconds: elapsed,
                    outcome: outcome, modeledEgressSeconds: modeled)
    }

    func testAppendedDrillsSurviveRelaunchNewestFirst() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try store().append(record(started: base, elapsed: 70))
        try store().append(record(started: base.addingTimeInterval(3600), elapsed: 55))

        // A fresh store over the same directory is what a relaunch looks like.
        let reloaded = try store().records(homeID: "home-1")
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.first?.elapsedSeconds, 55, "newest first")
        XCTAssertEqual(reloaded.last?.elapsedSeconds, 70)
        XCTAssertEqual(reloaded.first?.roomName, "Maya's bedroom")
        XCTAssertEqual(try store().lastPracticed(homeID: "home-1"),
                       base.addingTimeInterval(3600))
    }

    func testMultipleHomesCoexistInSeparateFiles() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try store().append(record(home: "home-1", started: base, elapsed: 40))
        try store().append(record(home: "home-2", profile: "p9", profileName: "Sam",
                                  started: base, elapsed: 90))

        XCTAssertEqual(try store().records(homeID: "home-1").count, 1)
        XCTAssertEqual(try store().records(homeID: "home-2").count, 1)
        XCTAssertEqual(try store().records(homeID: "home-2").first?.profileName, "Sam")
        XCTAssertTrue(try store().records(homeID: "home-3").isEmpty)
    }

    func testModeledTimeRoundTripsIncludingItsAbsence() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try store().append(record(started: base, elapsed: 70, modeled: 48.5))
        try store().append(record(profile: "p2", profileName: "Ari",
                                  started: base.addingTimeInterval(60), elapsed: 30,
                                  modeled: nil))

        let all = try store().records(homeID: "home-1")
        XCTAssertNil(all.first { $0.profileID == "p2" }?.modeledEgressSeconds,
                     "no timeline must persist as nil, never as a stand-in number")
        XCTAssertEqual(all.first { $0.profileID == "p1" }?.modeledEgressSeconds, 48.5)
    }

    func testSummariesTakeBestFromCompletedDrillsOnly() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try store().append(record(started: base, elapsed: 90, outcome: .completed))
        // A drill stopped early after 5 s must not become the "best time".
        try store().append(record(started: base.addingTimeInterval(60), elapsed: 5,
                                  outcome: .abandoned))
        try store().append(record(started: base.addingTimeInterval(120), elapsed: 62,
                                  outcome: .completed))

        let summaries = try store().summaries(homeID: "home-1")
        XCTAssertEqual(summaries.count, 1)
        let maya = try XCTUnwrap(summaries.first)
        XCTAssertEqual(maya.best?.elapsedSeconds, 62)
        XCTAssertEqual(maya.mostRecent.elapsedSeconds, 62)
        XCTAssertEqual(maya.completedCount, 2)
        XCTAssertEqual(maya.totalCount, 3)
    }

    func testSummaryHasNoBestWhenEveryDrillWasStoppedEarly() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try store().append(record(started: base, elapsed: 12, outcome: .abandoned))
        let maya = try XCTUnwrap(try store().summaries(homeID: "home-1").first)
        XCTAssertNil(maya.best)
        XCTAssertEqual(maya.totalCount, 1)
    }

    func testRenamingAProfileLeavesHistoryReadable() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try store().append(record(profileName: "Maya", started: base, elapsed: 70))
        // Same person, renamed in the HomeModel later.
        try store().append(record(profileName: "Maya R.", started: base.addingTimeInterval(600),
                                  elapsed: 65))

        let summaries = try store().summaries(homeID: "home-1")
        XCTAssertEqual(summaries.count, 1, "same profile id stays one person")
        XCTAssertEqual(summaries.first?.profileName, "Maya R.",
                       "the summary shows the most recent captured name")
        // The old record keeps the name it was recorded with — nothing is orphaned.
        XCTAssertEqual(try store().records(homeID: "home-1").last?.profileName, "Maya")
    }

    func testCorruptFileReadsAsEmptyRatherThanFailing() throws {
        let store = try self.store()
        try Data("not json at all".utf8).write(to: store.url(for: "home-1"))
        XCTAssertTrue(store.records(homeID: "home-1").isEmpty)
        // And it recovers: a new drill can still be recorded.
        try store.append(record(started: Date(), elapsed: 30))
        XCTAssertEqual(store.records(homeID: "home-1").count, 1)
    }

    func testFutureSchemaVersionIsNotReadAndNotClobbered() throws {
        let store = try self.store()
        let future = #"{"schemaVersion":99,"records":[]}"#
        try Data(future.utf8).write(to: store.url(for: "home-1"))

        XCTAssertTrue(store.records(homeID: "home-1").isEmpty)
        XCTAssertThrowsError(try store.append(record(started: Date(), elapsed: 10))) { error in
            XCTAssertEqual(error as? DrillLogError,
                           .unsupportedVersion(found: 99, supported: DrillLogFile.currentVersion))
        }
        // The newer build's file is still there, byte for byte.
        let onDisk = try String(contentsOf: store.url(for: "home-1"), encoding: .utf8)
        XCTAssertEqual(onDisk, future)
    }

    func testClearRemovesOnlyThatHome() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try store().append(record(home: "home-1", started: base, elapsed: 10))
        try store().append(record(home: "home-2", started: base, elapsed: 10))
        try store().clear(homeID: "home-1")
        XCTAssertTrue(try store().records(homeID: "home-1").isEmpty)
        XCTAssertEqual(try store().records(homeID: "home-2").count, 1)
        XCTAssertNoThrow(try store().clear(homeID: "never-existed"))
    }
}

// MARK: - Time to exit

final class DrillTimeComparisonTests: XCTestCase {

    func testUnavailableModeledTimeShowsTheRawTimeAndSaysSo() {
        let comparison = DrillTimeComparison(elapsed: 72, modeled: nil, personName: "Maya")
        XCTAssertFalse(comparison.isAvailable)
        XCTAssertNil(comparison.difference)
        XCTAssertEqual(comparison.headline, "Your practice: 1:12")
        XCTAssertTrue(comparison.detail.contains("nothing to compare"),
                      "got: \(comparison.detail)")
        XCTAssertTrue(comparison.detail.contains("just your stopwatch"))
        XCTAssertNil(comparison.disclaimer, "no modeled number on screen, no disclaimer needed")
    }

    func testSlowerThanModeledIsStatedPlainly() {
        let comparison = DrillTimeComparison(elapsed: 72, modeled: 48, personName: "Maya")
        XCTAssertEqual(comparison.headline, "Your practice: 1:12 · Modeled walk: 0:48")
        XCTAssertEqual(comparison.difference, 24)
        XCTAssertTrue(comparison.detail.contains("24 seconds longer than the modeled walk"),
                      "got: \(comparison.detail)")
        XCTAssertNotNil(comparison.disclaimer)
    }

    func testFasterThanModeled() {
        let comparison = DrillTimeComparison(elapsed: 40, modeled: 48, personName: "Maya")
        XCTAssertTrue(comparison.detail.contains("8 seconds quicker than the modeled walk"),
                      "got: \(comparison.detail)")
    }

    func testNearlyEqualTimesReadAsAboutTheSame() {
        let comparison = DrillTimeComparison(elapsed: 49, modeled: 48, personName: "Maya")
        XCTAssertTrue(comparison.detail.contains("about the same as the modeled walk"),
                      "got: \(comparison.detail)")
    }

    /// The framing rule, enforced: this is a comparison to an illustrative animation, not a
    /// survivability judgement, and a family reads it with children present.
    func testWordingNeverMakesASurvivabilityOrPassFailClaim() {
        let banned = ["surviv", "would have", "wouldn't have", "you failed", "failed",
                      "passed", "too slow", "danger", "die", "death", "not make it"]
        let cases = [
            DrillTimeComparison(elapsed: 200, modeled: 48, personName: "Maya"),
            DrillTimeComparison(elapsed: 10, modeled: 48, personName: "Maya"),
            DrillTimeComparison(elapsed: 72, modeled: nil, personName: "Maya"),
        ]
        for comparison in cases {
            let text = [comparison.headline, comparison.detail, comparison.disclaimer ?? "",
                        comparison.accessibilitySummary]
                .joined(separator: " ").lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word),
                               "drill result copy must not say '\(word)': \(text)")
            }
        }
        // And it must say out loud what the modeled number actually is.
        let withModel = DrillTimeComparison(elapsed: 72, modeled: 48, personName: "Maya")
        XCTAssertTrue(withModel.disclaimer?.contains("illustrative animation speeds") == true)
        XCTAssertTrue(withModel.disclaimer?.contains("not a prediction") == true)
    }

    func testModeledSecondsComeOnlyFromTheTimelineTrack() {
        let track = OccupantTrack(
            profile_id: "p1", profile_name: "Maya", gait: .child,
            start_room_id: "bed1", exit_id: "exit-front",
            steps: [TimedStep(x: 0, y: 0, floor_id: "f0", t_s: 0, kind: "room"),
                    TimedStep(x: 3, y: 0, floor_id: "f0", t_s: 12.5, kind: "exterior")],
            distance_m: 6, egress_time_s: 12.5
        )
        let timeline = EvacuationTimeline(home_id: "home-1", origin_room_id: "kitchen",
                                          tracks: [track], hazard: [], duration_s: 30)

        XCTAssertEqual(DrillTimeComparison.modeledEgressSeconds(forProfileID: "p1",
                                                                in: timeline), 12.5)
        XCTAssertNil(DrillTimeComparison.modeledEgressSeconds(forProfileID: "nobody",
                                                              in: timeline),
                     "a person with no track has no modeled time — never a substitute")
        XCTAssertNil(DrillTimeComparison.modeledEgressSeconds(forProfileID: "p1", in: nil),
                     "offline / no timeline computed = unavailable, not fabricated")
    }

    func testDurationFormatting() {
        XCTAssertEqual(DrillTimeComparison.clockString(0), "0:00")
        XCTAssertEqual(DrillTimeComparison.clockString(9), "0:09")
        XCTAssertEqual(DrillTimeComparison.clockString(72), "1:12")
        XCTAssertEqual(DrillTimeComparison.clockString(725), "12:05")

        XCTAssertEqual(DrillTimeComparison.spokenDuration(1), "1 second")
        XCTAssertEqual(DrillTimeComparison.spokenDuration(48), "48 seconds")
        XCTAssertEqual(DrillTimeComparison.spokenDuration(60), "1 minute")
        XCTAssertEqual(DrillTimeComparison.spokenDuration(72), "1 minute 12 seconds")
        XCTAssertEqual(DrillTimeComparison.spokenDuration(125), "2 minutes 5 seconds")
    }

    func testLastPracticedPhrasing() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(DrillTimeComparison.lastPracticedPhrase(nil, now: now),
                       "This household hasn't practised yet.")
        XCTAssertTrue(DrillTimeComparison.lastPracticedPhrase(now, now: now).contains("today"))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(DrillTimeComparison.lastPracticedPhrase(yesterday, now: now)
            .contains("yesterday"))
        let old = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        XCTAssertTrue(DrillTimeComparison.lastPracticedPhrase(old, now: now)
            .contains("40 days ago"))
    }
}

// MARK: - Reminders

/// Stands in for UNUserNotificationCenter so tests never touch the real one.
actor FakePracticeNotificationCenter: PracticeNotificationScheduling {
    struct Scheduled: Equatable {
        var identifier: String
        var title: String
        var body: String
        var date: Date
    }

    private var authorized: Bool
    private var grantsOnRequest: Bool
    private var throwsOnSchedule: Bool
    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelled: [String] = []
    private(set) var authorizationRequests = 0

    init(authorized: Bool = false, grantsOnRequest: Bool = true,
         throwsOnSchedule: Bool = false) {
        self.authorized = authorized
        self.grantsOnRequest = grantsOnRequest
        self.throwsOnSchedule = throwsOnSchedule
    }

    struct ScheduleFailure: Error {}

    func isAuthorized() -> Bool { authorized }

    func requestAuthorization() -> Bool {
        authorizationRequests += 1
        if authorized { return true }
        authorized = grantsOnRequest
        return grantsOnRequest
    }

    func schedule(identifier: String, title: String, body: String, at date: Date) throws {
        if throwsOnSchedule { throw ScheduleFailure() }
        scheduled.removeAll { $0.identifier == identifier }
        scheduled.append(Scheduled(identifier: identifier, title: title, body: body, date: date))
    }

    func cancel(identifiers: [String]) {
        cancelled.append(contentsOf: identifiers)
        scheduled.removeAll { identifiers.contains($0.identifier) }
    }

    func pendingIdentifiers() -> [String] { scheduled.map(\.identifier) }
}

final class PracticeReminderSchedulerTests: XCTestCase {

    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "practice-reminder-\(UUID().uuidString)"))
    }

    // MARK: Pure date maths

    func testTwiceAYearIsSixMonthsFromTheLastDrill() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let last = try XCTUnwrap(DateComponents(calendar: calendar, year: 2026, month: 1, day: 10)
            .date)
        let now = try XCTUnwrap(DateComponents(calendar: calendar, year: 2026, month: 1, day: 11)
            .date)

        let next = try XCTUnwrap(PracticeReminderScheduler.nextReminderDate(
            cadence: .twiceAYear, lastPracticed: last, now: now, calendar: calendar))
        let components = calendar.dateComponents([.year, .month, .day], from: next)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 10)
    }

    func testOffSchedulesNothing() {
        XCTAssertNil(PracticeReminderScheduler.nextReminderDate(cadence: .off,
                                                                lastPracticed: Date()))
        XCTAssertNil(PracticeCadence.off.months)
    }

    func testAnOverdueHouseholdIsRemindedSoonNotAfterAnotherFullCycle() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ancient = now.addingTimeInterval(-5 * 365 * 24 * 3600)
        let date = try XCTUnwrap(PracticeReminderScheduler.nextReminderDate(
            cadence: .twiceAYear, lastPracticed: ancient, now: now))
        XCTAssertGreaterThan(date, now)
        XCTAssertLessThan(date, now.addingTimeInterval(2 * 24 * 3600))
    }

    func testNeverPracticedAnchorsOnNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let next = PracticeReminderScheduler.nextReminderDate(cadence: .monthly,
                                                              lastPracticed: nil, now: now)
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(try XCTUnwrap(next), now)
    }

    func testOverdueDetection() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sevenMonthsAgo = Calendar.current.date(byAdding: .month, value: -7, to: now)!
        let lastWeek = now.addingTimeInterval(-7 * 24 * 3600)
        XCTAssertTrue(PracticeReminderScheduler.isOverdue(cadence: .twiceAYear,
                                                          lastPracticed: sevenMonthsAgo,
                                                          now: now))
        XCTAssertFalse(PracticeReminderScheduler.isOverdue(cadence: .twiceAYear,
                                                           lastPracticed: lastWeek, now: now))
        XCTAssertFalse(PracticeReminderScheduler.isOverdue(cadence: .off,
                                                           lastPracticed: sevenMonthsAgo,
                                                           now: now))
        XCTAssertFalse(PracticeReminderScheduler.isOverdue(cadence: .twiceAYear,
                                                           lastPracticed: nil, now: now))
    }

    // MARK: Scheduling

    func testApplySchedulesOneReminderAndPersistsTheChoice() async throws {
        let center = FakePracticeNotificationCenter(authorized: false, grantsOnRequest: true)
        let store = try defaults()
        let scheduler = PracticeReminderScheduler(center: center, defaults: store)

        let outcome = await scheduler.apply(.twiceAYear, homeID: "home-1", homeName: "Oak Street",
                                            lastPracticed: nil)
        guard case .scheduled = outcome else {
            return XCTFail("expected .scheduled, got \(outcome)")
        }
        let scheduled = await center.scheduled
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first?.identifier, "practice-reminder.home-1")
        XCTAssertTrue(try XCTUnwrap(scheduled.first?.body).contains("Oak Street"))

        // Persisted: a new scheduler over the same defaults is what a relaunch looks like.
        XCTAssertEqual(PracticeReminderScheduler(center: center, defaults: store)
            .cadence(homeID: "home-1"), .twiceAYear)
        XCTAssertEqual(PracticeReminderScheduler(center: center, defaults: store)
            .cadence(homeID: "home-2"), .off, "reminders are per home and default to off")
    }

    /// The banner has no room for a citation, so it must state no interval at all.
    func testTheNotificationTextMakesNoFrequencyClaim() async throws {
        let center = FakePracticeNotificationCenter(authorized: true)
        let scheduler = PracticeReminderScheduler(center: center, defaults: try defaults())
        _ = await scheduler.apply(.twiceAYear, homeID: "home-1", homeName: "Oak Street",
                                  lastPracticed: nil)
        let all = await center.scheduled
        let text = try XCTUnwrap(all.first)
        let combined = (text.title + " " + text.body).lowercased()
        for word in ["twice", "month", "year", "six", "annual", "every"] {
            XCTAssertFalse(combined.contains(word),
                           "the notification must not state a frequency: '\(combined)'")
        }
    }

    func testDeniedPermissionDegradesInsteadOfBreaking() async throws {
        let center = FakePracticeNotificationCenter(authorized: false, grantsOnRequest: false)
        let store = try defaults()
        let scheduler = PracticeReminderScheduler(center: center, defaults: store)

        let outcome = await scheduler.apply(.twiceAYear, homeID: "home-1", homeName: "Oak Street",
                                            lastPracticed: nil)
        XCTAssertEqual(outcome, .permissionDenied)
        let scheduled = await center.scheduled
        XCTAssertTrue(scheduled.isEmpty)
        // The preference is still remembered, so the in-app nudge knows what they wanted.
        XCTAssertEqual(scheduler.cadence(homeID: "home-1"), .twiceAYear)
    }

    func testTurningRemindersOffCancelsThePendingOne() async throws {
        let center = FakePracticeNotificationCenter(authorized: true)
        let scheduler = PracticeReminderScheduler(center: center, defaults: try defaults())
        _ = await scheduler.apply(.monthly, homeID: "home-1", homeName: "Oak Street",
                                  lastPracticed: nil)
        let pendingBefore = await scheduler.hasPendingReminder(homeID: "home-1")
        XCTAssertTrue(pendingBefore)

        let outcome = await scheduler.apply(.off, homeID: "home-1", homeName: "Oak Street",
                                            lastPracticed: nil)
        XCTAssertEqual(outcome, .cancelled)
        let pendingAfter = await scheduler.hasPendingReminder(homeID: "home-1")
        XCTAssertFalse(pendingAfter)
        XCTAssertEqual(scheduler.cadence(homeID: "home-1"), .off)
    }

    func testReschedulingAfterADrillMovesTheReminderAndKeepsExactlyOne() async throws {
        let center = FakePracticeNotificationCenter(authorized: true)
        let scheduler = PracticeReminderScheduler(center: center, defaults: try defaults())
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        _ = await scheduler.apply(.twiceAYear, homeID: "home-1", homeName: "Oak Street",
                                  lastPracticed: nil, now: now)
        let initial = await center.scheduled
        let first = try XCTUnwrap(initial.first?.date)

        let later = now.addingTimeInterval(30 * 24 * 3600)
        _ = await scheduler.reschedule(homeID: "home-1", homeName: "Oak Street",
                                       lastPracticed: later, now: later)
        let all = await center.scheduled
        XCTAssertEqual(all.count, 1, "one pending reminder per home, never a pile-up")
        XCTAssertGreaterThan(try XCTUnwrap(all.first?.date), first)
    }

    func testRescheduleIsANoOpWhenRemindersAreOff() async throws {
        let center = FakePracticeNotificationCenter(authorized: true)
        let scheduler = PracticeReminderScheduler(center: center, defaults: try defaults())
        let outcome = await scheduler.reschedule(homeID: "home-1", homeName: "Oak Street",
                                                 lastPracticed: Date())
        XCTAssertEqual(outcome, .cancelled)
        let prompts = await center.authorizationRequests
        XCTAssertEqual(prompts, 0,
                       "a household that never asked for reminders is never prompted")
    }

    func testScheduleFailureIsReportedNotSwallowed() async throws {
        let center = FakePracticeNotificationCenter(authorized: true, throwsOnSchedule: true)
        let scheduler = PracticeReminderScheduler(center: center, defaults: try defaults())
        let outcome = await scheduler.apply(.monthly, homeID: "home-1", homeName: "Oak Street",
                                            lastPracticed: nil)
        guard case .failed = outcome else {
            return XCTFail("expected .failed, got \(outcome)")
        }
    }
}

// MARK: - Grounding: the practice frequency must come from the corpus, verbatim

final class PracticeFrequencyGroundingTests: XCTestCase {

    private func corpusText(_ file: String) throws -> String {
        let url = PersistenceFixtures.repoRoot.appendingPathComponent("backend/corpus/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The number the app shows is the number the corpus states — and it is stated by the
    /// documents whose ids the copy cites, not by some other page.
    func testTwiceAYearIsWhatTheCitedCorpusDocumentsActuallySay() throws {
        let guidance = DrillInstructions.practiceFrequencyGuidance
        XCTAssertTrue(guidance.lowercased().contains("twice a year"))

        let ids = DrillInstructions.citationIDs(in: guidance)
        XCTAssertEqual(Set(ids), ["nfpa-escape-planning", "redcross-escape-plan"])

        let nfpa = try corpusText("escape-planning-nfpa.md").lowercased()
        XCTAssertTrue(nfpa.contains("practice the plan twice a year"),
                      "the NFPA doc must literally contain the frequency the app shows")
        XCTAssertTrue(nfpa.contains("[cite: nfpa-escape-planning]"))

        let redcross = try corpusText("home-fire-escape-redcross.md").lowercased()
        XCTAssertTrue(redcross.contains("twice a year"),
                      "the Red Cross doc must literally contain the frequency the app shows")
        XCTAssertTrue(redcross.contains("[cite: redcross-escape-plan]"))
    }

    /// The two-minute benchmark on the results card is likewise the corpus's, not the app's.
    func testTheDrillTimerGoalIsTheCorpusTwoMinuteBenchmark() throws {
        let goal = DrillInstructions.drillTimerGoal
        XCTAssertTrue(goal.contains("under two minutes"))
        XCTAssertEqual(DrillInstructions.citationIDs(in: goal), ["redcross-two-minutes"])
        let redcross = try corpusText("home-fire-escape-redcross.md").lowercased()
        XCTAssertTrue(redcross.contains("the goal is **under two minutes**"))
    }

    /// The cadences the corpus does NOT support are offered as the user's own preference, and
    /// the note that says so must itself make no safety claim (hence: no citation).
    func testOnlyTwiceAYearIsMarkedAsCorpusBacked() {
        XCTAssertEqual(PracticeCadence.allCases.filter(\.isCorpusBacked), [.twiceAYear])
        XCTAssertEqual(PracticeCadence.twiceAYear.months, 6)
        XCTAssertTrue(DrillInstructions.citationIDs(in: DrillInstructions.cadenceChoiceNote)
            .isEmpty)
        XCTAssertTrue(DrillInstructions.cadenceChoiceNote.contains("your own choice"))
    }

    /// The picker rows are bare interval labels. If one ever grew a word like "recommended"
    /// it would be uncited guidance sitting in a control.
    func testCadenceLabelsCarryNoRecommendation() {
        for cadence in PracticeCadence.allCases {
            let label = cadence.displayName.lowercased()
            for word in ["recommend", "should", "safe", "must", "best practice"] {
                XCTAssertFalse(label.contains(word),
                               "'\(label)' reads as advice; guidance belongs in cited copy")
            }
        }
    }
}
