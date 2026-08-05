//  PracticeLogView.swift
//  escape_plan — S4.2 drill mode, practice log UI
//
//  Reads DrillLogStore and shows three things a household actually asks: when did we last
//  practise, how is each person doing, and what have we run recently. Entirely local — this
//  screen works with the device in airplane mode, which it says out loud.

import SwiftUI

struct PracticeLogView: View {
    let homeID: String
    let store: DrillLogStore?
    /// Profiles currently on the home, so a record whose person has since been deleted can be
    /// marked as such instead of silently pretending they're still in the household.
    let currentProfileIDs: Set<String>

    @Environment(\.dismiss) private var dismiss

    private var records: [DrillRecord] { store?.records(homeID: homeID) ?? [] }
    private var summaries: [DrillPersonSummary] { store?.summaries(homeID: homeID) ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No drills yet",
                        systemImage: "figure.walk",
                        description: Text("Run a practice drill and it'll be recorded here — "
                                          + "who practised, from which room, and how long it took.")
                    )
                } else {
                    List {
                        householdSection
                        peopleSection
                        recentSection
                        offlineSection
                    }
                }
            }
            .navigationTitle("Practice log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityHint("Closes the practice log")
                }
            }
        }
    }

    // MARK: - Sections

    private var householdSection: some View {
        Section {
            Text(DrillTimeComparison.lastPracticedPhrase(store?.lastPracticed(homeID: homeID)))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        } header: {
            Text("This household")
        }
    }

    private var peopleSection: some View {
        Section {
            ForEach(summaries) { summary in
                personRow(summary)
            }
        } header: {
            Text("Per person")
        } footer: {
            Text("Best time counts completed drills only — a drill stopped part-way has no "
                 + "finish time to compare.")
        }
    }

    @ViewBuilder
    private func personRow(_ summary: DrillPersonSummary) -> some View {
        // Vertical, never a fixed-width HStack: at accessibility text sizes a name plus two
        // times will not sit on one line.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.profileName)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if !currentProfileIDs.contains(summary.profileID) {
                    Text("no longer in this home")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let best = summary.best {
                Text("Best: \(DrillTimeComparison.clockString(best.elapsedSeconds))")
                    .font(.subheadline)
            } else {
                Text("No completed drill yet").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Most recent: \(DrillTimeComparison.clockString(summary.mostRecent.elapsedSeconds)) "
                 + "· \(Self.dateText(summary.mostRecent.startedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(personAccessibilityLabel(summary))
    }

    private func personAccessibilityLabel(_ summary: DrillPersonSummary) -> String {
        var parts = [summary.profileName]
        if !currentProfileIDs.contains(summary.profileID) {
            parts.append("no longer in this home.")
        }
        if let best = summary.best {
            parts.append("Best completed drill "
                         + "\(DrillTimeComparison.spokenDuration(best.elapsedSeconds)).")
        } else {
            parts.append("No completed drill yet.")
        }
        parts.append("Most recent "
                     + "\(DrillTimeComparison.spokenDuration(summary.mostRecent.elapsedSeconds)) "
                     + "on \(Self.dateText(summary.mostRecent.startedAt)).")
        parts.append("\(summary.completedCount) of \(summary.totalCount) drills completed.")
        return parts.joined(separator: " ")
    }

    private var recentSection: some View {
        Section {
            ForEach(records.prefix(20)) { record in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(record.profileName) · \(record.roomName)")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Self.dateText(record.startedAt)) · "
                         + "\(DrillTimeComparison.clockString(record.elapsedSeconds)) · "
                         + record.outcome.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(record.profileName), starting in \(record.roomName), "
                    + "\(Self.dateText(record.startedAt)), "
                    + "\(DrillTimeComparison.spokenDuration(record.elapsedSeconds)), "
                    + record.outcome.displayName.lowercased()
                )
            }
        } header: {
            Text("Recent drills")
        }
    }

    private var offlineSection: some View {
        Section {
            Label("The practice log is stored on this device. It works with no connection at "
                  + "all — only the escape route itself is fetched from the server.",
                  systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }
}
