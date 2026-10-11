# Audit Report: Notifications, Background Work & Periodic Re-Checking

**Domain:** Notifications, Background Tasks, App Refresh, Periodic Re-checking, and Lifecycle Work  
**Target File:** `audit/2026-10-11_comprehensive/09_NOTIFICATIONS_BACKGROUND_WORK.md`  
**Repository Root:** `/Users/anish/Documents/Congressional App Challenge/Escape-Plan`  
**Audit Date:** 2026-10-11  
**Auditor:** Agent 9  

---

## 1. Executive Summary

This audit assesses the implementation, configuration, and architectural guarantees surrounding notifications (local and remote/APNs), background execution (`BGTaskScheduler`, background modes, Background App Refresh), system integrations (Live Activities, widgets, Siri/Shortcuts), scheduled reminders (alarm tests, readiness re-scan freshness, monthly smoke alarm tests), and background data handling (`URLSession` configurations, task expiration, and lifecycle persistence).

### Key Architectural Realities

1. **Complete Absence of Push Notifications & Background Modes:**
   The application target (`escape_plan`) contains **no entitlements file**, has no `aps-environment` entitlement, and configures no `UIBackgroundModes` in `escape_plan.xcodeproj/project.pbxproj`. It does not register for remote notifications (`UIApplication.shared.registerForRemoteNotifications()`), nor does it configure `BGTaskScheduler`, `BGAppRefreshTask`, `BGProcessingTask`, Background App Refresh, WidgetKit, ActivityKit (Live Activities), or AppIntents/SiriKit.

2. **Deletion of Scheduled Reminders in Demo Trim 2:**
   The repository historically implemented a corpus-cited local notification reminder system (`PracticeReminderScheduler.swift` in commit `6fd6220`, using `UNUserNotificationCenter` and `UNCalendarNotificationTrigger`) that scheduled twice-a-year fire drill notifications (`"practice-reminder.\(homeID)"`). However, on **2026-10-03 (commit `3038b44`, Demo Trim 2)**, this entire subsystem—along with the legacy practice log and AR drill walk—was intentionally deleted from the codebase.

3. **Current Role of `UNUserNotificationCenter`:**
   The framework `UserNotifications` is imported in exactly one file in the current codebase: `escape_plan/RootView.swift:10`. Its sole function is an asynchronous launch cleanup task (`RootView.swift:29-34`) that queries `pendingNotificationRequests()` and cancels orphaned `practice-reminder.*` notifications left on devices from pre-trim builds. It never requests user authorization (`requestAuthorization(options:)`), schedules no new notifications, and never issues alerts.

4. **Periodic Re-Checking is Exclusively In-App:**
   Periodic safety re-checking is conducted strictly through in-app UI cards and calculated status indicators:
   - **Floor Plan Freshness:** Evaluated locally via `ScanFreshness.swift` and persisted in `UserDefaults` via `ScanFreshnessStore.swift`. A home is flagged as requiring a re-scan if its scan age exceeds 180 days (`staleThresholdDays`) or if wall polygon counts changed since the last scan (`wallsChanged`). This surfaces as status text on `HomeScreen` and an in-app banner with a "Scan now" button on `TasksScreen`.
   - **Fire Drill Practice:** The server `/score` endpoint issues a recurring checklist item `practice.drill_recent` with `recurrence_days = 183` (~6 months). When marked done, `ScoreModels.swift` calculates a passive label (e.g. `"Done 3 months ago · due in 3 months"` or `"Done 7 months ago · due again now"`). A lapsed drill is non-punitive (`scoring = false`).
   - **Monthly Smoke Alarm Testing:** The checklist item `alarm.test_monthly` ("Test every smoke alarm this month") was converted on 2026-10-05 from a recurring 30-day item to a one-time non-recurring checkbox (`FORMERLY_RECURRING_IDS`). Once marked done, it never re-opens, never lapses, and never reminds the user in future months.

5. **Background Task & Network Execution Limitations:**
   - Scan pruning (`ScanStore.sweepStaleScansInBackground()`) runs as an unmonitored Swift concurrency task (`Task.detached(priority: .utility)`) at launch rather than through an iOS background processing task.
   - Network requests with extended timeouts (60–90 seconds for `/routes`, `/evacuate`, `/convert`, `/score`, `/chat`) run on standard foreground `URLSession` configurations (`.shared` or `.ephemeral`) without wrapping in `UIApplication.shared.beginBackgroundTask(withName:expirationHandler:)`. If the app is backgrounded during heavy operations, iOS suspension may stall or abort the requests.
   - Conversation history is saved synchronously when `scenePhase == .background` in `AssistantScreen.swift`, but the 3D editor in `HouseScreen.swift` does not listen to `scenePhase`.

---

## 2. Scope and Files Inspected

The audit inspected all configuration files, build settings, source files, and test suites related to background execution, notifications, reminders, lifecycle, and periodic re-checking across the repository:

### Project Configuration & Build Settings
- [`escape_plan.xcodeproj/project.pbxproj`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan.xcodeproj/project.pbxproj): Inspected all targets (`escape_plan`, `escape_planTests`, `escape_planUITests`), build configurations (`Debug`, `Release`), `INFOPLIST_KEY_*` settings, entitlements references (`CODE_SIGN_ENTITLEMENTS`), and framework linkages.

### Application Entry Point & Lifecycle
- [`escape_plan/escape_planApp.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/escape_planApp.swift#L1-L186): Verified application entry point `@main`, absence of `UIApplicationDelegateAdaptor`, launch routines (`ScanStore.sweepStaleScansInBackground()`), and dependency graph initialization.
- [`escape_plan/RootView.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/RootView.swift#L1-L50): Detailed inspection of `UNUserNotificationCenter` pending notification cancellation and legacy sign-out tasks.

### Periodic Re-Checking & Readiness Freshness
- [`escape_plan/Readiness/ScanFreshness.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/ScanFreshness.swift#L1-L104): Core business logic for scan age (`daysSince`, `staleThresholdDays = 180`), wall polygon edge counting (`wallEdgeCount`), structural edit detection (`wallsChanged`), and resident-maintained nudge copy.
- [`escape_plan/Readiness/ScanFreshnessStore.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/ScanFreshnessStore.swift#L1-L34): UserDefaults persistence wrapper for baseline room polygon edge counts (`readiness.wallEdgeCount.<homeID>`).
- [`escape_plan/Readiness/ActiveHomeMemory.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/ActiveHomeMemory.swift#L1-L36): Active home selection persistence across app launches.
- [`escape_plan/Screens/ReadinessStore.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift#L1-L490): In-memory store binding `ScanFreshnessStore`, evaluating `nudgeReason`, and routing checklist tasks (`TaskDestination`).

### User Interface & Nudge Presentation
- [`escape_plan/Screens/HomeScreen.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HomeScreen.swift#L240-L275): Scan age summary rendering (`ScanFreshness.scanAgeText`), scan import background cleanup invocation (`discardImportedScanInBackground`).
- [`escape_plan/Screens/TasksScreen.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/TasksScreen.swift#L37-L45): In-app banner presentation for layout changes (`nudgeReason == .wallsEdited`) and outdated scans (`nudgeReason == .stale`).
- [`escape_plan/Screens/HouseScreen.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L804-L831): Playback clock timeline behavior across backgrounding/resuming (`PlaybackClock.maxFrameDelta_s = 0.1`).
- [`escape_plan/Screens/AssistantScreen.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/AssistantScreen.swift#L110-L116): Scene phase tracking (`.onChange(of: scenePhase)`) and conversation persistence on `.background`.

### Network & File Cleanup
- [`escape_plan/Capture/Export/ScanCleanup.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Capture/Export/ScanCleanup.swift#L1-L130): Launch-time scan folder pruning (`sweepStaleScansInBackground`), post-conversion folder deletion (`discardImportedScanInBackground`), and retention policies (`ScanRetention.staleAge = 7 days`).
- [`escape_plan/Networking/APIClient.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient.swift#L57-L125) and extensions (`+Routes.swift`, `+Convert.swift`, `+Evacuate.swift`, `+Score.swift`, `+Chat.swift`): `URLSession.shared` configuration and timeout values (60s–90s).
- [`escape_plan/Auth/AuthClient.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Auth/AuthClient.swift#L56-L63): `URLSessionConfiguration.ephemeral` session factory.
- [`escape_plan/Sync/CloudHomesClient.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/CloudHomesClient.swift#L30-L36) & [`SyncManager.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/SyncManager.swift#L1-L100): Cloud sync state machine (switched off).

### Scoring Models & Backend Checklist Engine
- [`escape_plan/Models/ScoreModels.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Models/ScoreModels.swift#L205-L303): `ChecklistItem` recurrence model, retirement of recurring alarm tests (`formerlyRecurringIDs`), and recurrence label formatting (`recurrenceLabel`).
- [`backend/app/scoring/checklist.py`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/scoring/checklist.py#L60-L342): Backend checklist generator, `_is_done` evaluation, timestamp parsing (`parse_completion_time`), `alarm.test_monthly`, `practice.drill_recent`, and `rescan.home`.

### Authoritative Corpus & Documentation
- [`backend/corpus/smoke-alarms-usfa.md`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/smoke-alarms-usfa.md#L1-L41): USFA guidance on monthly testing and 10-year replacement.
- [`backend/corpus/escape-planning-nfpa.md`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/escape-planning-nfpa.md#L1-L65): NFPA guidance on twice-a-year escape drills.
- [`docs/decisions.md`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/docs/decisions.md#L60-L100): Decisions log for Demo Trim 1 (2026-10-02) and Demo Trim 2 (2026-10-03).
- [`docs/tracker/BLOCKERS.md`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/docs/tracker/BLOCKERS.md#L780-L804): Trim 2 tracker notes.
- [`docs/tools-used.md`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/docs/tools-used.md#L53): Recorded usage disclosure for `UserNotifications`.

### Automated Test Suites
- [`escape_planTests/ScanExportTests.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_planTests/ScanExportTests.swift#L270-L330): Unit tests for `ScanStore.sweepStaleScans` and directory pruning.
- [`tools/editorcore/Tests/EditorCoreTests/Shared/ReadinessScanFreshnessTests.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/tools/editorcore/Tests/EditorCoreTests/Shared/ReadinessScanFreshnessTests.swift#L1-L105): Unit tests for `ScanFreshness`.
- [`tools/editorcore/Tests/EditorCoreTests/Shared/ReadinessScanFreshnessStoreTests.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/tools/editorcore/Tests/EditorCoreTests/Shared/ReadinessScanFreshnessStoreTests.swift#L1-L65): Unit tests for `ScanFreshnessStore`.
- [`backend/tests/test_scoring.py`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/tests/test_scoring.py#L90-L180): Backend tests for checklist items and score calculations.

---

## 3. Methods and Checks Performed

1. **Entitlements and Build Settings Audit:**
   Inspected Xcode project file `escape_plan.xcodeproj/project.pbxproj` for target definitions, `CODE_SIGN_ENTITLEMENTS`, `GENERATE_INFOPLIST_FILE`, `INFOPLIST_KEY_*`, and `UIBackgroundModes`.
2. **Framework & Symbol Search:**
   Conducted repository-wide searches for system symbols: `UNUserNotificationCenter`, `UNCalendarNotificationTrigger`, `BGTaskScheduler`, `BGAppRefreshTask`, `BGProcessingTask`, `UIBackgroundModes`, `aps-environment`, `WidgetKit`, `ActivityKit`, `AppIntents`, `INIntent`, `UIApplication.shared.beginBackgroundTask`, and `URLSessionConfiguration.background`.
3. **Git History Reconstruction:**
   Traced commits `6fd6220` (introduction of `PracticeReminderScheduler`), `022b65e` (Demo Trim 1), and `3038b44` (Demo Trim 2) to evaluate the exact changes made when removing notifications and practice logs.
4. **Lifecycle and Suspension Analysis:**
   Audited scene phase handling (`scenePhase`), application state transitions, timer mechanisms (`PlaybackClock`), and persistence guarantees across backgrounding.
5. **Authoritative Standard Cross-Verification:**
   Cross-referenced app copy, checklist details, and corpus documentation against authoritative fire-safety guidance from USFA, FEMA, NFPA, and the American Red Cross using live web verification on 2026-10-11.
6. **Delivery Guarantee & Copy Review:**
   Screened all user-facing strings across SwiftUI views, localizations, and backend JSON models to ensure no text implies guaranteed delivery or promises push notifications.

---

## 4. Findings (with Evidence)

### 09-01 [MEDIUM] Residual Pending Notification Cancellation Omits Delivered Notifications
**Domain:** Notifications / UNUserNotificationCenter  
**Location:** [`escape_plan/RootView.swift:29-34`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/RootView.swift#L29-L34) / Lifecycle Task  
**Observed behavior:**  
When the app launches, `RootView.swift` inspects `UNUserNotificationCenter` for pending requests with prefix `practice-reminder.` and removes them using `removePendingNotificationRequests(withIdentifiers:)`. However, it does not call `removeDeliveredNotifications(withIdentifiers:)` or `removeAllDeliveredNotifications()`.  
**Evidence:**  
In [`escape_plan/RootView.swift:29-34`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/RootView.swift#L29-L34):
```swift
// Same idea for the practice reminders cut in trim 2 (2026-10-03): a phone that
// scheduled one in an earlier build would keep getting it, with no screen left to
// turn it off. Their ids were `practice-reminder.<home id>`.
let center = UNUserNotificationCenter.current()
let stale = await center.pendingNotificationRequests()
    .map(\.identifier)
    .filter { $0.hasPrefix("practice-reminder.") }
if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
```
**Expected behavior:**  
Defensive cleanup designed to eradicate orphaned notifications from previous app builds should clean both *pending* requests (triggers that have not yet fired) and *delivered* notifications (banners already posted to the iOS Notification Center or Lock Screen). If a user launched an older build, scheduled a reminder, and the date arrived while the app was closed, the banner remains visible in Notification Center until manually dismissed.  
**Root cause:**  
The cleanup routine only queries `pendingNotificationRequests()` and omits `deliveredNotifications()` / `removeDeliveredNotifications(withIdentifiers:)`.  
**Impact:**  
Low-to-medium user confusion: A user upgrading or testing across builds could see a lingering "Time to practise your fire drill" notification banner in their lock screen history, but upon tapping it, find that the practice drill and reminder settings no longer exist in the app.  
**Recommended improvement:**  
Expand the cleanup task to also remove delivered notifications:
```swift
let deliveredStale = await center.deliveredNotifications()
    .map(\.request.identifier)
    .filter { $0.hasPrefix("practice-reminder.") }
if !deliveredStale.isEmpty {
    center.removeDeliveredNotifications(withIdentifiers: deliveredStale)
}
```
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small (~5 lines in `RootView.swift`).  

---

### 09-02 [MEDIUM] Stale Corpus Documentation Promises Reminder Features Cut From App
**Domain:** Documentation / Safety Grounding & Claims  
**Location:** [`backend/corpus/escape-planning-nfpa.md:64`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/escape-planning-nfpa.md#L64), [`backend/corpus/smoke-alarms-usfa.md:40`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/smoke-alarms-usfa.md#L40)  
**Observed behavior:**  
The corpus markdown documents claim the app provides twice-a-year practice drill reminders and monthly smoke alarm test reminders. In reality, both notification systems were removed or eliminated from recurrence.  
**Evidence:**  
In [`backend/corpus/escape-planning-nfpa.md:62-65`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/escape-planning-nfpa.md#L62-L65):
```markdown
## Implications for the app (editorial note, not safety guidance)

These principles are the basis for the app's core features: primary + secondary route computation per room ("two ways out"), the meeting-point setting, the practice/drill mode with twice-a-year reminders, and profile-aware planning for household members with disabilities.
```
In [`backend/corpus/smoke-alarms-usfa.md:38-41`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/smoke-alarms-usfa.md#L38-L41):
```markdown
## How the app uses this (editorial note)

Checklist items generated from this doc: alarm in each `bedroom`-type room, alarm in halls adjacent to bedrooms, at least one alarm per floor, monthly test reminder, 10-year replacement reminder.
```
**Expected behavior:**  
Internal corpus files that document how safety standards map to the application must reflect actual software capabilities. The app does not provide twice-a-year reminders (cut 2026-10-03 in Trim 2) or monthly test reminders (the task does not recur and never issues reminders).  
**Root cause:**  
When features were trimmed in Demo Trim 2 and S11.35, app code was updated, but the editorial sections of the corpus markdown files were not synchronized.  
**Impact:**  
Auditors and judges reviewing the repository documentation against the codebase will identify a discrepancy between the claims in `backend/corpus/` and the actual SwiftUI app behavior.  
**Recommended improvement:**  
Update the editorial sections in `escape-planning-nfpa.md` and `smoke-alarms-usfa.md` to clarify that reminders were replaced with in-app checklist items and freshness indicators, rather than active OS-level reminders.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small.  

---

### 09-03 [MEDIUM] "Test Smoke Alarm This Month" Checklist Item Does Not Recur or Prompt Subsequent Monthly Tests
**Domain:** Scheduled Reminders / Periodic Safety Re-checking  
**Location:** [`backend/app/scoring/checklist.py:277-280`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/scoring/checklist.py#L277-L280), [`escape_plan/Models/ScoreModels.swift:207-226`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Models/ScoreModels.swift#L207-L226)  
**Observed behavior:**  
The checklist item `alarm.test_monthly` carries the title `"Test every smoke alarm this month"` and detail `"Press the test button on every alarm once a month."` (cited to USFA: `usfa-smoke-alarms`). However, on 2026-10-05, recurrence was removed (`recurrence_days=None`). Once checked, it is permanently marked as completed and never re-opens, never reminds the user in subsequent months, and never prompts for a re-test.  
**Evidence:**  
In [`escape_plan/Models/ScoreModels.swift:207-214`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Models/ScoreModels.swift#L207-L214):
```swift
// MARK: - Items that stopped recurring (owner, 2026-10-05)

extension ChecklistItem {
    /// Items that recurred from S11.34 until the owner made them one-time ticks on 2026-10-05:
    /// the monthly alarm test is ticked once and stays done, never lapses and never lowers the
    /// score. Its cited text still says to test monthly. Mirrors `FORMERLY_RECURRING_IDS` in
    /// `backend/app/scoring/checklist.py`; the recurring items left are the drill and the rescan.
    static let formerlyRecurringIDs: Set<String> = ["alarm.test_monthly"]
```
In [`backend/app/scoring/checklist.py:276-280`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/scoring/checklist.py#L276-L280):
```python
    add(
        "alarm.test_monthly",
        "Test every smoke alarm this month",
        "Press the test button on every alarm once a month.",
    )
```
Notice `recurrence_days` is omitted (defaults to `None`).  
**Expected behavior:**  
According to USFA guidance (*"Test every smoke alarm at least once a month using the test button"* [USFA, 2026-10-11: https://www.usfa.fema.gov/prevention/home-fires/prevent-fires/smoke-alarms/]), smoke alarm testing is inherently an ongoing periodic responsibility. If the item does not recur or prompt in subsequent months, the app's preparedness score will consider the household's smoke alarms tested in perpetuity after a single button press on day one.  
**Root cause:**  
The owner decided on 2026-10-05 that a recurring monthly alarm test that lapsed and reduced the user's score was annoying for a demo and created score volatility. However, removing recurrence completely detached the item from the USFA standard's monthly maintenance intent.  
**Impact:**  
Safety compromise: Users who rely on the checklist for safety guidance will see "Test every smoke alarm this month" marked green with a checkmark forever, giving the false impression that monthly smoke alarm testing is complete for the life of the home.  
**Recommended improvement:**  
Follow the same pattern used for `practice.drill_recent` and `rescan.home`: keep recurrence at 30 days (`recurrence_days = 30`), display `"Done X days ago · due in Y days"`, but make it non-punitive (`scoring = false`) so that a lapsed test flags an in-app notice without lowering the user's numeric score. Alternatively, if kept as a one-time tick, rephrase the title to `"Establish monthly smoke alarm testing routine"` so it accurately reflects a habit commitment rather than a specific month's test.  
**Dependencies:** Requires coordinate changes in `backend/app/scoring/checklist.py` and `escape_plan/Models/ScoreModels.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small.  

---

### 09-04 [LOW] Long-Running Network Operations Lack Background Task Assertions (`beginBackgroundTask`)
**Domain:** Background Work / URLSession & App Lifecycle  
**Location:** [`escape_plan/Networking/APIClient.swift:121`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient.swift#L121), [`escape_plan/Networking/APIClient+Routes.swift:24`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Routes.swift#L24), [`escape_plan/Networking/APIClient+Convert.swift:34`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Convert.swift#L34), [`escape_plan/Networking/APIClient+Evacuate.swift:55`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Evacuate.swift#L55)  
**Observed behavior:**  
Asynchronous network calls for heavy server operations (`/convert` for raw RoomPlan JSON/USDZ conversion, `/routes` for multi-person routing, `/evacuate` for fire spread simulation, and `/chat` for Claude-backed assistant queries) have request timeouts configured up to 90 seconds. These run on standard `URLSession.shared` without acquiring background execution time via `UIApplication.shared.beginBackgroundTask(withName:expirationHandler:)`.  
**Evidence:**  
In [`escape_plan/Networking/APIClient.swift:121`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient.swift#L121):
```swift
    init(baseURL: URL = APIClient.currentBaseURL(),
         session: URLSession = .shared,
         tokenProvider: @escaping @MainActor () -> String? = { APIClient.configuredSharedToken }) {
```
In [`escape_plan/Networking/APIClient+Routes.swift:24`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Routes.swift#L24):
```swift
        // Render free-tier cold starts take up to 50 s; 90 s ensures the cold start comfortably
        // exceeds URLSession's 60 s default.
        var request = URLRequest(url: url, timeoutInterval: 90)
```
**Expected behavior:**  
On iOS, when an app moves from the foreground to the background, suspended execution can occur within seconds (typically 5 seconds on iOS 17+). In-flight HTTP operations on standard sessions that are not protected by a background task assertion can be throttled, suspended, or terminated with `URLError.networkConnectionLost` or `URLError.cancelled`.  
**Root cause:**  
The network client relies solely on foreground UI execution and does not manage OS process lifecycle assertions.  
**Impact:**  
If a user initiates a RoomPlan scan import (`/convert`) or starts an evacuation drill calculation (`/evacuate`) and locks their iPhone or switches to another app (e.g. Messages), the upload/download task may stall or fail, requiring the user to restart the conversion or calculation when returning to the app.  
**Recommended improvement:**  
Wrap long-running tasks in `UIApplication.shared.beginBackgroundTask(withName:expirationHandler:)` to ensure the operating system grants up to 30 seconds of additional runtime to complete the network round-trip when transitioning to the background.  
**Dependencies:** UIKit integration.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small.  

---

### 09-05 [OBSERVATION] Residual Notification Cleanup in `RootView.swift` Has Zero Test Coverage
**Domain:** Notifications / Test Verification  
**Location:** [`escape_plan/RootView.swift:29-34`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/RootView.swift#L29-L34), [`docs/tracker/BLOCKERS.md:793-795`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/docs/tracker/BLOCKERS.md#L793-L795)  
**Observed behavior:**  
The startup cleanup code in `RootView.swift` that queries and removes stale `practice-reminder.*` notifications has no automated unit or UI test coverage in `escape_planTests` or `escape_planUITests`.  
**Evidence:**  
Searching `escape_planTests/` and `escape_planUITests/` for `UNUserNotificationCenter` or `pendingNotificationRequests` yields zero test assertions. Furthermore, in [`docs/tracker/BLOCKERS.md:793-795`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/docs/tracker/BLOCKERS.md#L793-L795):
```markdown
- [ ] **Leftover practice reminders from earlier builds are removed at launch** (`RootView`, ids `practice-reminder.*`),
      but this was never watched with a real leftover reminder. Next action: S11.10, on a phone that had one, confirm it
      is gone after launching this build.
```
**Expected behavior:**  
Defensive cleanup logic added to handle post-migration state should ideally be backed by a mockable notification center protocol or verified on a physical device.  
**Root cause:**  
`UNUserNotificationCenter` is a singleton with concrete system dependencies, and when `PracticeNotificationScheduling` was deleted in Demo Trim 2 (`3038b44`), the protocol and mock test fixtures were deleted along with it.  
**Impact:**  
Low: The cleanup logic is straightforward and low-risk, but remains officially unverified at runtime.  
**Recommended improvement:**  
Perform the verification step noted in `BLOCKERS.md` on a physical device or simulator with a seeded notification request.  
**Dependencies:** Requires physical test device.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small.  

---

### 09-06 [OBSERVATION] Architecture Completely Omits Push Notifications, Background Refresh, Widgets, and Siri
**Domain:** Architecture / Background Execution Modes  
**Location:** [`escape_plan.xcodeproj/project.pbxproj`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan.xcodeproj/project.pbxproj)  
**Observed behavior:**  
The app architecture deliberately contains zero background modes (`UIBackgroundModes`), zero APNs configuration (`aps-environment`), zero Background App Refresh implementations, zero WidgetKit widgets, zero Live Activities (`ActivityKit`), and zero Siri/Shortcuts (`AppIntents`). All features operate strictly while the app is in the foreground.  
**Evidence:**  
In [`escape_plan.xcodeproj/project.pbxproj`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan.xcodeproj/project.pbxproj):
The project defines `GENERATE_INFOPLIST_FILE = YES` with keys:
- `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES`
- `INFOPLIST_KEY_NSCameraUsageDescription = ...`
- `INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES`
- `INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES`
- `INFOPLIST_KEY_UIFileSharingEnabled = YES`
- `INFOPLIST_KEY_UILaunchScreen_BackgroundColor = LaunchBackground`
- `INFOPLIST_KEY_UILaunchScreen_Generation = YES`
No `UIBackgroundModes` key is defined. No `.entitlements` file exists in the repository.  
**Expected behavior:**  
Architectural choice matches the project's "local-first, privacy-respecting emergency prevention app" charter. The app does not claim to track users in real-time, does not run background sensors, and requires no push server infrastructure.  
**Root cause:**  
Deliberate scope definition: emergency escape planning and readiness education require zero background location tracking or server-driven push updates.  
**Impact:**  
Positive for battery efficiency, data privacy, and simplicity. Neutral for user experience, provided users open the app periodically to review readiness.  
**Recommended improvement:**  
Document explicitly in `docs/capabilities.md` that Escape Plan is fully foreground-driven and requires no background modes or push permissions.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** None.  

---

## 5. Positive Findings

1. **Strict Honesty Regarding Delivery Guarantees:**  
   The application never implies guaranteed delivery, background alarms, or automated sirens. Re-scan nudges prominently and explicitly state: *"This plan is resident-maintained, not verified: a re-scan keeps it accurate"* ([`ScanFreshness.swift:96-100`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/ScanFreshness.swift#L96-L100)).
2. **Deterministic, Tested In-App Freshness Engine:**  
   The `ScanFreshness` system ([`ScanFreshness.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/ScanFreshness.swift)) provides a grounded, dual-trigger mechanism to detect staleness:
   - Calendar duration (180 days based on `meta.last_scanned` with `modified` fallback).
   - Structural geometry shifts (`wallEdgeCount` summed over all room polygons compared against the baseline stored in `ScanFreshnessStore`).
   Both components have dedicated, unit tests ([`ReadinessScanFreshnessTests.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/tools/editorcore/Tests/EditorCoreTests/Shared/ReadinessScanFreshnessTests.swift) and [`ReadinessScanFreshnessStoreTests.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/tools/editorcore/Tests/EditorCoreTests/Shared/ReadinessScanFreshnessStoreTests.swift)).
3. **Defensive Orphan Cleanup at Launch:**  
   Recognizing that earlier internal test builds scheduled `practice-reminder.*` notifications, the team implemented a defensive cleanup hook in `RootView.swift:29-34` that runs at startup to cancel orphaned pending requests without prompting the user for permissions.
4. **Resilient Timeline Capping on App Resume:**  
   In [`HouseScreen.swift:808-826`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L808-L826), the `PlaybackClock` drives the 3D fire simulation using `TimelineView(.animation)` and explicitly caps elapsed frame delta to `0.1s` (`maxFrameDelta_s`). This prevents the SceneKit simulation from violently jumping forward or skipping the evacuation animation when returning from the background.
5. **Zero Background Battery or Network Overhead:**  
   By abstaining from background location updates, background app refresh, and silent push notifications, the app consumes zero energy when suspended and creates no privacy liabilities.

---

## 6. Systemic Issues and Root Causes

1. **Feature Trimming Documentation Lag:**  
   When features were cut in Demo Trim 1 (2026-10-02) and Demo Trim 2 (2026-10-03), source code and test files were deleted rapidly (`git rm` of 73 tests and multiple files in commit `3038b44`). However, editorial sections in `backend/corpus/` (`escape-planning-nfpa.md` and `smoke-alarms-usfa.md`) were left untouched, creating documentation drift where the corpus continues to claim the app provides reminder features that no longer exist.
2. **Absence of Unified Background Task Abstraction:**  
   Background work across the app is handled ad-hoc: `ScanCleanup` uses detached Swift tasks (`Task.detached`), `AssistantScreen` uses SwiftUI scene phase `.onChange(of: scenePhase)`, `HouseScreen` saves synchronously on user interaction but ignores `scenePhase`, and `APIClient` executes without background task assertions. There is no unified wrapper or lifecycle coordinator to manage OS suspension boundaries.

---

## 7. Unverified Assumptions

1. **Runtime Removal of Pre-Trim Notifications on Physical Device:**  
   *Assumption:* `center.removePendingNotificationRequests(withIdentifiers: stale)` successfully removes notifications on a device that had an older build.  
   *Status:* **Inferred but not verified** (tracked in `BLOCKERS.md:793-795`). Verification requires a physical iPhone with an older build or seeded notification request.
2. **Network Request Lifespan Upon Backgrounding:**  
   *Assumption:* In-flight `/convert` requests over cellular data or Wi-Fi are suspended by iOS within 5–10 seconds if backgrounded.  
   *Status:* **Inferred from iOS platform documentation**. Exact OS suspension timing varies based on system thermal and power conditions.

---

## 8. Areas Requiring Further Investigation

1. **Physical Device Verification for Notification Residuals:**  
   Execute the outstanding task in `BLOCKERS.md:793-795`: Deploy a build with a seeded notification request matching `practice-reminder.*`, install the current build, and verify that both pending and delivered notifications are purged.
2. **Scan Folder Cleanup Reliability Under Forced App Termination:**  
   Inspect whether `ScanStore.sweepStaleScansInBackground()` safely recovers if the application is killed by the user or OS while deleting a multi-megabyte scan folder.

---

## 9. Recommended Priorities

| Priority | Action Item | Target Location | Rationale |
|---|---|---|---|
| **P1** | Add delivered notification cleanup to `RootView.swift` | [`escape_plan/RootView.swift:33`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/RootView.swift#L33) | Ensures any previously fired reminder banners are cleared from Notification Center. |
| **P2** | Synchronize corpus markdown editorial sections with trimmed code | [`backend/corpus/escape-planning-nfpa.md:64`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/escape-planning-nfpa.md#L64), [`smoke-alarms-usfa.md:40`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/smoke-alarms-usfa.md#L40) | Eliminates audit discrepancies where documentation claims reminders that the app does not provide. |
| **P3** | Revisit monthly smoke alarm testing task recurrence vs phrasing | [`backend/app/scoring/checklist.py:277`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/scoring/checklist.py#L277) | Aligns `alarm.test_monthly` with USFA guidance (monthly routine vs one-time tick). |
| **P4** | Wrap long-running network calls in `beginBackgroundTask` | [`escape_plan/Networking/APIClient+Convert.swift`](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Convert.swift) | Protects 90-second LiDAR upload and scan conversion against premature OS suspension. |
| **P5** | Add automated test for `RootView` notification cleanup | `escape_planTests/RootViewNotificationCleanupTests.swift` | Closes open blocker item in `docs/tracker/BLOCKERS.md:793`. |
