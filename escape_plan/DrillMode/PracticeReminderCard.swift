//  PracticeReminderCard.swift
//  escape_plan — S4.2 drill mode, practice reminders UI
//
//  Lets a household turn on a local notification reminding them to practise again.
//
//  The citation rule, made visible: the recommended cadence — twice a year — is shown
//  immediately under the corpus text that states it, with its source chips (NFPA and the Red
//  Cross). Every other interval in the picker is offered as the user's own preference and is
//  explicitly labelled as carrying no safety claim. The app never states a frequency it cannot
//  cite.
//
//  Denial degrades, it does not break: with notifications refused, the card keeps working as
//  an in-app "you last practised N days ago" nudge and says where to change the setting.

import SwiftUI

struct PracticeReminderCard: View {
    let homeID: String
    let homeName: String
    let lastPracticed: Date?
    var scheduler = PracticeReminderScheduler()

    @State private var cadence: PracticeCadence = .off
    @State private var scheduledFor: Date?
    @State private var permissionDenied = false
    @State private var failureMessage: String?
    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Practice reminders")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // The cited claim sits directly above the picker so the recommended interval is
            // never on screen without its sources.
            DrillCitedText(text: DrillInstructions.practiceFrequencyGuidance, font: .caption)

            // Deliberately NOT `$cadence`: binding straight to the state would make the
            // load-from-defaults write look like a user choice and fire the notification
            // permission prompt the moment the screen appeared.
            Picker("Remind me", selection: Binding(
                get: { cadence },
                set: { newValue in
                    guard newValue != cadence else { return }
                    cadence = newValue
                    Task { await apply(newValue) }
                }
            )) {
                ForEach(PracticeCadence.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .disabled(isApplying)
            .accessibilityLabel("Practice reminder interval")
            .accessibilityValue(cadence.displayName
                                + (cadence.isCorpusBacked ? ", the interval published guidance recommends" : ""))
            .accessibilityHint("Schedules a local notification to practise again")

            Text(DrillInstructions.cadenceChoiceNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            statusLine
        }
        .task { await refresh() }
    }

    // MARK: - Status / degrade path

    @ViewBuilder
    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Always shown — this is the whole feature when notifications are refused.
            Text(DrillTimeComparison.lastPracticedPhrase(lastPracticed))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if permissionDenied {
                Label("Notifications are turned off for Escape Plan, so there's no reminder "
                      + "banner. You'll still see how long it's been right here. Turn "
                      + "notifications on in the Settings app if you'd like a reminder.",
                      systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let scheduledFor {
                Label("Next reminder \(PracticeLogView.dateText(scheduledFor))",
                      systemImage: "bell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("Reminders are scheduled on this device — no connection needed.",
                  systemImage: "wifi.slash")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func refresh() async {
        let stored = scheduler.cadence(homeID: homeID)
        if stored != cadence { cadence = stored }
        guard stored != .off else {
            scheduledFor = nil
            return
        }
        permissionDenied = !(await scheduler.isAuthorized())
        scheduledFor = permissionDenied ? nil
            : PracticeReminderScheduler.nextReminderDate(cadence: stored,
                                                         lastPracticed: lastPracticed)
    }

    private func apply(_ newValue: PracticeCadence) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        failureMessage = nil
        let outcome = await scheduler.apply(newValue, homeID: homeID, homeName: homeName,
                                            lastPracticed: lastPracticed)
        switch outcome {
        case .scheduled(let date):
            permissionDenied = false
            scheduledFor = date
        case .cancelled:
            permissionDenied = false
            scheduledFor = nil
        case .permissionDenied:
            permissionDenied = true
            scheduledFor = nil
        case .failed(let message):
            scheduledFor = nil
            failureMessage = "Couldn't schedule the reminder: \(message)"
        }
    }
}
