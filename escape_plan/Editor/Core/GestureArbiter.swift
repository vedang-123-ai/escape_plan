//  GestureArbiter.swift — who owns a one-finger drag: the camera or the editor?
//
//  The unified view has no edit mode, so every one-finger pan is ambiguous until the moment
//  it begins. The rule (confirmed spec): a drag EDITS only when it lands on the current
//  selection — the thing the user already tapped — or on a part of the selected room (its
//  corners and walls are what room editing is). Everything else orbits the camera. Decided
//  once at .began and latched for the whole gesture: no mid-drag reassignment.

import Foundation

enum GestureArbiter {

    enum DragIntent: Equatable {
        case camera
        case edit
    }

    /// `hit`: what's under the finger at .began (pure `HitTesting` result).
    /// `current`: the store's live selection.
    static func intent(hit: Selection, current: Selection) -> DragIntent {
        guard hit != .none, current != .none else { return .camera }
        if hit == current { return .edit }
        // Dragging any handle of the selected room (corner, wall, interior) is still editing
        // that room — requiring a separate tap per corner would make reshaping unbearable.
        if let selectedRoom = current.roomId, hit.roomId == selectedRoom { return .edit }
        return .camera
    }
}
