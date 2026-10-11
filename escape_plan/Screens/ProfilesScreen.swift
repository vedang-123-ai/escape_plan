//  ProfilesScreen.swift
//  escape_plan
//
//  S3.4 iOS half: per-home family profiles CRUD. Profiles live
//  inside the HomeModel document (not app settings), so this screen loads the home through
//  HomeDocumentStore, mutates it via HomeModelStore EditActions (validation for free), and
//  autosaves on every accepted commit — the same store/autosave pattern as EditorScreen.
//
//  Reached again since S11.20 (AUD-020): the revamp deleted BetaScreen, its only entry point.
//  `HouseholdRow` on Home is the entry (the old drill's empty state, deleted in trim 2, was another). Leaving the screen after
//  a change reloads ReadinessStore when this is the active home, so the score and checklist
//  count the new people. House picks the change up itself when it next appears (S11.19).
//
//  The Plan screen's profile selector (live /routes re-fetch with profile_id when you pick a
//  family member) landed with S2.3 — see PlanScreen.routeControls.

import os
import SwiftUI

struct ProfilesScreen: View {
    private static let log = Logger(subsystem: "escape_plan", category: "ProfilesScreen")

    let homeID: String
    /// Called after every autosave attempt. No caller passes it today; kept for callers that
    /// show their own copy of the home.
    var onModelChanged: (() -> Void)?

    // Optional so the #Preview, which has neither, still renders.
    @Environment(ReadinessStore.self) private var readiness: ReadinessStore?
    @Environment(APIClient.self) private var apiClient: APIClient?
    @State private var changedSinceAppear = false

    @State private var store: HomeModelStore?
    @State private var loadError: String?
    @State private var revision = 0
    @State private var saveError: String?
    @State private var showingAdd = false
    @State private var editingProfile: Profile?
    @State private var deleteCandidate: Profile?
    @State private var rejectionMessage: String?
    /// A rejection from the editor sheet. Kept apart from `rejectionMessage` so the alert is
    /// presented on the sheet, where the user is, not under it.
    @State private var editorRejection: String?

    /// The library's store, passed in by the caller (AUD-019): never a second store of its own.
    let documentStore: HomeDocumentStore?

    init(homeID: String, store: HomeDocumentStore?, onModelChanged: (() -> Void)? = nil) {
        self.homeID = homeID
        self.onModelChanged = onModelChanged
        self.documentStore = store
    }

    var body: some View {
        content
            .navigationTitle("Household")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                    .disabled(store == nil)
                    .accessibilityHint("Adds a person or pet who lives here, so their escape "
                                       + "routes can be personalised.")
                }
            }
            .task { loadIfNeeded() }
            .onDisappear(perform: reloadReadinessIfChanged)
            .sheet(isPresented: $showingAdd) { editorSheet(existing: nil) }
            .sheet(item: $editingProfile) { editorSheet(existing: $0) }
            .confirmationDialog(
                "Delete \(deleteCandidate?.name ?? "profile")?",
                isPresented: Binding(
                    get: { deleteCandidate != nil },
                    set: { if !$0 { deleteCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let candidate = deleteCandidate {
                        dispatch(.deleteProfile(profileId: candidate.id))
                    }
                    deleteCandidate = nil
                }
            }
            .alert("Couldn't save profile", isPresented: Binding(
                get: { rejectionMessage != nil },
                set: { if !$0 { rejectionMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rejectionMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ContentUnavailableView("Couldn't open home", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if let store {
            let _ = revision  // repaint on every commit — HomeModelStore isn't Observable
            if store.model.profiles.isEmpty {
                ContentUnavailableView {
                    Label("No profiles yet", systemImage: "person.2")
                } description: {
                    Text("Add the people (and pets) who live here so escape routes can be personalized to their needs.")
                } actions: {
                    // Was a bare accent text button: ~20 pt tall and under 4.5:1 on these surfaces.
                    DSPrimaryButton(title: "Add Profile", systemImage: "plus") { showingAdd = true }
                        .accessibilityHint("Opens the new profile form.")
                        .padding(.horizontal, DS.pagePadding)
                }
            } else {
                List {
                    if let saveError {
                        Text("Autosave failed: \(saveError)")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                            .accessibilityLabel("Autosave failed. \(saveError)")
                    }
                    ForEach(store.model.profiles) { profile in
                        Button {
                            editingProfile = profile
                        } label: {
                            row(for: profile, in: store.model)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spoken(profile, in: store.model))
                        .accessibilityHint("Opens this profile for editing. Swipe up or down "
                                           + "with one finger for Delete.")
                        .accessibilityAddTraits(.isButton)
                        // The swipe action is not reliably exposed once children are ignored.
                        .accessibilityAction(named: "Delete") { deleteCandidate = profile }
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleteCandidate = profile }
                                .accessibilityLabel("Delete \(profile.name)")
                        }
                    }
                }
            }
        } else {
            ProgressView("Loading…")
                .accessibilityLabel("Loading the people who live here.")
        }
    }

    /// The whole row as one sentence: "Maya. Sleeps in the Back Bedroom. Needs: Child,
    /// Limited Mobility." Reading name / room / three chips as five separate stops made the
    /// list unusable at exactly the moment it matters most.
    private func spoken(_ profile: Profile, in model: HomeModel) -> String {
        let room = model.locateRoom(profile.bedroom_room_id)?.room.name
        var sentence = "\(profile.name). "
        sentence += room.map { "Sleeps in the \($0)." } ?? "Bedroom is missing from this home."
        if !profile.tags.isEmpty {
            sentence += " Needs: " + profile.tags.map(\.displayName).joined(separator: ", ") + "."
        }
        return sentence
    }

    private func row(for profile: Profile, in model: HomeModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.name).font(.headline)
            // Name + room + N tag chips overflow the row well before AX1, so the metadata line
            // wraps to a second line rather than truncating the tags that shape the route.
            ViewThatFits(in: .horizontal) {
                metadata(for: profile, in: model, axis: .horizontal)
                metadata(for: profile, in: model, axis: .vertical)
            }
        }
    }

    @ViewBuilder
    private func metadata(for profile: Profile, in model: HomeModel,
                          axis: Axis) -> some View {
        let bedroom = Label(model.locateRoom(profile.bedroom_room_id)?.room.name ?? "Missing room",
                            systemImage: "bed.double")
            .font(.caption)
            .foregroundStyle(Theme.supporting)
        let chips = HStack(spacing: 6) {
            ForEach(profile.tags, id: \.self) { tag in
                Text(tag.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
            }
        }
        if axis == .horizontal {
            HStack(spacing: 6) { bedroom; chips }
        } else {
            // Chips never wrap, so at large text sizes they truncated the very tags that shape
            // the route. The fallback is one line of text that wraps instead.
            VStack(alignment: .leading, spacing: 4) {
                bedroom
                if !profile.tags.isEmpty {
                    Text(profile.tags.map(\.displayName).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func editorSheet(existing: Profile?) -> some View {
        // The store is always loaded by the time a sheet can open (add button is disabled
        // until then, rows only exist once loaded).
        ProfileEditorView(model: store!.model, existing: existing) { name, tags, bedroomRoomId in
            let ordered = ProfileTag.allCases.filter(tags.contains)
            let action: EditAction
            if let existing {
                action = .updateProfile(profileId: existing.id, name: name,
                                        tags: ordered, bedroom_room_id: bedroomRoomId)
            } else {
                action = .addProfile(profileId: UUID().uuidString, name: name,
                                     tags: ordered, bedroom_room_id: bedroomRoomId)
            }
            return dispatch(action, fromEditor: true)
        }
        .alert("Couldn't save profile", isPresented: Binding(
            get: { editorRejection != nil },
            set: { if !$0 { editorRejection = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editorRejection ?? "")
        }
    }

    /// Dispatches and surfaces a rejection; returns whether the store accepted it.
    @discardableResult
    private func dispatch(_ action: EditAction, fromEditor: Bool = false) -> Bool {
        guard let store else { return false }
        switch store.dispatch(action) {
        case .applied:
            return true
        case .rejected(let issues):
            let message = issues.map(\.message).joined(separator: "\n")
            if fromEditor { editorRejection = message } else { rejectionMessage = message }
            return false
        }
    }

    private func loadIfNeeded() {
        guard store == nil, loadError == nil else { return }
        do {
            guard let documentStore, documentStore.exists(homeID: homeID) else {
                loadError = "No saved home with id \(homeID)."
                return
            }
            let model = try documentStore.load(homeID: homeID, as: HomeModel.self)
            let newStore = try HomeModelStore(model: model)
            newStore.onCommit = { [documentStore] _ in
                revision += 1
                autosave(newStore, documentStore: documentStore)
            }
            store = newStore
        } catch {
            loadError = "\(error)"
        }
    }

    private func autosave(_ store: HomeModelStore, documentStore: HomeDocumentStore?) {
        do {
            try documentStore?.save(model: store.model)
            saveError = nil
            changedSinceAppear = true
        } catch {
            saveError = "\(error)"
            AccessibilityNotification.Announcement("Autosave failed. \(error)").post()
        }
        onModelChanged?()
    }

    /// The score and checklist are per person (vulnerable occupants, per-person routes), so a
    /// changed household has to reach ReadinessStore. Only for the active home: another home's
    /// score is not on screen. `replaceActiveHome`, not `load`: its rescore cancels a /score
    /// still in flight, where `load` would race it and could land the old household's score
    /// last (the AUD-014 race).
    private func reloadReadinessIfChanged() {
        guard changedSinceAppear, let readiness, let apiClient, let documentStore,
              readiness.activeHomeID == homeID else { return }
        do {
            let saved = try documentStore.load(homeID: homeID, as: HomeModel.self)
            changedSinceAppear = false
            readiness.replaceActiveHome(saved, api: apiClient)
        } catch {
            Self.log.error("Failed to reload home for readiness: \(error.localizedDescription)")
            saveError = "Failed to update readiness score: \(error.localizedDescription)"
            AccessibilityNotification.Announcement("Failed to update readiness score. \(error.localizedDescription)").post()
        }
    }
}

/// The way into Profiles for the active home: "Household", who lives there, and a chevron.
/// One row so every place that offers it reads the same.
struct HouseholdRow: View {
    let profiles: [Profile]
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 28

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Household").font(.subheadline).foregroundStyle(Theme.text)
                    Text(summary)
                        .font(.caption).foregroundStyle(Theme.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .dsCard(padding: nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Household. \(summary)")
        .accessibilityHint("Opens the people who live here. Routes and drills are planned for each of them.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("household.row")
    }

    private var summary: String {
        switch profiles.count {
        case 0: return "Add who lives here"
        case 1...3: return profiles.map(\.name).joined(separator: ", ")
        default: return "\(profiles.count) people"
        }
    }
}

#Preview {
    NavigationStack {
        ProfilesScreen(homeID: "missing", store: try? HomeDocumentStore())
    }
}
