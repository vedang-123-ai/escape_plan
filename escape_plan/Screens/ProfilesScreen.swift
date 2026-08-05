//  ProfilesScreen.swift
//  escape_plan
//
//  S3.4 iOS half: per-home family profiles CRUD, reached from the Homes list. Profiles live
//  inside the HomeModel document (not app settings), so this screen loads the home through
//  HomeDocumentStore, mutates it via HomeModelStore EditActions (validation for free), and
//  autosaves on every accepted commit — the same store/autosave pattern as EditorScreen.
//
//  The Plan screen's profile selector (live /routes re-fetch with profile_id when you pick a
//  family member) landed with S2.3 — see PlanScreen.routeControls.

import SwiftUI

struct ProfilesScreen: View {
    let homeID: String
    /// Called after any accepted mutation so the caller (HomeScreen) can refresh its list.
    var onModelChanged: (() -> Void)?

    @State private var store: HomeModelStore?
    @State private var loadError: String?
    @State private var revision = 0
    @State private var saveError: String?
    @State private var showingAdd = false
    @State private var editingProfile: Profile?
    @State private var deleteCandidate: Profile?
    @State private var rejectionMessage: String?

    private let documentStore: HomeDocumentStore?

    init(homeID: String, onModelChanged: (() -> Void)? = nil) {
        self.homeID = homeID
        self.onModelChanged = onModelChanged
        self.documentStore = try? HomeDocumentStore()
    }

    var body: some View {
        content
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                    .disabled(store == nil)
                }
            }
            .task { loadIfNeeded() }
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
                    Button("Add Profile") { showingAdd = true }
                }
            } else {
                List {
                    if let saveError {
                        Text("Autosave failed: \(saveError)")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                    ForEach(store.model.profiles) { profile in
                        Button {
                            editingProfile = profile
                        } label: {
                            row(for: profile, in: store.model)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleteCandidate = profile }
                        }
                    }
                }
            }
        } else {
            ProgressView("Loading…")
        }
    }

    private func row(for profile: Profile, in model: HomeModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.name).font(.headline)
            HStack(spacing: 6) {
                Label(model.locateRoom(profile.bedroom_room_id)?.room.name ?? "Missing room",
                      systemImage: "bed.double")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(profile.tags, id: \.self) { tag in
                    Text(tag.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
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
            return dispatch(action)
        }
    }

    /// Dispatches and surfaces a rejection; returns whether the store accepted it.
    @discardableResult
    private func dispatch(_ action: EditAction) -> Bool {
        guard let store else { return false }
        switch store.dispatch(action) {
        case .applied:
            return true
        case .rejected(let issues):
            rejectionMessage = issues.map(\.message).joined(separator: "\n")
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
        } catch {
            saveError = "\(error)"
        }
        onModelChanged?()
    }
}

#Preview {
    NavigationStack {
        ProfilesScreen(homeID: "missing")
    }
}
