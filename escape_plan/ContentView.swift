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

    /// Documents could not be opened this launch; `store` is a temporary stand-in.
    private let storageUnavailable: Bool

    /// `store` is the one created at launch (`escape_planApp`), not a second instance: two
    /// stores over one directory, each built with a `try!`, was the old arrangement.
    init(store: HomeDocumentStore, storageUnavailable: Bool = false) {
        let library = HomeLibrary(store: store)
        _library = StateObject(wrappedValue: library)
        _readiness = State(wrappedValue: ReadinessStore(library: library))
        self.storageUnavailable = storageUnavailable
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if storageUnavailable { storageBanner }
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
            // A deletion is remembered as a tombstone: it stops the next sync downloading the home
            // straight back, and an owned one sends `DELETE /homes/{id}` (docs/decisions.md 2026-09-24).
            library.deletionObserver = syncRepository
            readiness.ensureActiveHome()
            // Start waking the free-tier Render instance NOW, alongside the cached score, rather
            // than on the first real request (a cold start is tens of seconds). Fire and
            // forget: the answer does not matter and nothing waits on it.
            Task { _ = try? await apiClient.checkHealth() }
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
            OnboardingFlowView(documentStore: library.store) {
                // On the temporary fallback store the interview's answers vanish on quit, so do not
                // spend the flag on them: the next launch with real storage asks again. Same reason
                // escape_planApp skips starter seeding on the fallback (S11.18 review).
                if !storageUnavailable { onboardingCompleted = true }
                showingOnboarding = false
                // The interview just wrote profiles and tenure (and maybe a demo home) to disk.
                // Re-read so the Home tab shows them now, not after a relaunch.
                library.refresh()
                readiness.ensureActiveHome()
                Task { await readiness.load(api: apiClient) }
            }
        }
    }
}

// MARK: - Storage banner

private extension ContentView {
    /// Shown on every tab for the whole session when the Documents directory could not be
    /// opened. Deliberately not dismissible: every edit made in this state is lost on quit.
    var storageBanner: some View {
        Label("Storage unavailable. Changes won't be saved.", systemImage: "externaldrive.badge.exclamationmark")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.pagePadding)
            .padding(.vertical, 10)
            .background(Theme.card)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// The House tab follows the active home and any "show me where" request from another tab.
/// A new request (or a switched home) rebuilds the editor, which is how it refocuses.
private struct HouseTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(ReadinessStore.self) private var readiness
    @Environment(AppRouter.self) private var router
    @EnvironmentObject private var library: HomeLibrary
    /// The home a blank editor (empty library) created with its first edit. That save makes the
    /// home appear, which must not change the `.id` below: a rebuild would throw away the editor
    /// and the undo of the edit that created it (S11.21, AUD-021).
    @State private var homeCreatedByBlankEditor: String?
    /// Bumped when the library empties again, so the next blank editor is a fresh one.
    @State private var blankGeneration = 0

    var body: some View {
        // Only a request for the ACTIVE home counts. Preferring any request over the active home
        // stranded this tab on the old home after a switch on the Home tab (audit 2026-09-25).
        let request = HouseRequest.honoured(router.houseRequest, activeHomeID: readiness.activeHomeID)
        let homeID = readiness.activeHomeID ?? library.homes.first?.id
        let wasBlank = homeID == nil
        let key = homeID == nil || homeID == homeCreatedByBlankEditor ? "new\(blankGeneration)" : homeID!
        HouseScreen(homeID: homeID, library: library, initialFocusItemID: request?.focusItemID) {
            library.refresh()
            if wasBlank, homeCreatedByBlankEditor == nil {
                homeCreatedByBlankEditor = library.homes.first?.id
                readiness.ensureActiveHome()
            }
            Task { await readiness.load(api: apiClient) }
        }
        .id("\(key)-\(request?.token.uuidString ?? "")")
        .onChange(of: homeID) { old, new in
            if new == nil, old != nil {
                homeCreatedByBlankEditor = nil
                blankGeneration += 1
            }
        }
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    ContentView(store: HomeDocumentStore.launchStore().store)
        .environment(APIClient())
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
        .previewSyncEnvironment()
}
#endif
