# 02 SwiftUI Frontend Audit Report

**Audit Target:** Escape Plan iOS Application  
**Repository Root:** `/Users/anish/Documents/Congressional App Challenge/Escape-Plan`  
**Domain:** SwiftUI Frontend  
**Auditor:** Agent 2 (Senior Frontend / SwiftUI Engineer)  
**Date:** 2026-10-11  

---

## 1. Executive Summary

This audit evaluated the entire SwiftUI frontend architecture, UI view hierarchy, state management mechanisms (`@State`, `@Binding`, `@Observable`, `@StateObject`, `@Environment`, `@EnvironmentObject`), navigation routing, sheet and alert presentations, forms and validations, asynchronous operations, error and loading states, accessibility features (Dynamic Type, Reduce Motion, VoiceOver), and view lifecycle integrity across the Escape Plan iOS codebase.

The frontend is built for iOS 17.0+ as a dark-only application following a refined Linear-inspired aesthetic (revamped in September 2026). It integrates SwiftUI with RoomPlan UIKit representables and SceneKit 3D rendering. 

Key strengths of the implementation include:
- Strict compliance with dark-mode contrast standards (audited in unit tests via `ThemeContrastTests`).
- Exceptional accommodation of accessibility settings, notably `accessibilityReduceMotion` (degrading 3D flight paths into stepped stop-by-stop walks and suppressing particle animations) and `dynamicTypeSize` (responsive layout reflows from `HStack` to `VStack`/`FlowLayout` at accessibility sizes).
- Clear separation between client-side rendering and authoritative routing/scoring/simulation computations performed by the deterministic backend.

However, the audit identified several critical architectural and usability issues:
1. **Navigation Hierarchy Flaw (A02-01 & A02-02):** `HouseScreen` embeds its own root `NavigationStack`. When launched modally or embedded in `HouseTab`, this functions, but when pushed via `.navigationDestination` from `HomeScreen` ("Build Manually"), it creates a nested `NavigationStack` inside `HomeScreen`'s `NavigationStack`, masking back buttons and effectively trapping the user in `HouseScreen` without a dismiss or return control.
2. **Timing-Dependent Sheet Dismissal Workaround (A02-03):** Both `HomeScreen` and `TasksScreen` rely on an unmanaged, hardcoded `Task.sleep(for: .milliseconds(320))` when transitioning from `TaskDetailSheet` to `HouseScreen` to avoid sheet presentation conflicts. This race-condition-prone workaround is fragile under system animation lag or user interruption.
3. **Destructive View Identity Teardown (A02-04):** `HouseTab` applies a dynamic `.id("\(key)-\(request?.token.uuidString ?? "")")` modifier, which forcibly destroys and re-allocates the entire SceneKit scene controller, bridge, and camera rig whenever a cross-tab jump or focus request is triggered.
4. **Dead / Orphaned Auth & Sync Code (A02-05):** Since the decision to cut account gates and cloud sync on 2026-10-02, five full UI components (`AuthGateView`, `AuthSheetView`, `LoginView`, `SignupView`, `SyncStatusBadge`) remain compiled and maintained in the codebase despite being completely unreachable by users.
5. **Dangling Chat State on Context Switch (A02-06):** In `AssistantScreen`, switching the active home while a `/chat` request is in flight causes the incoming assistant reply to be dropped, but leaves the pending user message permanently saved to disk in the previous home's chat history.

---

## 2. Scope and Files Inspected

The inspection covered every SwiftUI view, screen, container, representable, and frontend support component in `escape_plan/`:

### Core App Shell & Routing
- `escape_plan/escape_planApp.swift`: Application entry point, dependency injection, fallback store banners.
- `escape_plan/RootView.swift`: Root view, legacy auth gate bypass, notification cleanup.
- `escape_plan/ContentView.swift`: Tab bar container, storage unavailable banner, `HouseTab` host.
- `escape_plan/Screens/AppRouter.swift`: Tab navigation state, cross-tab intent routing.
- `escape_plan/Screens/AppAppearance.swift`: Global UIKit appearance proxy configuration.

### Main Feature Screens
- `escape_plan/Screens/HomeScreen.swift`: Active home summary, preparedness score card, Up Next task list, Quick Actions, Manage Homes sheet.
- `escape_plan/Screens/HouseScreen.swift`: Unified 3D dollhouse editor, routes viewer, fire simulation playback, inspector docks, tour controls, toolbar.
- `escape_plan/Screens/HouseEditorSessionController+App.swift`: Bridge between app document store and session lifecycle.
- `escape_plan/Screens/ScoreScreen.swift`: Detailed preparedness breakdown, peril sub-scores, largest deduction card.
- `escape_plan/Screens/TasksScreen.swift`: Comprehensive readiness checklist, peril filter bar, urgent/todo/done groups, family plan section.
- `escape_plan/Screens/ProfilesScreen.swift`: Household member management, profile rows, deletion alerts.
- `escape_plan/Screens/ProfileEditorView.swift`: Create/edit profile sheet, needs toggles, bedroom picker.
- `escape_plan/Screens/AssistantScreen.swift`: Grounded safety assistant chat, prompt suggestions, message bubbles, citation chips.
- `escape_plan/Screens/SettingsScreen.swift`: Server address, connection test, developer toggles (DEBUG), privacy disclosures, export links.
- `escape_plan/Screens/BuildFromPlanView.swift`: Text description and photo/PDF intake sheet, async processing banners.
- `escape_plan/Screens/ConsentSheet.swift`: Explicit fire department snapshot export consent dialog.

### Onboarding & Capture Views
- `escape_plan/Onboarding/OnboardingFlowView.swift`: First-launch onboarding wizard (Welcome, Who lives here, Needs, Rent or Own).
- `escape_plan/Onboarding/OnboardingState.swift`: Onboarding view-model and commitment logic.
- `escape_plan/Onboarding/FixtureSeeder.swift`: Starter home bundle installation.
- `escape_plan/Capture/Views/ScanFlowView.swift`: LiDAR scan orchestration (Instructions, Scanning, RoomFinished, Processing, Review, Unsupported).
- `escape_plan/Capture/Views/RoomCaptureViewRepresentable.swift`: UIKit `RoomCaptureView` bridge.

### Shared UI Components, Design System & Export Views
- `escape_plan/Screens/Theme.swift`: Semantic colour palette, typography, WCAG mathematical contrast formulas.
- `escape_plan/Screens/DesignKit.swift`: `DS` constants, `dsPage`, `dsCard`, buttons (`DSPrimaryButton`, `DSSecondaryButton`), pills, badges, `FlowLayout`.
- `escape_plan/Screens/GlassControls.swift`: Floating glass pills, panels, and chips over SceneKit view.
- `escape_plan/Screens/BackendFailureBanner.swift`: Unified failure presentation, retry triggers, offline capability disclosure.
- `escape_plan/Screens/TaskComponents.swift`: Task status glyphs, chips, rows, headers, and `TaskDetailSheet`.
- `escape_plan/Screens/RouteFindingViews.swift`: Route check finding cards, hazard warnings, clear indicators.
- `escape_plan/Screens/EvacuationPeoplePanel.swift`: Evacuation journey narration cards, "Who does what" panel.
- `escape_plan/Screens/Components/LoadingTipView.swift`: Rotating cited prevention tips over loading spinners.
- `escape_plan/Screens/SyncStatusBadge.swift`: Cloud sync status icon and popover (orphaned).
- `escape_plan/Screens/SyncPreviewSupport.swift`: Environment mocking for SwiftUI previews.
- `escape_plan/Export/ExportPlanSheet.swift`: PDF printable escape plan generation sheet.
- `escape_plan/Export/ShareSheet.swift`: `UIActivityViewController` presentation wrapper.
- `escape_plan/Export/ShareWithFireDepartmentCard.swift`: First responder snapshot packaging card.
- `escape_plan/Screens/Auth/AuthGateView.swift`, `AuthSheetView.swift`, `LoginView.swift`, `SignupView.swift`, `AuthFormComponents.swift`: Authentication forms and modals (orphaned).

---

## 3. Methods and Checks Performed

1. **Source Code Static Analysis:**
   - Exhaustive line-by-line inspection of all 32 SwiftUI files in the target directories.
   - Traced state propagation across `@Observable` (`ReadinessStore`, `AppRouter`, `OnboardingState`), `@StateObject` (`HomeLibrary`), `@State`, and `@Binding`.
   - Audited view lifecycle triggers (`.task`, `.onAppear`, `.onDisappear`, `.onChange`).
   - Analyzed interaction handling under rapid taps, cancellation tokens, backgrounding, and scene phase changes.

2. **Navigation Flow & Presentation Mapping:**
   - Traced every modal sheet, full-screen cover, alert dialog, confirmation dialog, and navigation destination.
   - Evaluated view dismissal mechanisms and coordinate space references.

3. **Accessibility & Responsive Layout Review:**
   - Verified Dynamic Type adaptations (`@ScaledMetric`, `ViewThatFits`, `FlowLayout`, accessibility text truncation prevention).
   - Inspected `accessibilityReduceMotion` branches across animations, SceneKit tours, and timeline clocks.
   - Evaluated VoiceOver semantics (`accessibilityElement`, `accessibilityLabel`, `accessibilityHint`, `accessibilityAction`).

4. **Automated Test Cross-Referencing:**
   - Cross-referenced findings with automated test suites (`A11yHouseSceneTests`, `AppRouterTests`, `ThemeContrastTests`, `ReadinessStoreTests`, `S1157AccessibilityTests`, `SignedOutPathUITests`, `EntryPointUITests`).
   - Verified whether identified issues are covered or missed by automated testing.

---

## 4. Screen-by-Screen Inventory Table

| Screen / View | Primary Purpose | State Mechanism | Key Controls & Interactions | Loading / Empty / Error States | Presentation Mode | Verification Status |
|---|---|---|---|---|---|---|
| **RootView** | Root router and app initialization | `@Environment(AuthSession)` | Automatically signs out deprecated sessions and renders `ContentView`. | Storage unavailable banner propagated if disk fails. | Root View | Verified by source inspection |
| **ContentView** | Main app tab bar shell | `@StateObject(HomeLibrary)`, `@State(ReadinessStore)`, `@State(AppRouter)` | 5-tab switch (Home, Tasks, House, Assistant, Settings); fullScreenCover onboarding. | Displays non-dismissible storage fallback banner if local documents fail. | WindowGroup Root | Verified by source inspection |
| **HomeScreen** | Active home dashboard and triage | `@Environment(ReadinessStore)`, `@Environment(AppRouter)`, `@EnvironmentObject(HomeLibrary)`, local `@State` | Home picker menu, Add menu (Scan, Manual, Import), Score card button, Up Next checklist items, Drill & 3D buttons, Household row. | Skeleton scoring spinner (`LoadingTipView`), empty home CTA, AI draft review notice, scan conversion error banner. | Tab 1 (`AppTab.home`) | Verified by source inspection |
| **HouseScreen (in HouseTab)** | 3D unified editor, routes & fire simulation | `@State(EditorSession)`, `@State(UnifiedSceneController)`, `@State(EvacuationPlaybackModel)`, local holders | 3D gesture manipulation (orbit/pan/pinch), floor picker chips, tool buttons (Add Room, Openings, Stairs, Objects), Ignite room picker, Scrubber slider, Play/Pause/Replay, Route step list. | Scene loading spinner, load error unavailable view, deleted home unavailable view, AI draft confirmation banner, route fetch banner, simulation error banner. | Tab 3 (`AppTab.house`) | Verified by source inspection |
| **TasksScreen** | Full readiness checklist & family plan | `@Environment(ReadinessStore)`, `@Environment(AppRouter)`, local filter & expansion `@State` | Peril filter pills, Urgent/Todo/Done accordion headers, item toggle circles, row taps (detail sheet), Outside meeting point row, Share snapshot button. | Loading tasks tip spinner, No home empty state, AI draft review notice, Clock skew warning banner, backend failure banner. | Tab 2 (`AppTab.tasks`) | Verified by source inspection |
| **TaskDetailSheet** | Single checklist item deep-dive | Passed item constants, `@Environment(\.dismiss)` | Primary action button (Show in house / Run drill / Toggle), secondary drill practice confirmation button, Done button. | N/A (Static presentation over item model). | Sheet from `HomeScreen` or `TasksScreen` | Verified by source inspection |
| **ScoreScreen** | Preparedness score breakdown | `@Environment(ReadinessStore)`, `@Environment(APIClient)` | Largest deduction disclosure toggle ("Why"), peril sub-score cards, Try Again retry button. | Loading tip view, Scoring progress bar, Content unavailable view (no home / local load error), backend failure banner. | Navigation push from `HomeScreen` | Verified by source inspection |
| **ProfilesScreen** | Household occupant management | `@State(HomeModelStore)`, `@Environment(ReadinessStore)`, local `@State` | Add Profile toolbar button, occupant row tap (edit sheet), swipe-to-delete, delete confirmation dialog. | Loading spinner, No profiles empty state CTA, load error view, autosave failure banner. | Navigation push from `HomeScreen` | Verified by source inspection |
| **ProfileEditorView** | Occupant details editor | Local `@State` (name, tags, bedroom), `@Environment(\.dismiss)` | Name textfield, 6 need toggles, Bedroom navigation link picker, Save / Cancel toolbar buttons. | Validation alert on invalid store dispatch, Save disabled on empty name. | Sheet from `ProfilesScreen` | Verified by source inspection |
| **AssistantScreen** | FEMA/NFPA grounded chat | Local `@State(messages, draft)`, `@Environment(ReadinessStore)`, `@Environment(APIClient)` | Question input text field, Send button, Prompt suggestion pills, New chat button, citation chips. | Empty state with radial glow, typing dots indicator, backend failure banner, chat persistence warning line. | Tab 4 (`AppTab.assistant`) | Verified by source inspection |
| **SettingsScreen** | Server connection & privacy disclosure | `@Environment(APIClient)`, `@Environment(AuthSession)`, local `@State` | Test connection button, Server URL/token fields (DEBUG), Developer reset buttons (DEBUG), Share snapshot card, How routes are computed sheet link. | Health badge (Unknown, Testing spinner, Connected, Failed). | Tab 5 (`AppTab.settings`) | Verified by source inspection |
| **HowRoutesAreComputedSheet** | Architectural division of labor explanation | `@Environment(\.dismiss)` | Done dismissal button. | N/A (Static descriptive content). | Sheet from `SettingsScreen` | Verified by source inspection |
| **BuildFromPlanView** | AI floor plan intake | `@State(preparedImage, text)`, `@Environment(APIClient)`, `@EnvironmentObject(HomeLibrary)` | Description text editor, Photo picker, PDF document importer, Remove attachment button, Build draft home button, Cancel button. | Building progress view ("can take a minute"), preparing attachment indicator, attachment error text, backend failure banner. | Sheet from `HomeScreen` | Verified by source inspection |
| **ManageHomesSheet** | Home inventory management | `@EnvironmentObject(HomeLibrary)`, local `@State(pendingDelete)` | Home row selection (switch), swipe Duplicate, swipe Delete, Delete confirmation alert dialog, Done button. | Content unavailable view ("No homes on this iPhone"), failure banner. | Sheet from `HomeScreen` | Verified by source inspection |
| **OnboardingFlowView** | First launch onboarding wizard | `@State(OnboardingState)` | Step 0: Get started / I'll do this later; Step 1: Add person, name/age fields; Step 2: Need toggles; Step 3: Rent/Own cards, Finish button. | Seed error label, commit error label. | Full-screen cover from `ContentView` | Verified by source inspection |
| **ScanFlowView** | RoomPlan LiDAR capture flow | `@State(RoomCaptureController)` | Start scanning button, Done with this room button, Scan another room button, Finish scan button, Continue to editor button, Scan again button, Cancel button. | Scan unsupported view (no LiDAR), processing spinner, failure view with retry button. | Full-screen cover from `HomeScreen` | Verified by source inspection |
| **ExportPlanSheet** | Printable plan PDF generator | `@State(meetingPoint, preview, isGenerating)` | Outside meeting place text field, Create PDF button, Done toolbar button. | Loading tip view ("Reading your home…"), generation spinner, creation failure alert, unavailable view. | Sheet from `TasksScreen` | Verified by source inspection |
| **ConsentSheet** | First responder snapshot export consent | Local `@State(includeOccupantNames)`, `@Environment(\.dismiss)` | Include occupant names toggle, Share primary button, Cancel button. | N/A (Static informational and consent text). | Sheet from `ShareWithFireDepartmentCard` | Verified by source inspection |
| **AuthGateView** | Account creation / backup intake (Legacy) | Local `@State(path)` | Create account button, I already have an account button, Continue without account button, privacy disclosure toggle. | N/A | **Orphaned (unreachable)** | Verified by source inspection |
| **LoginView** | Account authentication form (Legacy) | Local `@State(email, password)`, `@FocusState` | Email field, Password field, Sign in button, Switch to sign up button. | Failure message banner, working spinner. | **Orphaned (unreachable)** | Verified by source inspection |
| **SignupView** | Account registration form (Legacy) | Local `@State(email, password)`, `@FocusState` | Email field, Password field, Create account button, Switch to sign in button. | Failure message banner, working spinner. | **Orphaned (unreachable)** | Verified by source inspection |
| **AuthSheetView** | Account sign-in sheet from settings (Legacy) | Local `@State(path)`, `@Environment(\.dismiss)` | Embeds `LoginView` and `SignupView`, Cancel toolbar button. | Inherits from child forms. | **Orphaned (unreachable)** | Verified by source inspection |
| **SyncStatusBadge** | Cloud sync status indicator & trigger (Legacy) | `@Environment(SyncManager)`, local `@State` | Sync status icon button, Popover detail card. | Pulsing sync animation, sync problem / sign in again banners. | **Orphaned (unreachable)** | Verified by source inspection |

---

## 5. Findings (with Evidence)

### ## [HIGH] A02-01: Nested NavigationStack Hierarchy When Navigating to HouseScreen from HomeScreen
**Domain:** Navigation & View Hierarchy  
**Location:** `escape_plan/Screens/HomeScreen.swift:96-101`, `escape_plan/Screens/HouseScreen.swift:218-222`  
**Observed behavior:** When a user chooses "Build Manually" or "Build it myself" from `HomeScreen`, `HouseScreen` is presented via `.navigationDestination(isPresented: $showingNewHome)`. However, `HouseScreen` wraps its own entire layout in an unconditional `NavigationStack`. This produces a nested `NavigationStack` inside `HomeScreen`'s `NavigationStack`.  
**Evidence:**  
In [HomeScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HomeScreen.swift#L33-L101):
```swift
33: NavigationStack {
34:     ScrollView { ... }
...
96:     .navigationDestination(isPresented: $showingNewHome) {
97:         HouseScreen(homeID: nil, library: library) {
98:             library.refresh()
99:             if let id = library.homes.first?.id { switchHome(to: id) }
100:         }
101:     }
```
In [HouseScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L217-L222):
```swift
217: var body: some View {
218:     NavigationStack {
219:         content
220:             .navigationTitle(session?.store.model.name ?? "House")
221:             .toolbar { toolbarContent }
222:     }
```
**Expected behavior:** `HouseScreen` should only declare a `NavigationStack` when it acts as the root of a tab (`HouseTab`), or `HomeScreen` should present `HouseScreen` modally (`.fullScreenCover` / `.sheet`), or `HouseScreen` should not embed its own `NavigationStack` if it is pushed onto an existing stack.  
**Root cause:** `HouseScreen` was redesigned to be a unified screen that acts as both a standalone tab root and a pushed destination, but retained an internal root `NavigationStack`.  
**Impact:** On iOS 17 and 18, nested `NavigationStack`s trigger layout glitches, duplicate navigation bars, incorrect safe-area insets, and erratic toolbar button rendering.  
**Recommended improvement:** Remove the root `NavigationStack` from `HouseScreen` and let its host (`HouseTab` or modal presentation) own the navigation container.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.  

---

### ## [HIGH] A02-02: Missing Navigation Return Affordance Traps User in Pushed HouseScreen
**Domain:** Navigation & Lifecycle  
**Location:** `escape_plan/Screens/HouseScreen.swift:2184-2207`, `HomeScreen.swift:59`, `HomeScreen.swift:96-101`  
**Observed behavior:** When `HouseScreen` is pushed from `HomeScreen` via "Build Manually", there is no "Back" or "Done" button to return to `HomeScreen`. Because `HomeScreen` sets `.toolbar(.hidden, for: .navigationBar)` on line 59 and `HouseScreen` overrides leading navigation bar items with Undo/Redo buttons (`ToolbarItem(placement: .navigationBarLeading)`), the standard SwiftUI navigation back button is not visible or functional. `dismiss()` is only invoked internally if the home file is deleted externally.  
**Evidence:**  
In [HomeScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HomeScreen.swift#L59):
```swift
59: .toolbar(.hidden, for: .navigationBar)
```
In [HouseScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L2184-L2207):
```swift
2184: @ToolbarContentBuilder
2185: private var toolbarContent: some ToolbarContent {
2186:     ToolbarItem(placement: .navigationBarLeading) {
2187:         Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
...
2197:     ToolbarItem(placement: .navigationBarLeading) {
2198:         Button { redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
```
In [HouseScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L350-L354):
```swift
350: .onChange(of: session.wasDeletedExternally) { _, deleted in
351:     guard deleted else { return }
352:     closeForDeletedHome(session, controller: sessionController)
353:     dismiss()
354: }
```
**Expected behavior:** Pushed screens must provide an explicit back button or restore the navigation bar back affordance so users can return to the dashboard.  
**Root cause:** `HouseScreen` was optimized as an embedded tab root (`HouseTab`) and toolbar items were placed in `.navigationBarLeading` without accounting for pushed navigation from `HomeScreen`.  
**Impact:** A user who taps "Build Manually" or "Build it myself" cannot return to the Home tab via navigation controls. They must tap another tab in the tab bar (or are completely trapped if they enter immersive fullscreen mode, which hides the tab bar as well).  
**Recommended improvement:** When `homeID == nil` or when opened outside `HouseTab`, add a prominent "Cancel" or "Done" toolbar button that calls `dismiss()`, and place Undo/Redo in a dedicated editor control bar or secondary toolbar group.  
**Dependencies:** A02-01.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.  

---

### ## [MEDIUM] A02-03: Arbitrary Sleep Delay (320ms) in Sheet Dismissal and Cross-Tab Navigation
**Domain:** Async Operations & Navigation  
**Location:** `escape_plan/Screens/HomeScreen.swift:515-522`, `escape_plan/Screens/TasksScreen.swift:368-372`  
**Observed behavior:** When a user taps a primary action in `TaskDetailSheet` ("Show me in the house" or "Run a drill"), the sheet is dismissed and an unmanaged `Task` sleeps for an arbitrary `320ms` before switching tabs or setting the focus item ID.  
**Evidence:**  
In [HomeScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HomeScreen.swift#L514-L523):
```swift
514: detailItem = nil
515: Task { @MainActor in
516:     try? await Task.sleep(for: .milliseconds(320))
517:     if destination == .drill {
518:         router.openFireDrill(homeID: readiness.activeHomeID)
519:     } else {
520:         router.openHouse(homeID: readiness.activeHomeID, focusItemID: item.id)
521:     }
522: }
```
In [TasksScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/TasksScreen.swift#L366-L372):
```swift
366: detailItem = nil
367: // Let the sheet finish dismissing before the tab switch or push, or it drops it.
368: Task { @MainActor in
369:     try? await Task.sleep(for: .milliseconds(320))
370:     go()
371: }
```
**Expected behavior:** Transitions between sheets and tabs should use structured navigation state or completion handlers rather than uncoordinated hardcoded sleep intervals.  
**Root cause:** Workaround for a known SwiftUI quirk where initiating a tab change while a sheet dismiss transition is active can drop the tab change or cause presentation collision warnings.  
**Impact:** If the user interacts with the UI during the 320ms window (e.g. switches tabs or taps another item), the delayed task still fires and forces them abruptly to the House tab. Conversely, if device performance hitches and sheet dismissal takes >320ms, the tab switch can still be dropped.  
**Recommended improvement:** Pass navigation intents through an environment coordinator or trigger the transition in the sheet's `onDismiss` callback.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.  

---

### ## [MEDIUM] A02-04: View Identity Re-Instantiation Destroys SceneKit Controller and Memory on Every Cross-Tab Request
**Domain:** View Identity & Lifecycle  
**Location:** `escape_plan/ContentView.swift:158-171`, `escape_plan/Screens/AppRouter.swift:21-27`  
**Observed behavior:** `HouseTab` applies a dynamic `.id("\(key)-\(request?.token.uuidString ?? "")")` modifier to `HouseScreen`. Every cross-tab request created via `AppRouter.openHouse` or `openFireDrill` creates a new `UUID()`. This causes SwiftUI to destroy and re-instantiate `HouseScreen`, the `EditorSceneView`, and `UnifiedSceneController` on every request.  
**Evidence:**  
In [AppRouter.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/AppRouter.swift#L21-L27):
```swift
21: struct HouseRequest: Equatable {
22:     let homeID: String?
23:     let focusItemID: String?
24:     var opensFireSimulation = false
25:     let token = UUID()
```
In [ContentView.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/ContentView.swift#L158-L171):
```swift
158: let request = HouseRequest.honoured(router.houseRequest, activeHomeID: readiness.activeHomeID)
...
162: HouseScreen(homeID: homeID, library: library, initialFocusItemID: request?.focusItemID,
163:             startsOnFireSimulation: request?.opensFireSimulation ?? false) {
...
170: }
171: .id("\(key)-\(request?.token.uuidString ?? "")")
```
**Expected behavior:** The 3D scene and controller should remain persistent across requests for the same home, and focus/drill requests should be passed imperatively or via `.onChange` to focus the camera without rebuilding the entire SceneKit scene.  
**Root cause:** To force `HouseScreen` to re-focus the camera when requested twice for the same item, developers attached a UUID token to the view identity rather than handling focus requests reactively.  
**Impact:** Significant GPU/CPU overhead, hitching, shader reloading, and dropped touch/camera momentum whenever a user navigates between Home/Tasks and House.  
**Recommended improvement:** Remove `request.token` from `.id(...)` and handle camera recentering reactively via `.onChange(of: router.houseRequest)`.  
**Dependencies:** `AppRouter`, `HouseScreen`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Medium.  

---

### ## [MEDIUM] A02-05: Orphaned and Unreachable Authentication and Cloud Sync UI Code
**Domain:** Code Health & Frontend Architecture  
**Location:** `escape_plan/Screens/Auth/AuthGateView.swift`, `AuthSheetView.swift`, `LoginView.swift`, `SignupView.swift`, `SyncStatusBadge.swift`  
**Observed behavior:** Five complete SwiftUI views remain in `Screens/Auth/` and `Screens/SyncStatusBadge.swift`, but are completely unreachable from the app's user interface. `RootView.swift` permanently bypasses the gate, unconditionally signs out any session, and renders `ContentView`.  
**Evidence:**  
In [RootView.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/RootView.swift#L4-L25):
```swift
4: // The app's root. Until 2026-10-02 it chose between the account gate and the app; accounts
5: // and cloud sync were then cut from the demo app (docs/decisions.md 2026-10-02, branch
6: // `trim-1-demo-cuts`). `Auth/` and `Sync/` are kept, switched off: no gate, no sign-in, no sync.
...
20: ContentView(store: homeStore, storageUnavailable: storageUnavailable)
21:     .task {
22:         if session.state.isSignedIn { session.signOut() }
```
And search confirms no active references to `AuthGateView`, `AuthSheetView`, or `SyncStatusBadge` in production screens.  
**Expected behavior:** Dead code should either be clearly sequestered behind a build configuration flag, or removed to avoid misleading developers and auditors regarding active capabilities.  
**Root cause:** Cloud sync and account gates were cut from the submission build on 2026-10-02, but UI files were left in the project.  
**Impact:** Misleading codebase footprint (~800 lines of dead frontend code), unnecessary compilation overhead, and risk of confusion over cloud sync capabilities.  
**Recommended improvement:** Wrap legacy auth UI files in `#if ENABLE_CLOUD_SYNC` or isolate them in an archival folder outside production targets.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.  

---

### ## [MEDIUM] A02-06: Dangling Unanswered User Message When Switching Active Home During Chat Request
**Domain:** Async Operations & State Integrity  
**Location:** `escape_plan/Screens/AssistantScreen.swift:406-460`  
**Observed behavior:** In `AssistantScreen.send()`, a user's message is immediately appended to `messages` and persisted to disk. If the user changes the active home while `/chat` is awaiting a response, the completion callback executes `guard readiness.activeHomeID == askedAbout else { isSending = false; return }` and discards the assistant reply. The user message remains permanently written to the previous home's conversation history on disk without a corresponding assistant response.  
**Evidence:**  
In [AssistantScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/AssistantScreen.swift#L412-L452):
```swift
412: messages.append(AssistantMessage(role: .user, content: text))
413: persist()
414: deliverPendingUserMessage()
...
442: let response = try await apiClient.chat(home: home, messages: history)
443: // The user switched homes while this was in flight: the answer is about a home
444: // no longer on screen, so it does not join the new home's thread.
445: guard readiness.activeHomeID == askedAbout else { isSending = false; return }
446: messages.append(
447:     AssistantMessage(role: .assistant, content: response.reply, citations: response.citations)
448: )
449: persist(homeID: askedAbout)
```
**Expected behavior:** If the user switches away, the assistant's reply should either be written to the `askedAbout` home's persisted conversation document in `store`, or the orphaned user message should be retracted/marked failed so returning to that home does not display a permanently hanging unanswered question.  
**Root cause:** Guarding against updating the current UI array (`messages`) also skipped saving the response to the target home's persistent store.  
**Impact:** Corrupted turn-alternating conversation history on disk; user returns to a home to find an unanswered query and no retry affordance.  
**Recommended improvement:** Persist the assistant's response directly to `store.save(ConversationDocument(homeID: askedAbout, ...))` even if `readiness.activeHomeID != askedAbout`.  
**Dependencies:** `ConversationStore`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.  

---

### ## [LOW] A02-07: "Clear My Snapshot" Action Offers Zero Visual Feedback or Confirmation
**Domain:** Forms & Feedback  
**Location:** `escape_plan/Export/ShareWithFireDepartmentCard.swift:94-101`  
**Observed behavior:** In `ShareWithFireDepartmentCard`, the "Clear my snapshot" button executes `ResponderSnapshotStore().clearSnapshots()` with no confirmation dialog, no success alert, and no change in UI state.  
**Evidence:**  
In [ShareWithFireDepartmentCard.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/ShareWithFireDepartmentCard.swift#L94-L101):
```swift
94: Button("Clear my snapshot") {
95:     ResponderSnapshotStore().clearSnapshots()
96: }
97: .font(.footnote.weight(.medium))
98: .foregroundStyle(Theme.supporting)
99: .minimumTapTarget()
100: .accessibilityHint("Deletes any Responder Snapshot files saved on this device.")
101: .accessibilityIdentifier("shareWithFireDepartment.clearSnapshot")
```
**Expected behavior:** Destructive deletion of exported snapshots should present a confirmation prompt and provide haptic or visible feedback (e.g. "Snapshots cleared") upon completion.  
**Root cause:** Action is implemented as a fire-and-forget closure with no state binding.  
**Impact:** Users cannot tell if tapping the button had any effect, leading to repeated taps and uncertainty regarding data removal.  
**Recommended improvement:** Add a confirmation dialog or temporary status text confirming that all cached snapshots were removed.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.  

---

### ## [LOW] A02-08: Synchronous Main-Thread JSON Disk Writes During Rapid Checklist Toggles
**Domain:** State Mechanisms & Performance  
**Location:** `escape_plan/Screens/ReadinessStore.swift:352-367`  
**Observed behavior:** In `ReadinessStore.toggleDone`, every single toggle synchronously calls `stateStore.save(checklistState, homeID: activeHomeID)` directly on the main thread before invoking `rescore`.  
**Evidence:**  
In [ReadinessStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift#L358-L364):
```swift
358: withAnimation(animated ? .snappy(duration: 0.22) : nil) {
359:     checklistState[item.id] = mark
360:     if recurs { pendingRecurring[item.id] = newDone }
361: }
362: if !recurs { untimedTicks[item.id] = newDone ? now() : nil }
363: stateStore.save(checklistState, homeID: activeHomeID)
364: if newDone { Haptics.tick() } else { Haptics.selection() }
```
**Expected behavior:** File system persistence should be debounced or offloaded to a background task so rapid user toggles do not block the main runloop.  
**Root cause:** Synchronous design in `ChecklistStateStore.save` executed immediately on `@MainActor`.  
**Impact:** Minor frame drops or micro-stutters when rapidly checking off tasks on older devices.  
**Recommended improvement:** Dispatch `stateStore.save` asynchronously or debounce multiple writes.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** Medium. **Effort:** Small.  

---

### ## [LOW] A02-09: Onboarding Interview Assigns All Household Members to the Same Bedroom
**Domain:** Forms & Data Flow  
**Location:** `escape_plan/Onboarding/OnboardingState.swift:107-138`, `escape_plan/Onboarding/OnboardingFlowView.swift:147-198`  
**Observed behavior:** During onboarding, users can add multiple persons and assign their special needs. However, the onboarding wizard never asks which room each person sleeps in. When committed via `commitAndFinish()`, every single profile is hardcoded to `defaultBedroom` (the first bedroom found on the lowest floor).  
**Evidence:**  
In [OnboardingState.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Onboarding/OnboardingState.swift#L107-L138):
```swift
107: let ordered = home.floors.sorted { $0.level < $1.level }
108: let defaultBedroom = ordered.flatMap(\.rooms).first(where: { $0.type == .bedroom })?.id
109:     ?? ordered.first?.rooms.first?.id ?? ""
...
136: let outcome = store.dispatch(.addProfile(profileId: p.id, name: name, tags: tags,
137:                                          bedroom_room_id: defaultBedroom))
```
**Expected behavior:** While onboarding can default bedrooms for speed, users should be informed that room assignments defaulted to the main bedroom and can be customized in the Household tab, or the interview should include an optional bedroom picker.  
**Root cause:** The onboarding flow was streamlined to minimize cognitive friction, skipping room allocation.  
**Impact:** On the 3D map and fire simulation, all family members start clustered together in the same bedroom until the user discovers `ProfilesScreen` and edits each profile.  
**Recommended improvement:** Add a subtle footnote or summary note informing the user that bedroom locations can be customized under Household.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.  

---

### ## [OBSERVATION] A02-10: Reference-Type Box Wrappers Employed to Prevent SwiftUI Render Loops in SceneKit
**Domain:** State Management Patterns  
**Location:** `escape_plan/Screens/HouseScreen.swift:76-80`, `117-160`, `1757-1763`  
**Observed behavior:** `HouseScreen` utilizes reference-type class wrappers (`SceneViewStateHolder` and `RouteOverlayHolder`) stored inside `@State` to allow closures captured during `makeUIView`/`attach` to read and write live data without triggering recursive `updateUIView` cycles or reading stale value-type structs.  
**Evidence:**  
In [HouseScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L114-L125):
```swift
114: /// Overlay lives in a stable class box, NOT directly in @State: `onRebuild` fires inside
115: /// `updateUIView`, and reassigning an @State var there invalidates the view from within
116: /// its own update — an endless rebuild loop that starves gesture handling.
117: @MainActor
118: private final class RouteOverlayHolder {
119:     var overlay: RouteOverlay?
...
125:     var plan: RoutePlan?
```
**Observed architecture:** This pattern reflects sound engineering pragmatism when bridging imperative SceneKit rendering loops with declarative SwiftUI state. While non-idiomatic in pure SwiftUI, it correctly resolves gesture starvation and stale closure bugs.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** N/A.  

---

## 6. Positive Findings

1. **Exemplary Dynamic Type and Responsive Layout Reflow:**
   Across all audited screens (`HomeScreen`, `HouseScreen`, `ScoreScreen`, `TasksScreen`, `SettingsScreen`), components systematically inspect `dynamicTypeSize.isAccessibilitySize` and reflow horizontal clusters into `VStack`s or `FlowLayout`s. Text views consistently employ `.fixedSize(horizontal: false, vertical: true)` to prevent multi-line truncation under accessibility font sizes.
2. **Deep Reduce Motion Integration:**
   `@Environment(\.accessibilityReduceMotion)` is respected throughout the app. Rather than simply disabling features, the app thoughtfully degrades them: the continuous camera fly-through tour is replaced with a discrete, user-paced stop-by-stop walk (`steppedTourControls`); the simulation scrubber steps in 1-second intervals; and pulsing shaders are disabled to save battery and reduce vestibular discomfort.
3. **Robust VoiceOver Semantics and Screen Reader Alternatives:**
   SceneKit 3D surfaces are inherently inaccessible to screen readers. Escape Plan bridges this gap thoroughly with `HouseSceneAccessibility`: the 3D viewport exposes numbered route steps as an ordered list via a dedicated `Route steps` sheet, ensuring blind and low-vision users receive identical navigational directions.
4. **Honest Failure Classification with BackendFailure:**
   The unified `BackendFailure` component cleanly classifies errors (502 vs 503 vs 401 vs offline) and avoids displaying deceptive "Retry" buttons when an operator must intervene or when credentials are missing.
5. **Deterministic Separation of AI and Routing:**
   The UI maintains strict transparency: AI drafts are prominently flagged with mandatory review notices (`DraftReviewNotice`), the Assistant screen clearly indicates that AI explains but never computes routes, and fire drill disclaimers (`illustrativeNotice`) are displayed unconditionally.

---

## 7. Systemic Issues and Root Causes

1. **Dual Container Roles for Reusable Screens:**
   The primary architectural friction point stems from `HouseScreen` being designed both as a top-level tab container and as a destination pushed from `HomeScreen`. Reusable views should delegate navigation container ownership to their parents.
2. **Ad-Hoc Async Workarounds (`Task.sleep`):**
   Using arbitrary millisecond sleeps to coordinate sheet dismissals and tab switches is symptomatic of missing formal coordination patterns between sheet presentations and router state.
3. **Dead Code Retention After Product Scope Reductions:**
   The complete elimination of cloud accounts and sync on 2026-10-02 was executed cleanly in core persistence, but UI files were left in the repository without compiler-level gating.

---

## 8. Unverified Assumptions

1. **iOS Simulator Runtime Availability:**
   As noted in `_AUDIT_BRIEF.md`, `xcrun simctl list runtimes` indicates no installed iOS simulator runtimes in the host environment. Runtime verification of animated transitions and gesture responses was blocked; all findings are substantiated by exhaustive static source analysis and verified against existing test suites.
2. **SE-Class Small Screen Clipping:**
   Comments in `AuthGateView` note that scroll behavior on iPhone SE screens requires physical or simulator rendering to confirm lack of clipping. Since auth is disabled, this does not affect production users.

---

## 9. Recommended Priorities

1. **P1 (Immediate Fix):** Resolve A02-01 and A02-02 by removing the root `NavigationStack` inside `HouseScreen` and adding an explicit back/dismiss button when presented modally or pushed from `HomeScreen`.
2. **P2 (Reliability):** Replace the 320ms sleep workaround in `HomeScreen` and `TasksScreen` (A02-03) with structured sheet dismissal coordination.
3. **P3 (Performance):** Remove `request.token` from `HouseTab`'s view identity (A02-04) to prevent SceneKit scene destruction on cross-tab jumps.
4. **P4 (Data Integrity):** Fix assistant chat persistence (A02-06) so replies to in-flight requests are saved to the origin home's thread even if the user switches active homes.
5. **P5 (Code Hygiene):** Gate or remove orphaned auth and sync views (A02-05).
