//
//  ChecklistItem+Objects.swift
//  escape_plan — S7.7 (finding → object in the 3D view)
//
//  Which object in the model a checklist row is talking about. The backend owns the id grammar
//  (`backend/app/scoring/checklist.py`); this is the only place that reads it, so when that
//  grammar changes there is one file to fix.
//
//      hazard.<rule_id>.<object_id>                       — S7.5 object hazards
//      mitigation.secure.<object_id>[.renter]             — the generic strap-it item
//      routes.blocked_opening.<room_id>.<object_id>[-<object_id>…]
//      routes.narrows_route.<room_id>.<object_id>[-<object_id>…]
//
//  The route ids join their culprits with "-", and object ids CONTAIN "-" — the converter emits
//  `obj-<hex>` and "Add Object" in House uses a raw `UUID().uuidString`. So the tail cannot be split on
//  "-" without shredding the ids. It is resolved against the ids the home actually has instead,
//  which also means a row pointing at an object that has since been deleted resolves to nothing
//  rather than to a wrong object.

import Foundation

enum ChecklistObjectIDs {

    /// The object ids `itemID` refers to, in the order they appear, filtered to `known`.
    static func resolve(itemID: String, known: [String]) -> [String] {
        let parts = itemID.split(separator: ".").map(String.init)
        guard let head = parts.first else { return [] }

        switch head {
        case "hazard":
            // hazard.<rule_id>.<object_id> — rule ids never contain a dot.
            guard parts.count >= 3 else { return [] }
            return known.contains(parts[2]) ? [parts[2]] : []

        case "mitigation":
            // mitigation.secure.<object_id>, optionally followed by ".renter".
            guard parts.count >= 3, parts[1] == "secure" else { return [] }
            return known.contains(parts[2]) ? [parts[2]] : []

        case "routes":
            guard parts.count >= 4,
                  parts[1] == "blocked_opening" || parts[1] == "narrows_route" else { return [] }
            // Everything past the room id is the "-"-joined culprit list (or the literal
            // "obstruction" when the culprit is the room's geometry rather than furniture).
            let tail = parts[3...].joined(separator: ".")
            return known.filter { contains(tail: tail, id: $0) }
                        .sorted { (tail.range(of: $0)?.lowerBound ?? tail.startIndex)
                                < (tail.range(of: $1)?.lowerBound ?? tail.startIndex) }

        default:
            return []
        }
    }

    /// `id` appears in `tail` as a whole element of a "-"-joined list, not as a fragment of a
    /// longer id.
    private static func contains(tail: String, id: String) -> Bool {
        if tail == id { return true }
        if tail.hasPrefix(id + "-") { return true }
        if tail.hasSuffix("-" + id) { return true }
        return tail.contains("-" + id + "-")
    }
}

extension ChecklistItem {
    /// The objects this row points at, resolved against `home`. Empty when the row is not about
    /// a specific object (most rows are not).
    func objectIDs(in home: HomeModel) -> [String] {
        let known = home.floors.flatMap { $0.objects }.map { $0.id }
        return ChecklistObjectIDs.resolve(itemID: id, known: known)
    }
}
