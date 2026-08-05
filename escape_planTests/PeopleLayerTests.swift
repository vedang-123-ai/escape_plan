//  PeopleLayerTests.swift
//  The household figures standing in the dollhouse.
//
//  A profile's entire justification is that it changes the route. Until this layer existed a
//  profile was a row in a picker with no presence in the model, so switching profiles moved a
//  line on screen with nothing to attribute the change to.

import SceneKit
import Testing

@testable import escape_plan

@MainActor
@Suite("PeopleLayer")
struct PeopleLayerTests {

    @Test("One figure per profile, each named so a tap can resolve it")
    func oneFigurePerProfile() throws {
        let home = try FixtureLoader.load(.twostory)
        #expect(!home.profiles.isEmpty, "the fixture must have profiles for this to mean anything")

        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)
        let issues = layer.show(profiles: home.profiles, home: home, highlighted: nil)

        #expect(issues.isEmpty, "every fixture profile's bedroom should resolve")
        var found: [String] = []
        built.dollhouse.scene.rootNode.enumerateChildNodes { node, _ in
            if let name = node.name, name.hasPrefix("person:") {
                found.append(String(name.dropFirst("person:".count)))
            }
        }
        #expect(Set(found) == Set(home.profiles.map(\.id)))
    }

    @Test("A figure stands in its own bedroom, on that bedroom's floor")
    func standsInTheRightRoom() throws {
        let home = try FixtureLoader.load(.twostory)
        let profile = try #require(home.profiles.first)
        let (floorID, room) = try #require(home.locateRoom(profile.bedroom_room_id))

        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)
        layer.show(profiles: [profile], home: home, highlighted: nil)

        var figure: SCNNode?
        built.dollhouse.scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "person:\(profile.id)" { figure = node }
        }
        let node = try #require(figure)

        let centroid = Geometry.centroid(room.polygon)
        #expect(abs(Double(node.position.x) - centroid.x) < 1e-4)
        // Plan +y maps to scene −z.
        #expect(abs(Double(node.position.z) + centroid.y) < 1e-4)

        let expectedY = DollhouseGeometry.floorBaseHeights(of: home)[floorID] ?? 0
        #expect(abs(Double(node.position.y) - expectedY) < 1e-4,
                "an upstairs bedroom's figure must stand on the upstairs slab, not the ground")
    }

    @Test("Clearing removes every figure and leaves the built scene alone")
    func clearRemovesOnlyWhatItAdded() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)

        var before = 0
        built.dollhouse.scene.rootNode.enumerateChildNodes { _, _ in before += 1 }

        let layer = PeopleLayer(dollhouse: built.dollhouse)
        layer.show(profiles: home.profiles, home: home, highlighted: nil)
        layer.clear()

        var after = 0
        built.dollhouse.scene.rootNode.enumerateChildNodes { _, _ in after += 1 }
        #expect(after == before, "clear() must not strip anything the builder made")
    }

    @Test("Re-showing replaces figures rather than stacking them")
    func showIsIdempotent() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)

        layer.show(profiles: home.profiles, home: home, highlighted: nil)
        layer.show(profiles: home.profiles, home: home,
                   highlighted: home.profiles.first?.id)

        var count = 0
        built.dollhouse.scene.rootNode.enumerateChildNodes { node, _ in
            if node.name?.hasPrefix("person:") == true { count += 1 }
        }
        #expect(count == home.profiles.count,
                "every profile-change redraw would otherwise leave its predecessor behind")
    }

    @Test("A missing bedroom is reported, not silently dropped")
    func danglingBedroomIsSurfaced() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)

        let ghost = Profile(id: "p-ghost", name: "Nobody", bedroom_room_id: "room-does-not-exist")
        let issues = layer.show(profiles: [ghost], home: home, highlighted: nil)

        #expect(issues.count == 1)
        #expect(issues[0].contains("Nobody"))
    }

    @Test("A tap anywhere on a figure resolves to its profile")
    func hitTestWalksUpToTheContainer() {
        let node = PersonFixture.node(id: "p1", name: "Ana", highlighted: false)
        let child = try? #require(node.childNodes.first)
        #expect(PeopleLayer.profileID(forHit: node) == "p1")
        if let child {
            #expect(PeopleLayer.profileID(forHit: child) == "p1",
                    "the body, head and name pill must all resolve to the same person")
        }
        #expect(PeopleLayer.profileID(forHit: SCNNode()) == nil)
    }
}
