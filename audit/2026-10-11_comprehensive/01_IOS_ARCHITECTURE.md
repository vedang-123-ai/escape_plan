# iOS Architecture Audit Report

**Report File:** `audit/2026-10-11_comprehensive/01_IOS_ARCHITECTURE.md`  
**Audit Date:** 2026-10-11  
**Target:** iOS Engineering Architecture (`escape_plan.xcodeproj`, `escape_plan/`, `tools/editorcore`)  
**Auditor:** Agent 1 (iOS Architecture Domain)  

---

## 1. Executive Summary

This audit evaluates the iOS engineering architecture of the "Escape Plan" application (~36,000 lines of Swift across 107 files in the app target, accompanied by the `tools/editorcore` SwiftPM test harness and ~12,000 lines of tests). The application is built using SwiftUI, SceneKit, and Apple's RoomPlan framework, interacting with a Python/FastAPI backend.

The architecture displays a stark contrast between an exceptionally well-engineered core domain layer and an overburdened presentation layer:
1. **Core Domain & Reducer Excellence:** The core editing engine (`HomeModelStore`, `EditAction`, `UndoStack`, `EditorValidation`) is an exemplary implementation of unidirectional data flow and strict invariant enforcement. Mutations are executed against copies, rigorously validated, and atomically committed.
2. **Monolithic Presentation Bottlenecks:** The primary 3D editing and simulation screen (`HouseScreen.swift`, 2,875 lines) has become an architectural kitchen sink. It manages 45+ state variables, drives SceneKit gesture arbitration and rendering loops, runs asynchronous networking tasks with manual sleep debounces, handles disk synchronization lifecycles, and employs manual reference-class "boxes" (`SceneViewStateHolder`, `RouteOverlayHolder`) to circumvent SwiftUI closure capture bugs during UIKit representable updates.
3. **High-Frequency Re-render Cascade:** Timeline simulation playback updates an `@Observable` model at ~60 Hz. Because the view's root body observes this clock, the entire 2,875-line SwiftUI view hierarchy re-evaluates 60 times per second, forcing defensive caching (`rebuildIfNeeded`) inside the SceneKit bridge to prevent continuous teardown and reconstruction of the 3D scene graph.
4. **Symlink Split-Brain Harness:** The `tools/editorcore` Swift Package harness uses filesystem symlinks into `escape_plan/` to allow 656 unit tests to run hermetically on macOS under `swift test`. While highly effective at bypassing CI/dev machine simulator limitations, it establishes a fragile dual-module boundary (`EditorCore` vs `escape_plan`) governed by conditional compilation (`#if SWIFT_PACKAGE`) and restricts shared code to pure Foundation.
5. **Zombie Architecture from Product Trims:** Subsystems cut in early October 2026 (User Accounts/Auth, Cloud Sync, and Practice Reminders) remain heavily embedded in the launch sequence. `escape_planApp.init()` continues to initialize the full `AuthSession`, `SyncRepository`, and `SyncManager` stack and injects them into the SwiftUI environment, while `RootView.task` executes defensive cleanups on every launch to sign out dead logins and delete stale notification requests.
6. **Mixed State Paradigms:** The codebase is suspended halfway between Combine (`ObservableObject` / `@StateObject` / `@EnvironmentObject` in `HomeLibrary`) and Swift 5.9+ Observation (`@Observable` / `@State` / `@Environment` across all other stores).

Overall, the core data model and persistence design are robust and capable of supporting the app's evolution. However, the SwiftUI presentation layer requires refactoring to decompose monolithic views into dedicated ViewModels/Coordinators and purge abandoned cloud/auth infrastructure.

---

## 2. Scope and Files Inspected

### Source Files Inspected (Full End-to-End Traces)
- **App Entry & Lifecycle:**
  - `escape_plan/escape_planApp.swift` (186 lines)
  - `escape_plan/RootView.swift` (50 lines)
  - `escape_plan/ContentView.swift` (193 lines)
- **Navigation & Presentation:**
  - `escape_plan/Screens/AppRouter.swift` (69 lines)
  - `escape_plan/Screens/HomeScreen.swift` (806 lines)
  - `escape_plan/Screens/HouseScreen.swift` (2,875 lines)
  - `escape_plan/Screens/HouseEditorSessionController+App.swift` (53 lines)
  - `escape_plan/Screens/AssistantScreen.swift` (625 lines)
  - `escape_plan/Screens/SettingsScreen.swift` (419 lines)
  - `escape_plan/Screens/TasksScreen.swift` (410 lines)
  - `escape_plan/Screens/SyncStatusBadge.swift` (178 lines)
- **Editor Core & Shared State:**
  - `escape_plan/Editor/Core/HomeModelStore.swift` (702 lines)
  - `escape_plan/Editor/Core/HouseEditorSessionController.swift` (162 lines)
  - `escape_plan/Editor/Core/EditorValidation.swift` (604 lines)
  - `escape_plan/Editor/Core/UndoStack.swift` (124 lines)
  - `escape_plan/Editor/Core/EditorGeometry.swift` (237 lines)
  - `escape_plan/Editor/Core/GestureArbiter.swift` (87 lines)
  - `escape_plan/Editor/Core/CameraRigModel.swift` (243 lines)
  - `escape_plan/Editor/EditorSession.swift` (42 lines)
  - `escape_plan/Screens/ReadinessStore.swift` (489 lines)
- **SceneKit & Renderer Layer:**
  - `escape_plan/Editor/SceneKit/EditorSceneView.swift` (284 lines)
  - `escape_plan/Editor/SceneKit/SceneKitEditorBridge.swift` (282 lines)
  - `escape_plan/Renderer/UnifiedSceneController.swift` (487 lines)
  - `escape_plan/Renderer/Evacuation/UnifiedSceneController+Evacuation.swift` (72 lines)
  - `escape_plan/Renderer/Evacuation/EvacuationPlaybackCoordinator.swift` (491 lines)
  - `escape_plan/Renderer/DollhouseScene.swift` (656 lines)
  - `escape_plan/Renderer/RouteOverlay.swift` (541 lines)
  - `escape_plan/Renderer/PeopleLayer.swift` (466 lines)
- **Persistence & Cloud Sync:**
  - `escape_plan/Persistence/HomeDocumentStore.swift` (375 lines)
  - `escape_plan/Persistence/HomeLibrary.swift` (125 lines)
  - `escape_plan/Persistence/HomeDocumentSyncRepository.swift` (187 lines)
  - `escape_plan/Sync/SyncManager.swift` (532 lines)
  - `escape_plan/Sync/SyncReconciler.swift` (278 lines)
  - `escape_plan/Auth/AuthSession.swift` (388 lines)
  - `escape_plan/Auth/KeychainTokenStore.swift` (112 lines)
- **Harness & Packages:**
  - `tools/editorcore/Package.swift` (49 lines)
  - Symlinks in `tools/editorcore/Sources/EditorCore/` and `tools/editorcore/Tests/EditorCoreTests/Shared`
  - `escape_plan.xcodeproj/project.pbxproj`

---

## 3. Methods and Checks Performed

1. **Automated Test Execution:**
   - Ran `swift test --package-path tools/editorcore --scratch-path /tmp/audit-editorcore-a1`. Executed 656 unit tests hermetically on macOS. Verified that all 656 tests passed in 4.85 seconds.
2. **Environment & Simulator Verification:**
   - Evaluated `xcrun simctl list runtimes` and `xcrun simctl list devices`. Recorded that iOS 27.0 runtime is listed, but physical simulators are shutdown and several report `unavailable, runtime profile not found using “System” match policy`. App-target test execution via `xcodebuild test` was preserved for dedicated build agents per audit rules.
3. **Source Code Static Analysis:**
   - Line counts, state distribution, and structural breakdown of the 30 largest Swift files.
   - Comprehensive assessment of `HouseScreen.swift` (state variables, closure captures, threading, ViewModifier implementations, preference keys).
   - Architectural dependency analysis between `escape_planApp`, `ContentView`, `HouseScreen`, `UnifiedSceneController`, and `EvacuationPlaybackCoordinator`.
   - Inspection of dead code paths resulting from the 2026-10-02 product trims (Auth, Cloud Sync, Practice Reminders).

---

## 4. Architectural Map

### 4.1 Modules and Layers

```
┌────────────────────────────────────────────────────────────────────────┐
│                        SwiftUI Presentation Layer                      │
│   RootView -> ContentView (TabBar) -> HomeScreen, TasksScreen,         │
│   HouseTab/HouseScreen, AssistantScreen, SettingsScreen               │
└──────────────────────────┬─────────────────────────────────────────────┘
                           │ Observes & Dispatches
┌──────────────────────────▼─────────────────────────────────────────────┐
│                       State & Coordination Layer                       │
│   • ReadinessStore (@Observable): Active Home, Scores, Checklist Marks │
│   • AppRouter (@Observable): Selected Tab, Cross-Tab House Requests    │
│   • EditorSession (@Observable): Open Home Store, UndoStack, Deletion  │
│   • HouseEditorSessionController: Disk Fingerprinting, Save Concurrency│
│   • HomeLibrary (ObservableObject): List of Homes, Store Facade        │
│   • AuthSession & SyncManager (@Observable): [Zombie / Cut Feature]    │
└──────────────────────────┬─────────────────────────────────────────────┘
                           │ Manages / Mutates
┌──────────────────────────▼─────────────────────────────────────────────┐
│                         Domain & Reducer Layer                         │
│   • HomeModelStore (@Observable): Single Point of Mutation, Reducer    │
│   • EditAction: Enum of all valid mutations                            │
│   • EditorValidation: Structural invariant validator                   │
│   • Models: HomeModel, Geometry, RoutePlan, ScoreModels (Pure Codable) │
└──────────────────────────┬─────────────────────────────────────────────┘
                           │ Binds To / Renders
┌──────────────────────────▼─────────────────────────────────────────────┐
│                    SceneKit 3D & Export Engines                        │
│   • EditorSceneView (UIViewRepresentable) -> UnifiedSceneController    │
│   • SceneKitEditorBridge -> Translates Gestures to EditAction          │
│   • RouteOverlay / RouteGeometry -> Renders /routes tube geometry      │
│   • EvacuationPlaybackCoordinator -> Multi-agent simulation clock      │
│   • EscapePlanPDF / ResponderSnapshotJSON -> Documents & Disclosures  │
└──────────────────────────┬─────────────────────────────────────────────┘
                           │ I/O Operations
┌──────────────────────────▼─────────────────────────────────────────────┐
│                 Persistence & External Services Layer                  │
│   • HomeDocumentStore: Atomic JSON filesystem persistence (Documents/) │
│   • APIClient: Async/await URLSession HTTP client to FastAPI backend   │
│   • ConversationStore: SQLite / JSON assistant chat history            │
│   • RoomCaptureController: Apple RoomPlan LiDAR capture                │
└────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Entry Points and Navigation Flows

```
[App Launch: escape_planApp.init()]
  │── AppAppearance.install()
  │── HomeDocumentStore.launchStore() (Fallback detection)
  │── FixtureSeeder.seedStarterHomes()
  │── Setup SyncStateStore, HomeDocumentSyncRepository, AuthSession, SyncManager
  ▼
[RootView]
  │── .task: Force sign-out dead sessions; purge stale practice-reminder notifications
  ▼
[ContentView] (TabView Shell)
  ├── Tab 1: HomeScreen (Overview, score card, up-next tasks, home switcher, scan flow)
  ├── Tab 2: TasksScreen (Full checklist with peril filter, task completion toggles)
  ├── Tab 3: HouseTab -> HouseScreen (3D interactive house editor, routes, fire simulation)
  ├── Tab 4: AssistantScreen (AI chatbot against backend /chat with streaming)
  └── Tab 5: SettingsScreen (Server endpoints, local share, privacy disclosure)
```

**Cross-Tab Navigation (`AppRouter`):**
- `TasksScreen` / `HomeScreen` -> `router.openHouse(homeID:focusItemID:)` -> Sets `selectedTab = .house`, supplies `HouseRequest` -> `HouseTab` mounts/reconfigures `HouseScreen`.
- `HomeScreen` -> `router.openFireDrill(homeID:)` -> Sets `selectedTab = .house`, sets `opensFireSimulation = true` -> `HouseTab` mounts `HouseScreen` with fire dock active.
- `HomeScreen` -> `showingNewHome = true` -> Pushes `HouseScreen(homeID: nil)` onto `HomeScreen`'s nested `NavigationStack` (**Dual Mounting Defect**).

### 4.3 State Owners and Data Sources

| State Entity | Owning Scope | Lifetime | Data Source | Primary Consumers |
|---|---|---|---|---|
| `HomeModel` (Active Document) | `HomeModelStore` / `EditorSession` | Open editor session | Disk (`HomeDocumentStore`) | `HouseScreen`, `EditorSceneView`, `UnifiedSceneController` |
| `ActiveHomeID` | `ReadinessStore` | App lifecycle (persisted via `ActiveHomeMemory`) | `UserDefaults` / `HomeLibrary` | `ContentView`, `HomeScreen`, `TasksScreen`, `HouseTab` |
| `ScoreBreakdown` & Checklist | `ReadinessStore` | In-memory + `ScoreCache` | Backend `POST /score` | `HomeScreen`, `TasksScreen`, `ScoreScreen` |
| `RoutePlan` | `HouseScreen` (Local `@State`) | Active screen visit | Backend `POST /routes` | `RouteOverlayHolder`, `RouteOverlay`, `RouteStepsSheet` |
| `EvacuationTimeline` | `EvacuationPlaybackModel` (in `HouseScreen`) | Active simulation | Backend `POST /evacuate` | `EvacuationPlaybackCoordinator`, `PlaybackClock` |
| `HomeSummaries` | `HomeLibrary` (`@Published`) | App lifecycle | Filesystem scan (`Documents/Homes/`) | `HomeScreen` top bar, `ContentView`, `HouseTab` |
| `AppTab` & Cross-Tab Requests | `AppRouter` (`@Observable`) | App lifecycle | In-memory UI actions | `ContentView`, `HomeScreen`, `TasksScreen` |

### 4.4 External and System Dependencies

| Dependency | Purpose | Architectural Layer | Isolation Status |
|---|---|---|---|
| **SceneKit** | 3D Dollhouse rendering, camera control, route geometry | Rendering / Editor | Mixed; isolated in `Renderer/` and `Editor/SceneKit/`, but lifecycle leaked into `HouseScreen.swift` |
| **RoomPlan** | LiDAR room capture & USDZ export | Capture | Well-isolated in `Capture/` (`RoomCaptureController`, `RoomCaptureViewRepresentable`) |
| **PDFKit & UIKit** | Floor plan graphics rendering & PDF document export | Export | Isolated in `Export/EscapePlanPDF.swift` and `FloorPlanDrawing.swift` |
| **Observation** | Reactive state propagation (`@Observable`) | Core State | Pervasive across modern stores (`iOS 17+` / `macOS 14+`) |
| **Combine** | Legacy reactive published properties (`@Published`) | Persistence | Confined to `HomeLibrary.swift` |
| **URLSession** | HTTP / SSE networking | Networking | Isolated in `Networking/APIClient*.swift` |
| **Security (Keychain)** | Secure token persistence | Auth | Isolated in `Auth/KeychainTokenStore.swift` |

---

## 5. Feature Completeness Table

| Feature / Subsystem | Status | Evidence (Path:Line) | Architectural Assessment |
|---|---|---|---|
| **3D Dollhouse Floor Plan Editor** | **Complete** | `escape_plan/Editor/Core/HomeModelStore.swift:1-120`<br>`escape_plan/Editor/SceneKit/EditorSceneView.swift:40-100` | Fully functioning unidirectional reducer; validated edits, parametric openings, snapping, undo/redo. |
| **Fire Escape Route Generation** | **Complete** | `escape_plan/Networking/APIClient+Routes.swift:1-60`<br>`escape_plan/Renderer/RouteOverlay.swift:1-150` | Server-grounded escape routes fetched from `/routes`, rendered as 3D SceneKit glowing path tubes. |
| **Fire-Origin Evacuation Simulation** | **Complete** | `escape_plan/Screens/HouseScreen.swift:1496-1530`<br>`escape_plan/Renderer/Evacuation/EvacuationPlaybackCoordinator.swift:1-120` | Server-driven evacuation timeline (`POST /evacuate`), multi-agent walking animation, playback scrubber. |
| **Readiness Scoring & Checklist** | **Complete** | `escape_plan/Screens/ReadinessStore.swift:1-100`<br>`escape_plan/Screens/TasksScreen.swift:1-80` | Grounded `/score` responses parsed into categories; recurring task aging handled server-side. |
| **Grounded AI Assistant** | **Complete** | `escape_plan/Screens/AssistantScreen.swift:1-100`<br>`escape_plan/Networking/APIClient+Chat.swift:1-80` | Streaming chat against `/chat`, persists conversation history in `ConversationStore`. |
| **AI Floor Plan Intake (Build from Plan)** | **Complete** | `escape_plan/Screens/BuildFromPlanView.swift:1-70`<br>`escape_plan/Networking/APIClient+Build.swift:1-50` | Photo/document intake sent to `/build`, returns AI-drafted model requiring explicit editor review. |
| **LiDAR RoomPlan Capture** | **Complete** | `escape_plan/Capture/RoomCaptureController.swift:1-80`<br>`escape_plan/Capture/Views/ScanFlowView.swift:1-90` | Uses Apple RoomPlan on supported hardware; exports raw USDZ/JSON artifacts for backend conversion. |
| **PDF & Responder Snapshot Export** | **Complete** | `escape_plan/Export/EscapePlanPDF.swift:1-80`<br>`escape_plan/Export/ResponderSnapshotStore.swift:1-50` | Generates multi-page readiness PDFs and standardized First Responder JSON snapshots for local sharing. |
| **Multi-Disaster Support (Earthquake / Weather)** | **Partial** | `escape_plan/Models/Enums.swift:10-35`<br>`escape_plan/Readiness/PreventionTip.swift:1-60` | Disaster enums and safety tips exist for earthquake/weather, but routing and simulation are fire-only. |
| **User Accounts & Authentication** | **Unused / Dead** | `escape_plan/RootView.swift:4-7, 25`<br>`escape_plan/Screens/Auth/LoginView.swift:1-50` | Cut on 2026-10-02 (`docs/decisions.md`). Full auth code kept; `RootView` unconditionally signs out. |
| **Cloud Homes Sync** | **Unused / Dead** | `escape_plan/RootView.swift:5-8`<br>`escape_plan/Sync/SyncManager.swift:65-100` | Cut on 2026-10-02. Sync manager initialized on launch but disconnected from UI; tombstone observer unhooked. |
| **Family Practice Reminders** | **Unused / Dead** | `escape_plan/RootView.swift:26-34` | Cut in trim 2 (2026-10-03). `RootView` executes background UNUserNotificationCenter purges every launch. |
| **Room-by-Room Re-scan Review** | **Unused / Dead** | `escape_plan/Screens/AppRouter.swift:13-15` | Cut on 2026-10-02 (`recheckRoom` removed from `HomeIntent`). |
| **Canned Score UI Test Injection** | **Mocked** | `escape_plan/escape_planApp.swift:83-105` | UI test harness seeds mock `/score` responses via `ScoreCache` when `UITEST_CANNED_SCORE` is set. |

---

## 6. Findings (with Evidence)

### ## [HIGH] A01-01 Monolithic 2875-Line HouseScreen Violates Separation of Concerns
**Domain:** Presentation / View Architecture  
**Location:** `escape_plan/Screens/HouseScreen.swift:1-2875`  
**Observed behavior:** `HouseScreen.swift` is 2,875 lines long and acts as the view, controller, network coordinator, gesture delegate, and accessibility narrator simultaneously. It maintains 45+ `@State` and `@Environment` properties, coordinates scene lifecycle, schedules network tasks, implements sleep-based debouncing, and calculates layout physics.  
**Evidence:**
- 45+ state declarations (`escape_plan/Screens/HouseScreen.swift:36-200`):
  ```swift
  @State private var session: EditorSession?
  @State private var sessionController: HouseEditorSessionController?
  @State private var controller: UnifiedSceneController?
  @State private var viewStateHolder = SceneViewStateHolder()
  @State private var overlayHolder = RouteOverlayHolder()
  @State private var routePlan: RoutePlan?
  @State private var playback = EvacuationPlaybackModel()
  @State private var routesTask: Task<Void, Never>?
  @State private var refetchDebounce: Task<Void, Never>?
  @State private var evacuateTask: Task<Void, Never>?
  ```
- Direct session initialization and disk lifecycle orchestration inside a SwiftUI View (`escape_plan/Screens/HouseScreen.swift:2286-2317`):
  ```swift
  private func loadIfNeeded() {
      ...
      let existing = HouseEditorSessionController(homeID: homeID, disk: documentStore)
      loaded = try existing.open()
      let newStore = try HomeModelStore(model: model)
      let newSession = EditorSession(store: newStore)
      newStore.onCommit = { [controller] _commit in
          newSession.undoStack.recordCommit(_commit)
          autosave(newSession, controller: controller)
          invalidateRoutes()
      }
      session = newSession
      ...
  ```
- Networking with manual 900ms sleep debouncing inside view helper methods (`escape_plan/Screens/HouseScreen.swift:1737-1742`):
  ```swift
  refetchDebounce = Task {
      try? await Task.sleep(nanoseconds: 900_000_000)
      guard !Task.isCancelled else { return }
      fetchRoutes()
  }
  ```
**Expected behavior:** Views should be lightweight presentation declarations. Business logic, disk synchronization, network debouncing, and SceneKit coordinator lifecycle should reside in a dedicated ViewModel or Presentation Controller.  
**Root cause:** Rapid feature accumulation during sprints S11.9 through S11.37 without architectural refactoring to extract a `HouseScreenViewModel` or `HouseSceneCoordinator`.  
**Impact:** Massive cognitive overhead, severe regression risk during modifications, untestable view-bound business logic, and memory leak vulnerability from complex closure captures.  
**Recommended improvement:** Extract `HouseScreenViewModel` (as a `@MainActor @Observable` class) to own `EditorSession`, network tasks, debouncing, and disk synchronization. Split `HouseScreen` into subviews: `HouseSceneCard`, `HouseDockView`, `HouseInspectionPanel`, and `HousePlaybackBar`.  
**Dependencies:** `EditorSession`, `UnifiedSceneController`, `APIClient`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Large  

---

### ## [HIGH] A01-02 SwiftUI Re-render Cascade at 60Hz During Evacuation Simulation
**Domain:** SwiftUI Data Flow / Performance  
**Location:** `escape_plan/Screens/HouseScreen.swift:188, 812-831`, `escape_plan/Editor/SceneKit/EditorSceneView.swift:108-115`  
**Observed behavior:** During fire evacuation simulation playback, `PlaybackClock` drives `playback.tick()` off `TimelineView(.animation)`. Because `playback` (`EvacuationPlaybackModel`) is an `@Observable` model observed directly by `HouseScreen`'s root body, the entire 2,875-line view hierarchy re-evaluates 60 times per second. This forced `EditorSceneView` to implement defensive caching to prevent scene graph recreation on every display frame.  
**Evidence:**
- `PlaybackClock` ticks the playback model on animation cadence (`escape_plan/Screens/HouseScreen.swift:812-827`):
  ```swift
  private struct PlaybackClock: View {
      let playback: EvacuationPlaybackModel
      var body: some View {
          TimelineView(.animation(minimumInterval: playback.isSteppedMode ? 0.2 : nil,
                                  paused: !playback.isPlaying)) { context in
              Color.clear
                  .onChange(of: context.date) { oldDate, newDate in
                      playback.tick(deltaTime: min(delta, Self.maxFrameDelta_s))
                  }
          }
      }
  }
  ```
- Comment in `EditorSceneView.swift:108-115` acknowledging the 60fps re-render problem:
  ```swift
  // Rebuild only when the geometry inputs actually changed...
  // That was harmless while updates only followed an edit commit, but
  // HouseScreen's body reads the evacuation playback clock, so this path now runs on every
  // frame of a simulation; rebuilding there would restart the animation 60×/sec.
  controller.rebuildIfNeeded(home: store.model, activeFloorId: store.activeFloorId)
  ```
**Expected behavior:** High-frequency animation state (playhead position, elapsed time) should be isolated in a leaf subview or handled directly within the SceneKit renderer coordinator, without triggering re-renders of the root container view and its inspectors.  
**Root cause:** Coupling simulation playback state directly to the top-level screen container instead of isolating the simulation dock and playback controls into an isolated component.  
**Impact:** Unnecessary CPU and battery drain during simulation playback; potential UI thread stutter on older hardware; tight coupling forcing workaround hacks in underlying views.  
**Recommended improvement:** Isolate `playback` observation to a dedicated `SimulationPlaybackDock` leaf view. Pass playback updates directly to `EvacuationPlaybackCoordinator` without invalidating the parent `HouseScreen`.  
**Dependencies:** `EvacuationPlaybackModel`, `EvacuationPlaybackCoordinator`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Medium  

---

### ## [HIGH] A01-03 Manual Reference-Box Hacks to Circumvent SwiftUI Closure Capture Bugs
**Domain:** Architecture / SwiftUI-UIKit Interop  
**Location:** `escape_plan/Screens/HouseScreen.swift:66-81, 113-160`  
**Observed behavior:** `HouseScreen` creates custom `@MainActor final class` reference wrappers (`SceneViewStateHolder` and `RouteOverlayHolder`) stored in `@State` solely to allow UIKit/SceneKit closures (`onRebuild`, `updateUIView`) to read mutable state without capturing stale struct copies of the SwiftUI view.  
**Evidence:**
- `SceneViewStateHolder` definition and rationale (`escape_plan/Screens/HouseScreen.swift:66-81`):
  ```swift
  /// The focused floor ALSO lives in a stable class box: the `onRebuild` closure is captured
  /// once (at attach) and reads through a stale copy of this struct — @State reads from that
  /// copy returned the values from attach time, so every editor rebuild silently reset the
  /// view back to defaults.
  @MainActor
  private final class SceneViewStateHolder {
      var activeFloorID: String?
  }
  @State private var viewStateHolder = SceneViewStateHolder()
  ```
- `RouteOverlayHolder` definition and rationale (`escape_plan/Screens/HouseScreen.swift:113-125`):
  ```swift
  /// Overlay lives in a stable class box, NOT directly in @State: `onRebuild` fires inside
  /// `updateUIView`, and reassigning an @State var there invalidates the view from within
  /// its own update — an endless rebuild loop that starves gesture handling.
  @MainActor
  private final class RouteOverlayHolder {
      var overlay: RouteOverlay?
      var plan: RoutePlan?
      var selectedRoomID: String?
      var model: HomeModel?
      ...
  ```
- Infinite loop defensive tripwire (`escape_plan/Screens/HouseScreen.swift:1758-1760`):
  ```swift
  // May run inside updateUIView (via onRebuild): only touch @State when the value
  // actually changed, or the view invalidates itself from within its own update forever.
  if issues != overlayIssues { overlayIssues = issues }
  ```
**Expected behavior:** UIKit/SceneKit bridging state should be owned by an `Observable` Coordinator or ViewModel whose lifetime is independent of SwiftUI struct generation.  
**Root cause:** Attempting to manage imperative SceneKit bridge lifecycles directly within a declarative SwiftUI View struct rather than establishing a clean ViewModel/Coordinator layer.  
**Impact:** High architectural fragility; risk of infinite update loops if equality checks fail; convoluted state synchronization.  
**Recommended improvement:** Move `UnifiedSceneController`, `RouteOverlay`, and `PeopleLayer` management out of `HouseScreen` and into a dedicated `HouseSceneCoordinator` class.  
**Dependencies:** `UnifiedSceneController`, `RouteOverlay`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Medium  

---

### ## [MEDIUM] A01-04 Objective-C Associated Object Used for Dynamic Dependency Retention
**Domain:** Dependency Injection & Architecture  
**Location:** `escape_plan/Renderer/Evacuation/UnifiedSceneController+Evacuation.swift:4-10, 42-50, 57-63`  
**Observed behavior:** `UnifiedSceneController+Evacuation.swift` uses Objective-C runtime associated objects (`objc_setAssociatedObject` / `objc_getAssociatedObject`) to attach `EvacuationPlaybackCoordinator` to `UnifiedSceneController` because `UnifiedSceneController` was implemented without stored properties for evacuation state.  
**Evidence:**
- Implementation in `escape_plan/Renderer/Evacuation/UnifiedSceneController+Evacuation.swift:10, 42-50`:
  ```swift
  private nonisolated(unsafe) var evacuationPlaybackCoordinatorKey: UInt8 = 0

  extension UnifiedSceneController {
      func bindEvacuationPlayback(...) -> EvacuationPlaybackCoordinator {
          ...
          objc_setAssociatedObject(
              self,
              &evacuationPlaybackCoordinatorKey,
              coordinator,
              .OBJC_ASSOCIATION_RETAIN_NONATOMIC
          )
          coordinator.start()
          return coordinator
      }
  ```
**Expected behavior:** Object dependencies and coordinator hierarchies should be expressed cleanly via explicit Swift properties or formal composition patterns.  
**Root cause:** `UnifiedSceneController` was designed to be evacuation-agnostic, and subsequent feature additions worked around this limitation using Objective-C runtime tricks instead of modifying the core class or creating a composed controller wrapper.  
**Impact:** Bypasses Swift compile-time type safety and ownership tracking; introduces implicit hidden state; brittle during refactoring.  
**Recommended improvement:** Add an optional `evacuationCoordinator: EvacuationPlaybackCoordinator?` stored property directly to `UnifiedSceneController`, or wrap both in a composite `HouseSceneController`.  
**Dependencies:** `UnifiedSceneController`, `EvacuationPlaybackCoordinator`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small  

---

### ## [MEDIUM] A01-05 Split-Brain Testing Architecture via tools/editorcore Symlinks
**Domain:** Build Architecture & Testability  
**Location:** `tools/editorcore/Package.swift:1-49`, `tools/editorcore/Sources/EditorCore/`, `escape_planTests/EditorCore/`  
**Observed behavior:** The repository maintains two parallel build systems for the same Swift files: the primary Xcode project (`escape_plan.xcodeproj`) and a secondary SwiftPM package (`tools/editorcore`). `tools/editorcore` uses filesystem symlinks to cherry-pick files from `escape_plan/`. Code compiled in both runners must use conditional imports (`#if SWIFT_PACKAGE import EditorCore #else @testable import escape_plan #endif`), and symlinked files are strictly forbidden from importing UIKit, SwiftUI, or SceneKit.  
**Evidence:**
- `Package.swift:3-19` documentation:
  ```swift
  //  EditorCore — a TEST HARNESS, not a shipping module.
  //  Why this exists: no iOS simulator runtime is installed on the CI/dev machine this lane runs
  //  on, so `xcodebuild test` cannot execute a single test. The S2.1 editor core is deliberately
  //  pure (Foundation only — no SceneKit, no SwiftUI)...
  ```
- Symlink tree in `tools/editorcore/Sources/EditorCore/`:
  - `Auth -> ../../../../escape_plan/Auth`
  - `Core -> ../../../../escape_plan/Editor/Core`
  - `EscapePlanDocument.swift -> ../../../../escape_plan/Export/EscapePlanDocument.swift`
  - `Fixtures -> ../../../../escape_plan/Fixtures`
  - `Models -> ../../../../escape_plan/Models`
  - `Readiness -> ../../../../escape_plan/Readiness`
  - `ResponderSnapshotExtractor.swift -> ../../../../escape_plan/Export/ResponderSnapshotExtractor.swift`
  - `ResponderSnapshotJSON.swift -> ../../../../escape_plan/Export/ResponderSnapshotJSON.swift`
  - `SnapshotHazardSummary.swift -> ../../../../escape_plan/Export/SnapshotHazardSummary.swift`
  - `Sync -> ../../../../escape_plan/Sync`
**Expected behavior:** The application core should be organized into a first-class Swift Package or framework target consumed directly by both Xcode and standalone CLI tooling, without relying on filesystem symlinks or conditional module names.  
**Root cause:** Workaround developed to run unit tests on CI/dev environments lacking an installed iOS simulator runtime.  
**Impact:** Fragile symlink dependencies; arbitrary restrictions on source files (accidental imports of UI frameworks break the SPM build); 39 test files outside `EditorCore` remain unexecutable without an iOS simulator.  
**Recommended improvement:** Formalize `EditorCore` as a real local Swift Package dependency embedded in `escape_plan.xcodeproj`, rather than maintaining a shadow harness that symlinks app files.  
**Dependencies:** `escape_plan.xcodeproj`, Xcode build configuration.  
**Verification status:** Verified by automated test (`swift test` passing 656 tests) and source inspection.  
**Confidence:** High  
**Effort:** Medium  

---

### ## [MEDIUM] A01-06 Zombie Architecture: Cut Auth and Cloud Sync Subsystems Retained in Launch
**Domain:** System Architecture & Dead Code  
**Location:** `escape_plan/escape_planApp.swift:30-37, 110-138`, `escape_plan/RootView.swift:4-8, 21-34`  
**Observed behavior:** User accounts, authentication, and cloud sync were formally cut from the app on 2026-10-02 (`docs/decisions.md`). However, `escape_planApp.init()` continues to initialize `FileSyncStateStore`, `HomeDocumentSyncRepository`, `AuthSession`, and `SyncManager`, injecting them into the SwiftUI environment on every launch. Furthermore, `RootView.task` executes defensive cleanups on every launch to sign out dead logins and purge stale notifications.  
**Evidence:**
- Launch initialization in `escape_plan/escape_planApp.swift:110-138`:
  ```swift
  let syncStateStore = FileSyncStateStore(...)
  let repository = HomeDocumentSyncRepository(store: homeStore, stateStore: syncStateStore)
  _syncRepository = State(wrappedValue: repository)
  let session = AuthSession(client: AuthClient(baseURL: APIClient.currentBaseURL()),
                            store: KeychainTokenStore())
  _authSession = State(wrappedValue: session)
  _syncManager = State(wrappedValue: SyncManager(
      client: CloudHomesClient(baseURL: APIClient.currentBaseURL()),
      repository: repository,
      stateStore: syncStateStore,
      tokenProvider: { session.token },
      onSessionExpired: { session.signOut() }))
  ```
- Unconditional sign-out and purge in `escape_plan/RootView.swift:21-34`:
  ```swift
  .task {
      if session.state.isSignedIn { session.signOut() }
      let center = UNUserNotificationCenter.current()
      let stale = await center.pendingNotificationRequests()
          .map(\.identifier)
          .filter { $0.hasPrefix("practice-reminder.") }
      if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
  }
  ```
- Unused UI files still present in target: `AuthGateView.swift`, `LoginView.swift`, `SignupView.swift`, `AuthSheetView.swift`, `SyncStatusBadge.swift`.  
**Expected behavior:** Dormant or cut subsystems should be cleanly removed or placed behind an explicit feature flag compile gate rather than initialized and maintained in the primary launch path.  
**Root cause:** Fear of regressions or breaking migration paths during the October 2026 feature trims led developers to retain full object graphs while severing only top-level navigation routes.  
**Impact:** Unnecessary startup memory allocation, Keychain reads, and file system I/O on every app launch; developer confusion regarding whether cloud sync is active.  
**Recommended improvement:** Remove `AuthSession`, `SyncManager`, and `HomeDocumentSyncRepository` from `escape_planApp.init()`. Retain cleanup logic in a one-time migration utility if backward compatibility is required, then prune dormant views.  
**Dependencies:** `escape_planApp`, `RootView`, `ContentView`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Medium  

---

### ## [MEDIUM] A01-07 Dual Mounting of HouseScreen via NavigationDestination and Tab Shell
**Domain:** Navigation & State Ownership  
**Location:** `escape_plan/Screens/HomeScreen.swift:96-101`, `escape_plan/ContentView.swift:56-60, 155-179`  
**Observed behavior:** `HouseScreen` is mounted permanently inside Tab 3 (`HouseTab`) in `ContentView`. However, `HomeScreen` also contains a `.navigationDestination(isPresented: $showingNewHome)` that instantiates and pushes a *second* `HouseScreen` when the user taps "Build Manually" or "Build it myself".  
**Evidence:**
- Tab shell mounting in `escape_plan/ContentView.swift:56-60`:
  ```swift
  HouseTab()
      .tabItem { Label("House", systemImage: "cube") }
      .tag(AppTab.house)
  ```
- Second modal/push mounting in `escape_plan/Screens/HomeScreen.swift:96-101`:
  ```swift
  .navigationDestination(isPresented: $showingNewHome) {
      HouseScreen(homeID: nil, library: library) {
          library.refresh()
          if let id = library.homes.first?.id { switchHome(to: id) }
      }
  }
  ```
- Triggered by `HomeScreen:163` and `HomeScreen:498`:
  ```swift
  Button { showingNewHome = true } label: { Label("Build Manually", systemImage: "square.and.pencil") }
  DSSecondaryButton(title: "Build it myself") { showingNewHome = true }
  ```
**Expected behavior:** All house editing should route through the single canonical `HouseTab` instance via `AppRouter.openHouse(homeID: nil)` rather than pushing duplicate instances inside `HomeScreen`'s navigation stack.  
**Root cause:** Divergence between original multi-screen navigation concepts and the Linear revamp tab-based architecture.  
**Impact:** Two concurrent `HouseScreen` instances, each holding separate SceneKit views, gesture recognizers, and `HouseEditorSessionController` instances. Risk of conflicting autosaves and duplicated resource usage.  
**Recommended improvement:** Change `HomeScreen`'s "Build Manually" action to call `router.openHouse(homeID: nil)` and switch to Tab 3, removing `.navigationDestination(isPresented: $showingNewHome)`.  
**Dependencies:** `AppRouter`, `HomeScreen`, `HouseTab`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small  

---

### ## [LOW] A01-08 Mixed State Management Paradigms Across Core Stores
**Domain:** SwiftUI Data Flow  
**Location:** `escape_plan/Persistence/HomeLibrary.swift:28`, `escape_plan/ContentView.swift:23-25, 74-76`  
**Observed behavior:** The application mixes Combine's legacy `ObservableObject` / `@Published` / `@StateObject` paradigm with modern Swift 5.9+ Observation (`@Observable` / `@State`). `HomeLibrary` is an `ObservableObject` injected via `.environmentObject()`, while `ReadinessStore`, `AppRouter`, and `APIClient` are `@Observable` models injected via `.environment()`.  
**Evidence:**
- `HomeLibrary.swift:28`:
  ```swift
  final class HomeLibrary: ObservableObject {
      @Published private(set) var homes: [HomeSummary] = []
      @Published private(set) var loadError: String?
  ```
- `ContentView.swift:23-25, 74-76`:
  ```swift
  @StateObject private var library: HomeLibrary
  @State private var readiness: ReadinessStore
  @State private var router = AppRouter()
  ...
  .environmentObject(library)
  .environment(readiness)
  .environment(router)
  ```
**Expected behavior:** Unified state management utilizing Swift 5.9+ `@Observable` macro consistently across all store and repository facades.  
**Root cause:** Incremental adoption of the `@Observable` macro without refactoring older persistence facades (`HomeLibrary`).  
**Impact:** Developer friction; requirement to use both `@EnvironmentObject` and `@Environment`; minor runtime overhead maintaining Combine publisher machinery.  
**Recommended improvement:** Migrate `HomeLibrary` from `ObservableObject` to `@Observable`.  
**Dependencies:** `HomeLibrary`, `ContentView`, `HomeScreen`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small  

---

## 7. Positive Findings

1. **Robust Reducer Invariants in `HomeModelStore`:** The core editor reducer (`escape_plan/Editor/Core/HomeModelStore.swift:1-45`) guarantees that a store initialized with a valid model can never transition to an invalid model. Mutations are executed against deep copies, validated via `EditorValidation.validate()`, and committed only if zero errors occur.
2. **Deterministic and Hermetic Testability:** The pure Foundation editor core compiles cleanly on macOS without UIKit/SceneKit dependencies. 656 unit tests run hermetically under `swift test` in under 5 seconds, providing fast regression feedback.
3. **Immutability and Schema Fidelity:** Models in `escape_plan/Models/` (`HomeModel`, `Geometry`, `RoutePlan`, `ScoreModels`) are pure Codable structs mirroring JSON schemas and backend Python models exactly, with zero UI framework contamination.
4. **Crash Resilience and Graceful Fallback:** `HomeDocumentStore.launchStore()` (`escape_plan/escape_planApp.swift:51-55`) gracefully traps file system errors, providing an in-memory fallback store and presenting a permanent non-intrusive warning banner instead of crashing on launch if the Documents directory is inaccessible.
5. **Clear Disclaimer Enforcements:** Simulation playback (`HouseScreen.swift:843-870`) strictly enforces illustrative disclaimers floating above the 3D scene, explicitly preventing users from misinterpreting assumed-speed geometric visualizations as predictive survival guarantees.

---

## 8. Systemic Issues and Root Causes

1. **Absence of a Formal Presentation/ViewModel Architecture:** SwiftUI view structs were treated as catch-all containers for view hierarchy, asynchronous network coordination, disk synchronization, and SceneKit animation loops. The lack of an intermediate ViewModel layer led directly to the creation of oversized files (`HouseScreen` at 2,875 lines, `HomeScreen` at 806 lines).
2. **Incomplete Subsystem Decommissioning:** When cloud synchronization and user authentication were removed from the product scope on 2026-10-02, the engineering team trimmed UI access points but retained the complete service and repository graph in the launch path.
3. **Bespoke Build Workarounds over Modular Architecture:** The lack of iOS simulator runtimes on CI/dev machines drove the creation of the `tools/editorcore` symlink harness. While ingenious, it created an unnatural dual-module structure that complicates dependency boundaries.

---

## 9. Unverified Assumptions

1. **Simulator Execution of Non-EditorCore Tests:** It is assumed that the 39 test suites in `escape_planTests/` (outside `EditorCore/`) pass when executed in an Xcode environment with a valid iOS 27 simulator runtime. This could not be verified in this environment due to missing simulator runtime profiles.
2. **Memory Footprint of Dual HouseScreen Mounting:** It is assumed that opening "Build Manually" from `HomeScreen` instantiates a second SCNView that noticeably increases memory pressure, though instrumented leak profiling was not conducted.

---

## 10. Areas Requiring Further Investigation

1. **SceneKit Memory Lifecycle in `EditorSceneView`:** Investigate whether rapid floor switching or frequent view rebuilding leads to leaked `SCNNode` or `SCNGeometry` allocations over extended editing sessions.
2. **LiDAR RoomPlan USDZ Export Footprint:** Evaluate temporary disk usage during RoomPlan capture and confirm that `ScanStore.sweepStaleScansInBackground()` properly purges large binary assets under low-storage conditions.
3. **Backend Network Timeout Behavior:** Evaluate how `APIClient` behaves during severe latency on cold-start Render backend instances (e.g. 50-second timeouts during `/score` or `/evacuate` requests).

---

## 11. Recommended Priorities

| Priority | Action Item | Target Files | Estimated Effort |
|---|---|---|---|
| **P1** | **Refactor `HouseScreen.swift`:** Extract `HouseScreenViewModel` to own `EditorSession`, network tasks, debouncing, and SceneKit coordination. Decompose view body into modular subviews. | `escape_plan/Screens/HouseScreen.swift` | Large |
| **P2** | **Fix Dual Mounting Defect:** Route `HomeScreen`'s "Build Manually" directly through `AppRouter.openHouse(homeID: nil)` to prevent duplicate active editor instances. | `escape_plan/Screens/HomeScreen.swift` | Small |
| **P3** | **Isolate Evacuation Playback Ticks:** Decouple `PlaybackClock` and `playback.tick()` observation from `HouseScreen`'s root body to eliminate 60Hz full-view invalidations. | `escape_plan/Screens/HouseScreen.swift` | Medium |
| **P4** | **Decommission Zombie Auth & Sync Infrastructure:** Prune `AuthSession`, `SyncManager`, and `HomeDocumentSyncRepository` from `escape_planApp.init()` and delete unreachable auth views. | `escape_plan/escape_planApp.swift`<br>`escape_plan/RootView.swift` | Medium |
| **P5** | **Replace Objective-C Associated Objects:** Explicitly declare `EvacuationPlaybackCoordinator` retention on `UnifiedSceneController` or introduce a composite wrapper. | `escape_plan/Renderer/Evacuation/UnifiedSceneController+Evacuation.swift` | Small |
| **P6** | **Unify Observation Framework:** Migrate `HomeLibrary` from `ObservableObject` to `@Observable` to eliminate mixed state management paradigms. | `escape_plan/Persistence/HomeLibrary.swift`<br>`escape_plan/ContentView.swift` | Small |
| **P7** | **Formalize SwiftPM Module Structure:** Convert `EditorCore` into a first-class local Swift Package consumed directly by Xcode, eliminating brittle filesystem symlinks. | `tools/editorcore/Package.swift` | Medium |

---

## 12. Architectural Verdict

**Does the architecture fit current size and expected evolution?**

- **Current Size (~36k LoC Swift):** **Conditionally Acceptable.** The application's core domain (`HomeModelStore`, `EditAction`, `EditorValidation`, models, persistence) is exceptionally strong, well-tested, and resilient. However, the presentation layer—anchored by `HouseScreen` at 2,875 lines—has reached its architectural scaling limit. The presence of manual reference-box hacks, 60Hz view invalidation cascades, and defensive re-render checks demonstrates that the presentation architecture is actively straining against SwiftUI's declarative paradigm.
- **Expected Evolution (Multi-peril routing, advanced simulations, multi-story enhancements):** **Needs Structural Intervention.** Attempting to add earthquake evacuation or severe weather planning directly into the current `HouseScreen` architecture will result in severe instability. Decomposing `HouseScreen` into an MVVM/Coordinator pattern (P1) and removing dead cloud/auth baggage (P4) are critical prerequisites for future feature development.
