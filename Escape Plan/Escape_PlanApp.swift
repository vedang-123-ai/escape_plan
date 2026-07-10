//
//  Escape_PlanApp.swift
//  Escape Plan
//
//  Created by Manogna Bhargav on 7/10/26.
//

import SwiftUI
import CoreData

@main
struct Escape_PlanApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
