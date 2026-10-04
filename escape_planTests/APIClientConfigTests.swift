import XCTest
@testable import escape_plan

/// AUD-009: token precedence, migration, reset and server-address validation.
/// All values are fake; the bundled token is injected, never read from the config file.
final class APIClientConfigTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "APIClientConfigTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeClient(launch: [String: Any] = [:], bundled: String? = "bundled-v1") -> APIClient {
        APIClient(defaults: defaults, launchArguments: launch, bundledToken: { bundled })
    }

    func testFreshInstallUsesBundledToken() {
        let client = makeClient()
        XCTAssertEqual(client.bearerToken, "bundled-v1")
        XCTAssertFalse(client.isTokenOverridden)
    }

    func testOverrideSurvivesRelaunchAndBeatsBundled() {
        makeClient().overrideBearerToken("mine")
        let relaunched = makeClient(bundled: "bundled-v2")
        XCTAssertEqual(relaunched.bearerToken, "mine")
        XCTAssertTrue(relaunched.isTokenOverridden)
    }

    func testPlainAssignmentIsNotPersisted() {
        makeClient().bearerToken = "transient"
        XCTAssertEqual(makeClient().bearerToken, "bundled-v1")
    }

    /// A token stored by the old build (no flag) must yield to a rotated bundled token.
    func testMigrationStoredTokenWithoutFlagIsIgnored() {
        defaults.set("old-token", forKey: "APIClient.bearerToken")
        let client = makeClient(bundled: "rotated")
        XCTAssertEqual(client.bearerToken, "rotated")
        XCTAssertFalse(client.isTokenOverridden)
    }

    func testLaunchArgumentBeatsOverrideAndIsNotPersisted() {
        makeClient().overrideBearerToken("mine")
        let ui = makeClient(launch: ["APIClient.bearerToken": "ui-test"])
        XCTAssertEqual(ui.bearerToken, "ui-test")
        XCTAssertFalse(ui.isTokenOverridden)
        XCTAssertEqual(makeClient().bearerToken, "mine")
    }

    func testResetRestoresBundledTokenAndDeployedURL() {
        let client = makeClient()
        client.overrideBearerToken("mine")
        client.baseURL = URL(string: "https://example.test")!
        client.resetToDefaults()
        XCTAssertEqual(client.bearerToken, "bundled-v1")
        XCTAssertEqual(client.baseURL, APIClient.deployedDefaultBaseURL)
        XCTAssertFalse(client.isTokenOverridden)
        let relaunched = makeClient()
        XCTAssertEqual(relaunched.bearerToken, "bundled-v1")
        XCTAssertEqual(relaunched.baseURL, APIClient.deployedDefaultBaseURL)
    }

    func testMissingBundledTokenIsEmpty() {
        XCTAssertEqual(makeClient(bundled: nil).bearerToken, "")
    }

    func testClearOverrideReturnsToBundled() {
        let client = makeClient()
        client.overrideBearerToken("mine")
        client.clearBearerTokenOverride()
        XCTAssertEqual(client.bearerToken, "bundled-v1")
        XCTAssertEqual(makeClient().bearerToken, "bundled-v1")
    }

    func testFlagWithoutStoredTokenIsNotAnOverride() {
        defaults.set(true, forKey: "APIClient.bearerTokenOverridden")
        XCTAssertEqual(makeClient().bearerToken, "bundled-v1")
    }

    // MARK: Stored address and Release behaviour

    func testStoredInvalidOrInsecureURLFallsBackToDeployed() {
        for bad in ["api.example.com", "http://evil.example.com", "", "https://"] {
            defaults.set(bad, forKey: "APIClient.baseURL")
            XCTAssertEqual(APIClient.currentBaseURL(defaults: defaults, honorOverrides: true),
                           APIClient.deployedDefaultBaseURL, bad)
        }
    }

    func testStoredValidURLHonouredWhenOverridesAllowed() {
        defaults.set("https://staging.example.test", forKey: "APIClient.baseURL")
        XCTAssertEqual(APIClient.currentBaseURL(defaults: defaults, honorOverrides: true).host, "staging.example.test")
    }

    /// Release: a leftover override, a stored address and launch arguments are all ignored.
    func testReleaseIgnoresEveryOverride() {
        makeClient().overrideBearerToken("mine")
        defaults.set("https://staging.example.test", forKey: "APIClient.baseURL")
        let client = APIClient(defaults: defaults,
                               launchArguments: ["APIClient.bearerToken": "ui", "APIClient.baseURL": "http://evil.test"],
                               bundledToken: { "bundled-v1" },
                               honorOverrides: false)
        XCTAssertEqual(client.bearerToken, "bundled-v1")
        XCTAssertEqual(client.baseURL, APIClient.deployedDefaultBaseURL)
        XCTAssertFalse(client.isTokenOverridden)
    }

    // MARK: URL validation

    private func url(_ text: String, local: Bool = false) -> URL? {
        if case .success(let u) = APIClient.validatedBaseURL(text, allowLocalHTTP: local) { return u }
        return nil
    }

    func testAcceptsHTTPSWithHost() {
        XCTAssertEqual(url("  https://escape-plan-backend.onrender.com ")?.host, "escape-plan-backend.onrender.com")
    }

    func testRefusesPlaceholderAndSchemeless() {
        XCTAssertNil(url("api.example.com"))
        XCTAssertNil(url("example.com:8000"))
        XCTAssertNil(url(""))
        XCTAssertNil(url("https://"))
        XCTAssertNil(url("ftp://example.com"))
        XCTAssertNil(url("https://user:pw@example.com"))
    }

    func testPlainHTTPRefusedExceptLocalhostInDebug() {
        XCTAssertNil(url("http://example.com", local: true))
        XCTAssertNil(url("http://localhost:8000", local: false))
        XCTAssertEqual(url("http://localhost:8000", local: true)?.port, 8000)
        XCTAssertNotNil(url("http://127.0.0.1:8000", local: true))
    }
}
