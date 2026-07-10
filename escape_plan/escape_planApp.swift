//
//  escape_planApp.swift
//  escape_plan
//
//  Created by Manogna Bhargav on 7/10/26.
//

import SwiftUI
import CoreData

@main
struct escape_planApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
