//  HomeLibraryHermeticTests.swift
//  S11.50: a library built in a test never reaches the real `Documents/Assistant`.
//
//  `HomeLibrary.conversations` used to default to `try? ConversationStore()`, the real folder, so
//  every test that built a library created that folder in the test host and every test that
//  deleted a home deleted `<id>.json` from it. The app now passes the real store in
//  (`ContentView`); without one, a library has none.

import Foundation
import XCTest

@testable import escape_plan

@MainActor
final class HomeLibraryHermeticTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeLibraryHermeticTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testALibraryWithNoConversationStoreHasNone() throws {
        let library = HomeLibrary(store: try HomeDocumentStore(directory: directory.appendingPathComponent("Homes")))
        XCTAssertNil(library.conversations, "no default: a test must never get the real Documents/Assistant")
    }

    func testTheStorePassedInIsTheOneDeletesReach() throws {
        let docStore = try HomeDocumentStore(directory: directory.appendingPathComponent("Homes"))
        let conversations = try ConversationStore(directory: directory.appendingPathComponent("Assistant"))
        let library = HomeLibrary(store: docStore, conversations: conversations)
        XCTAssertEqual(library.conversations?.directory, conversations.directory)

        let homeID = try docStore.save(model: FixtureLoader.load(.bungalow)).id
        try conversations.save(ConversationDocument(homeID: homeID,
                                                    messages: [AssistantMessage(role: .user, content: "hi")]))
        XCTAssertTrue(library.delete(homeID: homeID))
        XCTAssertNil(try conversations.load(forHomeID: homeID), "the thread in the passed-in folder went")
    }
}
