import XCTest
@testable import escape_plan

final class ResponderSnapshotTests: XCTestCase {
    func testAnonymityOfSnapshot() throws {
        let parent = Profile(id: "p1", name: "Alice", tags: [ProfileTag.vision_impaired], bedroom_room_id: "bed1")
        let child = Profile(id: "p2", name: "Bob", tags: [ProfileTag.mobility_limited], bedroom_room_id: "bed1")
        
        let floor = Floor(id: "f1", level: 1, name: "First Floor", height_m: 3, rooms: [
            Room(id: "bed1", name: "Master Bedroom", type: .bedroom, polygon: [], source: .manual)
        ])
        
        let home = HomeModel(
            schema_version: "1",
            home_id: "h1",
            name: "Test Home",
            floors: [floor],
            stairs: [],
            profiles: [parent, child],
            meta: Meta(created: Date(), modified: Date(), last_scanned: Date()),
            household: nil
        )
        
        let plan = EscapePlanDocument(
            home: home,
            plan: nil,
            scoreResponse: nil,
            isResponderSnapshot: true
        )
        
        // Test JSON extraction
        let json = ResponderSnapshotExtractor.extract(from: plan)
        let jsonEncoder = JSONEncoder()
        let jsonData = try jsonEncoder.encode(json)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        XCTAssertFalse(jsonString.contains("Alice"), "JSON must not contain the name Alice")
        XCTAssertFalse(jsonString.contains("Bob"), "JSON must not contain the name Bob")
        XCTAssertTrue(jsonString.contains("count\":2"), "JSON must have count of 2 for the room")
        
        // Test PDF generation
        let pdfOutput = EscapePlanPDF.render(plan)
        guard let pdfString = String(data: pdfOutput.data, encoding: .utf8) ?? String(data: pdfOutput.data, encoding: .ascii) else {
            return
        }
        XCTAssertFalse(pdfString.contains("Alice"), "PDF must not contain the name Alice")
        XCTAssertFalse(pdfString.contains("Bob"), "PDF must not contain the name Bob")
    }
}

extension ResponderSnapshotTests {
    func testTwostoryFixtureAnonymity() throws {
        var home = try FixtureLoader.load(.twostory)
        
        // Give someone a name so we can assert it is stripped
        home.profiles[0].name = "Grandpa Joe"
        home.profiles[0].tags.append(.mobility_limited)
        home.meta.last_scanned = nil // Force stale
        
        let plan = EscapePlanDocument(
            home: home,
            plan: nil,
            scoreResponse: nil,
            isResponderSnapshot: true
        )
        
        let json = ResponderSnapshotExtractor.extract(from: plan)
        
        // Stale test
        XCTAssertTrue(json.isStale)
        
        let jsonEncoder = JSONEncoder()
        let jsonData = try jsonEncoder.encode(json)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        XCTAssertFalse(jsonString.contains("Grandpa Joe"), "JSON must not contain the name")
        // The twostory fixture might have multiple profiles, but at least 1 is mobility_limited now.
        XCTAssertTrue(json.vulnerableOccupants.count > 0, "Should have at least 1 vulnerable occupant count")
        
        let pdfOutput = EscapePlanPDF.render(plan)
        XCTAssertTrue(pdfOutput.data.count > 0, "PDF renders without error and produces data")
    }
}
