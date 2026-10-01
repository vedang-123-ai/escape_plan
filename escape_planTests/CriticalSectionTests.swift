import Testing
import Foundation
@testable import escape_plan

@Suite("Critical Section")
struct CriticalSectionTests {
    @Test("A high-severity finding from the API flows through to the decoded checklist")
    func highSeverityFindingIsPreserved() async throws {
        let json = """
        {
          "home_id": "home-1",
          "home_name": "Twostory",
          "score": 75,
          "sub_scores": {"fire": 75, "earthquake": 75, "severe_weather": 75},
          "components": [],
          "checklist": [
            {
              "id": "engine.no_viable_route.r1",
              "category": "agent_finding",
              "title": "Blocked",
              "detail": "Blocked",
              "done": false,
              "scoring": false,
              "severity": "high"
            }
          ]
        }
        """
        
        // Its own stub, not `OfflineStubProtocol`: that one keeps its responder in a static that
        // `OfflineIntegrityTests` (serialized only against itself) sets to `.notConnectedToInternet`
        // while this suite runs in parallel, which failed this test with -1009 (S11.8).
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScoreJSONStub.self]
        ScoreJSONStub.body = json.data(using: .utf8)!
        let session = URLSession(configuration: config)
        let client = APIClient(session: session)
        
        let home = try FixtureLoader.load(.twostory)
        let breakdown = try await client.score(home: home, checklistState: [:])
        
        // Assert the wired-up path produces the high severity item for the UI to consume
        let highSeverityItems = breakdown.checklist.filter { $0.severity == .high }
        #expect(highSeverityItems.count == 1, "The high severity item must decode correctly through the real APIClient path")
        #expect(highSeverityItems.first?.id == "engine.no_viable_route.r1")
    }
}

/// Answers every request with 200 and `body`. Used by this suite alone; set before the request.
private final class ScoreJSONStub: URLProtocol {
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
