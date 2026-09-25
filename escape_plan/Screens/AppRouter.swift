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

    func go(home intent: HomeIntent) {
        homeIntent = intent
        selectedTab = .home
    }
}
