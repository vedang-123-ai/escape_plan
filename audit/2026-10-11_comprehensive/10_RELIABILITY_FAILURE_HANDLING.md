# Reliability and Failure Handling Audit Report

**Report File:** `audit/2026-10-11_comprehensive/10_RELIABILITY_FAILURE_HANDLING.md`  
**Audit Date:** 2026-10-11  
**Target:** iOS App Reliability, Failure Modes, Network/Transport Resiliency, Stale Data Exposure, Safety Boundaries  
**Auditor:** Agent 10 (Reliability & Failure Handling Domain)  

---

## 1. Executive Summary

This audit assesses the fault tolerance, error recovery, offline behavior, and failure handling semantics across the Escape Plan iOS application (`escape_plan.xcodeproj`, ~60,000 lines of Swift across 161 files, plus SwiftPM `tools/editorcore`). Special attention is paid to network resilience, backend outages (Anthropic credit exhaustion, proxy timeouts, cold starts), offline caches, stale safety-critical data, input boundaries, concurrency, and emergency life-safety disclaimers.

### Key Conclusions:
1. **Centralized Backend Failure Architecture:** The introduction of `BackendFailure` (`Networking/BackendFailure.swift`) and `BackendFailureBanner` represents a substantial architectural improvement. Error classifications across 7 operational domains (`/routes`, `/convert`, `/score`, `/analyze`, `/chat`, `/evacuate`, `/build`) cleanly delineate between operator-dependent failures (502 `aiUnavailable`), transient infrastructure backpressure (503/429 `serverBusy`), client-side storage issues (`localData`), input rejections (413/422 `rejectedInput`), and benign task cancellations (`cancelled`).
2. **Defensive Route Cache vs. Permissive Score Cache Split:** Route caching (`APIClient+Cache.swift`, `RoutePlanCache`) is strictly governed: cached escape paths require exact match on `homeID`, `peril`, `profileID`, and a cryptographic `HomeFingerprint` of the home geometry. In sharp contrast, `ScoreCache` (`Persistence/ScoreCache.swift`) stores raw `ScoreBreakdown` objects keyed solely by `homeID` with **no model fingerprint, no timestamp, and no staleness check**.
3. **CRITICAL Vulnerability in First Responder Exports:** When generating the official firefighter export (`EscapePlanExporter.swift:115`), `writeResponderSnapshot` queries `ScoreCache` without verifying model geometry or age. Consequently, if a resident alters their floor plan (e.g., removing a smoke alarm, blocking a doorway, or remodeling rooms) while offline or before rescoring, the exported `ResponderSnapshot.pdf` and `ResponderSnapshot.json` embed stale readiness scores and outdated hazard summaries for emergency personnel.
4. **Proxy 502 Disconnect from Route Cache:** While `APIClientError.forStatus` distinguishes proxy 502s from application 502s, `APIClient.isConnectionFailure` only evaluates `URLError` codes. Consequently, if Render's edge gateway terminates an in-flight `/routes` call with a proxy 502, `fetchRoutesCached` fails to activate the offline route cache, displaying a gateway cut-off banner and clearing routes rather than gracefully serving the valid cached escape plan.
5. **Rigorous Life-Safety Disclaimers:** The application meticulously adheres to life-safety messaging boundaries. It explicitly avoids claiming to replace 911 or official emergency dispatch. Static and animated simulations feature hardcoded, non-bypassable disclaimers (`"Illustrative only... not a prediction of how a real fire would spread"`), responder snapshots embed non-removable tactical caveats (`"not a tool for use during an active emergency"`), and AI chat responses hard-code immediate 911 referral whenever unsourced safety questions arise.
6. **Robust Concurrency and Memory Guards:** Reentrancy, rapid repeated taps, and generation mismatch during asynchronous operations (`ReadinessStore.scoreGeneration`, `HouseScreen.routesTask`, `BuildFromPlanView.isBuilding`) are defensively protected via task cancellation and generational discarding.

---

## 2. Scope and Files Inspected

### Source Files Inspected (Full End-to-End Traces)
- **Networking & Error Handling Core:**
  - `escape_plan/Networking/BackendFailure.swift` (407 lines)
  - `escape_plan/Networking/APIClient.swift` (220 lines)
  - `escape_plan/Networking/APIClient+Routes.swift` (47 lines)
  - `escape_plan/Networking/APIClient+Cache.swift` (207 lines)
  - `escape_plan/Networking/APIClient+Score.swift` (32 lines)
  - `escape_plan/Networking/APIClient+Evacuate.swift` (46 lines)
  - `escape_plan/Networking/APIClient+Build.swift` (48 lines)
  - `escape_plan/Networking/APIClient+Convert.swift` (38 lines)
  - `escape_plan/Networking/APIClient+Chat.swift` (152 lines)
  - `escape_plan/Networking/ImagePreparation.swift` (156 lines)
- **Persistence & Caches:**
  - `escape_plan/Persistence/ScoreCache.swift` (37 lines)
  - `escape_plan/Persistence/HomeDocumentStore.swift` (376 lines)
  - `escape_plan/Persistence/HomeLibrary.swift` (188 lines)
  - `escape_plan/Persistence/ChecklistStateStore.swift` (89 lines)
  - `escape_plan/Persistence/ConversationStore.swift` (230 lines)
  - `escape_plan/Readiness/ScanFreshnessStore.swift` (38 lines)
  - `escape_plan/Readiness/ActiveHomeMemory.swift` (68 lines)
- **Presentation & Screen Failure Lifecycles:**
  - `escape_plan/Screens/BackendFailureBanner.swift` (207 lines)
  - `escape_plan/Screens/HouseScreen.swift` (2,876 lines)
  - `escape_plan/Screens/HomeScreen.swift` (807 lines)
  - `escape_plan/Screens/ScoreScreen.swift` (332 lines)
  - `escape_plan/Screens/TasksScreen.swift` (410 lines)
  - `escape_plan/Screens/AssistantScreen.swift` (625 lines)
  - `escape_plan/Screens/BuildFromPlanView.swift` (291 lines)
  - `escape_plan/Screens/ReadinessStore.swift` (490 lines)
  - `escape_plan/Screens/ProfilesScreen.swift` (348 lines)
  - `escape_plan/Screens/SettingsScreen.swift` (419 lines)
- **Hardware & Sensor Capture:**
  - `escape_plan/Capture/RoomCaptureController.swift` (332 lines)
  - `escape_plan/Capture/Views/ScanFlowView.swift` (423 lines)
  - `escape_plan/Capture/Views/RoomCaptureViewRepresentable.swift` (38 lines)
  - `escape_plan/Capture/Export/ScanStore.swift` (140 lines)
- **Export & Fire Department Integration:**
  - `escape_plan/Export/EscapePlanExporter.swift` (139 lines)
  - `escape_plan/Export/EscapePlanDocument.swift` (35 lines)
  - `escape_plan/Export/EscapePlanPDF.swift` (627 lines)
  - `escape_plan/Export/ExportPlanSheet.swift` (205 lines)
  - `escape_plan/Export/ResponderSnapshotExtractor.swift` (101 lines)
  - `escape_plan/Export/ResponderSnapshotJSON.swift` (110 lines)
  - `escape_plan/Export/ResponderSnapshotStore.swift` (62 lines)
- **Authentication & Cloud Synchronization:**
  - `escape_plan/Auth/AuthFailure.swift` (169 lines)
  - `escape_plan/Auth/AuthSession.swift` (389 lines)
  - `escape_plan/Auth/KeychainTokenStore.swift` (124 lines)
  - `escape_plan/Sync/SyncFailure.swift` (148 lines)
  - `escape_plan/Sync/SyncManager.swift` (533 lines)
- **Documentation & Tracking:**
  - `docs/tracker/BLOCKERS.md` (3,515 lines)
  - `docs/playbook/01-product-spec.md` (142 lines)
  - `docs/demo/claims-ledger-v2.md` (215 lines)

---

## 3. Methods and Checks Performed

1. **End-to-End Failure Flow Tracing:** Audited call sites across all 7 API endpoints, tracing from URLSession invocation through status categorization (`APIClientError`), domain translation (`BackendFailure`, `AuthFailure`, `SyncFailure`), View Model reception (`ReadinessStore`, `HouseScreen`, `BuildFromPlanView`), to UI presentation (`BackendFailureBanner`, alert states, inline warnings).
2. **Offline & Transport Degradation Testing:** Inspected fallback paths when internet connectivity is severed, DNS lookups fail, or HTTP timeouts occur. Verified offline route caching, score caching, and local checklist persistence.
3. **Outage Simulation Analysis:** Traced app behavior when Anthropic API quotas are exhausted (HTTP 502), Render servers cold start (HTTP 504 / timeouts), and edge proxies sever connections mid-stream.
4. **Data Freshness and Staleness Verification:** Analyzed cache key schemas, file modification tracking, hash fingerprinting (`HomeFingerprint`), and UI age labels across routes, preparedness scores, and checklist items.
5. **Crash-Prone Construct Code Search:** Conducted repository-wide searches for unsafe constructs (`try!`, `fatalError`, `precondition`, forced unwraps `!`, and silent `try?` catch blocks).
6. **Device Constraint & Permission Checks:** Examined device capability handling on non-LiDAR hardware, simulator environments, and camera permission denial pathways.
7. **Concurrency & Reentrancy Analysis:** Investigated async task management, debounce handlers, button disabled states, and race conditions during rapid user interactions or backgrounding.
8. **Emergency Policy & Safety Claim Verification:** Cross-referenced app text, export artifacts, and simulation canvases against NFPA, USFA, and FEMA emergency messaging guidelines.

---

## 4. Findings (with Evidence)

### [CRITICAL] A10-01: Unvalidated Stale Score and Hazard Data Exported to Fire Department Responders
**Domain:** First Responder Export / Data Freshness  
**Location:** [EscapePlanExporter.swift:115-117](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/EscapePlanExporter.swift#L115-L117), [ScoreCache.swift:17-35](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ScoreCache.swift#L17-L35), [ResponderSnapshotExtractor.swift:76-94](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/ResponderSnapshotExtractor.swift#L76-L94)  
**Observed behavior:** When preparing a Responder Snapshot (both PDF and JSON intended for local fire departments), the exporter loads the score breakdown directly from `ScoreCache` without verifying whether the home model has been altered since the score was generated, and without stamping the age of the score.  
**Evidence:**  
In `EscapePlanExporter.swift:115-117`:
```swift
if let cache = try? ScoreCache() {
    document.scoreResponse = cache.load(homeID: preview.home.id)
}
```
In `ScoreCache.swift:28-35`:
```swift
func load(homeID: String) -> ScoreBreakdown? {
    do {
        let data = try Data(contentsOf: file(for: homeID))
        return try HomeModel.decoder.decode(ScoreBreakdown.self, from: data)
    } catch {
        return nil
    }
}
```
In `ResponderSnapshotExtractor.swift:81-88`:
```swift
let hazardSummary = SnapshotHazardSummary.summarize(checklist: document.scoreResponse?.checklist ?? [])

return ResponderSnapshotJSON(
    generatedAt: now,
    asOf: home.meta.last_scanned,
    isStale: isStale,
    consent: consent,
    readinessScore: document.scoreResponse?.score,
    safeRoomName: safeRoomName,
    vulnerableOccupants: vulnerableList,
    safetyPoints: safetyPoints,
    hazards: hazards,
    hazardSummary: hazardSummary
)
```
While `RoutePlanCache` verifies `HomeFingerprint.of(home)` and refuses to serve routes if the geometry has changed, `ScoreCache` contains only a raw JSON serialization of `ScoreBreakdown`. It stores no timestamp, no home fingerprint, and no version tag. If a user deletes smoke alarms, adds blocked corridors, or significantly remodels the house, `ScoreCache` retains the pre-edit score until an online `/score` call succeeds. If the resident subsequently exports a snapshot for the fire department (e.g., during pre-incident planning or offline), the snapshot includes the obsolete preparedness score and incorrect hazard summary.  
**Expected behavior:** `ScoreCache` must store a cache metadata record containing the `homeFingerprint` and `savedAt` timestamp. If the fingerprint of the current home model does not match the cached score, `load()` must return `nil`, and the export must explicitly mark the score and hazard summary as unavailable (`readinessScore: nil`, `hazardSummary: nil`).  
**Root cause:** `ScoreCache` was implemented as a primitive key-value file store and was not updated when S11.36 introduced fingerprint-based validation to `RoutePlanCache`.  
**Impact:** Firefighters and emergency responders could receive an official tactical snapshot certifying a high safety score and absent hazards for a home that was recently modified into a high-risk layout.  
**Dependencies:** `EscapePlanExporter.swift`, `ScoreCache.swift`, `ResponderSnapshotExtractor.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.

---

### [HIGH] A10-02: Proxy 502 Errors Bypass Offline Route Cache Fallback
**Domain:** Network Resilience / Offline Degradation  
**Location:** [APIClient+Cache.swift:170-179](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Cache.swift#L170-L179), [APIClient+Cache.swift:199-204](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Cache.swift#L199-L204), [APIClient.swift:26-29](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient.swift#L26-L29)  
**Observed behavior:** When a deployed backend on Render experiences an upstream proxy timeout or edge drop, the edge proxy responds with an HTML 502. The client correctly parses this as `APIClientError.gatewayFailure(statusCode: 502)`. However, `APIClient.isConnectionFailure` only checks for `URLError`, so `fetchRoutesCached` treats `gatewayFailure` as a non-connection error, rethrows it, and fails to fall back to the cached offline route plan.  
**Evidence:**  
In `APIClient+Cache.swift:170-179`:
```swift
static func isConnectionFailure(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else { return false }
    switch urlError.code {
    case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
         .timedOut, .networkConnectionLost, .dnsLookupFailed:
        return true
    default:
        return false
    }
}
```
In `APIClient+Cache.swift:199-204`:
```swift
} catch where Self.isConnectionFailure(error) {
    if let cached = cache.load(key, homeFingerprint: fingerprint) {
        return .cached(cached)
    }
    throw error
}
```
When `error` is `APIClientError.gatewayFailure(502)`, `isConnectionFailure` returns `false`. In `HouseScreen.swift:1718`, the error is caught and translated to `BackendFailure.responseCutOff`, which shows: `"The server's answer about your escape routes was cut off on the way. Try again in a moment."` The existing valid cached route plan is discarded and the 3D scene clears all escape routes (`routePlan = nil`).  
**Expected behavior:** Transient transport failures caused by intermediate proxy terminations (`gatewayFailure`) should be recognized as connection-class failures in `isConnectionFailure`, triggering fallback to the cached route plan stamped with its saved timestamp.  
**Root cause:** `isConnectionFailure` was written before S11.50 added `APIClientError.gatewayFailure`, and the helper was not updated to include gateway cutoffs.  
**Impact:** A temporary server hiccup or edge proxy disconnect strips the resident of their displayed escape routes even when an identical, valid route plan is stored locally on the device.  
**Dependencies:** `APIClient+Cache.swift`, `APIClient.swift`, `HouseScreen.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.

---

### [HIGH] A10-03: Camera Permission Denial Generates Unhelpful Generic ARKit Failure
**Domain:** Hardware & Permissions / User Guidance  
**Location:** [RoomCaptureController.swift:84-108](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift#L84-L108), [RoomCaptureController.swift:273-278](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift#L273-L278), [ScanFlowView.swift:182-193](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Capture/Views/ScanFlowView.swift#L182-L193)  
**Observed behavior:** `RoomCaptureController` checks hardware capability (`RoomCaptureSession.isSupported`) but performs no check on camera authorization status (`AVCaptureDevice.authorizationStatus(for: .video)`). If a user denies camera access, the scanner starts the session anyway, causing ARKit to fail via delegate callback with an opaque system error string. The UI displays `"The scan couldn't be completed: [error]"` and provides a "Retry" button that fails repeatedly without directing the user to iOS Settings.  
**Evidence:**  
In `RoomCaptureController.swift:84-90`:
```swift
var isSupported: Bool {
    #if canImport(RoomPlan) && !targetEnvironment(simulator)
    return RoomCaptureSession.isSupported
    #else
    return false
    #endif
}
```
In `RoomCaptureController.swift:273-278`:
```swift
static func userFacingMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return "The scan couldn't be completed: \(error.localizedDescription)"
}
```
When `AVCaptureDevice.authorizationStatus(for: .video) == .denied`, ARKit fails asynchronously. `userFacingMessage` formats the NSError string without detecting the permission fault code. In `ScanFailureView` (`ScanFlowView.swift:356-385`), the only actions are `Retry` (which simply returns to instructions and attempts `session.run()` again) and `Cancel`. No deep link to `UIApplication.openSettingsURLString` is offered.  
**Expected behavior:** `RoomCaptureController` should check `AVCaptureDevice.authorizationStatus(for: .video)` prior to starting. If denied or restricted, `phase` should transition to a dedicated `.permissionDenied` state explaining that camera access is required, accompanied by a button to open iOS Settings.  
**Root cause:** Absence of AVFoundation authorization checks in the capture controller lifecycle.  
**Impact:** Users who accidentally tap "Don't Allow" on the camera prompt are permanently blocked from scanning and left in an uninformative retry loop.  
**Dependencies:** `AVFoundation`, `RoomCaptureController.swift`, `ScanFlowView.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.

---

### [MEDIUM] A10-04: Monolithic 3D Editor Omits ScenePhase Lifecycle Observation
**Domain:** Concurrency & App Lifecycle / Data Integrity  
**Location:** [HouseScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift), [HouseEditorSessionController.swift:141-160](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/HouseEditorSessionController.swift#L141-L160)  
**Observed behavior:** `HouseScreen` does not observe `@Environment(\.scenePhase)`. While committed editing actions are saved immediately on commit via `newStore.onCommit`, active in-progress multi-touch gestures (such as dragging a wall node, panning an opening, or repositioning furniture) remain uncommitted in ephemeral memory until touch termination. If the app is sent to the background or terminated by iOS memory pressure during an active manipulation, no teardown hook forces a commit or clean state reset.  
**Evidence:**  
In `HouseScreen.swift`, a search for `scenePhase` yields zero occurrences. In contrast, `AssistantScreen.swift:25, 113` properly captures `scenePhase` and executes backgrounding flushes:
```swift
@Environment(\.scenePhase) private var scenePhase
...
.onChange(of: scenePhase) { _, phase in
    if phase == .background { saveOnBackground() }
}
```
In `HouseScreen.swift:2305-2309`:
```swift
newStore.onCommit = { [controller] _commit in
    newSession.undoStack.recordCommit(_commit)
    autosave(newSession, controller: controller)
    invalidateRoutes()
}
```
If the user switches apps mid-gesture, the uncommitted gesture coordinate transformation is abruptly discarded upon OS termination.  
**Expected behavior:** `HouseScreen` should observe `scenePhase` and cancel or commit any active gesture arbiter interactions upon entering `.background`.  
**Root cause:** `scenePhase` was implemented in `AssistantScreen` during S11.45 but was omitted from `HouseScreen`.  
**Impact:** Low risk of silent document corruption because `HomeDocumentStore` saves atomically, but uncommitted edits in flight when an interruption occurs (phone call, app switch) are lost without notification.  
**Dependencies:** `HouseScreen.swift`, `GestureArbiter.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** Medium. **Effort:** Small.

---

### [MEDIUM] A10-05: Silent Catch-and-Ignore Swallows Persistence and Synchronization Errors
**Domain:** Error Handling Integrity / Silent Failures  
**Location:** [ScoreCache.swift:20-22](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ScoreCache.swift#L20-L22), [ProfilesScreen.swift:284-288](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ProfilesScreen.swift#L284-L288), [SyncManager.swift:497](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/SyncManager.swift#L497)  
**Observed behavior:** Critical operations catch exceptions with empty bodies or silent `try?` guards, leaving the subsystem in an inconsistent state without logging.  
**Evidence:**  
1. In `ScoreCache.swift:17-22`:
```swift
func save(_ score: ScoreBreakdown, for homeID: String) {
    do {
        let data = try HomeModel.encoder().encode(score)
        try data.write(to: file(for: homeID), options: Data.WritingOptions.atomic)
    } catch { }
}
```
Disk-full conditions, permission errors, or file system failures during cache writes are completely swallowed with an empty `catch { }`. No OSLog entry is written.  
2. In `ProfilesScreen.swift:283-288`:
```swift
private func reloadReadinessIfChanged() {
    guard changedSinceAppear, let readiness, let apiClient, let documentStore,
          readiness.activeHomeID == homeID,
          let saved = try? documentStore.load(homeID: homeID, as: HomeModel.self) else { return }
    changedSinceAppear = false
    readiness.replaceActiveHome(saved, api: apiClient)
}
```
If `documentStore.load` throws (e.g. disk corruption, schema incompatibility), `saved` is `nil`, the guard returns silently, and `ReadinessStore` continues calculating scores for the OLD household profile without notifying the user that their profile edits failed to apply.  
3. In `SyncManager.swift:497`:
```swift
try? stateStore.save(state)
```
Sync state tracking persistence is ignored with `try?`, risking desynchronization between the local sync sidecar and cloud state.  
**Expected behavior:** Throwing calls should either propagate errors to callers, record telemetry through `os.Logger`, or surface a user-visible banner via `BackendFailureBanner`.  
**Root cause:** Defensive coding shortcuts (`try?` and empty `catch`) masking system-level faults.  
**Impact:** Silent failures can leave users believing an update took effect when it was dropped, or conceal underlying storage degradation.  
**Dependencies:** `ScoreCache.swift`, `ProfilesScreen.swift`, `SyncManager.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.

---

### [MEDIUM] A10-06: 3D Scene Hazard Highlighting Utilizes Stale ScoreCache Without Geometry Check
**Domain:** Data Freshness / 3D Visualization  
**Location:** [HouseScreen.swift:2342-2354](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L2342-L2354)  
**Observed behavior:** When opening the 3D editor, `HouseScreen.applyCachedHazardEmphasis` loads hazard item IDs directly from `ScoreCache` without verifying that the cached checklist corresponds to the current state of the home.  
**Evidence:**  
In `HouseScreen.swift:2342-2354`:
```swift
private func applyCachedHazardEmphasis(for session: EditorSession, focusing itemID: String?) {
    let model = session.store.model
    guard !model.hasAIDraftContent, let cache = try? ScoreCache(),
          let score = cache.load(homeID: model.home_id) else {
        hazardObjectIDs = []
        controller?.setHazardObjects(hazardObjectIDs)
        return
    }
    hazardObjectIDs = Set(score.checklist
        .filter { $0.id.hasPrefix("hazard.") }
        .flatMap { $0.objectIDs(in: model) })
    controller?.setHazardObjects(hazardObjectIDs)
```
If an object previously identified as a hazard (e.g. an obstruction near a doorway) has been moved or if new hazards have been introduced, the 3D scene continues to emphasize the old hazard object IDs until an online `/score` round-trip completes. If the user is offline, the editor displays hazard rings around objects that may no longer be hazardous or fails to highlight newly hazardous objects.  
**Expected behavior:** `applyCachedHazardEmphasis` should only apply cached hazards if `ScoreCache` validates against `HomeFingerprint.of(model)`. If the model has changed, hazard emphasis should be cleared or marked as pending re-evaluation.  
**Root cause:** Reliance on unvalidated `ScoreCache` data.  
**Impact:** Misleading visual hazard markers on the 3D dollhouse model.  
**Dependencies:** `HouseScreen.swift`, `ScoreCache.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.

---

### [LOW] A10-07: ScoreScreen Displays Cached Score During Cold Start Without In-Flight Indicator
**Domain:** User Perception / Stale State Transparency  
**Location:** [ReadinessStore.swift:213-220](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift#L213-L220), [ScoreScreen.swift:78-83](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ScoreScreen.swift#L78-L83)  
**Observed behavior:** Upon app launch, `ReadinessStore.load` loads the cached score from `ScoreCache` synchronously into `scored`. In `ScoreScreen`, because `readiness.breakdown` immediately returns this cached score, the view displays the full score breakdown and hero number. While `isScoring == true` in the background, there is no subtle progress bar or "Updating..." spinner on the score card.  
**Evidence:**  
In `ReadinessStore.swift:213-220`:
```swift
if breakdown == nil, !seenAsDraft.contains(activeHomeID),
   let cached = (try? ScoreCache())?.load(homeID: activeHomeID) {
    scored = (activeHomeID, cached)
}
await startScoreFetch(api: api).value
```
In `ScoreScreen.swift:78-83`:
```swift
private func scoreList(_ breakdown: ScoreBreakdown) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            scoreHeader(breakdown)
                .padding(.top, 8)
```
If `scoreFailure != nil`, `BackendFailureBanner` is shown. However, during the 10-30 seconds of an in-flight fetch on a cold-starting server where `scoreFailure == nil`, the user sees the old score without any visual feedback that a re-calculation is currently underway.  
**Expected behavior:** `ScoreScreen` should present a subtle loading indicator (e.g., pulsing activity dot or "Refreshing...") when `readiness.isScoring` is active while showing a cached breakdown.  
**Root cause:** Visual score header only checks for static `breakdown` presence, not `readiness.isScoring`.  
**Impact:** The user may briefly assume a newly remodeled home's score is already finalized before the server responds.  
**Dependencies:** `ScoreScreen.swift`, `ReadinessStore.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.

---

### [LOW] A10-08: Recurring Checklist Completion State Stored Only in Memory Prior to Server Acknowledgment
**Domain:** Offline Checklist State / Ephemeral State  
**Location:** [ReadinessStore.swift:355-364](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift#L355-L364), [ReadinessStore.swift:96-103](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift#L96-L103)  
**Observed behavior:** When a user checks a recurring item (e.g. fire drill practice or smoke alarm test) while offline, `isDone` displays the state from `pendingRecurring`. While `checklistState` is saved to UserDefaults, `pendingRecurring` is an in-memory dictionary. If the user terminates the app before an online `/score` call confirms the tick, the next launch does not restore `pendingRecurring`.  
**Evidence:**  
In `ReadinessStore.swift:24-32`:
```swift
/// A recurring item ticked or unticked since the last /score answer (S11.35). Shown until the
/// answer lands, then dropped: from there the server's done is the only clock.
private var pendingRecurring: [String: Bool] = [:]
```
In `ReadinessStore.swift:96-103`:
```swift
func isDone(_ item: ChecklistItem) -> Bool {
    if item.recurrence_days != nil { return pendingRecurring[item.id] ?? item.done }
    switch checklistState[item.id] {
    case .flag(let done): return done
    case .completed, nil: return item.done
    }
}
```
If an offline user checks a recurring item, kills the app, and relaunches still offline, `pendingRecurring` is empty. The cached score from `ScoreCache` has `item.done == false`. The item reverts to unchecked on screen until a network connection is re-established and `/score` receives the `.completed(Date)` mark saved in `checklistStateStore`.  
**Expected behavior:** `pendingRecurring` should be persisted to local storage alongside `checklistState` so that offline recurring ticks remain visually checked across app restarts.  
**Root cause:** Design decision in S11.35 to treat server `done` as the sole authority for recurring items without persisting local optimistic overrides across app relaunches.  
**Impact:** A user practicing a drill while offline who quits the app sees their task revert to incomplete on subsequent offline launches.  
**Dependencies:** `ReadinessStore.swift`, `ChecklistStateStore.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.

---

### [OBSERVATION] A10-09: Exemplary Life-Safety Disclaimers and Non-Replacement Guarantees
**Domain:** Safety Standards / Emergency Messaging  
**Location:** [HouseScreen.swift:863-869](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L863-L869), [ResponderSnapshotJSON.swift:84-87](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/ResponderSnapshotJSON.swift#L84-L87), [APIClient+Chat.swift:94-96](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Chat.swift#L94-L96), [Resources/prevention_tips.json](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Resources/prevention_tips.json)  
**Observed behavior:** The application rigorously and consistently avoids implying that it can replace 911, official emergency dispatch, or professional fire service tools. Across all sensitive surfaces, hardcoded disclaimers explicitly define the boundaries of the software as a preventative preparation aid rather than an active-incident guidance tool.  
**Evidence:**  
1. *Tactical Responder Disclaimer (`ResponderSnapshotJSON.swift:84-87`, printed on PDF and exported in JSON):*
   > `"This is a prevention and readiness snapshot, not a tool for use during an active emergency. Responders should not rely on it for tactical decisions."`
2. *Simulation Canvas Disclaimer (`HouseScreen.swift:863-869`, floating glass notice on 3D view):*
   > `"Illustrative only: this animates your floor plan and assumed walking speeds. It is not a prediction of how a real fire would spread or who would get out."`
3. *AI Safety Citations Fallback (`docs/tracker/BLOCKERS.md:458-462`, `claims.py`):*
   > `"If anyone is in danger right now, get out if safe, then call 911. I don't have a sourced answer for that, so I won't guess. For anything else, please consult your local fire department or emergency management office."`
4. *Prevention Tip Guidance (`prevention_tips.json:41`):*
   > `"Get out first, then call 911 from outside. Do not stop to phone from inside the house."`  
**Expected behavior:** Complies with NFPA (National Fire Protection Association) Public Education and FEMA Ready.gov guidelines.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** None (conforming).

---

## 5. Positive Findings

1. **Unified Error Classification (`BackendFailure.swift`):** The transition from dispersed error-handling ladders in individual view files to a single, testable Foundation value type (`BackendFailure`) prevents divergent UI error states and centralizes retry policies.
2. **Cryptographic Route Fingerprinting (`RoutePlanCache.swift`):** Routes are strictly bound to `HomeFingerprint.of(home)`. Any modification to walls, rooms, doors, or windows immediately invalidates the cache lookup, guaranteeing that an escape path through a wall that was deleted is never rendered.
3. **Generational Task Cancellation:** `ReadinessStore` uses `scoreGeneration` and `refreshTask?.cancel()` to gracefully discard late-arriving responses when a user rapidly toggles checklist items or switches between homes.
4. **Zero Fatal Constructs in App Source:** The codebase contains 0 calls to `fatalError`, 0 calls to `precondition()`, and 0 occurrences of `try!` in production app source files (confined strictly to unit test harnesses and `#if DEBUG` previews).
5. **Atomic Document Persistence:** `HomeDocumentStore` serializes all files with `.atomic` writing options (`document.serialized().write(to: url, options: .atomic)`), ensuring that mid-write termination or power loss cannot leave a corrupted partial document on disk.
6. **Robust Input Safeguards in LLM Importer:** `BuildFromPlanView` enforces client-side character caps, downscales photo inputs through `ImagePreparation` using CoreGraphics (avoiding UIKit memory bloat), prevents empty submissions, and blocks interactive dismiss during asynchronous synthesis.

---

## 6. Systemic Issues and Root Causes

1. **Asymmetric Cache Rigor:** The repository demonstrates high architectural rigor for route caching (storing fingerprints, perils, profile keys, and timestamps), but neglected score caching (`ScoreCache`), leaving scores as raw un-fingerprinted JSON.
2. **Transport Classification Gap:** The evolution of `APIClientError` to handle edge-proxy failures (`gatewayFailure`) was not mirrored into `APIClient.isConnectionFailure`, causing proxy errors to bypass offline caching.
3. **SwiftUI Monoliths:** Screens like `HouseScreen.swift` (2,876 lines) mix 3D scene control, networking, autosave synchronization, and UI presentation, making comprehensive lifecycle management (e.g., scene phase handling) prone to omissions.

---

## 7. Failure-Mode Matrix

The following matrix maps operational triggers across the application to their concrete code paths, user-visible outcomes, and reliability ratings.

| Trigger / Failure Condition | Triggering Code Path | Handling Code Path | User-Visible Result | Reliability Rating |
| :--- | :--- | :--- | :--- | :--- |
| **Complete Device Offline** (Flight Mode / No Wi-Fi) | User loads `HouseScreen` | `APIClient.fetchRoutesCached` → `RoutePlanCache.load` | Displays `BackendFailureBanner`: *"You're offline — showing your last saved fire routes for everyone from [date]."* Escape overlay visible. | **PASS (Robust)** |
| **Offline Route Request (No Cache)** | First view of a newly edited home while offline | `fetchRoutesCached` → `BackendFailure.init(offline)` | Banners: *"You're offline. Getting your escape routes needs a connection..."* Shows `OfflineCapabilityNote`. Routes overlay empty. | **PASS (Honest)** |
| **Proxy / Edge 502 Timeout** (Render edge cutoff) | `session.data` returns HTTP 502 with HTML body | `APIClientError.forStatus` → `gatewayFailure` → `BackendFailure.cutOffWhile` | Banners: *"The server's answer about your escape routes was cut off on the way."* Routes cleared despite valid offline cache! | **FAIL (Defect A10-02)** |
| **Anthropic Credits Exhausted** (Backend 502) | Backend catches `anthropic.APIError`, returns 502 JSON | `APIClientError.unexpectedResponse(502)` → `BackendFailure.Kind.aiUnavailable` | Banner: *"AI features are unavailable right now — the server needs attention. Your escape routes still work."* No Retry button. | **PASS (Honest)** |
| **Render Cold Start Timeout** (HTTP 504 / Phone timeout) | Gateway times out waiting for service or URLSession 90s timer | `URLError.timedOut` → `BackendFailure.timedOut` | Banner: *"The server didn't answer in time. It may be waking up. Try again in a moment."* Retry button enabled. | **PASS (Actionable)** |
| **Camera Permission Denied** | User taps "Start scanning" with video auth `.denied` | `RoomCaptureSession.run` → ARKit delegate fail | Banner: *"The scan couldn't be completed: [system error]"*. Retry button loops indefinitely; no Settings link. | **FAIL (Defect A10-03)** |
| **Device Lacks LiDAR** | User opens scanning on non-Pro iPhone or Simulator | `RoomCaptureController.isSupported == false` | "Start scanning" button disabled. Label: *"This device doesn't have LiDAR, so scanning is unavailable. You can still build in editor."* | **PASS (Clean)** |
| **Malformed Response Body** (Shape Mismatch) | Backend deployment API schema drift (200 OK, bad JSON) | `DecodingError` in `BackendFailure.init` | Banner: *"The app and the server disagree about [noun]. Update the app, then try again."* No useless Retry button. | **PASS (Accurate)** |
| **401 Unauthorized Token** | Bundled bearer token expired or misconfigured | `APIClientError.unexpectedResponse(401)` | Banner: *"The server didn't accept the access token — check it in Settings."* Auto-presents Settings sheet. | **PASS (Recoverable)** |
| **Export Snapshot After Home Edit Offline** | Resident edits home offline, exports Fire Dept PDF/JSON | `EscapePlanExporter.writeResponderSnapshot` | Snapshot PDF and JSON embed obsolete readiness score and stale hazard list computed for old layout. | **CRITICAL (Defect A10-01)** |
| **Rapid Button Tapping (Rescore)** | User rapidly toggles checklist tasks | `ReadinessStore.startScoreFetch` | Previous task cancelled via `refreshTask?.cancel()`. Generation checked; obsolete results discarded. | **PASS (Thread-safe)** |
| **Rapid Button Tapping (Build Plan)** | User taps "Build draft home" repeatedly | `BuildFromPlanView.isBuilding` | Button disabled immediately (`.disabled(isBuilding)`), spinner active, interactive dismiss locked. | **PASS (Guarded)** |
| **Backgrounding Mid-Edit Gesture** | User minimizes app while dragging wall corner | `HouseScreen` (missing `scenePhase`) | In-flight gesture discarded on process termination; last committed action on disk remains intact. | **WARN (Defect A10-04)** |
| **Corrupt Local Home File** | Local file fails to decode due to disk error | `HomeDocumentStore.load` throws | `BackendFailure.localLoad`: *"Couldn't open this home's saved file on this device... other homes unaffected."* | **PASS (Honest)** |
| **Chat Safety Query Without Citation** | Resident asks AI an unsupported safety question | `claims.py` checks citations | Chat bot answers: *"If anyone is in danger right now, get out if safe, then call 911. I don't have a sourced answer..."* | **PASS (Safety)** |

---

## 8. Unverified Assumptions

1. **Live Render Edge 502 Payloads:** Inferred from codebase architecture and `BLOCKERS.md` that Render's edge proxy sends HTML or empty bodies on HTTP 502 timeouts. Verified by source inspection of `APIClient.isAppErrorBody`, but live edge probing was blocked by the read-only mandate.
2. **Cold Start Wake-up Latency:** Render free tier spin-up is documented in `BLOCKERS.md` as reaching 50-60 seconds. Client timeout is verified set to 90 seconds in `APIClient+Routes.swift:21` and `APIClient+Score.swift:21`.
3. **LiDAR Device Execution:** Verified through source inspection of `RoomCaptureController.swift:85` and `canImport(RoomPlan)`. Physical execution on a LiDAR-equipped device is environment-blocked due to lack of local physical hardware in the execution container.

---

## 9. Areas Requiring Further Investigation

1. **Sync Deletion Tombstone Persistence:** Investigate behavior in `HomeDocumentSyncRepository` when an offline home deletion is performed and the device is subsequently re-authenticated against cloud sync.
2. **Memory Footprint of SceneKit Under Repeated Load:** In `HouseScreen`, investigate whether rapid scene rebuilds (`controller?.rebuild()`) during error retries release geometry buffers cleanly or accumulate memory pressure.
3. **VoiceOver Live Region Behavior on Repeated Failures:** While `BackendFailureBanner` posts `AccessibilityNotification.Announcement`, verify whether rapid repeated error messages cause VoiceOver speech queue collisions.

---

## 10. Recommended Priorities

### Immediate (Critical / P0 - Before App Store / Challenge Submission)
1. **Fix A10-01 (`ScoreCache` Fingerprint & Freshness Validation):**
   - Refactor `ScoreCache` to store `CachedScoreBreakdown` containing `homeFingerprint: String` and `savedAt: Date`.
   - Update `ScoreCache.load` to reject any score whose fingerprint does not match `HomeFingerprint.of(home)`.
   - In `EscapePlanExporter.swift`, omit `scoreResponse` if `ScoreCache.load` returns `nil`, ensuring firefighter exports never present obsolete hazard data.

### High Priority (P1)
2. **Fix A10-02 (Include Gateway Failure in Route Fallback):**
   - Update `APIClient.isConnectionFailure` to accept `APIClientError.gatewayFailure`:
     ```swift
     static func isConnectionFailure(_ error: Error) -> Bool {
         if case APIClientError.gatewayFailure = error { return true }
         guard let urlError = error as? URLError else { return false }
         ...
     }
     ```
3. **Fix A10-03 (Handle Camera Permission in RoomCaptureController):**
   - Check `AVCaptureDevice.authorizationStatus(for: .video)` in `RoomCaptureController.startScanningRoom()`.
   - Surface an explicit `.permissionDenied` phase with an action button navigating to `UIApplication.openSettingsURLString`.

### Medium Priority (P2)
4. **Fix A10-04 (`HouseScreen` Lifecycle & Gesture Teardown):**
   - Attach `@Environment(\.scenePhase)` to `HouseScreen` and cancel in-flight gesture arbiter tracking on `.background`.
5. **Fix A10-05 (Eliminate Silent Error Swallowing):**
   - Replace empty `catch { }` in `ScoreCache.save` with `Logger.error` telemetry.
   - Update `ProfilesScreen.reloadReadinessIfChanged` to log and notify if `documentStore.load` fails.
6. **Fix A10-06 (Validate Hazard Emphasis Geometry):**
   - Gate `HouseScreen.applyCachedHazardEmphasis` on matching `HomeFingerprint.of(model)`.
