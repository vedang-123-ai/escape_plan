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

public final class HomeModelStore {

    /// Records one accepted mutation. S2.2's undo stack and autosave both subscribe here —
    /// `before`/`after` snapshots are all an undo stack needs, so undo never re-runs a reducer.
    public struct Commit: Sendable {
        public let action: EditAction
        public let before: HomeModel
        public let after: HomeModel
    }

    public enum Outcome: Equatable {
        /// Applied. Carries what the snapper did, so the UI can show "snapped to wall".
        case applied(snap: SnapResult?)
        /// Refused; the model is untouched. The editor plays an error haptic and shows these.
        case rejected([ValidationIssue])

        public var didApply: Bool {
            if case .applied = self { return true }
            return false
        }
    }

    // MARK: - State

    public private(set) var model: HomeModel
    public private(set) var activeFloorId: String
    /// UI-only; never persisted into the document.
    public private(set) var selection: Selection = .none
    public var snapSettings: SnapSettings

    /// Called after every accepted mutation. S2.2 attaches undo-stack push + autosave here.
    /// Not called for `replaceModel` (undo itself must not push onto the undo stack).
    public var onCommit: ((Commit) -> Void)?

    private let now: () -> Date
    private let makeId: () -> String

    // MARK: - Defaults

    /// A new room's footprint, in meters. Big enough to grab and drag on a phone.
    public static let defaultRoomSize = (width: 3.0, height: 3.0)
    public static let defaultFloorHeightM = 2.7

    // MARK: - Init

    /// Fails if `model` is already invalid — the store's guarantee only holds from a valid seed,
    /// so we refuse to launder a broken document into a "trusted" one.
    public init(model: HomeModel,
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

    public enum StoreError: Error {
        case invalidInitialModel([ValidationIssue])
    }

    // MARK: - Selection (UI state — no validation, no commit)

    public func select(_ selection: Selection) {
        self.selection = selection
    }

    public func clearSelection() { selection = .none }

    /// Switches the edited floor. Per-floor edit isolation: every action resolves ids against
    /// the whole model, but `snapContext` and the renderer only ever see the active floor.
    @discardableResult
    public func setActiveFloor(_ floorId: String) -> Bool {
        guard model.floor(floorId) != nil else { return false }
        activeFloorId = floorId
        selection = .none
        return true
    }

    public var activeFloor: Floor {
        // Safe: activeFloorId is only ever set to a floor that exists, and deleteFloor
        // reassigns it before committing.
        model.floor(activeFloorId)!
    }

    // MARK: - Dispatch

    /// The one door in. Reduce onto a copy -> validate -> commit or reject.
    @discardableResult
    public func dispatch(_ action: EditAction) -> Outcome {
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

        draft.meta.modified = Self.iso8601.string(from: now())

        let before = model
        model = draft
        onCommit?(Commit(action: action, before: before, after: draft))
        return .applied(snap: snap)
    }

    /// Wholesale replacement, used by S2.2's undo/redo (and by loading a document). Validated
    /// like everything else, but does NOT fire `onCommit` — undoing must not record a commit.
    @discardableResult
    public func replaceModel(_ newModel: HomeModel) -> Outcome {
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

        case .setFloorHeight(let floorId, let heightM):
            let i = try floorIndex(draft, floorId)
            draft.floors[i].heightM = heightM
            return nil

        case .addRoom(let floorId, let origin, let widthM, let heightM, let type, let name):
            let i = try floorIndex(draft, floorId)
            let snapped = SnapEngine.snap(origin, context: snapContext(draft, floorId: floorId),
                                          settings: snapSettings)
            draft.floors[i].rooms.append(
                Room(id: makeId(), name: name, type: type,
                     polygon: Geometry.rectangle(origin: snapped.point,
                                                 width: widthM, height: heightM),
                     source: .manual))
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
                  heightM: Self.defaultFloorHeightM,
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
        let roomIds = Set(draft.floors[i].rooms.map(\.id))

        if let p = draft.profiles.first(where: { roomIds.contains($0.bedroomRoomId) }) {
            throw ValidationIssue(.danglingReference, entityId: floorId,
                                  "profile '\(p.name)' sleeps on this floor — reassign it first")
        }
        // Stairs landing on this floor have no meaning once it's gone.
        draft.stairs.removeAll { $0.fromEnd.floorId == floorId || $0.toEnd.floorId == floorId }
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
        if let p = draft.profiles.first(where: { $0.bedroomRoomId == roomId }) {
            throw ValidationIssue(.danglingReference, entityId: roomId,
                                  "profile '\(p.name)' sleeps here — reassign them first")
        }
        if let s = draft.stairs.first(where: { $0.fromEnd.roomId == roomId || $0.toEnd.roomId == roomId }) {
            throw ValidationIssue(.danglingReference, entityId: roomId,
                                  "stairs '\(s.id)' land in this room — delete them first")
        }
        draft.floors[f].openings.removeAll { $0.roomIds.contains(roomId) }
        draft.floors[f].rooms.remove(at: r)

        if selection.roomId == roomId { selection = .none }
    }

    // MARK: Drags

    private func dragVertex(_ draft: inout HomeModel, _ roomId: String,
                            _ vertexIndex: Int, _ target: Point2D) throws -> SnapResult {
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
                          _ edgeIndex: Int, _ by: Point2D) throws -> SnapResult {
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

    // MARK: - Snap context

    /// Everything on `floorId` worth snapping to, minus the room being dragged. Per-floor
    /// isolation: geometry on other floors is never a snap target.
    public func snapContext(_ model: HomeModel, floorId: String,
                            excludingRoom excluded: String? = nil) -> SnapContext {
        guard let floor = model.floor(floorId) else { return .empty }
        var vertices: [Point2D] = []
        var segments: [[Point2D]] = []
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

    // MARK: - Factories

    private func starterRoom() -> Room {
        Room(id: makeId(), name: "Room", type: .other,
             polygon: Geometry.rectangle(origin: Point2D(0, 0),
                                         width: Self.defaultRoomSize.width,
                                         height: Self.defaultRoomSize.height),
             source: .manual)
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

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The emptiest model the schema permits: one floor, one room. There is no such thing as a
    /// zero-room home in the contract (`floor.rooms` is minItems: 1), so "start from empty"
    /// means starting here and reshaping.
    public static func newHome(name: String = "My Home",
                               now: @escaping () -> Date = Date.init,
                               makeId: @escaping () -> String = { UUID().uuidString }) -> HomeModel {
        let stamp = iso8601.string(from: now())
        let room = Room(id: makeId(), name: "Room", type: .other,
                        polygon: Geometry.rectangle(origin: Point2D(0, 0),
                                                    width: defaultRoomSize.width,
                                                    height: defaultRoomSize.height),
                        source: .manual)
        return HomeModel(
            homeId: UUID().uuidString,
            name: name,
            floors: [Floor(id: makeId(), level: 0, name: floorName(level: 0),
                           heightM: defaultFloorHeightM, rooms: [room])],
            meta: Meta(created: stamp, modified: stamp))
    }
}
