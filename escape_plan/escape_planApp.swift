//
//  escape_planApp.swift
//  escape_plan
//
//  Created by Manogna Bhargav on 7/10/26.
//

import SwiftUI

// TODO(integration): S1.3 points the app at the renderer demo so the dollhouse can be run and
// screenshotted. S0.3 replaces this with the real tab shell (and deletes the stock Core Data
// template's PersistenceController / ContentView, which this no longer references).
@main
struct escape_planApp: App {
    var body: some Scene {
        WindowGroup {
            DollhouseDemoView()
        }
    }
}
