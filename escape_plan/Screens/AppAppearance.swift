//  AppAppearance.swift
//  Screens — UIKit appearance for the chrome SwiftUI does not expose: navigation bars, lists,
//  segmented controls. Part of the Linear revamp (2026-09-25); colours come from `Theme`.

import SwiftUI
import UIKit

enum AppAppearance {
    @MainActor
    static func install() {
        let canvas = Theme.canvasComponents.uiColor
        let text = Theme.textComponents.uiColor

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = canvas
        nav.shadowColor = .clear
        nav.titleTextAttributes = [
            .foregroundColor: text,
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: text,
            .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
        ]
        let scrollEdge = nav.copy()
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge

        // Grouped lists and forms: canvas page, card rows.
        UITableView.appearance().backgroundColor = canvas
        UICollectionView.appearance().backgroundColor = canvas

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = Theme.hoverComponents.uiColor
        segmented.backgroundColor = Theme.cardComponents.uiColor
        segmented.setTitleTextAttributes([.foregroundColor: text], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: Theme.supportingComponents.uiColor], for: .normal)
    }
}
