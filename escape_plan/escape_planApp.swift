//  escape_planApp.swift
//  escape_plan
//
//  S0.3: replaced the stock Core Data template wholesale. Persistence is local JSON documents
//  via FileManager (S2.4), not Core Data — this entry point just owns the shared APIClient.

import SwiftUI

@main
struct escape_planApp: App {
    @State private var apiClient = APIClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(apiClient)
        }
    }
}
