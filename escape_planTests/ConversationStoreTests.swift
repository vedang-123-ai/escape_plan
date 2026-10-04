//  ConversationStoreTests.swift
//  escape_planTests
//
//  S3.3's conversation persistence beyond the basic round-trip already covered in
//  ChatRequestEncodingTests: relaunch survival (the store half of the "survives backgrounding"
//  acceptance), the append-and-resave pattern AssistantScreen uses after every message, and the
//  ChatError messages the screen shows when /chat fails. S11.45 (AUD-033, AUD-049): one file per
//  home, the move of the old single file, unreadable files kept aside rather than overwritten,
//  hostile ids refused, save failures thrown, and a deleted home taking its thread with it. All
//  against a temp directory per test.

import XCTest
@testable import escape_plan

final class ConversationStoreTests: XCTestCase {

    private var directory: URL!
    private var store: ConversationStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationStoreTests-\(UUID().uuidString)")
        store = try ConversationStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeThread(homeID: String = "home-1") -> ConversationDocument {
        ConversationDocument(
            homeID: homeID,
            messages: [
                AssistantMessage(role: .user, content: "Is my smoke alarm coverage okay?"),
                AssistantMessage(role: .assistant,
                                 content: "Add one on floor 2 [cite: nfpa-alarms].",
                                 citations: ["nfpa-alarms"]),
            ])
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    // MARK: - One conversation per home (AUD-033)

    /// The bug: one file for every home, so chatting about B overwrote A's thread.
    func testAThreadAboutAnotherHomeDoesNotOverwriteThisOne() throws {
        let threadA = makeThread(homeID: "home-a")
        try store.save(threadA)
        var threadB = ConversationDocument(homeID: "home-b")
        threadB.messages.append(AssistantMessage(role: .user, content: "One question about B"))
        try store.save(threadB)

        XCTAssertEqual(try store.load(forHomeID: "home-a"), threadA, "A's thread must survive chatting about B")
        XCTAssertEqual(try store.load(forHomeID: "home-b"), threadB)
        XCTAssertEqual(try files(), ["home-a.json", "home-b.json"])
    }

    func testAHomeWithNoThreadAndNoHomeAtAllLoadAsNil() throws {
        try store.save(makeThread(homeID: "home-a"))
        XCTAssertNil(try store.load(forHomeID: "home-b"))
        XCTAssertNil(try store.load(forHomeID: nil))
    }

    func testNewChatClearsOnlyThatHome() throws {
        try store.save(makeThread(homeID: "home-a"))
        try store.save(makeThread(homeID: "home-b"))
        try store.clear(homeID: "home-a")
        XCTAssertNil(try store.load(forHomeID: "home-a"))
        XCTAssertNotNil(try store.load(forHomeID: "home-b"))
        XCTAssertNoThrow(try store.clear(homeID: "home-a"), "clearing an empty conversation is a no-op")
    }

    // MARK: - Relaunch / backgrounding survival

    func testThreadSurvivesRelaunchExactly() throws {
        let thread = makeThread()
        try store.save(thread)

        // A brand-new store over the same directory is the unit-level relaunch: nothing
        // shared with the first instance but the file it wrote on backgrounding.
        let relaunched = try ConversationStore(directory: directory)
        let loaded = try XCTUnwrap(try relaunched.load(forHomeID: "home-1"))
        XCTAssertEqual(loaded, thread)
        XCTAssertEqual(loaded.messages.map(\.id), thread.messages.map(\.id),
                       "message identity must survive, or SwiftUI list state scrambles on relaunch")
        XCTAssertEqual(loaded.messages.last?.citations, ["nfpa-alarms"],
                       "citation chips must come back after relaunch")
    }

    func testIncrementalResavesAccumulateTheWholeThread() throws {
        var document = ConversationDocument(homeID: "home-1")
        for turn in 0..<5 {
            document.messages.append(AssistantMessage(role: .user, content: "Question \(turn)"))
            try store.save(document)
            document.messages.append(AssistantMessage(role: .assistant, content: "Answer \(turn)"))
            try store.save(document)
        }

        let loaded = try XCTUnwrap(try store.load(forHomeID: "home-1"))
        XCTAssertEqual(loaded.messages.count, 10)
        XCTAssertEqual(loaded.messages.map(\.content).prefix(2), ["Question 0", "Answer 0"],
                       "order must be preserved across every resave")
    }

    func testAssistantMessageRoundTripKeepsIdentityAndCitations() throws {
        let message = AssistantMessage(role: .assistant,
                                       content: "Close doors behind you [cite: nfpa-escape-planning].",
                                       citations: ["nfpa-escape-planning"])
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AssistantMessage.self, from: data)
        XCTAssertEqual(decoded, message, "persisted messages keep id + citations (unlike wireMessage)")
    }

    // MARK: - Unreadable files are kept aside, never overwritten

    func testACorruptThreadIsKeptAsideNotReplacedByTheNextSave() throws {
        let corrupt = Data("{ this is not JSON".utf8)
        try corrupt.write(to: try store.fileURL(for: "home-1"))

        XCTAssertThrowsError(try store.load(forHomeID: "home-1")) { error in
            guard let unreadable = error as? UnreadableConversation else {
                return XCTFail("expected UnreadableConversation, got \(error)")
            }
            XCTAssertEqual(try? Data(contentsOf: unreadable.keptAt), corrupt,
                           "the unreadable bytes must be kept exactly, not lost")
            XCTAssertTrue(unreadable.keptAt.lastPathComponent.hasPrefix("home-1.unreadable-"))
        }
        XCTAssertNil(try store.load(forHomeID: "home-1"), "after setting aside, the home starts fresh")

        let thread = makeThread()
        try store.save(thread)
        XCTAssertEqual(try store.load(forHomeID: "home-1"), thread)
        XCTAssertEqual(try files().count, 2, "the fresh thread and the kept-aside copy, side by side")
    }

    /// A file named for one home but recording another is not resumed as this home's thread.
    func testAFileWhoseRecordedHomeDisagreesWithItsNameIsKeptAside() throws {
        let wrong = makeThread(homeID: "home-b")
        let encoder = JSONEncoder()
        try encoder.encode(wrong).write(to: try store.fileURL(for: "home-a"))
        XCTAssertThrowsError(try store.load(forHomeID: "home-a")) {
            XCTAssertTrue($0 is UnreadableConversation, "\($0)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.fileURL(for: "home-a").path))
    }

    // MARK: - Hostile ids (S11.41's HomeID rule)

    func testAHostileHomeIDCannotNameAFileOutsideTheFolder() throws {
        let outside = directory.deletingLastPathComponent()
            .appendingPathComponent("escaped-\(UUID().uuidString).json")
        let hostile = "../" + outside.deletingPathExtension().lastPathComponent

        XCTAssertThrowsError(try store.fileURL(for: hostile)) { XCTAssertTrue($0 is InvalidHomeID) }
        XCTAssertThrowsError(try store.save(makeThread(homeID: hostile))) { XCTAssertTrue($0 is InvalidHomeID) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path), "nothing was written outside")
        XCTAssertNil(try store.load(forHomeID: hostile))
        XCTAssertThrowsError(try store.clear(homeID: hostile))
        XCTAssertEqual(try files(), [])
    }

    // MARK: - Save failures are thrown, not swallowed (AUD-049)

    func testASaveThatCannotBeWrittenThrows() throws {
        // A thread with no home has nowhere to go.
        XCTAssertThrowsError(try store.save(ConversationDocument(homeID: nil, messages: [])))
        // The folder vanished out from under the store: the write fails, and says so.
        try FileManager.default.removeItem(at: directory)
        XCTAssertThrowsError(try store.save(makeThread()),
                             "a failed write must reach the screen, which shows it")
    }

    // MARK: - Moving the old single file (first launch of S11.45)

    private func writeLegacy(_ data: Data) throws { try data.write(to: store.legacyFileURL) }

    func testTheOldSingleFileMovesToItsHome() throws {
        let thread = makeThread(homeID: "home-a")
        try writeLegacy(try JSONEncoder().encode(thread))

        XCTAssertEqual(try store.migrateLegacyConversation(), .moved(homeID: "home-a"))
        XCTAssertEqual(try store.load(forHomeID: "home-a"), thread, "never lose the existing thread")
        XCTAssertEqual(try files(), ["home-a.json"])
        XCTAssertEqual(try store.migrateLegacyConversation(), .nothingToMigrate, "runs once")
    }

    func testAnOldFileThatCannotBeGivenToAHomeIsKeptAsideNeverDeleted() throws {
        let unmatchable: [(String, Data)] = [
            ("no home recorded", try JSONEncoder().encode(ConversationDocument(homeID: nil, messages: makeThread().messages))),
            ("hostile id", try JSONEncoder().encode(makeThread(homeID: "../../etc"))),
            ("corrupt", Data("{ nope".utf8)),
        ]
        for (label, data) in unmatchable {
            try writeLegacy(data)
            guard case .keptAside(let aside) = try store.migrateLegacyConversation() else {
                XCTFail("\(label): expected keptAside"); continue
            }
            XCTAssertEqual(try Data(contentsOf: aside), data, "\(label): bytes kept exactly")
            XCTAssertEqual(aside.deletingLastPathComponent().standardizedFileURL.path,
                           directory.standardizedFileURL.path, "\(label): kept inside the folder")
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyFileURL.path), label)
        }
        XCTAssertEqual(try files().filter { $0.hasPrefix("conversation.unmigrated-") }.count, 3)
    }

    func testAnOldFileDoesNotOverwriteAThreadItsHomeAlreadyHas() throws {
        let current = makeThread(homeID: "home-a")
        try store.save(current)
        let old = ConversationDocument(homeID: "home-a",
                                       messages: [AssistantMessage(role: .user, content: "older")])
        try writeLegacy(try JSONEncoder().encode(old))

        guard case .keptAside = try store.migrateLegacyConversation() else {
            return XCTFail("expected keptAside")
        }
        XCTAssertEqual(try store.load(forHomeID: "home-a"), current)
    }

    // MARK: - Deleting a home deletes its thread (S11.21's delete path)

    func testDeleteConversationRemovesTheThreadAndItsKeptAsideCopiesOnly() throws {
        try store.save(makeThread(homeID: "home"))
        try store.save(makeThread(homeID: "home-1"))
        try Data("{".utf8).write(to: try store.fileURL(for: "home-1"))
        _ = try? store.load(forHomeID: "home-1")             // kept aside as home-1.unreadable-…
        try store.save(makeThread(homeID: "home-1"))

        try store.deleteConversation(homeID: "home-1")
        XCTAssertEqual(try files(), ["home.json"], "`home` shares a prefix with `home-1` and must stay")
    }

    @MainActor
    func testDeletingAHomeDeletesItsConversationAndDuplicatingDoesNotCopyIt() throws {
        let homes = directory.appendingPathComponent("Homes", isDirectory: true)
        let docStore = try HomeDocumentStore(directory: homes)
        let library = HomeLibrary(store: docStore)
        let conversations = try ConversationStore(directory: directory.appendingPathComponent("Assistant"))
        library.conversations = conversations

        let homeID = try docStore.save(model: FixtureLoader.load(.bungalow)).id
        try conversations.save(makeThread(homeID: homeID))

        let copyID = try XCTUnwrap(library.duplicate(homeID: homeID))
        XCTAssertNil(try conversations.load(forHomeID: copyID), "a duplicate starts with no chat")

        XCTAssertTrue(library.delete(homeID: homeID))
        XCTAssertNil(library.loadError)
        XCTAssertNil(try conversations.load(forHomeID: homeID), "a deleted home's chat goes with it")
    }

    // MARK: - Reviewer findings (S11.45): a file that cannot be READ is left exactly where it is

    /// A read failure is not a corrupt file: it is rethrown as-is (the screen then blocks saving
    /// for that home) and the file is not renamed, because it may read fine next time.
    func testAThreadThatCannotBeReadIsLeftInPlaceAndNotCalledUnreadable() throws {
        let path = try store.fileURL(for: "home-1")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)  // read fails
        XCTAssertThrowsError(try store.load(forHomeID: "home-1")) {
            XCTAssertFalse($0 is UnreadableConversation, "a read failure must not be reported as set aside")
        }
        XCTAssertEqual(try files(), ["home-1.json"], "nothing was moved or deleted")
    }

    func testAnOldFileThatCannotBeReadStaysWhereItIs() throws {
        try FileManager.default.createDirectory(at: store.legacyFileURL, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.migrateLegacyConversation())
        XCTAssertEqual(try files(), ["conversation.json"], "a read failure must not divert the old chat")
    }

    /// A home literally called `conversation` would share the old single file's name.
    func testTheLegacyFileNameIsNotAHomesFileName() throws {
        XCTAssertThrowsError(try store.fileURL(for: "conversation")) { XCTAssertTrue($0 is InvalidHomeID) }
        XCTAssertNil(try store.load(forHomeID: "conversation"))
    }

    @MainActor
    func testADeletedHomesThreadGoesEvenWhenItsTombstoneFails() throws {
        let docStore = try HomeDocumentStore(directory: directory.appendingPathComponent("Homes", isDirectory: true))
        let library = HomeLibrary(store: docStore)
        let conversations = try ConversationStore(directory: directory.appendingPathComponent("Assistant"))
        library.conversations = conversations
        let observer = FailingDeletionObserver()
        library.deletionObserver = observer

        let homeID = try docStore.save(model: FixtureLoader.load(.bungalow)).id
        try conversations.save(makeThread(homeID: homeID))

        XCTAssertTrue(library.delete(homeID: homeID))
        XCTAssertNotNil(library.loadError, "the tombstone failure is still reported")
        XCTAssertNil(try conversations.load(forHomeID: homeID), "and the thread is gone anyway")
    }

    // MARK: - ChatError → user-facing message mapping

    /// Audit 2026-09-25: the chat client had its own copy of every failure message, which had
    /// drifted from `BackendFailure` (a 502 told the user "the server's AI isn't configured
    /// yet" where every other screen said an operator must act). Chat errors now bridge into
    /// the shared classifier, so the assistant says exactly what the rest of the app says.
    func testChatErrorsReadExactlyAsTheSharedClassifierSaysForTheAssistant() {
        let cases: [(ChatError, Int)] = [
            (.unauthorized, 401),
            (.aiUnavailable(statusCode: 502), 502),
            (.aiUnavailable(statusCode: 503), 503),
            // A 422 WITH a detail is deliberately not here any more: S11.37 shows the server's own
            // sentence (BackendFailureTests.chatUnprocessableKeepsDetail). Without one it is generic.
            (.unexpectedStatus(statusCode: 422, detail: nil), 422),
            (.unexpectedStatus(statusCode: 413, detail: "Request body too large."), 413),
            (.unexpectedStatus(statusCode: 429, detail: nil), 429),
        ]
        for (error, status) in cases {
            let direct = BackendFailure(APIClientError.unexpectedResponse(statusCode: status),
                                        while: .assistant)
            XCTAssertEqual(BackendFailure(error, while: .assistant), direct, "HTTP \(status)")
            XCTAssertEqual(error.errorDescription, direct.message, "HTTP \(status)")
        }
    }

    func testA502FromChatIsNotRetryableAndSaysRoutesStillWork() {
        let failure = BackendFailure(ChatError.aiUnavailable(statusCode: 502), while: .assistant)
        XCTAssertEqual(failure.kind, .aiUnavailable)
        XCTAssertFalse(failure.isRetryable, "a Retry button cannot fix an operator problem")
        XCTAssertTrue(failure.message.contains("escape routes still work"), failure.message)
    }

    /// The backend's AI cost guard answers 429; that is "busy, wait a moment", not an error.
    func testA429FromChatReadsAsBusyAndOffersRetry() {
        let failure = BackendFailure(ChatError.unexpectedStatus(statusCode: 429, detail: nil),
                                     while: .assistant)
        XCTAssertEqual(failure.kind, .serverBusy)
        XCTAssertTrue(failure.isRetryable)
    }
}

private final class FailingDeletionObserver: HomeDeletionObserving {
    struct Refused: Error {}
    func homeWasDeletedLocally(homeID: String) throws { throw Refused() }
}
