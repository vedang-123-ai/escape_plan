//  EditorScreen.swift
//  escape_plan
//
//  Real S2.1 editor screen, replacing the S1.3-pending placeholder. Loads (or creates) a
//  HomeModel, drives it through a `HomeModelStore`, and renders it with `EditorSceneView`
//  (the SceneKit top-down editor surface — see Editor/SceneKit/EditorSceneController.swift).
//
//  Autosaves through `HomeDocumentStore` on every accepted commit — the "S2.1's store should
//  call store.save(model:) on autosave" seam from Persistence/HomeLibrary.swift.

import SwiftUI

struct EditorScreen: View {
    /// nil = start a brand-new home; otherwise open an existing saved one.
    let homeID: String?
    /// Called after the editor creates or renames a home, so the caller (HomeScreen) can
    /// refresh its list without polling.
    var onModelChanged: (() -> Void)?

    @State private var store: HomeModelStore?
    @State private var loadError: String?
    @State private var revision = 0
    @State private var saveError: String?
    @State private var undoStack = UndoStack()
    @State private var addStairsSheetPresented = false

    private let documentStore: HomeDocumentStore?

    init(homeID: String?, onModelChanged: (() -> Void)? = nil) {
        self.homeID = homeID
        self.onModelChanged = onModelChanged
        self.documentStore = try? HomeDocumentStore()
    }

    /// Editor tab entry point (no specific home chosen via the Home list): resumes the most
    /// recently modified saved home, or starts a new one if there isn't one yet.
    init() {
        let documentStore = try? HomeDocumentStore()
        self.homeID = documentStore?.list().first?.id
        self.onModelChanged = nil
        self.documentStore = documentStore
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(store?.model.name ?? "Editor")
                .toolbar { toolbarContent }
        }
        .task { loadIfNeeded() }
        .sheet(isPresented: $addStairsSheetPresented) {
            if let store {
                addStairsSheet(for: store)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ContentUnavailableView("Couldn't open home", systemImage: "exclamationmark.triangle",
                                    description: Text(error))
        } else if let store {
            VStack(spacing: 0) {
                EditorSceneView(store: store, revision: revision, undoStack: undoStack)
                floorPicker(for: store)
                if let saveError {
                    Text("Autosave failed: \(saveError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
        } else {
            ProgressView("Loading…")
        }
    }

    @ViewBuilder
    private func floorPicker(for store: HomeModelStore) -> some View {
        if store.model.floors.count > 1 {
            Picker("Floor", selection: Binding(
                get: { store.activeFloorId },
                set: { store.setActiveFloor($0); revision += 1 }
            )) {
                ForEach(store.model.floorsByLevel) { floor in
                    Text(floor.name.isEmpty ? "Level \(floor.level)" : floor.name).tag(floor.id)
                }
            }
            .pickerStyle(.segmented)
            .padding()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!undoStack.canUndo)
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!undoStack.canRedo)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                addRoom()
            } label: {
                Label("Add Room", systemImage: "plus.square.on.square")
            }
            .disabled(store == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                addStairsSheetPresented = true
            } label: {
                Label("Add Stairs", systemImage: "figure.stairs")
            }
            .disabled(!canAddStairs)
        }
    }

    private func loadIfNeeded() {
        guard store == nil, loadError == nil else { return }
        do {
            let model: HomeModel
            if let homeID, let documentStore, documentStore.exists(homeID: homeID) {
                model = try documentStore.load(homeID: homeID, as: HomeModel.self)
            } else {
                model = Self.blankHome()
            }
            let newStore = try HomeModelStore(model: model)
            newStore.onCommit = { [documentStore, undoStack] commit in
                // Every accepted mutation (including each step of a live drag) must repaint the
                // 3D view — `HomeModelStore` isn't Observable, so nothing else triggers it.
                undoStack.recordCommit(commit)
                revision += 1
                autosave(newStore, documentStore: documentStore)
            }
            store = newStore
            // A brand-new home has nothing on disk yet — write it immediately so it shows up
            // in the home list without waiting for the first edit.
            if homeID == nil {
                autosave(newStore, documentStore: documentStore)
            }
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

    private func addRoom() {
        guard let store else { return }
        // Stagger new rooms so they don't land exactly on top of each other; not spatially
        // clever, just enough that the new room is visibly separate and grabbable.
        let count = store.activeFloor.rooms.count
        let offset = Double(count) * (HomeModelStore.defaultRoomSize.width + 0.5)
        store.dispatch(.addRoom(
            floorId: store.activeFloorId,
            origin: Point(x: offset, y: 0),
            width_m: HomeModelStore.defaultRoomSize.width,
            height_m: HomeModelStore.defaultRoomSize.height,
            type: .other,
            name: "New Room"
        ))
        revision += 1
    }

    // MARK: Undo/redo

    private func undo() {
        guard let store, undoStack.undo(on: store) else { return }
        // replaceModel does NOT fire onCommit (undoing must not push its own undo entry), so
        // this mirrors addRoom()'s manual revision-bump + explicit autosave.
        revision += 1
        autosave(store, documentStore: documentStore)
    }

    private func redo() {
        guard let store, undoStack.redo(on: store) else { return }
        revision += 1
        autosave(store, documentStore: documentStore)
    }

    // MARK: Stairs

    private var canAddStairs: Bool {
        guard let store else { return false }
        let hasFloorAbove = store.model.floors.contains { $0.level == store.activeFloor.level + 1 }
        return hasFloorAbove && store.selection.roomId != nil
    }

    @ViewBuilder
    private func addStairsSheet(for store: HomeModelStore) -> some View {
        NavigationStack {
            List {
                if let above = store.model.floors.first(where: { $0.level == store.activeFloor.level + 1 }) {
                    ForEach(above.rooms) { room in
                        Button(room.name) {
                            addStairs(toFloorId: above.id, toRoomId: room.id)
                        }
                    }
                }
            }
            .navigationTitle("Add Stairs To…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { addStairsSheetPresented = false }
                }
            }
        }
    }

    private func addStairs(toFloorId: String, toRoomId: String) {
        guard let store, let fromRoomId = store.selection.roomId,
              let fromRoom = store.activeFloor.room(fromRoomId) else { return }
        let sum = fromRoom.polygon.reduce(Point(0, 0)) { Point($0.x + $1.x, $0.y + $1.y) }
        let centroid = Point(sum.x / Double(fromRoom.polygon.count), sum.y / Double(fromRoom.polygon.count))
        let footprint: Polygon = [
            Point(centroid.x - 0.5, centroid.y - 0.5),
            Point(centroid.x + 0.5, centroid.y - 0.5),
            Point(centroid.x + 0.5, centroid.y + 0.5),
            Point(centroid.x - 0.5, centroid.y + 0.5)
        ]
        store.dispatch(.addStairs(fromFloorId: store.activeFloorId, fromRoomId: fromRoomId,
                                  toFloorId: toFloorId, toRoomId: toRoomId,
                                  footprint: footprint, kind: .straight))
        revision += 1
        addStairsSheetPresented = false
    }

    private static func blankHome() -> HomeModel {
        let now = Date()
        return HomeModel(
            schema_version: HomeModel.currentSchemaVersion,
            home_id: UUID().uuidString,
            name: "New Home",
            floors: [
                Floor(id: "floor-\(UUID().uuidString.prefix(8))", level: 0, name: "Ground Floor",
                      height_m: HomeModelStore.defaultFloorHeightM,
                      rooms: [Room(id: "room-\(UUID().uuidString.prefix(8))", name: "Room 1", type: .other,
                                   polygon: [Point(x: 0, y: 0), Point(x: 3, y: 0), Point(x: 3, y: 3), Point(x: 0, y: 3)],
                                   source: .manual, confidence: nil)],
                      openings: [])
            ],
            stairs: [],
            meta: Meta(created: now, modified: now)
        )
    }
}

#Preview {
    EditorScreen(homeID: nil)
}
