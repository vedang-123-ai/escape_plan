//  TasksScreen.swift
//  Screens — the readiness checklist as a Linear-style issue list (revamp, 2026-09-25).
//
//  Everything the user can do to get more prepared, grouped Urgent / To do / Done, filterable
//  by peril. Each task knows where it is done (`TaskDestination`): tapping one opens its detail
//  sheet, whose button sends the user to the right place — the object in the House tab, the fire
//  drill (House's fire simulation), or a tick right here. The family plan's own to-dos sit at the bottom.

import SwiftUI

struct TasksScreen: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(ReadinessStore.self) private var readiness
    @Environment(AppRouter.self) private var router
    @EnvironmentObject private var library: HomeLibrary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var filter: HazardTag?
    @State private var urgentExpanded = true
    @State private var todoExpanded = true
    @State private var doneExpanded = false
    @AppStorage("tasks.showDetails") private var showDetails = false

    @State private var detailItem: ChecklistItem?
    @State private var showingExportSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if readiness.activeHomeID == nil {
                        noHome
                    } else if readiness.needsDraftReview {
                        // No checklist for a home nobody has confirmed (AUD-023).
                        DraftReviewNotice().padding(.horizontal, DS.pagePadding)
                    } else if readiness.breakdown == nil {
                        placeholder
                    } else {
                        filterBar
                        if let reason = readiness.nudgeReason { nudge(reason) }
                        if let notice = readiness.tickNotice { clockNotice(notice) }
                        groups
                    }
                    // The meeting point opens the PDF export and the fire-department card shares
                    // a snapshot; neither is offered for an unreviewed draft (AUD-023).
                    if let home = readiness.activeHome, !readiness.needsDraftReview { familyPlan(home) }
                }
                .padding(.bottom, 32)
            }
            .refreshable { Haptics.begin(); await readiness.load(api: apiClient) }
            .dsPage()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $detailItem) { item in
                TaskDetailSheet(item: item,
                                isDone: readiness.isDone(item),
                                onPrimary: { perform(item, fromSheet: true) },
                                onToggle: { readiness.toggleDone(item, api: apiClient, animated: !reduceMotion) })
            }
            .sheet(isPresented: $showingExportSheet) {
                if let id = readiness.activeHomeID { ExportPlanSheet(homeID: id, store: library.store) }
            }
        }
    }

    // MARK: - Header

    private var items: [ChecklistItem] {
        readiness.items.filter { filter == nil || $0.hazard == filter }
    }

    private var header: some View {
        let all = readiness.items
        let done = all.filter(readiness.isDone).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tasks")
                    .font(.system(.largeTitle, weight: .semibold))
                    .kerning(-0.8)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { showDetails.toggle() }
                } label: {
                    Image(systemName: showDetails ? "text.alignleft" : "list.bullet")
                        // The glyph sits in a fixed 36 pt tile: capped so it stays inside it at XXXL.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(showDetails ? Theme.accentText : Theme.supporting)
                        .frame(width: 36, height: 36)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HapticPlainButtonStyle())
                .accessibilityLabel(showDetails ? "Hide details" : "Show details")
            }
            if !all.isEmpty {
                HStack(spacing: 10) {
                    Text("\(done) of \(all.count) done")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.supporting)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.raised)
                            Capsule().fill(Theme.success)
                                .frame(width: geo.size.width * CGFloat(done) / CGFloat(max(1, all.count)))
                        }
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    /// With no home in the library there is nothing to score, and no request will ever finish:
    /// this used to be "Loading your tasks…" forever (audit 2026-09-25).
    private var noHome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No home yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("Your tasks come from your home's layout. Scan it or build it, and the checklist appears here.")
                .font(.subheadline)
                .foregroundStyle(Theme.supporting)
                .fixedSize(horizontal: false, vertical: true)
            DSPrimaryButton(title: "Scan my home", systemImage: "camera.viewfinder") {
                router.go(home: .scan)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var placeholder: some View {
        if readiness.isScoring || readiness.scoreFailure == nil {
            LoadingTipView(label: "Loading your tasks…")
                .frame(minHeight: 320)
        } else if let failure = readiness.scoreFailure {
            BackendFailureBanner(failure: failure,
                                 retry: failure.isRetryable ? { readiness.rescore(api: apiClient) } : nil)
                .padding(.horizontal, DS.pagePadding)
        }
    }

    private var filterBar: some View {
        let perils = HazardTag.allCases.filter { tag in tag != .general && readiness.items.contains { $0.hazard == tag } }
        return Group {
            if typeSize.isAccessibilitySize {
                // S53-4: at XXXL the scrolling row showed "Earthqua…" at the screen edge with the
                // rest out of sight. The pills wrap onto new lines instead, all in view.
                FlowLayout(spacing: 6, lineSpacing: 0) {
                    filterPill("All", tag: nil)
                    ForEach(perils, id: \.self) { filterPill($0.label, tag: $0) }
                }
                .padding(.horizontal, DS.pagePadding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterPill("All", tag: nil)
                        ForEach(perils, id: \.self) { filterPill($0.label, tag: $0) }
                    }
                    .padding(.horizontal, DS.pagePadding)
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func filterPill(_ title: String, tag: HazardTag?) -> some View {
        let selected = filter == tag
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { filter = tag }
            Haptics.selection()
        } label: {
            HStack(spacing: 5) {
                if let tag { Circle().fill(tag.tint).frame(width: 6, height: 6) }
                Text(title)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(selected ? Theme.text : Theme.supporting)
            .padding(.horizontal, 11)
            // A minimum, not a fixed 30: at XXXL the text is taller and the outline crossed it.
            .padding(.vertical, typeSize.isAccessibilitySize ? 6 : 0)
            .frame(minHeight: 30)
            .background(selected ? Theme.hover : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Theme.borderStrong : Theme.border, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("tasks.filter.\(tag?.rawValue ?? "all")")
    }

    // MARK: - Groups

    @ViewBuilder
    private var groups: some View {
        let urgent = items.filter { $0.severity == .high && !readiness.isDone($0) }
        let todo = items.filter { $0.severity != .high && !readiness.isDone($0) }
            .sorted { ($0.scoring ? 0 : 1) < ($1.scoring ? 0 : 1) }
        let done = items.filter(readiness.isDone)

        VStack(spacing: 0) {
            if !urgent.isEmpty {
                TaskGroupHeader(title: "Urgent", count: urgent.count, expanded: $urgentExpanded) {
                    Image(systemName: "exclamationmark.square.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.warning)
                }
                if urgentExpanded { rows(urgent) }
            }
            TaskGroupHeader(title: "To do", count: todo.count, expanded: $todoExpanded) {
                TaskStatusIcon(done: false)
            }
            if todoExpanded {
                if todo.isEmpty { emptyRow("Nothing left to do here.") } else { rows(todo) }
            }
            TaskGroupHeader(title: "Done", count: done.count, expanded: $doneExpanded) {
                TaskStatusIcon(done: true)
            }
            if doneExpanded {
                if done.isEmpty { emptyRow("Finished tasks will collect here.") } else { rows(done) }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: 1))
        .padding(.horizontal, DS.pagePadding)
    }

    private func rows(_ items: [ChecklistItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            VStack(spacing: 0) {
                RowDivider(inset: index == 0 ? 0 : 44)
                TaskRow(item: item,
                        done: readiness.isDone(item),
                        showsDetail: showDetails,
                        onToggle: { readiness.toggleDone(item, api: apiClient, animated: !reduceMotion) },
                        onOpen: { detailItem = item })
            }
            .transition(.opacity)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        VStack(spacing: 0) {
            RowDivider(inset: 0)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.supporting)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 44)
                .frame(minHeight: 44)
        }
    }

    private func nudge(_ reason: ScanFreshness.NudgeReason) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DSIconBadge(systemImage: "clock.arrow.circlepath", fill: Theme.caution, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(reason == .wallsEdited ? "Layout changed since the last scan" : "Your floor plan may be out of date")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                Text(ScanFreshness.nudgeMessage(reason))
                    .font(.footnote)
                    .foregroundStyle(Theme.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Scan now") { router.go(home: .scan) }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
                    .hapticTap()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: 14)
        .padding(.horizontal, DS.pagePadding)
        .padding(.bottom, 12)
    }

    /// A tick the server refused because this phone's clock is off (S11.50). Without it the row
    /// just flipped back to not done with no reason given.
    private func clockNotice(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DSIconBadge(systemImage: "clock.badge.exclamationmark", fill: Theme.caution, size: 28)
            Text(notice)
                .font(.footnote)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: 14)
        .padding(.horizontal, DS.pagePadding)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Family plan

    @ViewBuilder
    private func familyPlan(_ home: HomeModel) -> some View {
        Text("Family plan")
            .sectionHeaderStyle()
            .padding(.horizontal, DS.pagePadding)
            .padding(.top, 28)
            .padding(.bottom, 8)
        VStack(spacing: 8) {
            meetingPointRow(home)
            ShareWithFireDepartmentCard(homeID: home.id, homeName: home.name, store: library.store)
        }
        .padding(.horizontal, DS.pagePadding)
    }

    /// Read-only here; the meeting place is edited in the export flow, which this row opens.
    private func meetingPointRow(_ home: HomeModel) -> some View {
        let point = MeetingPointStore().meetingPoint(forHomeID: home.id)
        return Button { showingExportSheet = true } label: {
            HStack(spacing: 0) {
                TaskStatusIcon(done: !point.isEmpty).frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Outside meeting point").font(.subheadline).foregroundStyle(Theme.text)
                    Text(point.isEmpty ? "Not set yet" : point)
                        .font(.caption).foregroundStyle(Theme.supporting).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.trailing, 14)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .dsCard(padding: nil)
        .accessibilityLabel("Outside meeting point: \(point.isEmpty ? "not set" : point)")
        .accessibilityHint("Opens the export sheet to set it.")
    }

    // MARK: - Doing a task

    private func perform(_ item: ChecklistItem, fromSheet: Bool) {
        let go = {
            switch TaskDestination(item) {
            case .house: router.openHouse(homeID: readiness.activeHomeID, focusItemID: item.id)
            case .drill: router.openFireDrill(homeID: readiness.activeHomeID)
            case .toggle: readiness.toggleDone(item, api: apiClient, animated: !reduceMotion)
            }
        }
        guard fromSheet, TaskDestination(item) != .toggle else { go(); return }
        detailItem = nil
        // Let the sheet finish dismissing before the tab switch or push, or it drops it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            go()
        }
    }
}

// MARK: - Review your draft (AUD-023)

/// What Home, Tasks and Score show instead of a score while the active home is an unreviewed AI
/// draft (`ReadinessStore.needsDraftReview`). It sends the user to House, where "Confirm draft" is
/// the only way to turn the draft into a home the engine will score and route.
struct DraftReviewNotice: View {
    @Environment(ReadinessStore.self) private var readiness
    @Environment(AppRouter.self) private var router

    // Layout and copy chosen by Anish in the simulator, 2026-10-01 (over a one-line row).
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            Text("Review your draft")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("This floor plan is an AI draft. Check its rooms, doors and windows in House, then tap Confirm draft. Your score, tasks and escape routes appear after that.")
                .font(.subheadline)
                .foregroundStyle(Theme.supporting)
                .fixedSize(horizontal: false, vertical: true)
            DSPrimaryButton(title: "Review in House", systemImage: "cube") {
                Haptics.selection()
                router.openHouse(homeID: readiness.activeHomeID)
            }
            .accessibilityHint("Opens the 3D house so you can check and confirm the draft.")
            .accessibilityIdentifier("draftReview.openHouse")
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: 16)
    }
}
