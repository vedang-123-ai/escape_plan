//  HomeModelStore.swift — the single reducer-style gate for every HomeModel mutation.
//
//  THE INVARIANT THIS FILE EXISTS TO GUARANTEE:
//    a store constructed from a valid model can never hold an invalid one, no matter what
//    sequence of actions is dispatched at it.
//  It is enforced structurally, not by discipline: `dispatch` reduces onto a COPY, validates
//  the copy with EditorValidation, and only then commits. A rejected action leaves the model
//  bit-for-bit unchanged and hands back the reasons (the UI answers with a haptic).
//
//  Pure except for the commit hooks. No I/O, no SceneKit, no SwiftUI — the SceneKit bridge and
//  S2.2's undo/autosave layer sit on top of `onCommit`, they don't reach inside.
//
//  Not thread-safe by design: it is main-actor UI state. Callers stay on the main thread.

import Foundation

final class HomeModelStore {

    /// Records one accepted mutation. S2.2's undo stack and autosave both subscribe here —
    /// `before`/`after` snapshots are all an undo stack needs, so undo never re-runs a reducer.
    struct Commit: Sendable {
        let action: EditAction
        let before: HomeModel
        let after: HomeModel
    }

    enum Outcome: Equatable {
        /// Applied. Carries what the snapper did, so the UI can show "snapped to wall".
        case applied(snap: SnapResult?)
        /// Refused; the model is untouched. The editor plays an error haptic and shows these.
        case rejected([ValidationIssue])

        var didApply: Bool {
            if case .applied = self { return true }
            return false
        }
    }

    // MARK: - State

    private(set) var model: HomeModel
    private(set) var activeFloorId: String
    /// UI-only; never persisted into the document.
    private(set) var selection: Selection = .none
    var snapSettings: SnapSettings

    /// Called after every accepted mutation. S2.2 attaches undo-stack push + autosave here.
    /// Not called for `replaceModel` (undo itself must not push onto the undo stack).
    var onCommit: ((Commit) -> Void)?

    private let now: () -> Date
    private let makeId: () -> String

    // MARK: - Defaults

    /// A new room's footprint, in meters. Big enough to grab and drag on a phone.
    static let defaultRoomSize = (width: 3.0, height: 3.0)
    static let defaultFloorHeightM = 2.7

    // MARK: - Init

    /// Fails if `model` is already invalid — the store's guarantee only holds from a valid seed,
    /// so we refuse to launder a broken document into a "trusted" one.
    init(model: HomeModel,
                activeFloorId: String? = nil,
                snapSettings: SnapSettings = .default,
                now: @escaping () -> Date = Date.init,
                makeId: @escaping () -> String = { UUID().uuidString }) throws {
        let issues = EditorValidation.validate(model)
        guard issues.isEmpty else { throw StoreError.invalidInitialModel(issues) }

        self.model = model
        self.snapSettings = snapSettings
        self.now = now
        self.makeId = makeId

        if let activeFloorId, model.floor(activeFloorId) != nil {
            self.activeFloorId = activeFloorId
        } else {
            // Lowest level = ground floor = where you start editing.
            self.activeFloorId = model.floors.min(by: { $0.level < $1.level })!.id
        }
    }

    enum StoreError: Error {
        case invalidInitialModel([ValidationIssue])
    }

    // MARK: - Selection (UI state — no validation, no commit)

    func select(_ selection: Selection) {
        self.selection = selection
    }

    func clearSelection() { selection = .none }

    /// Switches the edited floor. Per-floor edit isolation: every action resolves ids against
    /// the whole model, but `snapContext` and the renderer only ever see the active floor.
    @discardableResult
    func setActiveFloor(_ floorId: String) -> Bool {
        guard model.floor(floorId) != nil else { return false }
        activeFloorId = floorId
        selection = .none
        return true
    }

    var activeFloor: Floor {
        // Safe: activeFloorId is only ever set to a floor that exists, and deleteFloor
        // reassigns it before committing.
        model.floor(activeFloorId)!
    }

    // MARK: - Dispatch

    /// The one door in. Reduce onto a copy -> validate -> commit or reject.
    @discardableResult
    func dispatch(_ action: EditAction) -> Outcome {
        var draft = model
        let snap: SnapResult?

        do {
            snap = try reduce(&draft, action)
        } catch let issue as ValidationIssue {
            return .rejected([issue])
        } catch {
            return .rejected([.init(.danglingReference, "unexpected reducer failure: \(error)")])
        }

        let issues = EditorValidation.validate(draft)
        guard issues.isEmpty else { return .rejected(issues) }

        draft.meta.modified = now()

        let before = model
        model = draft
        onCommit?(Commit(action: action, before: before, after: draft))
        return .applied(snap: snap)
    }

    /// Wholesale replacement, used by S2.2's undo/redo (and by loading a document). Validated
    /// like everything else, but does NOT fire `onCommit` — undoing must not record a commit.
    @discardableResult
    func replaceModel(_ newModel: HomeModel) -> Outcome {
        let issues = EditorValidation.validate(newModel)
        guard issues.isEmpty else { return .rejected(issues) }
        model = newModel
        if model.floor(activeFloorId) == nil {
            activeFloorId = model.floors.min(by: { $0.level < $1.level })!.id
        }
        selection = .none
        return .applied(snap: nil)
    }

    // MARK: - Reducer

    /// Mutates `draft` or throws a ValidationIssue for things validation alone can't phrase
    /// (a missing id has no entity to complain about). Never touches `self.model`.
    private func reduce(_ draft: inout HomeModel, _ action: EditAction) throws -> SnapResult? {
        switch action {

        case .setHomeName(let name):
            draft.name = name
            return nil

        case .addFloor(let relativeTo, let above):
            try addFloor(&draft, relativeTo: relativeTo, above: above)
            return nil

        case .deleteFloor(let floorId):
            try deleteFloor(&draft, floorId)
            return nil

        case .renameFloor(let floorId, let name):
            let i = try floorIndex(draft, floorId)
            draft.floors[i].name = name
            return nil

        case .setFloorHeight(let floorId, let height_m):
            let i = try floorIndex(draft, floorId)
            draft.floors[i].height_m = height_m
            return nil

        case .addRoom(let floorId, let origin, let width_m, let height_m, let type, let name):
            let i = try floorIndex(draft, floorId)
            let snapped = SnapEngine.snap(origin, context: snapContext(draft, floorId: floorId),
                                          settings: snapSettings)
            draft.floors[i].rooms.append(
                Room(id: makeId(), name: name, type: type,
                     polygon: Geometry.rectangle(origin: snapped.point,
                                                 width: width_m, height: height_m),
                     source: .manual, confidence: nil))
            return snapped

        case .deleteRoom(let roomId):
            try deleteRoom(&draft, roomId)
            return nil

        case .renameRoom(let roomId, let name):
            let (f, r) = try roomIndex(draft, roomId)
            draft.floors[f].rooms[r].name = name
            return nil

        case .setRoomType(let roomId, let type):
            let (f, r) = try roomIndex(draft, roomId)
            draft.floors[f].rooms[r].type = type
            return nil

        case .dragVertex(let roomId, let vertexIndex, let target):
            return try dragVertex(&draft, roomId, vertexIndex, target)

        case .dragEdge(let roomId, let edgeIndex, let by):
            return try dragEdge(&draft, roomId, edgeIndex, by)

        case .dragRoom(let roomId, let by):
            let (f, r) = try roomIndex(draft, roomId)
            let delta = SnapEngine.snapTranslation(by, settings: snapSettings)
            draft.floors[f].rooms[r].polygon =
                Geometry.translate(draft.floors[f].rooms[r].polygon, by: delta)
            return SnapResult(delta, snapSettings.gridEnabled ? .grid : .none)

        case .dragOpening(let openingId, let t):
            try dragOpening(&draft, openingId, t)
            return nil

        case .addStairs(let fromFloorId, let fromRoomId, let toFloorId, let toRoomId,
                        let footprint, let kind):
            try addStairs(&draft, fromFloorId, fromRoomId, toFloorId, toRoomId, footprint, kind)
            return nil

        case .deleteStairs(let stairsId):
            try deleteStairs(&draft, stairsId)
            return nil

        case .addProfile(let profileId, let name, let tags, let bedroom_room_id):
            draft.profiles.append(Profile(id: profileId, name: name, tags: tags,
                                          bedroom_room_id: bedroom_room_id))
            return nil

        case .updateProfile(let profileId, let name, let tags, let bedroom_room_id):
            let i = try profileIndex(draft, profileId)
            draft.profiles[i] = Profile(id: profileId, name: name, tags: tags,
                                        bedroom_room_id: bedroom_room_id)
            return nil

        case .deleteProfile(let profileId):
            let i = try profileIndex(draft, profileId)
            draft.profiles.remove(at: i)
            return nil
        }
    }

    // MARK: Floors

    private func addFloor(_ draft: inout HomeModel, relativeTo: String, above: Bool) throws {
        let i = try floorIndex(draft, relativeTo)
        let base = draft.floors[i].level
        let used = Set(draft.floors.map(\.level))

        // Take the first free level in the requested direction, so "add above" twice gives you
        // two floors rather than a level collision.
        var level = above ? base + 1 : base - 1
        while used.contains(level) { level += above ? 1 : -1 }

        let floorId = makeId()
        draft.floors.append(
            Floor(id: floorId,
                  level: level,
                  name: Self.floorName(level: level),
                  height_m: Self.defaultFloorHeightM,
                  // The schema requires >= 1 room per floor, so a new floor is born with a
                  // starter room for the user to reshape rather than an invalid empty one.
                  rooms: [starterRoom()]))
        draft.floors.sort { $0.level < $1.level }
    }

    private func deleteFloor(_ draft: inout HomeModel, _ floorId: String) throws {
        let i = try floorIndex(draft, floorId)
        guard draft.floors.count > 1 else {
            throw ValidationIssue(.emptyCollection, entityId: floorId,
                                  "cannot delete the only floor — a home must have at least one")
        }
        let room_ids = Set(draft.floors[i].rooms.map(\.id))

        if let p = draft.profiles.first(where: { room_ids.contains($0.bedroom_room_id) }) {
            throw ValidationIssue(.danglingReference, entityId: floorId,
                                  "profile '\(p.name)' sleeps on this floor — reassign it first")
        }
        // Stairs landing on this floor have no meaning once it's gone.
        draft.stairs.removeAll { $0.from.floor_id == floorId || $0.to.floor_id == floorId }
        draft.floors.remove(at: i)

        if activeFloorId == floorId {
            activeFloorId = draft.floors.min(by: { $0.level < $1.level })!.id
            selection = .none
        }
    }

    // MARK: Rooms

    private func deleteRoom(_ draft: inout HomeModel, _ roomId: String) throws {
        let (f, r) = try roomIndex(draft, roomId)
        guard draft.floors[f].rooms.count > 1 else {
            throw ValidationIssue(.emptyCollection, entityId: roomId,
                                  "cannot delete the only room on this floor — delete the floor instead")
        }
        // Refuse rather than cascade: silently deleting someone's bedroom assignment loses
        // information the user can't get back. Cascading openings is safe (they only exist to
        // connect this room); cascading a profile's home is not.
        if let p = draft.profiles.first(where: { $0.bedroom_room_id == roomId }) {
            throw ValidationIssue(.danglingReference, entityId: roomId,
                                  "profile '\(p.name)' sleeps here — reassign them first")
        }
        if let s = draft.stairs.first(where: { $0.from.room_id == roomId || $0.to.room_id == roomId }) {
            throw ValidationIssue(.danglingReference, entityId: roomId,
                                  "stairs '\(s.id)' land in this room — delete them first")
        }
        draft.floors[f].openings.removeAll { $0.room_ids.contains(roomId) }
        draft.floors[f].rooms.remove(at: r)

        if selection.roomId == roomId { selection = .none }
    }

    // MARK: Drags

    private func dragVertex(_ draft: inout HomeModel, _ roomId: String,
                            _ vertexIndex: Int, _ target: Point) throws -> SnapResult {
        let (f, r) = try roomIndex(draft, roomId)
        let polygon = draft.floors[f].rooms[r].polygon
        guard vertexIndex >= 0, vertexIndex < polygon.count else {
            throw ValidationIssue(.polygonDegenerate, entityId: roomId,
                                  "vertex index \(vertexIndex) is out of range (\(polygon.count) vertices)")
        }

        // Axis anchors are this vertex's own two neighbours: locking onto their x/y is what
        // keeps the two walls meeting here orthogonal.
        let n = polygon.count
        var context = snapContext(draft, floorId: draft.floors[f].id, excludingRoom: roomId)
        context.axisAnchors = [polygon[(vertexIndex + n - 1) % n], polygon[(vertexIndex + 1) % n]]

        let snapped = SnapEngine.snap(target, context: context, settings: snapSettings)
        draft.floors[f].rooms[r].polygon[vertexIndex] = snapped.point
        return snapped
    }

    private func dragEdge(_ draft: inout HomeModel, _ roomId: String,
                          _ edgeIndex: Int, _ by: Point) throws -> SnapResult {
        let (f, r) = try roomIndex(draft, roomId)
        let count = draft.floors[f].rooms[r].polygon.count
        guard edgeIndex >= 0, edgeIndex < count else {
            throw ValidationIssue(.openingPlacement, entityId: roomId,
                                  "edge index \(edgeIndex) is out of range (\(count) edges)")
        }

        // Translate the whole delta rather than each endpoint independently: the wall keeps its
        // length and direction, and the two neighbouring walls stretch because they share the
        // endpoints we just moved. Openings need no adjustment — their placement is parametric.
        let delta = SnapEngine.snapTranslation(by, settings: snapSettings)
        let a = edgeIndex
        let b = (edgeIndex + 1) % count
        draft.floors[f].rooms[r].polygon[a] = Geometry.add(draft.floors[f].rooms[r].polygon[a], delta)
        draft.floors[f].rooms[r].polygon[b] = Geometry.add(draft.floors[f].rooms[r].polygon[b], delta)
        return SnapResult(delta, snapSettings.gridEnabled ? .grid : .none)
    }

    // MARK: Openings

    /// Slides an opening's t0/t1 along its host wall, preserving its width_m. `t` is the
    /// requested midpoint position; the reducer (not the caller) owns turning that plus the
    /// opening's own width into a t0/t1 pair, matching how dragEdge owns its own delta math.
    private func dragOpening(_ draft: inout HomeModel, _ openingId: String, _ t: Double) throws {
        let (f, o) = try openingIndex(draft, openingId)
        let opening = draft.floors[f].openings[o]
        let seg = opening.wall_segment
        guard let host = draft.floors[f].room(seg.room_id),
              let edge = Geometry.edge(host.polygon, seg.edge_index) else {
            throw ValidationIssue(.danglingReference, entityId: openingId,
                                  "opening's host wall no longer exists")
        }
        let edgeLength = Geometry.distance(edge.a, edge.b)
        guard edgeLength > 1e-6 else {
            throw ValidationIssue(.openingPlacement, entityId: openingId,
                                  "host wall has zero length")
        }
        let halfWidthT = (opening.width_m / 2) / edgeLength
        let clampedT = min(1, max(0, t))
        let newT0 = min(1, max(0, clampedT - halfWidthT))
        let newT1 = min(1, max(0, clampedT + halfWidthT))
        draft.floors[f].openings[o].wall_segment.t0 = newT0
        draft.floors[f].openings[o].wall_segment.t1 = newT1
    }

    // MARK: Stairs

    private func addStairs(_ draft: inout HomeModel, _ fromFloorId: String, _ fromRoomId: String,
                           _ toFloorId: String, _ toRoomId: String, _ footprint: Polygon,
                           _ kind: StairKind) throws {
        _ = try floorIndex(draft, fromFloorId)
        _ = try floorIndex(draft, toFloorId)
        guard draft.floor(fromFloorId)?.room(fromRoomId) != nil else {
            throw ValidationIssue(.danglingReference, entityId: fromRoomId,
                                  "no such room on the from-floor")
        }
        guard draft.floor(toFloorId)?.room(toRoomId) != nil else {
            throw ValidationIssue(.danglingReference, entityId: toRoomId,
                                  "no such room on the to-floor")
        }
        // EditorValidation.validateStairs is the real gate (from/to distinctness, footprint
        // simplicity, provenance) — this just builds a well-formed candidate.
        draft.stairs.append(Stairs(id: makeId(),
                                   from: StairEnd(floor_id: fromFloorId, room_id: fromRoomId),
                                   to: StairEnd(floor_id: toFloorId, room_id: toRoomId),
                                   footprint: footprint, kind: kind, source: .manual,
                                   confidence: nil))
    }

    private func deleteStairs(_ draft: inout HomeModel, _ stairsId: String) throws {
        guard let i = draft.stairs.firstIndex(where: { $0.id == stairsId }) else {
            throw ValidationIssue(.danglingReference, entityId: stairsId, "no such stairs")
        }
        draft.stairs.remove(at: i)
        if case .stairs(let id) = selection, id == stairsId { selection = .none }
    }

    // MARK: - Snap context

    /// Everything on `floorId` worth snapping to, minus the room being dragged. Per-floor
    /// isolation: geometry on other floors is never a snap target.
    func snapContext(_ model: HomeModel, floorId: String,
                            excludingRoom excluded: String? = nil) -> SnapContext {
        guard let floor = model.floor(floorId) else { return .empty }
        var vertices: [Point] = []
        var segments: [[Point]] = []
        for room in floor.rooms where room.id != excluded {
            vertices += room.polygon
            for i in room.polygon.indices {
                let e = room.polygon[(i + 1) % room.polygon.count]
                segments.append([room.polygon[i], e])
            }
        }
        return SnapContext(vertices: vertices, segments: segments)
    }

    // MARK: - Index helpers

    private func floorIndex(_ model: HomeModel, _ floorId: String) throws -> Int {
        guard let i = model.floorIndex(floorId) else {
            throw ValidationIssue(.danglingReference, entityId: floorId, "no such floor")
        }
        return i
    }

    private func roomIndex(_ model: HomeModel, _ roomId: String) throws -> (Int, Int) {
        for (f, floor) in model.floors.enumerated() {
            if let r = floor.rooms.firstIndex(where: { $0.id == roomId }) { return (f, r) }
        }
        throw ValidationIssue(.danglingReference, entityId: roomId, "no such room")
    }

    private func openingIndex(_ model: HomeModel, _ openingId: String) throws -> (Int, Int) {
        for (f, floor) in model.floors.enumerated() {
            if let o = floor.openings.firstIndex(where: { $0.id == openingId }) { return (f, o) }
        }
        throw ValidationIssue(.danglingReference, entityId: openingId, "no such opening")
    }

    private func profileIndex(_ model: HomeModel, _ profileId: String) throws -> Int {
        guard let i = model.profiles.firstIndex(where: { $0.id == profileId }) else {
            throw ValidationIssue(.danglingReference, entityId: profileId, "no such profile")
        }
        return i
    }

    // MARK: - Factories

    private func starterRoom() -> Room {
        Room(id: makeId(), name: "Room", type: .other,
             polygon: Geometry.rectangle(origin: Point(0, 0),
                                         width: Self.defaultRoomSize.width,
                                         height: Self.defaultRoomSize.height),
             source: .manual, confidence: nil)
    }

    static func floorName(level: Int) -> String {
        switch level {
        case 0: return "Ground Floor"
        case 1: return "Second Floor"
        case 2: return "Third Floor"
        case -1: return "Basement"
        case let l where l < -1: return "Basement \(-l)"
        default: return "Floor \(level + 1)"
        }
    }

    /// The emptiest model the schema permits: one floor, one room. There is no such thing as a
    /// zero-room home in the contract (`floor.rooms` is minItems: 1), so "start from empty"
    /// means starting here and reshaping.
    static func newHome(name: String = "My Home",
                               now: @escaping () -> Date = Date.init,
                               makeId: @escaping () -> String = { UUID().uuidString }) -> HomeModel {
        let stamp = now()
        let room = Room(id: makeId(), name: "Room", type: .other,
                        polygon: Geometry.rectangle(origin: Point(0, 0),
                                                    width: defaultRoomSize.width,
                                                    height: defaultRoomSize.height),
                        source: .manual, confidence: nil)
        return HomeModel(
            schema_version: HomeModel.currentSchemaVersion,
            home_id: UUID().uuidString,
            name: name,
            floors: [Floor(id: makeId(), level: 0, name: floorName(level: 0),
                           height_m: defaultFloorHeightM, rooms: [room])],
            meta: Meta(created: stamp, modified: stamp))
    }
}
