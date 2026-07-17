//  EditAction.swift — the complete vocabulary of editor mutations.
//
//  Every change to a HomeModel is one of these values, dispatched to HomeModelStore. Nothing
//  else may mutate the model (rules/languages/swift.md). Because the set is closed and each
//  action is a plain value, undo/redo (S2.2) and autosave are bookkeeping on top of it rather
//  than a rewrite.
//
//  Note what is deliberately ABSENT: nothing here touches `egress` (computed by the S1.1
//  backend annotator) or the geometry of an opening relative to its wall (parametric refs mean
//  openings ride along when walls move — that is the schema design paying off, not an action).

import Foundation

enum EditAction: Equatable, Sendable {

    // MARK: Home
    case setHomeName(String)

    // MARK: Floors
    /// Inserts a floor directly above or below `relativeTo`, taking the next free level.
    /// The new floor is seeded with one default room, because the schema requires every floor
    /// to have at least one (see `HomeModelStore.defaultRoomSize`).
    case addFloor(relativeTo: String, above: Bool)
    case deleteFloor(floorId: String)
    case renameFloor(floorId: String, name: String)
    case setFloorHeight(floorId: String, height_m: Double)

    // MARK: Rooms
    case addRoom(floorId: String, origin: Point, width_m: Double, height_m: Double,
                 type: RoomType, name: String)
    /// Cascades to the room's openings. Rejected if a profile or stair still references it.
    case deleteRoom(roomId: String)
    case renameRoom(roomId: String, name: String)
    case setRoomType(roomId: String, type: RoomType)

    // MARK: Drags
    /// Moves one corner. Connected walls follow because they share the vertex.
    case dragVertex(roomId: String, vertexIndex: Int, to: Point)
    /// Translates wall `edgeIndex` by `by`; the two neighbouring walls stretch to keep up.
    case dragEdge(roomId: String, edgeIndex: Int, by: Point)
    /// Translates the whole footprint.
    case dragRoom(roomId: String, by: Point)
}

extension EditAction {
    /// Human-readable label — S2.2 uses this for "Undo Move Wall" style menu titles.
    var undoLabel: String {
        switch self {
        case .setHomeName: return "Rename Home"
        case .addFloor: return "Add Floor"
        case .deleteFloor: return "Delete Floor"
        case .renameFloor: return "Rename Floor"
        case .setFloorHeight: return "Change Ceiling Height"
        case .addRoom: return "Add Room"
        case .deleteRoom: return "Delete Room"
        case .renameRoom: return "Rename Room"
        case .setRoomType: return "Change Room Type"
        case .dragVertex: return "Move Corner"
        case .dragEdge: return "Move Wall"
        case .dragRoom: return "Move Room"
        }
    }

    /// True for the continuous gestures. S2.2 coalesces a drag's many intermediate actions into
    /// one undo entry instead of 200.
    var isContinuousDrag: Bool {
        switch self {
        case .dragVertex, .dragEdge, .dragRoom: return true
        default: return false
        }
    }
}

// MARK: - Selection

/// What the user currently has selected. NOT part of the HomeModel — it is editor UI state and
/// must never be persisted into the document.
enum Selection: Equatable, Sendable {
    case none
    case room(roomId: String)
    case wall(roomId: String, edgeIndex: Int)
    case vertex(roomId: String, vertexIndex: Int)
    case opening(openingId: String)

    var roomId: String? {
        switch self {
        case .none, .opening: return nil
        case .room(let id), .wall(let id, _), .vertex(let id, _): return id
        }
    }
}
