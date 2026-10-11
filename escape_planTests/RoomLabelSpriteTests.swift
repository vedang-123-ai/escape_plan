import UIKit
import XCTest
@testable import escape_plan

final class RoomLabelSpriteTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RoomLabelSprite.clearCache()
    }

    override func tearDown() {
        RoomLabelSprite.clearCache()
        super.tearDown()
    }

    func testIdenticalRoomNamesHitCache() {
        let first = RoomLabelSprite.make(name: "Bedroom")
        let second = RoomLabelSprite.make(name: "Bedroom")

        XCTAssertTrue(first.image === second.image,
                      "Subsequent calls with identical room name and scale must return the cached UIImage")
        XCTAssertEqual(first.aspect, second.aspect, accuracy: 1e-6)
    }

    func testDifferentRoomNamesProduceDifferentSprites() {
        let bedroom = RoomLabelSprite.make(name: "Bedroom")
        let kitchen = RoomLabelSprite.make(name: "Kitchen")

        XCTAssertFalse(bedroom.image === kitchen.image,
                       "Different room names must produce distinct Sprite instances")
    }

    func testDifferentScalesProduceDifferentSprites() {
        let scale2 = RoomLabelSprite.make(name: "Bathroom", scale: 2.0)
        let scale3 = RoomLabelSprite.make(name: "Bathroom", scale: 3.0)

        XCTAssertFalse(scale2.image === scale3.image,
                       "Different render scales must produce distinct Sprite instances")
    }

    func testClearCachePurgesExistingSprites() {
        let before = RoomLabelSprite.make(name: "Living Room")
        RoomLabelSprite.clearCache()
        let after = RoomLabelSprite.make(name: "Living Room")

        XCTAssertFalse(before.image === after.image,
                       "Calling clearCache must purge cached Sprite instances so a new sprite is created")
    }

    func testLongRoomNamesAreTruncatedAndCached() {
        let longName = "A Very Long Room Name That Exceeds Limit"
        let first = RoomLabelSprite.make(name: longName)
        let second = RoomLabelSprite.make(name: longName)

        XCTAssertTrue(first.image === second.image,
                      "Long names truncated with ellipsis should still be cached")
    }

    func testSpriteCachingPerformance() {
        // Measure 100 cache hits vs initial creation
        let name = "Master Bedroom"
        _ = RoomLabelSprite.make(name: name)

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            _ = RoomLabelSprite.make(name: name)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // 100 cache lookups should take well under 10ms (typically <0.1ms)
        XCTAssertLessThan(elapsed, 0.05, "100 cached lookups should be instantaneous")
    }
}
