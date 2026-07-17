//  StoreInvariantTests.swift — S2.1's headline acceptance criterion:
//
//      "no sequence of store actions can produce an invalid model"
//
//  Example-based tests can only show that the drags we thought of are safe. This file attacks
//  the store with long randomised sequences of every action — including deliberately hostile
//  ones (corners flung across the room, walls dragged through each other, rooms deleted out
//  from under profiles) — and asserts after EVERY step that:
//
//    1. the model is valid (the store's whole reason to exist), and
//    2. a rejected action changed absolutely nothing.
//
//  The RNG is seeded and hand-rolled, so a failure is reproducible from its seed forever and
//  the suite can never go flaky. `swift test` and `xcodebuild test` run the identical sequence.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

/// SplitMix64 — deterministic across platforms and Swift versions, unlike SystemRandomNumberGenerator.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class StoreInvariantTests: XCTestCase {

    /// The proof, run against every fixture and a from-scratch home, across several seeds.
    func testNoActionSequenceCanProduceAnInvalidModel() throws {
        var seeds: [(String, HomeModel)] = [("new_home", HomeModelStore.newHome())]
        for name in Fixtures.validNames {
            seeds.append((name, try Fixtures.load(name)))
        }

        for (label, model) in seeds {
            for seed in UInt64(1)...UInt64(8) {
                try runFuzz(label: label, model: model, seed: seed, steps: 300)
            }
        }
    }

    /// Same attack with snapping ON. Snapping moves the point the user asked for, so it is a
    /// second chance to produce degenerate geometry (two corners snapped onto one another) —
    /// it must not be able to either.
    func testSnappingCannotProduceAnInvalidModel() throws {
        for seed in UInt64(1)...UInt64(8) {
            try runFuzz(label: "bungalow+snap", model: try Fixtures.load("bungalow"),
                        seed: seed, steps: 300, snap: .default)
        }
    }

    /// Tiny geometry, aggressive grid: maximises the chance of a snap collapsing a wall to
    /// zero length, which is the most plausible way to sneak a degenerate polygon through.
    func testCoarseGridOnSmallRoomsStillCannotBreakTheModel() throws {
        let coarse = SnapSettings(gridEnabled: true, gridSizeM: 1.0,
                                  axisEnabled: true, axisToleranceM: 0.5,
                                  wallSnapEnabled: true, wallSnapRadiusM: 1.5)
        for seed in UInt64(1)...UInt64(6) {
            try runFuzz(label: "coarse", model: HomeModelStore.newHome(),
                        seed: seed, steps: 250, snap: coarse, dragRange: 3.0)
        }
    }

    // MARK: - The fuzz loop

    private func runFuzz(label: String, model: HomeModel, seed: UInt64, steps: Int,
                         snap: SnapSettings = .disabled, dragRange: Double = 12.0) throws {
        var rng = SeededGenerator(seed: seed)
        var counter = 0
        let store = try HomeModelStore(
            model: model,
            snapSettings: snap,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            makeId: {
                counter += 1
                return "fuzz_\(seed)_\(counter)"
            })

        var applied = 0
        var rejected = 0

        for step in 0..<steps {
            let action = randomAction(store: store, rng: &rng, dragRange: dragRange)
            let before = store.model
            let outcome = store.dispatch(action)
            let context = "\(label) seed=\(seed) step=\(step) action=\(action)"

            switch outcome {
            case .applied:
                applied += 1
                let issues = EditorValidation.validate(store.model)
                XCTAssertTrue(issues.isEmpty,
                              "INVALID MODEL after an accepted action — \(context)\n"
                              + issues.map(\.description).joined(separator: "\n"))
                if !issues.isEmpty { return }  // stop at the first breach; the rest is noise
            case .rejected:
                rejected += 1
                XCTAssertEqual(store.model, before,
                               "a rejected action mutated the model — \(context)")
                if store.model != before { return }
            }

            // The store's own bookkeeping must stay coherent too, not just the document.
            XCTAssertNotNil(store.model.floor(store.activeFloorId),
                            "activeFloorId points at a deleted floor — \(context)")
            if let roomId = store.selection.roomId {
                XCTAssertNotNil(store.model.locateRoom(roomId),
                                "selection points at a deleted room — \(context)")
            }
        }

        // A fuzz run where everything bounced would prove nothing. Assert the attack actually
        // landed hits, so this test can't quietly rot into a no-op.
        XCTAssertGreaterThan(applied, steps / 10,
                             "\(label) seed=\(seed): only \(applied)/\(steps) actions applied — "
                             + "the fuzzer is not exercising the store")
        XCTAssertGreaterThan(rejected, 0,
                             "\(label) seed=\(seed): nothing was rejected — the hostile actions "
                             + "are not hostile enough to prove the gate works")
        XCTAssertModelValid(store.model, "\(label) seed=\(seed): final model")
    }

    // MARK: - Action generation

    private func randomAction(store: HomeModelStore, rng: inout SeededGenerator,
                              dragRange: Double) -> EditAction {
        let model = store.model
        let floor = store.activeFloor
        let room = floor.rooms.randomElement(using: &rng)!
        let anyRoom = model.floors.randomElement(using: &rng)!.rooms.randomElement(using: &rng)!

        func coord() -> Double {
            Double.random(in: -dragRange...dragRange, using: &rng)
        }
        func point() -> Point2D { Point2D(coord(), coord()) }

        // Weighted so the geometry-mangling drags dominate — they're where invalid states come
        // from. Structural actions are sprinkled in to keep the shape of the model moving.
        switch Int.random(in: 0..<100, using: &rng) {
        case 0..<28:
            // Fling a corner anywhere, including straight through the opposite wall.
            return .dragVertex(roomId: room.id,
                               vertexIndex: Int.random(in: 0..<(room.polygon.count + 1), using: &rng),
                               to: point())
        case 28..<48:
            // Nudge a corner slightly: the near-degenerate cases the wild flings mostly miss.
            let i = Int.random(in: 0..<room.polygon.count, using: &rng)
            let jitter = Point2D(Double.random(in: -0.3...0.3, using: &rng),
                                 Double.random(in: -0.3...0.3, using: &rng))
            return .dragVertex(roomId: room.id, vertexIndex: i,
                               to: Geometry.add(room.polygon[i], jitter))
        case 48..<62:
            return .dragEdge(roomId: room.id,
                             edgeIndex: Int.random(in: 0..<(room.polygon.count + 1), using: &rng),
                             by: point())
        case 62..<72:
            return .dragRoom(roomId: anyRoom.id, by: point())
        case 72..<78:
            return .addRoom(floorId: floor.id, origin: point(),
                            widthM: Double.random(in: 0.5...6, using: &rng),
                            heightM: Double.random(in: 0.5...6, using: &rng),
                            type: RoomType.allCases.randomElement(using: &rng)!,
                            name: "Fuzz Room")
        case 78..<84:
            return .deleteRoom(roomId: anyRoom.id)
        case 84..<88:
            return .addFloor(relativeTo: model.floors.randomElement(using: &rng)!.id,
                             above: Bool.random(using: &rng))
        case 88..<92:
            return .deleteFloor(floorId: model.floors.randomElement(using: &rng)!.id)
        case 92..<95:
            // Empty names must bounce — that's a rejection path worth hitting.
            return .renameRoom(roomId: anyRoom.id,
                               name: Bool.random(using: &rng) ? "" : "Renamed")
        case 95..<97:
            return .setRoomType(roomId: anyRoom.id,
                                type: RoomType.allCases.randomElement(using: &rng)!)
        case 97..<99:
            return .setFloorHeight(floorId: floor.id,
                                   heightM: Double.random(in: -1...4, using: &rng))
        default:
            return .setHomeName(Bool.random(using: &rng) ? "" : "Fuzzed Home")
        }
    }

    // MARK: - Targeted attacks
    //
    // The specific ways a user CAN break a footprint, called out by name so a regression here
    // reads as "you broke bowtie protection", not "seed 5 step 212 failed".

    func testDraggingACornerAcrossTheDiagonalIsRejected() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        // r_living is [0,0],[5,0],[5,4],[0,4]. Vertex 0 -> [5,4] is vertex 2: a bowtie.
        XCTAssertRejected(store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 0,
                                                     to: Point2D(5, 4))))
    }

    func testCollapsingAWallToZeroLengthIsRejected() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        // Drop vertex 0 exactly onto vertex 1: edge 0 vanishes.
        XCTAssertRejected(store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 0,
                                                     to: Point2D(5, 0))))
    }

    func testFlatteningARoomToALineIsRejected() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        XCTAssertApplied(store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 3,
                                                    to: Point2D(0, 0.5))))
        // Now push the last off-line corner onto the line: zero area.
        XCTAssertRejected(store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 2,
                                                     to: Point2D(5, 0))))
    }

    func testInvertingWindingIsRejected() throws {
        // Dragging a corner far enough past the opposite wall would flip the polygon clockwise.
        // The schema demands CCW, so this must bounce rather than silently reorient — silently
        // reorienting would renumber every edge and teleport the room's doors.
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        var model = store.model
        model.floors[0].rooms[0].polygon.reverse()
        XCTAssertRejected(store.replaceModel(model))
    }

    func testAWallDraggedThroughTheOppositeWallIsRejected() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        // Push the top wall of r_living (edge 2) down past the bottom wall.
        XCTAssertRejected(store.dispatch(.dragEdge(roomId: "r_living", edgeIndex: 2,
                                                   by: Point2D(0, -6))))
    }

    // MARK: - Openings survive everything

    func testNoDragEverOrphansAnOpening() throws {
        // Openings are the fragile part: they reference (room, edge_index, t). A drag that
        // changed vertex count or winding would leave them pointing at the wrong wall. This
        // asserts the store never lets that happen.
        var rng = SeededGenerator(seed: 99)
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"), snap: .default)
        let openingIds = Set(store.activeFloor.openings.map(\.id))
        let refsBefore = store.activeFloor.openings.map { ($0.id, $0.wallSegment) }

        for _ in 0..<400 {
            let room = store.activeFloor.rooms.randomElement(using: &rng)!
            let i = Int.random(in: 0..<room.polygon.count, using: &rng)
            store.dispatch(.dragVertex(roomId: room.id, vertexIndex: i,
                                       to: Point2D(Double.random(in: -2...12, using: &rng),
                                                   Double.random(in: -2...12, using: &rng))))
            store.dispatch(.dragEdge(roomId: room.id, edgeIndex: i,
                                     by: Point2D(Double.random(in: -1...1, using: &rng),
                                                 Double.random(in: -1...1, using: &rng))))
        }

        XCTAssertEqual(Set(store.activeFloor.openings.map(\.id)), openingIds,
                       "no drag should ever add or drop an opening")
        for (id, seg) in refsBefore {
            let now = store.activeFloor.openings.first { $0.id == id }!
            XCTAssertEqual(now.wallSegment, seg,
                           "opening \(id)'s parametric ref was rewritten — it should never need to be")
        }
        XCTAssertModelValid(store.model)
    }

    // MARK: - Determinism

    func testTheSameSeedProducesTheSameModel() throws {
        // If this ever fails, every other fuzz failure stops being reproducible.
        func run() throws -> HomeModel {
            var rng = SeededGenerator(seed: 4242)
            var counter = 0
            let store = try HomeModelStore(
                model: try Fixtures.load("bungalow"),
                snapSettings: .default,
                now: { Date(timeIntervalSince1970: 1_700_000_000) },
                makeId: { counter += 1; return "d_\(counter)" })
            for _ in 0..<200 {
                store.dispatch(randomAction(store: store, rng: &rng, dragRange: 12))
            }
            return store.model
        }
        XCTAssertEqual(try run(), try run())
    }
}
