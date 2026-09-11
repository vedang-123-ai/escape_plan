//
//  HazardHuntPlan.swift
//  EditorCore
//
//  The guided hazard hunt, as a pure function of the model.
//
//  WHY THIS EXISTS AS A SEPARATE FILE: the hunt's questions used to live inside
//  `HazardHuntView`, where nothing could test them — and three real defects hid there as a
//  result (see docs/decisions.md, 2026-09-10). Question generation is now Foundation-only and
//  lives in EditorCore, so `swift test` reaches it; the view is a renderer for what this
//  produces.
//
//  WHAT THE HUNT IS FOR: RoomPlan's taxonomy has no bookcase, no water heater and no portable
//  heater — the three objects the hazard rules care about most. A bookcase arrives as generic
//  `storage`; the other two do not arrive at all. So the hunt asks. The rule this file follows
//  everywhere: ASK ABOUT WHAT THE SCAN FOUND rather than inventing a second object on top of
//  it, because the scan already knows the position and size and the user should not have to
//  re-supply them.

import Foundation

/// One hunt question plus the exact edits each answer performs.
struct HazardHuntQuestion: Equatable, Identifiable {

    /// What the question is about.
    enum Subject: Equatable {
        /// An object already in the model — a Yes refines what we know about it.
        case existing(objectId: String)
        /// No object matches; a Yes creates one with this pre-generated id. The id is decided
        /// up front so a follow-up question can reference the object before it exists.
        case new(objectId: String)
    }

    let id: String
    let text: String
    let subject: Subject
    /// Dispatched in order on Yes.
    let yes: [EditAction]
    /// Dispatched in order on No. Usually empty — but NOT for "is it strapped?", where No is
    /// the hazard and has to be written down rather than skipped.
    let no: [EditAction]
    /// Ask only when the question with this id was answered Yes. nil = always ask.
    let requiresYesOf: String?
    /// Non-nil when a Yes creates an object the app cannot position on the user's behalf, so
    /// the view can tell them to drag it. Absent whenever the placement was derived from real
    /// geometry (beside the scanned bed, on the wall above it).
    let placementHint: String?

    var objectId: String {
        switch subject {
        case .existing(let id), .new(let id): return id
        }
    }
}

/// Builds the per-room question list.
enum HazardHuntPlan {

    // MARK: Tuning

    /// Categories the topple rule already treats as prone (mirrors `object_hazards.py` R1).
    /// Asking "is it strapped?" about anything in this set is never wasted breath.
    static let toppleProneCategories: Set<ObjectCategory> = [
        .bookcase, .wardrobe, .storage, .water_heater
    ]

    /// A scanned `storage`/`wardrobe` at least this tall is worth asking about — below it,
    /// a topple onto a bed is not the failure mode and the question is noise.
    static let bookcaseAskHeight_m = 1.2

    /// Default footprints for objects the hunt creates. Kept here, next to the questions that
    /// use them, rather than scattered through the view.
    static let bookcaseSize_m = [0.8, 0.4]
    static let bookcaseHeight_m = 1.8
    static let mountedTVSize_m = [1.0, 0.1]
    static let mountedTVHeight_m = 0.6
    static let mountedTVElevation_m = 1.5
    static let heaterSize_m = [0.3, 0.3]
    static let heaterHeight_m = 0.5
    static let waterHeaterSize_m = [0.6, 0.6]
    static let waterHeaterHeight_m = 1.5

    private static let placeItHint = "Drag it where it actually sits — the warnings are about distance."

    // MARK: Entry point

    /// - Parameter newObjectId: maps a stable key ("bookcase") to the id a created object gets.
    ///   The view passes UUIDs; tests pass something predictable.
    static func questions(for room: Room,
                          floorId: String,
                          objects: [FloorObject],
                          newObjectId: (String) -> String) -> [HazardHuntQuestion] {
        let inRoom = objectsIn(room: room, from: objects)
        var qs: [HazardHuntQuestion] = []

        qs += identifyBookcaseQuestions(room: room, objects: inRoom)
        qs += strapQuestions(room: room, objects: inRoom)
        qs += toppleFallbackQuestion(room: room, floorId: floorId, objects: inRoom,
                                     newObjectId: newObjectId)
        qs += mountedAboveBedQuestion(room: room, floorId: floorId, objects: inRoom,
                                      newObjectId: newObjectId)
        qs += heaterQuestion(room: room, floorId: floorId, newObjectId: newObjectId)
        qs += waterHeaterQuestions(room: room, floorId: floorId, objects: inRoom,
                                   newObjectId: newObjectId)
        return qs
    }

    /// Objects whose center falls inside the room — the same containment test the renderer's
    /// hit-testing uses, so "in this room" means one thing across the app.
    static func objectsIn(room: Room, from objects: [FloorObject]) -> [FloorObject] {
        objects.filter { Geometry.contains(room.polygon, $0.center) }
    }

    // MARK: Questions

    /// A tall scanned `storage`/`wardrobe` is the shape a bookcase arrives in. Confirming it
    /// RELABELS that object; it never adds a second one beside it.
    private static func identifyBookcaseQuestions(room: Room,
                                                  objects: [FloorObject]) -> [HazardHuntQuestion] {
        objects
            .filter { $0.source == .scan }
            .filter { $0.category == .storage || $0.category == .wardrobe }
            .filter { $0.height_m >= bookcaseAskHeight_m }
            .map { object in
                HazardHuntQuestion(
                    id: "identify.bookcase.\(object.id)",
                    text: "The scan found a tall \(object.category.displayName.lowercased()) "
                        + "in \(room.name). Is it a bookcase or open shelving?",
                    subject: .existing(objectId: object.id),
                    yes: [.setObjectCategory(objectId: object.id, category: .bookcase)],
                    no: [],
                    requiresYesOf: nil,
                    placementHint: nil
                )
            }
    }

    /// The one question that clears a topple finding. Asked about every topple-prone object
    /// already in the room, scanned or hand-placed.
    ///
    /// No is dispatched, not skipped: `secured` already defaults to false, but a recorded
    /// false is an answer and a defaulted false is an assumption, and the checklist tells the
    /// user to strap it either way.
    private static func strapQuestions(room: Room,
                                       objects: [FloorObject]) -> [HazardHuntQuestion] {
        objects
            .filter { toppleProneCategories.contains($0.category) }
            .filter { !$0.mounted }
            .map { object in
                HazardHuntQuestion(
                    id: "strap.\(object.id)",
                    text: "Is the \(object.category.displayName.lowercased()) in \(room.name) "
                        + "strapped or bolted to the wall?",
                    subject: .existing(objectId: object.id),
                    yes: [.setObjectSecured(objectId: object.id, secured: true)],
                    no: [.setObjectSecured(objectId: object.id, secured: false)],
                    requiresYesOf: nil,
                    placementHint: nil
                )
            }
    }

    /// Only when the scan found nothing topple-prone in a bedroom. Placed beside the bed when
    /// there is one, because the topple rule is measured in distance from the bed and the old
    /// room-center default put every answer in the wrong place.
    private static func toppleFallbackQuestion(room: Room,
                                               floorId: String,
                                               objects: [FloorObject],
                                               newObjectId: (String) -> String)
        -> [HazardHuntQuestion] {
        guard room.type == .bedroom else { return [] }
        guard !objects.contains(where: { toppleProneCategories.contains($0.category) }) else {
            return []
        }

        let id = newObjectId("bookcase")
        let bed = objects.first { $0.category == .bed }
        let beside = bed.flatMap {
            placeBeside($0, size: bookcaseSize_m, inside: room.polygon)
        }

        return [HazardHuntQuestion(
            id: "add.bookcase",
            text: "Anything tall and heavy near the bed — a bookcase, a dresser, a wardrobe?",
            subject: .new(objectId: id),
            yes: [.addObject(objectId: id, floorId: floorId, category: .bookcase,
                             center: beside ?? centroid(room.polygon),
                             size_m: bookcaseSize_m, height_m: bookcaseHeight_m)],
            no: [],
            requiresYesOf: nil,
            placementHint: beside == nil ? placeItHint : nil
        )]
    }

    /// "Above it" needs an "it": without a bed there is no wall to mean, so the question is
    /// not asked at all rather than dropped in the middle of the room.
    private static func mountedAboveBedQuestion(room: Room,
                                                floorId: String,
                                                objects: [FloorObject],
                                                newObjectId: (String) -> String)
        -> [HazardHuntQuestion] {
        guard room.type == .bedroom, let bed = objects.first(where: { $0.category == .bed })
        else { return [] }

        let id = newObjectId("mounted")
        return [HazardHuntQuestion(
            id: "add.mounted",
            text: "Anything mounted on the wall above the bed — a TV, a mirror, a heavy shelf?",
            subject: .new(objectId: id),
            yes: [.addObject(objectId: id, floorId: floorId, category: .tv, center: bed.center,
                             size_m: mountedTVSize_m, height_m: mountedTVHeight_m),
                  .setObjectMounted(objectId: id, mounted: true),
                  .setObjectElevation(objectId: id, elevation_m: mountedTVElevation_m)],
            no: [],
            requiresYesOf: nil,
            placementHint: nil
        )]
    }

    /// Portable heaters are invisible to the scan and can be anywhere, so this one is always a
    /// cold ask — and says so, because the clearance rule is a distance.
    private static func heaterQuestion(room: Room,
                                       floorId: String,
                                       newObjectId: (String) -> String) -> [HazardHuntQuestion] {
        guard room.type != .bath, room.type != .kitchen else { return [] }

        let id = newObjectId("heater")
        return [HazardHuntQuestion(
            id: "add.heater",
            text: "Is there a portable space heater in \(room.name)?",
            subject: .new(objectId: id),
            yes: [.addObject(objectId: id, floorId: floorId, category: .heat_source,
                             center: centroid(room.polygon),
                             size_m: heaterSize_m, height_m: heaterHeight_m)],
            no: [],
            requiresYesOf: nil,
            placementHint: placeItHint
        )]
    }

    /// THE FIX for the inverted question (decisions.md 2026-09-10). It used to ask
    /// "Water heater — strapped?" and create a SECURED heater on Yes — so the person whose
    /// heater is not strapped answered No and the app recorded nothing at all, silently
    /// defeating the rule that cites FEMA on gas-line rupture.
    ///
    /// Now it is two questions: does one exist, and is it strapped. Every combination of
    /// answers lands in the model.
    private static func waterHeaterQuestions(room: Room,
                                             floorId: String,
                                             objects: [FloorObject],
                                             newObjectId: (String) -> String)
        -> [HazardHuntQuestion] {
        // An existing water heater already got its strap question above.
        guard !objects.contains(where: { $0.category == .water_heater }) else { return [] }
        guard room.type == .garage || isUtilityNamed(room) else { return [] }

        // Prefer relabeling a scanned appliance over inventing one: RoomPlan sees the box, it
        // just calls it something else.
        let candidate = objects.first { $0.source == .scan && $0.category == .appliance }
        let id = candidate?.id ?? newObjectId("waterHeater")

        let presence: HazardHuntQuestion
        if let candidate {
            presence = HazardHuntQuestion(
                id: "identify.waterHeater",
                text: "The scan found an appliance in \(room.name). Is it the water heater?",
                subject: .existing(objectId: candidate.id),
                yes: [.setObjectCategory(objectId: candidate.id, category: .water_heater)],
                no: [],
                requiresYesOf: nil,
                placementHint: nil
            )
        } else {
            presence = HazardHuntQuestion(
                id: "identify.waterHeater",
                text: "Is there a water heater in \(room.name)?",
                subject: .new(objectId: id),
                yes: [.addObject(objectId: id, floorId: floorId, category: .water_heater,
                                 center: centroid(room.polygon),
                                 size_m: waterHeaterSize_m, height_m: waterHeaterHeight_m)],
                no: [],
                requiresYesOf: nil,
                placementHint: placeItHint
            )
        }

        let strapped = HazardHuntQuestion(
            id: "strap.waterHeater",
            text: "Is it strapped to the wall studs, top and bottom?",
            subject: .existing(objectId: id),
            yes: [.setObjectSecured(objectId: id, secured: true)],
            no: [.setObjectSecured(objectId: id, secured: false)],
            requiresYesOf: presence.id,
            placementHint: nil
        )
        return [presence, strapped]
    }

    /// Rooms a water heater actually lives in. RoomPlan has no label for these, so they arrive
    /// as `other` with whatever name the user typed — matching the name is the only signal
    /// there is, and asking every `other` room would be noise.
    static func isUtilityNamed(_ room: Room) -> Bool {
        let name = room.name.lowercased()
        return ["utility", "basement", "boiler", "mechanical", "furnace", "laundry"]
            .contains { name.contains($0) }
    }

    // MARK: Placement

    /// First side of `target` where a `size` footprint fits inside the room, tried in a fixed
    /// order so the same home always produces the same placement.
    static func placeBeside(_ target: FloorObject, size: [Double],
                           inside polygon: Polygon) -> Point? {
        guard size.count == 2, polygon.count >= 3 else { return nil }
        let gap = 0.05
        let dx = target.size_m[0] / 2 + size[0] / 2 + gap
        let dy = target.size_m[1] / 2 + size[1] / 2 + gap
        let candidates = [
            Point(x: target.center.x + dx, y: target.center.y),
            Point(x: target.center.x - dx, y: target.center.y),
            Point(x: target.center.x, y: target.center.y + dy),
            Point(x: target.center.x, y: target.center.y - dy),
        ]
        return candidates.first { Geometry.contains(polygon, $0) }
    }

    static func centroid(_ polygon: Polygon) -> Point {
        guard !polygon.isEmpty else { return Point(x: 0, y: 0) }
        let sumX = polygon.map(\.x).reduce(0, +)
        let sumY = polygon.map(\.y).reduce(0, +)
        return Point(x: sumX / Double(polygon.count), y: sumY / Double(polygon.count))
    }
}
