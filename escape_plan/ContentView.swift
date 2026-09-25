//  ContentView.swift
//  escape_plan
//
//  Tab shell: Home / Tasks / House / Assistant / Settings (Linear revamp, 2026-09-25: the Beta
//  tab is gone — switching homes lives in Home's top bar — and the checklist got its own tab),
//  plus the S4.1 onboarding flow on
//  first launch — seed a demo home from the twostory fixture, review low-confidence items,
//  then land on routes + inspection. Finishing (or skipping) marks onboarding done; the flow
//  never reappears on its own after that.

import SwiftUI

struct ContentView: View {
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var showingOnboarding = false

    @Environment(APIClient.self) private var apiClient
    @Environment(SyncManager.self) private var sync
    @Environment(HomeDocumentSyncRepository.self) private var syncRepository

    /// One library, one readiness store, one router — shared by every tab, so Home, Tasks and
    /// House always agree on which home is active and what its checklist says.
    @StateObject private var library: HomeLibrary
    @State private var readiness: ReadinessStore
    @State private var router = AppRouter()

    init() {
        let library = HomeLibrary(store: try! HomeDocumentStore())
        _library = StateObject(wrappedValue: library)
        _readiness = State(wrappedValue: ReadinessStore(library: library))
    }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeScreen()
                .tabItem { Label("Home", systemImage: "house") }
                .accessibilityHint("How prepared your home is, and what to do next.")
                .tag(AppTab.home)

            TasksScreen()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .badge(readiness.urgentOpen.count)
                .accessibilityHint("Your readiness checklist.")
                .tag(AppTab.tasks)

            HouseTab()
                .tabItem { Label("House", systemImage: "cube") }
                .accessibilityHint("The 3D model of your home, with escape routes.")
                .tag(AppTab.house)

            AssistantScreen()
                .tabItem { Label("Assistant", systemImage: "sparkles") }
                .accessibilityHint("Ask questions about your escape plan.")
                .tag(AppTab.assistant)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .accessibilityHint("Server connection and app information.")
                .tag(AppTab.settings)
        }
        .environmentObject(library)
        .environment(readiness)
        .environment(router)
        // The tab bar is the one control SwiftUI renders without a click of its own.
        .onChange(of: router.selectedTab) { Haptics.selection() }
        .task {
            // Sync writes pulled homes through this library, and reads its `editor` to know
            // which home is open so it never overwrites one mid-edit.
            syncRepository.library = library
            // The backend has no delete endpoint, so a deletion has to be remembered here or the
            // next sync downloads the home straight back.
            library.deletionObserver = syncRepository
            readiness.ensureActiveHome()
            await readiness.load(api: apiClient)
        }
        .onChange(of: sync.status) { _, status in
            // A home from another device is on disk but not in the library until something
            // re-reads the directory; and the active home may be one that just changed.
            guard case .synced(_, let outcome) = status,
                  outcome.pulled > 0 || !outcome.conflicts.isEmpty else { return }
            library.refresh()
            readiness.ensureActiveHome()
            Task { await readiness.load(api: apiClient) }
        }
        .onAppear {
            if !onboardingCompleted { showingOnboarding = true }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingFlowView {
                onboardingCompleted = true
                showingOnboarding = false
            }
        }
    }
}

/// The House tab follows the active home and any "show me where" request from another tab.
/// A new request (or a switched home) rebuilds the editor, which is how it refocuses.
private struct HouseTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(ReadinessStore.self) private var readiness
    @Environment(AppRouter.self) private var router
    @EnvironmentObject private var library: HomeLibrary

    var body: some View {
        let request = router.houseRequest
        let homeID = request?.homeID ?? readiness.activeHomeID ?? library.homes.first?.id
        HouseScreen(homeID: homeID, library: library, initialFocusItemID: request?.focusItemID) {
            library.refresh()
            Task { await readiness.load(api: apiClient) }
        }
        .id("\(homeID ?? "new")-\(request?.token.uuidString ?? "")")
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    ContentView()
        .environment(APIClient())
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
        .previewSyncEnvironment()
}
#endif
