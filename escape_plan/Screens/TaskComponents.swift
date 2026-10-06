//  TaskComponents.swift
//  Screens — the issue-list vocabulary the Tasks tab and Home's "Up next" share (Linear revamp,
//  2026-09-25): a status circle, a peril chip, a compact row, a group header and the detail sheet.

import SwiftUI

/// Linear's status glyph: an empty ring for to-do (red when it caps the score), a filled check
/// for done. Shape changes with state, so it never relies on colour alone.
struct TaskStatusIcon: View {
    let done: Bool
    var urgent = false

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Theme.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Theme.canvas)
            } else if urgent {
                Circle().strokeBorder(Theme.warning, lineWidth: 1.5)
                Circle().fill(Theme.warning).frame(width: 5, height: 5)
            } else {
                Circle().strokeBorder(Theme.supporting, lineWidth: 1.5)
            }
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }
}

/// A dot-and-label chip, like Linear's label chips.
struct TaskChip: View {
    let text: String
    var tint: Color? = nil
    var symbol: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 5) {
            if let tint { Circle().fill(tint).frame(width: 6, height: 6) }
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).accessibilityHidden(true) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Theme.supporting)
        .padding(.horizontal, 7)
        // A minimum, not a fixed 20: at XXXL the outline crossed the text (S53-4).
        .padding(.vertical, typeSize.isAccessibilitySize ? 3 : 0)
        .frame(minHeight: 20)
        .background(Theme.canvas.opacity(0.4), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderStrong, lineWidth: 1))
        .fixedSize()
    }
}

/// One task. The leading circle ticks narrative items in place; the rest of the row opens the
/// detail sheet. Engine-scored items show their state but can't be ticked by hand.
struct TaskRow: View {
    let item: ChecklistItem
    let done: Bool
    var showsDetail = false
    let onToggle: () -> Void
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var destination: TaskDestination { TaskDestination(item) }
    private var recurrence: String? { item.recurrenceLabel(now: Date(), shownDone: done) }
    /// The peril chip, if the item has one. At the accessibility sizes it sits under the title
    /// rather than beside it, so the title keeps the row's width (S53-4: one word per line).
    private var perilChip: TaskChip? {
        guard let hazard = item.hazard, hazard != .general else { return nil }
        return TaskChip(text: hazard.shortLabel, tint: hazard.tint)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            statusControl
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(done ? Theme.supporting : Theme.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if showsDetail {
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.supporting)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        // S11.35: when a recurring task was done and when it is due again.
                        if let recurrence {
                            Text(recurrence)
                                .font(.caption)
                                .foregroundStyle(Theme.supporting)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if typeSize.isAccessibilitySize, let perilChip { perilChip.padding(.top, 2) }
                    }
                    Spacer(minLength: 6)
                    if !typeSize.isAccessibilitySize, let perilChip { perilChip }
                    if let symbol = destination.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                            .frame(width: 14)
                    }
                }
                .padding(.vertical, 11)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(item.title)
            .accessibilityValue([done ? "Done" : (item.severity == .high ? "Urgent, to do" : "To do"), recurrence?.replacingOccurrences(of: " · ", with: ", ")]
                .compactMap { $0 }.joined(separator: ". "))
            .accessibilityHint(destination.label.map { "Opens the details. Goes to \($0)." } ?? "Opens the details.")
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var statusControl: some View {
        let icon = TaskStatusIcon(done: done, urgent: item.severity == .high)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        if destination.isTickedByUser {
            Button(action: onToggle) { icon }
                .buttonStyle(HapticPlainButtonStyle())
                .accessibilityLabel(done ? "Mark \(item.title) as not done" : "Mark \(item.title) as done")
        } else {
            icon
        }
    }
}

/// A row that brightens its background on press, like a hovered Linear row.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.hover.opacity(0.6) : .clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.press() }
            }
    }
}

/// A hairline between rows, inset past the status circle.
struct RowDivider: View {
    var inset: CGFloat = 44
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, inset)
    }
}

/// Linear's group header: chevron, status glyph, name, count.
struct TaskGroupHeader<Glyph: View>: View {
    let title: String
    let count: Int
    @Binding var expanded: Bool
    @ViewBuilder var glyph: () -> Glyph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12)
                glyph()
                Text(title).font(.footnote.weight(.medium)).foregroundStyle(Theme.text)
                Text("\(count)").font(.footnote).monospacedDigit().foregroundStyle(Theme.supporting)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Theme.raised.opacity(0.55))
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticPlainButtonStyle())
        .accessibilityLabel(TaskGroupSpeech.label(title: title, count: count))
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isHeader)
    }
}

/// What VoiceOver reads for a task group header.
enum TaskGroupSpeech {
    /// "Done, 1 item", "To do, 39 items" (S53-5: it read "Done, 1 items").
    static func label(title: String, count: Int) -> String {
        "\(title), \(CountPhrase.of(count, "item"))"
    }
}

// MARK: - Detail sheet

/// The issue page for one task: everything the compact row leaves out, and the one thing to do.
struct TaskDetailSheet: View {
    let item: ChecklistItem
    let isDone: Bool
    let onPrimary: () -> Void
    /// Ticks or unticks the item. Shown as a second button only where the primary does something
    /// else (the drill item: "Run a drill" opens House, this marks it done).
    var onToggle: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var destination: TaskDestination { TaskDestination(item) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Wraps instead of running off the sheet at the accessibility sizes (S53-4);
                    // one plain row below them, as before.
                    let chipRow = typeSize.isAccessibilitySize ? AnyLayout(FlowLayout(spacing: 6))
                                                               : AnyLayout(HStackLayout(spacing: 6))
                    chipRow {
                        HStack(spacing: 6) {
                            TaskStatusIcon(done: isDone, urgent: item.severity == .high)
                            Text(isDone ? "Done" : (item.severity == .high ? "Urgent" : "To do"))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, typeSize.isAccessibilitySize ? 2 : 0)
                        .frame(minHeight: 24)
                        .background(Theme.raised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                        if let hazard = item.hazard { TaskChip(text: hazard.label, tint: hazard.tint) }
                        if let label = destination.label, let symbol = destination.symbol {
                            TaskChip(text: label, symbol: symbol)
                        }
                    }
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(item.detail)
                        .font(.subheadline)
                        .foregroundStyle(DS.bodyInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 0) {
                        if let source = item.source_citation, !source.isEmpty {
                            propertyRow("Source", value: source, symbol: "doc.text")
                        }
                        if item.scoring {
                            if item.source_citation?.isEmpty == false { RowDivider(inset: 12) }
                            propertyRow("Score", value: "Counts toward your score", symbol: "chart.bar")
                        }
                    }
                    .dsCard(radius: Theme.radius, padding: nil)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.pagePadding)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    DSPrimaryButton(title: destination.actionTitle(done: isDone),
                                    systemImage: destination.actionSymbol(done: isDone),
                                    action: onPrimary)
                    if destination == .drill, let onToggle {
                        // Watching the simulation is not the family practising, so the tick says
                        // what it records (trim 2 review).
                        DSSecondaryButton(title: isDone ? "Mark as not done" : "We practiced it for real",
                                          action: onToggle)
                            .accessibilityHint(isDone ? "Unticks this task."
                                : "Ticks this task. Watching the simulation does not count as practice.")
                            .accessibilityIdentifier("task.markDone")
                    }
                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.bottom, 8)
                .background(Theme.canvas)
            }
            .dsPage()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.hapticTap()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
    }

    private func propertyRow(_ name: String, value: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Theme.supporting).frame(width: 16)
            Text(name).font(.footnote).foregroundStyle(Theme.supporting).frame(width: 52, alignment: .leading)
            Text(value).font(.footnote).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}
