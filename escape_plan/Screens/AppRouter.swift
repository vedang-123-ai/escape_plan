//  AppRouter.swift
//  Screens — which tab is showing, and the cross-tab requests that move the user between them
//  (Linear revamp, 2026-09-25). A task in the Tasks tab can land the user in the House tab on
//  the right object, or back on Home to re-scan, without either screen knowing about the other.

import Observation
import SwiftUI

enum AppTab: Hashable {
    case home, tasks, house, assistant, settings
}

/// Something Home should do once it is showing: flows it owns (the camera, the room picker).
enum HomeIntent: Equatable {
    case scan
    case recheckRoom
}

/// Open the House tab on `homeID`, optionally swinging the camera to a checklist item's object.
/// `token` changes on every request, so asking for the same item twice still refocuses.
struct HouseRequest: Equatable {
    let homeID: String?
    let focusItemID: String?
    let token = UUID()

    /// The request the House tab should act on: `request` only while it is for the active
    /// home. A request is about one home; once another is active it is stale, whether or not
    /// anyone remembered to clear it.
    static func honoured(_ request: HouseRequest?, activeHomeID: String?) -> HouseRequest? {
        guard let request, request.homeID == activeHomeID else { return nil }
        return request
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    private(set) var houseRequest: HouseRequest?
    var homeIntent: HomeIntent?

    func openHouse(homeID: String?, focusItemID: String? = nil) {
        houseRequest = HouseRequest(homeID: homeID, focusItemID: focusItemID)
        selectedTab = .house
    }

    /// Forget the last "show me in the house" request. Called whenever the active home changes:
    /// a request is for one home, and a stale one used to pin the House tab to the old home
    /// after switching on the Home tab (audit 2026-09-25). `HouseTab` also ignores a request
    /// for a home that is no longer active, so a missed call cannot strand it either.
    func clearHouseRequest() {
        houseRequest = nil
    }

    func go(home intent: HomeIntent) {
        homeIntent = intent
        selectedTab = .home
    }
}
