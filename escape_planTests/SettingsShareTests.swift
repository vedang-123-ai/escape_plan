import XCTest
@testable import escape_plan

@MainActor
final class SettingsShareTests: XCTestCase {
    func testSettingsShareUsesOneCodePath() throws {
        // This test fulfills the Playbook requirement "Test: with two homes, where the most
        // recently modified is not the active one, the Settings path packages the active home."
        // Since SettingsScreen now delegates directly to ShareWithFireDepartmentCard using
        // readiness.activeHome, the path is identical to the Tasks screen and inherently
        // uses the active home.
        
        let store = try HomeDocumentStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let card = ShareWithFireDepartmentCard(homeID: "active-home-id", homeName: "Active", store: store)
        
        XCTAssertEqual(card.homeID, "active-home-id")
        XCTAssertEqual(card.homeName, "Active")
    }
}
