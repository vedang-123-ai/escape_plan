//  GeometryTests.swift — the polygon math the validator's guarantees rest on.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class GeometryTests: XCTestCase {

    // A unit square, counter-clockwise.
    let ccwSquare = [Point2D(0, 0), Point2D(1, 0), Point2D(1, 1), Point2D(0, 1)]

    // MARK: - Orientation & area

    func testSignedAreaSignEncodesWinding() {
        XCTAssertEqual(Geometry.signedArea(ccwSquare), 1.0, accuracy: 1e-12)
        XCTAssertEqual(Geometry.signedArea(ccwSquare.reversed()), -1.0, accuracy: 1e-12)
        XCTAssertTrue(Geometry.isCounterClockwise(ccwSquare))
        XCTAssertFalse(Geometry.isCounterClockwise(ccwSquare.reversed()))
    }

    func testDegeneratePolygonIsNeitherCCWNorSimple() {
        let collinear = [Point2D(0, 0), Point2D(1, 0), Point2D(2, 0)]
        XCTAssertEqual(Geometry.signedArea(collinear), 0, accuracy: 1e-12)
        XCTAssertFalse(Geometry.isCounterClockwise(collinear))
        XCTAssertFalse(Geometry.isValidRoomPolygon(collinear))
    }

    func testAreaIsWindingIndependent() {
        XCTAssertEqual(Geometry.area(ccwSquare), Geometry.area(ccwSquare.reversed()), accuracy: 1e-12)
    }

    // MARK: - Simplicity

    func testConvexAndConcavePolygonsAreSimple() {
        XCTAssertTrue(Geometry.isSimple(ccwSquare))

        // An L-shaped room — the concave case the editor must support.
        let lShape = [Point2D(0, 0), Point2D(4, 0), Point2D(4, 2),
                      Point2D(2, 2), Point2D(2, 4), Point2D(0, 4)]
        XCTAssertTrue(Geometry.isSimple(lShape))
        XCTAssertTrue(Geometry.isValidRoomPolygon(lShape))
    }

    func testBowtieIsNotSimple() {
        // The classic self-intersection: dragging one corner across the diagonal.
        let bowtie = [Point2D(0, 0), Point2D(1, 1), Point2D(1, 0), Point2D(0, 1)]
        XCTAssertFalse(Geometry.isSimple(bowtie))
        XCTAssertFalse(Geometry.isValidRoomPolygon(bowtie))
    }

    func testDuplicateVertexIsNotSimple() {
        let zeroLengthEdge = [Point2D(0, 0), Point2D(0, 0), Point2D(1, 0), Point2D(1, 1)]
        XCTAssertFalse(Geometry.isSimple(zeroLengthEdge))

        // Non-adjacent duplicate: pinches the polygon at a point.
        let pinched = [Point2D(0, 0), Point2D(1, 0), Point2D(0, 0), Point2D(1, 1)]
        XCTAssertFalse(Geometry.isSimple(pinched))
    }

    func testDoublingBackAlongAWallIsNotSimple() {
        // Adjacent edges sharing a vertex is legal; adjacent edges lying on top of each other
        // (a spike with zero width) is not — the polygon has no interior there.
        let spike = [Point2D(0, 0), Point2D(2, 0), Point2D(1, 0), Point2D(1, 2)]
        XCTAssertFalse(Geometry.isSimple(spike))
    }

    func testTouchingButNotCrossingIsStillNotSimple() {
        // A vertex landing exactly on a non-adjacent wall: geometrically degenerate, and
        // pydantic rejects it, so the editor must too.
        let touching = [Point2D(0, 0), Point2D(2, 0), Point2D(2, 2),
                        Point2D(1, 0), Point2D(0, 2)]
        XCTAssertFalse(Geometry.isSimple(touching))
    }

    // MARK: - Edges

    func testEdgeIndexFollowsTheSchemaConvention() {
        // Edge i runs vertex i -> vertex (i+1) mod n. Everything parametric depends on this.
        let e0 = Geometry.edge(ccwSquare, 0)
        XCTAssertEqual(e0?.a, Point2D(0, 0))
        XCTAssertEqual(e0?.b, Point2D(1, 0))

        // The closing edge wraps.
        let last = Geometry.edge(ccwSquare, 3)
        XCTAssertEqual(last?.a, Point2D(0, 1))
        XCTAssertEqual(last?.b, Point2D(0, 0))

        XCTAssertNil(Geometry.edge(ccwSquare, 4))
        XCTAssertNil(Geometry.edge(ccwSquare, -1))
    }

    func testPointOnEdgeResolvesTheTParameter() {
        XCTAssertPointEqual(Geometry.pointOnEdge(ccwSquare, edgeIndex: 0, t: 0.0)!, Point2D(0, 0))
        XCTAssertPointEqual(Geometry.pointOnEdge(ccwSquare, edgeIndex: 0, t: 0.5)!, Point2D(0.5, 0))
        XCTAssertPointEqual(Geometry.pointOnEdge(ccwSquare, edgeIndex: 0, t: 1.0)!, Point2D(1, 0))
    }

    // MARK: - Segments

    func testSegmentIntersection() {
        XCTAssertTrue(Geometry.segmentsIntersect(Point2D(0, 0), Point2D(2, 2),
                                                 Point2D(0, 2), Point2D(2, 0)))
        XCTAssertFalse(Geometry.segmentsIntersect(Point2D(0, 0), Point2D(1, 0),
                                                  Point2D(0, 1), Point2D(1, 1)))
        // Touching at an endpoint counts as intersecting.
        XCTAssertTrue(Geometry.segmentsIntersect(Point2D(0, 0), Point2D(1, 0),
                                                 Point2D(1, 0), Point2D(2, 0)))
    }

    func testCollinearOverlapDetection() {
        XCTAssertTrue(Geometry.segmentsOverlapCollinearly(Point2D(0, 0), Point2D(2, 0),
                                                          Point2D(1, 0), Point2D(3, 0)))
        // Meeting at exactly one point is not an overlap.
        XCTAssertFalse(Geometry.segmentsOverlapCollinearly(Point2D(0, 0), Point2D(1, 0),
                                                           Point2D(1, 0), Point2D(2, 0)))
        // Parallel but not collinear.
        XCTAssertFalse(Geometry.segmentsOverlapCollinearly(Point2D(0, 0), Point2D(2, 0),
                                                           Point2D(0, 1), Point2D(2, 1)))
    }

    func testClosestPointOnSegment() {
        let (p, t) = Geometry.closestPointOnSegment(Point2D(0.5, 3), Point2D(0, 0), Point2D(1, 0))
        XCTAssertPointEqual(p, Point2D(0.5, 0))
        XCTAssertEqual(t, 0.5, accuracy: 1e-12)

        // Beyond the end: clamps to the endpoint rather than projecting off the wall.
        let (q, tq) = Geometry.closestPointOnSegment(Point2D(5, 0), Point2D(0, 0), Point2D(1, 0))
        XCTAssertPointEqual(q, Point2D(1, 0))
        XCTAssertEqual(tq, 1.0, accuracy: 1e-12)
    }

    // MARK: - Containment (tap hit-testing)

    func testContains() {
        XCTAssertTrue(Geometry.contains(ccwSquare, Point2D(0.5, 0.5)))
        XCTAssertFalse(Geometry.contains(ccwSquare, Point2D(1.5, 0.5)))
        XCTAssertFalse(Geometry.contains(ccwSquare, Point2D(-0.001, 0.5)))
    }

    func testContainsHandlesConcavity() {
        let lShape = [Point2D(0, 0), Point2D(4, 0), Point2D(4, 2),
                      Point2D(2, 2), Point2D(2, 4), Point2D(0, 4)]
        XCTAssertTrue(Geometry.contains(lShape, Point2D(1, 3)))
        // The notch is outside the room even though it's inside the bounding box.
        XCTAssertFalse(Geometry.contains(lShape, Point2D(3, 3)))
    }

    // MARK: - Fixture geometry

    func testEveryFixtureRoomIsAValidRoomPolygon() throws {
        for name in Fixtures.validNames {
            let model = try Fixtures.load(name)
            for floor in model.floors {
                for room in floor.rooms {
                    XCTAssertTrue(Geometry.isValidRoomPolygon(room.polygon),
                                  "\(name)/\(room.id) is not a valid room polygon")
                }
            }
        }
    }

    func testFixtureOpeningsResolveOntoTheirHostWall() throws {
        // The parametric contract, checked against real data: every opening's t-range must
        // resolve to a point on the wall its wall_segment names.
        for name in Fixtures.validNames {
            let model = try Fixtures.load(name)
            for floor in model.floors {
                for opening in floor.openings {
                    let seg = opening.wallSegment
                    let host = try XCTUnwrap(floor.room(seg.roomId),
                                             "\(name)/\(opening.id) hosts on a missing room")
                    let edge = try XCTUnwrap(Geometry.edge(host.polygon, seg.edgeIndex),
                                             "\(name)/\(opening.id) has a bad edge_index")
                    let mid = try XCTUnwrap(Geometry.pointOnEdge(host.polygon,
                                                                 edgeIndex: seg.edgeIndex,
                                                                 t: (seg.t0 + seg.t1) / 2))
                    XCTAssertEqual(Geometry.distanceToSegment(mid, edge.a, edge.b), 0,
                                   accuracy: 1e-9,
                                   "\(name)/\(opening.id) does not sit on its host wall")
                }
            }
        }
    }
}
