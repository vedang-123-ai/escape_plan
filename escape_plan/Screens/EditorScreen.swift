//  EditorScreen.swift
//  escape_plan
//
//  The S2.1/S2.2 editor screen. Loads (or creates) a HomeModel into an `EditorSession`
//  (HomeModelStore + UndoStack + the delete-under-editor seam) and renders it with
//  `EditorSceneView` (the SceneKit top-down editor surface).
//
//  Rendering is reactive: `HomeModelStore` and `UndoStack` are @Observable, so every accepted
//  mutation, selection change, and undo/redo re-renders whatever reads them — the pre-S2.2
//  manual `revision += 1` bumps (which missed tap-selection and first-tap redo) are gone.
//
//  Autosaves through `HomeDocumentStore` on every accepted commit.

import SwiftUI

/// What a tap in the 3D view currently means. `.select` is the ordinary select/drag mode;
/// `.placeOpening` is armed by Add Door / Add Window and disarms after one placement.
enum EditorTool: Equatable {
    case select
    case placeOpening(OpeningKind)
}

struct EditorScreen: View {
    /// nil = start a brand-new home; otherwise open an existing saved one.
    let homeID: String?
    /// Called after the editor creates or renames a home, so the caller (HomeScreen) can
    /// refresh its list without polling.
    var onModelChanged: (() -> Void)?
    /// When the caller owns a `HomeLibrary`, the session registers as its open editor so a
    /// home deleted from the list closes this screen and drops its undo history (the
    /// `HomeModelPersisting` seam). The Editor-tab entry point has no library; that's fine.
    var library: HomeLibrary?

    @State private var session: EditorSession?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var addStairsSheetPresented = false
    @State private var tool: EditorTool = .select
    /// The most recent rejected action's reasons — the editor's visible "that's not allowed".
    @State private var rejection: String?

    @State private var renameTarget: RenameTarget?
    @State private var renameDraft = ""

    @Environment(\.dismiss) private var dismiss

    private let documentStore: HomeDocumentStore?

    init(homeID: String?, library: HomeLibrary? = nil, onModelChanged: (() -> Void)? = nil) {
        self.homeID = homeID
        self.library = library
        self.onModelChanged = onModelChanged
        self.documentStore = try? HomeDocumentStore()
    }

    /// Editor tab entry point (no specific home chosen via the Home list): resumes the most
    /// recently modified saved home, or starts a new one if there isn't one yet.
    init() {
        let documentStore = try? HomeDocumentStore()
        self.homeID = documentStore?.list().first?.id
        self.onModelChanged = nil
        self.library = nil
        self.documentStore = documentStore
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(session?.store.model.name ?? "Editor")
                .toolbar { toolbarContent }
        }
        .task { loadIfNeeded() }
        .onDisappear { unregisterFromLibrary() }
        .sheet(isPresented: $addStairsSheetPresented) {
            if let session {
                addStairsSheet(for: session.store)
            }
        }
        .alert(renameTarget?.title ?? "Rename", isPresented: renameAlertPresented,
               presenting: renameTarget) { target in
            TextField("Name", text: $renameDraft)
            Button("Rename") { commitRename(target) }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ContentUnavailableView("Couldn't open home", systemImage: "exclamationmark.triangle",
                                    description: Text(error))
        } else if let session {
            let store = session.store
            VStack(spacing: 0) {
                EditorSceneView(store: store,
                                model: store.model,
                                activeFloorId: store.activeFloorId,
                                selection: store.selection,
                                tool: tool,
                                undoStack: session.undoStack,
                                onOpeningPlaced: { tool = .select })
                if case .placeOpening(let kind) = tool {
                    placementHint(kind: kind)
                }
                inspector(for: store)
                floorPicker(for: store)
                if let rejection {
                    Text(rejection)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }
                if let saveError {
                    Text("Autosave failed: \(saveError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .onChange(of: session.wasDeletedExternally) { _, deleted in
                if deleted { dismiss() }
            }
        } else {
            ProgressView("Loading…")
        }
    }

    // MARK: Placement mode

    @ViewBuilder
    private func placementHint(kind: OpeningKind) -> some View {
        HStack {
            Image(systemName: kind == .door ? "door.left.hand.open" : "window.vertical.open")
            Text("Tap a wall to place the \(kind.rawValue). Interior vs. exterior is automatic.")
                .font(.caption)
            Spacer()
            Button("Cancel") { tool = .select }
                .font(.caption.bold())
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    // MARK: Inspector (selection-driven entry points)

    @ViewBuilder
    private func inspector(for store: HomeModelStore) -> some View {
        switch store.selection {
        case .room(let roomId):
            if let (_, room) = store.model.locateRoom(roomId) {
                inspectorBar {
                    Button {
                        beginRename(.room(roomId), currentName: room.name)
                    } label: {
                        Label(room.name, systemImage: "pencil")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    Picker("Type", selection: Binding(
                        get: { room.type },
                        set: { dispatch(.setRoomType(roomId: roomId, type: $0)) }
                    )) {
                        ForEach(RoomType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Button(role: .destructive) {
                        dispatch(.deleteRoom(roomId: roomId))
                    } label: {
                        Label("Delete Room", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        case .opening(let openingId):
            if let opening = store.activeFloor.openings.first(where: { $0.id == openingId }) {
                inspectorBar {
                    Picker("Kind", selection: Binding(
                        get: { opening.kind },
                        set: { dispatch(.setOpeningKind(openingId: openingId, kind: $0)) }
                    )) {
                        ForEach(OpeningKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                    Text(opening.isExit ? "Exterior" : "Interior")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        dispatch(.deleteOpening(openingId: openingId))
                    } label: {
                        Label("Delete Opening", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        case .stairs(let stairsId):
            inspectorBar {
                Label("Stairs", systemImage: "figure.stairs")
                    .font(.caption)
                Spacer()
                Button(role: .destructive) {
                    dispatch(.deleteStairs(stairsId: stairsId))
                } label: {
                    Label("Delete Stairs", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
        case .none, .wall, .vertex:
            EmptyView()
        }
    }

    @ViewBuilder
    private func inspectorBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12, content: content)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func floorPicker(for store: HomeModelStore) -> some View {
        if store.model.floors.count > 1 {
            Picker("Floor", selection: Binding(
                get: { store.activeFloorId },
                set: { store.setActiveFloor($0) }
            )) {
                ForEach(store.model.floorsByLevel) { floor in
                    Text(floor.name.isEmpty ? "Level \(floor.level)" : floor.name).tag(floor.id)
                }
            }
            .pickerStyle(.segmented)
            .padding()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!(session?.undoStack.canUndo ?? false))
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!(session?.undoStack.canRedo ?? false))
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    addRoom()
                } label: {
                    Label("Add Room", systemImage: "plus.square.on.square")
                }
                Button {
                    tool = .placeOpening(.door)
                } label: {
                    Label("Add Door", systemImage: "door.left.hand.open")
                }
                Button {
                    tool = .placeOpening(.window)
                } label: {
                    Label("Add Window", systemImage: "window.vertical.open")
                }
                Button {
                    addStairsSheetPresented = true
                } label: {
                    Label("Add Stairs", systemImage: "figure.stairs")
                }
                .disabled(!canAddStairs)
                Divider()
                Button {
                    addFloor(above: true)
                } label: {
                    Label("Add Floor Above", systemImage: "square.3.layers.3d.top.filled")
                }
                Button {
                    addFloor(above: false)
                } label: {
                    Label("Add Floor Below", systemImage: "square.3.layers.3d.bottom.filled")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .disabled(session == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    beginRename(.home, currentName: session?.store.model.name ?? "")
                } label: {
                    Label("Rename Home", systemImage: "pencil")
                }
                Button {
                    guard let store = session?.store else { return }
                    beginRename(.floor(store.activeFloorId), currentName: store.activeFloor.name)
                } label: {
                    Label("Rename Floor", systemImage: "pencil.line")
                }
                Button(role: .destructive) {
                    guard let store = session?.store else { return }
                    dispatch(.deleteFloor(floorId: store.activeFloorId))
                } label: {
                    Label("Delete This Floor", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(session == nil)
        }
    }

    // MARK: Loading & saving

    private func loadIfNeeded() {
        guard session == nil, loadError == nil else { return }
        do {
            let model: HomeModel
            if let homeID, let documentStore, documentStore.exists(homeID: homeID) {
                model = try documentStore.load(homeID: homeID, as: HomeModel.self)
            } else {
                model = Self.blankHome()
            }
            let newStore = try HomeModelStore(model: model)
            let newSession = EditorSession(store: newStore)
            newStore.onCommit = { [documentStore] commit in
                newSession.undoStack.recordCommit(commit)
                autosave(newStore, documentStore: documentStore)
            }
            session = newSession
            library?.editor = newSession
            // A brand-new home has nothing on disk yet — write it immediately so it shows up
            // in the home list without waiting for the first edit.
            if homeID == nil {
                autosave(newStore, documentStore: documentStore)
            }
        } catch {
            loadError = "\(error)"
        }
    }

    private func unregisterFromLibrary() {
        if let library, library.editor === session {
            library.editor = nil
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

    // MARK: Dispatch

    /// Screen-level dispatch: forwards to the store and surfaces a rejection's reasons in the
    /// UI (the store guarantees a rejected action left the model untouched).
    private func dispatch(_ action: EditAction) {
        guard let store = session?.store else { return }
        switch store.dispatch(action) {
        case .applied:
            rejection = nil
        case .rejected(let issues):
            rejection = issues.first?.message
        }
    }

    private func addRoom() {
        guard let store = session?.store else { return }
        // Stagger new rooms so they don't land exactly on top of each other; not spatially
        // clever, just enough that the new room is visibly separate and grabbable.
        let count = store.activeFloor.rooms.count
        let offset = Double(count) * (HomeModelStore.defaultRoomSize.width + 0.5)
        dispatch(.addRoom(
            floorId: store.activeFloorId,
            origin: Point(x: offset, y: 0),
            width_m: HomeModelStore.defaultRoomSize.width,
            height_m: HomeModelStore.defaultRoomSize.height,
            type: .other,
            name: "New Room"
        ))
    }

    private func addFloor(above: Bool) {
        guard let store = session?.store else { return }
        dispatch(.addFloor(relativeTo: store.activeFloorId, above: above))
    }

    // MARK: Undo/redo

    private func undo() {
        guard let session, session.undoStack.undo(on: session.store) else { return }
        // replaceModel does NOT fire onCommit (undoing must not push its own undo entry), so
        // autosave explicitly.
        autosave(session.store, documentStore: documentStore)
    }

    private func redo() {
        guard let session, session.undoStack.redo(on: session.store) else { return }
        autosave(session.store, documentStore: documentStore)
    }

    // MARK: Rename

    private enum RenameTarget: Equatable {
        case home
        case floor(String)
        case room(String)

        var title: String {
            switch self {
            case .home: return "Rename Home"
            case .floor: return "Rename Floor"
            case .room: return "Rename Room"
            }
        }
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func beginRename(_ target: RenameTarget, currentName: String) {
        renameDraft = currentName
        renameTarget = target
    }

    private func commitRename(_ target: RenameTarget) {
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !name.isEmpty else { return }
        switch target {
        case .home: dispatch(.setHomeName(name))
        case .floor(let floorId): dispatch(.renameFloor(floorId: floorId, name: name))
        case .room(let roomId): dispatch(.renameRoom(roomId: roomId, name: name))
        }
    }

    // MARK: Stairs

    private var canAddStairs: Bool {
        guard let store = session?.store else { return false }
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
        guard let store = session?.store, let fromRoomId = store.selection.roomId,
              let fromRoom = store.activeFloor.room(fromRoomId) else { return }
        let sum = fromRoom.polygon.reduce(Point(0, 0)) { Point($0.x + $1.x, $0.y + $1.y) }
        let centroid = Point(sum.x / Double(fromRoom.polygon.count), sum.y / Double(fromRoom.polygon.count))
        let footprint: Polygon = [
            Point(centroid.x - 0.5, centroid.y - 0.5),
            Point(centroid.x + 0.5, centroid.y - 0.5),
            Point(centroid.x + 0.5, centroid.y + 0.5),
            Point(centroid.x - 0.5, centroid.y + 0.5)
        ]
        dispatch(.addStairs(fromFloorId: store.activeFloorId, fromRoomId: fromRoomId,
                            toFloorId: toFloorId, toRoomId: toRoomId,
                            footprint: footprint, kind: .straight))
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
