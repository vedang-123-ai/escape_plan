# Audit Domain 07: Data Persistence, Storage & State Management

**Audit Target:** Escape Plan iOS Client (`escape_plan.xcodeproj`, `tools/editorcore`)  
**Auditor:** Senior Systems & Storage Engineer (Agent 07)  
**Date:** 2026-10-11  
**Scope:** File storage (`HomeDocumentStore`, `ConversationStore`, `ScanStore`), In-memory state & Reducers (`HomeModelStore`, `UndoStack`, `EditorSession`), Facades & Lifecycles (`HomeLibrary`, `HouseEditorSessionController`, `HouseEditorAppRegistration`), Schema Versioning & Forward Migration (`SchemaMigrator`, `HomeDocument`), Cloud Sync & Reconciliation (`SyncManager`, `SyncReconciler`, `SyncState`, `HomeDocumentSyncRepository`, `CloudHomesClient`), Persistence Sidecars (`sync-state.json`), Keychain & Credentials (`KeychainTokenStore`), UserDefaults stores (`ChecklistStateStore`, `MeetingPointStore`, `ScanFreshnessStore`, `ActiveHomeMemory`, `DeviceIdentity`), Caches (`ScoreCache`, `RoutePlanCache`, `SummaryProbe`), and Concurrency / Relaunch Lifecycles.

---

## 1. Executive Summary

This audit examined every layer of data storage, serialization, transaction safety, state management, and lifecycle restoration in Escape Plan.

### Key Architectural Strengths:
1. **Local-First, Schema-Valid Document Architecture:** Homes are saved as raw, un-enveloped JSON files under `<Documents>/Homes/<home_id>.homeplan.json`. Stored files, wire payloads, and shared exports share an identical schema contract (`schema/homemodel.schema.json`).
2. **Defensive Atomic Writes:** All persistence subsystems (`HomeDocumentStore`, `ConversationStore`, `FileSyncStateStore`, `RoutePlanCache`, and `ScoreCache`) utilize Foundation's `.atomic` file writing options, ensuring crash resistance during in-flight serialization.
3. **Immutability & Reducer Guarantees:** `HomeModelStore` implements an uncompromising reducer architecture: every mutation reduces onto a temporary copy, executes comprehensive validation (`EditorValidation`), and commits only if 100% valid.
4. **Resilient Offline Degradation:** If network requests fail, the app gracefully falls back to local storage and valid caches, with detailed offline notices.

### Critical Vulnerabilities & Defects Identified:
1. **`library.deletionObserver` Disconnected in Production (`A07-01` - CRITICAL):** In [ContentView.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/ContentView.swift#L83-L85), the assignment of `library.deletionObserver = syncRepository` was commented out during a pre-demo trim on 2026-10-02. As a result, local deletions in `HomeLibrary` fail to record tombstones in `SyncState`, and never dispatch `DELETE /homes/{id}` to the server. If sync is activated, deleted homes will inevitably resurrect as "zombies" on the next sync pull.
2. **`ScoreCache` Lacks Model Fingerprinting (`A07-02` - HIGH):** Unlike `RoutePlanCache` (which verifies `HomeFingerprint`), `ScoreCache` stores score breakdowns keyed only by `home_id`. When offline, `ReadinessStore` and `HouseScreen` load cached scores for edited homes, displaying obsolete preparedness scores and highlighting nonexistent or reassigned hazard objects.
3. **Internal Entity ID Duplication on Home Duplication (`A07-03` - HIGH):** `HomeDocumentStore.duplicate` re-identifies `home_id`, `name`, and `meta.modified`, but leaves all floor, room, opening, object, and profile UUIDs untouched. This creates duplicate entity IDs across distinct homes in the user's library.
4. **Widespread Store Orphanage on Home Deletion (`A07-04` - MEDIUM):** Deleting a home purges the document file and Assistant conversation, but leaves stale data behind in `ChecklistStateStore`, `MeetingPointStore`, `ScanFreshnessStore`, `ScoreCache`, and `RoutePlanCache`.
5. **Path Traversal Risk in `ScoreCache` (`A07-05` - MEDIUM):** `ScoreCache` concatenates `homeID` into file paths without validating against `HomeID.isValid`.
6. **Unbounded In-Memory Undo Stack (`A07-06` - MEDIUM):** `UndoStack` stores full `before`/`after` snapshot pairs of `HomeModel` with no capacity ceiling, presenting a potential memory leak during prolonged editing sessions.

---

## 2. Scope and Files Inspected

### Source Files Inspected:
- **Persistence:**
  - [HomeDocument.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocument.swift) (Lines 1–121)
  - [HomeDocumentStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift) (Lines 1–376)
  - [HomeLibrary.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeLibrary.swift) (Lines 1–125)
  - [SchemaMigrator.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/SchemaMigrator.swift) (Lines 1–116)
  - [PersistenceError.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/PersistenceError.swift) (Lines 1–38)
  - [HomeDocumentSyncRepository.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentSyncRepository.swift) (Lines 1–195)
  - [ChecklistStateStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ChecklistStateStore.swift) (Lines 1–55)
  - [ConversationStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ConversationStore.swift) (Lines 1–191)
  - [ScoreCache.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ScoreCache.swift) (Lines 1–37)
  - [DeviceIdentity.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/DeviceIdentity.swift) (Lines 1–37)
- **Editor Core & Session Management:**
  - [HomeModelStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/HomeModelStore.swift) (Lines 1–703)
  - [UndoStack.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/UndoStack.swift) (Lines 1–95)
  - [EditorValidation.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/EditorValidation.swift) (Lines 1–605)
  - [EditorSession.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/EditorSession.swift) (Lines 1–42)
  - [HouseEditorSessionController.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/HouseEditorSessionController.swift) (Lines 1–162)
  - [HouseEditorSessionController+App.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseEditorSessionController+App.swift) (Lines 1–53)
- **Cloud Sync:**
  - [SyncManager.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/SyncManager.swift) (Lines 1–533)
  - [SyncReconciler.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/SyncReconciler.swift) (Lines 1–287)
  - [SyncState.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/SyncState.swift) (Lines 1–366)
  - [HomeID.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/HomeID.swift) (Lines 1–58)
  - [HomeFingerprint.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/HomeFingerprint.swift) (Lines 1–70)
  - [HomeDeletionReach.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/HomeDeletionReach.swift) (Lines 1–80)
- **Key-Value, Cache & Keychain Stores:**
  - [KeychainTokenStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Auth/KeychainTokenStore.swift) (Lines 1–99)
  - [TokenStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Auth/TokenStore.swift) (Lines 1–62)
  - [MeetingPointStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/MeetingPointStore.swift) (Lines 1–47)
  - [ScanFreshnessStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/ScanFreshnessStore.swift) (Lines 1–34)
  - [ActiveHomeMemory.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/ActiveHomeMemory.swift) (Lines 1–49)
  - [ResponderSnapshotStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/ResponderSnapshotStore.swift) (Lines 1–24)
  - [APIClient+Cache.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Cache.swift) (Lines 1–207)
  - [FixtureSeeder.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Onboarding/FixtureSeeder.swift) (Lines 1–164)
- **App Lifecycle & View Integration:**
  - [escape_planApp.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/escape_planApp.swift) (Lines 1–186)
  - [ContentView.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/ContentView.swift) (Lines 1–193)
  - [ReadinessStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift) (Lines 1–490)
  - [HouseScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift) (Selected lifecycle sections, Lines 2280–2510)
  - [SettingsScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/SettingsScreen.swift) (Lines 180–225)

---

## 3. Methods and Checks Performed

1. **SwiftPM Isolated Package Test Run:**
   - In accordance with the prompt instruction, `tools/editorcore` was copied to `/tmp/test-editorcore` dereferencing symlinks and excluding `.build`.
   - Missing out-of-package repository fixtures (`schema/fixtures`, `escape_plan/Resources/prevention_tips.json`, and backend reference files) were populated in `/tmp/test-editorcore` to mirror the development environment.
   - Executed `swift test --package-path /tmp/test-editorcore`.
   - **Result:** **656 tests executed, 656 passed, 0 failures** in 5.357 seconds.
   - Pinned suite coverage includes: `HomeModelStoreTests`, `StoreInvariantTests`, `SnappingTests`, `UndoStackTests`, `SyncReconcilerTests`, `SyncManagerTests`, `SyncStateStoreTests`, `SyncDeletionTests`, `TokenStoreTests`, `ReadinessScanFreshnessStoreTests`.
2. **Analysis of Persistence & Offline Test Suites:**
   - Inspected `PersistenceTests.swift`, `OfflineIntegrityTests.swift`, `HomeDocumentSyncRepositoryTests.swift`, `ChecklistStateStoreTests.swift`, and `ConversationStoreTests.swift`.
   - Analyzed what each test suite actually exercises vs what remains unexecuted due to the missing iOS simulator runtime.
3. **End-to-End Tracing:**
   - Traced the `save → navigate → kill → relaunch` lifecycle through source code.
   - Traced error recovery paths for corrupt documents, unreadable directories, network failures, and 401 session expiries.
4. **Git Workspace Verification:**
   - Ran `git status` to verify that no files outside `audit/2026-10-11_comprehensive/` were modified, created, or deleted.

---

## 4. Findings (with Evidence)

### [CRITICAL] `library.deletionObserver` is disconnected in `ContentView.swift`, breaking cloud deletion and tombstone tracking
**Domain:** Persistence & Cloud Sync  
**Location:** [ContentView.swift:83-85](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/ContentView.swift#L83-L85)  
**Observed behavior:** When `HomeLibrary.delete(homeID:)` executes, `try deletionObserver?.homeWasDeletedLocally(homeID: homeID)` attempts to record a deletion tombstone. However, in `ContentView.swift`, the wiring line `library.deletionObserver = syncRepository` is commented out. As a result, `deletionObserver` is perpetually `nil` in production.  
**Evidence:**
From [ContentView.swift:81-86](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/ContentView.swift#L81-L86):
```swift
syncRepository.library = library
// `library.deletionObserver = syncRepository` wrote a sync tombstone per deleted home. Not
// wired while accounts and sync are switched off (demo trim, 2026-10-02): with no sync a
// deleted home cannot come back, and a failed tombstone write warned that it might.
readiness.ensureActiveHome()
```
And in [HomeLibrary.swift:81](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeLibrary.swift#L81):
```swift
try deletionObserver?.homeWasDeletedLocally(homeID: homeID)
```
**Expected behavior:** `library.deletionObserver` must be connected to `syncRepository` so that when a user deletes a home, a tombstone is written to `sync-state.json`, and `SyncManager` dispatches `DELETE /homes/{id}` to remove the remote record.  
**Root cause:** On 2026-10-02, during a demo trim, accounts were visually removed from Settings, and `library.deletionObserver` was commented out to avoid tombstone write warnings when signed out. However, `SyncManager` and `HomeDocumentSyncRepository` remain active in `escape_planApp`.  
**Impact:** If a user signs in or sync runs, any locally deleted home is never recorded in `SyncState.deletions`. The server's copy remains untouched, and on the subsequent sync cycle, `SyncReconciler` sees the home as `newRemoteHome` and downloads it back onto the device, resurrecting the deleted home.  
**Recommended improvement:** Restore `library.deletionObserver = syncRepository` in `ContentView.swift`, or conditionally wire it when an account is active.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small  

---

### [HIGH] `ScoreCache` lacks model fingerprinting and serves stale scores for edited homes when offline
**Domain:** Caching & Preparedness Score State  
**Location:** [ScoreCache.swift:13-36](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ScoreCache.swift#L13-L36), [ReadinessStore.swift:213-216](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift#L213-L216), [HouseScreen.swift:2344-2354](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L2344-L2354)  
**Observed behavior:** `ScoreCache` caches `ScoreBreakdown` to `<Caches>/ScoreCache/<home_id>.json` without associating it with the model's `HomeFingerprint`. When the app launches offline or loses connectivity, `ReadinessStore` loads this cached score regardless of whether the user edited rooms, moved walls, or removed safety equipment. Furthermore, `HouseScreen` uses this stale cache to highlight hazard objects.  
**Evidence:**
In [ScoreCache.swift:28-35](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ScoreCache.swift#L28-L35):
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
Contrast with [APIClient+Cache.swift:103-115](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Cache.swift#L103-L115), where `RoutePlanCache` enforces:
```swift
guard cached.homeFingerprint == homeFingerprint, ... else { return nil }
```
In [ReadinessStore.swift:213-216](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift#L213-L216):
```swift
if breakdown == nil, !seenAsDraft.contains(activeHomeID),
   let cached = (try? ScoreCache())?.load(homeID: activeHomeID) {
    scored = (activeHomeID, cached)
}
```
**Expected behavior:** The cache should wrap `ScoreBreakdown` in a container storing `homeFingerprint: String` and reject entries where `fingerprint != HomeFingerprint.of(home)`.  
**Root cause:** `ScoreCache` was implemented as a primitive store and was never upgraded with the fingerprint validation that S11.36 introduced for `RoutePlanCache`.  
**Impact:** Misleading safety score displayed to user offline. If an exit is blocked or room layout modified, the app indicates high readiness based on an obsolete floor plan. Hazard object highlighting in 3D scene points to stale or invalid object IDs.  
**Recommended improvement:** Wrap the cached score in `CachedScoreBreakdown` containing `homeFingerprint`, validate upon load, and return `nil` if the model changed.  
**Dependencies:** `HomeFingerprint`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small  

---

### [HIGH] `HomeDocumentStore.duplicate` preserves internal entity IDs, causing cross-home ID collisions
**Domain:** Persistence & Entity Identity  
**Location:** [HomeDocumentStore.swift:249-262](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift#L249-L262), [HomeDocument.swift:82-93](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocument.swift#L82-L93)  
**Observed behavior:** Duplicating a home generates a fresh UUID for `home_id`, but preserves identical IDs for all child entities: `floor.id`, `room.id`, `opening.id`, `object.id`, `stairs.id`, and `profile.id`.  
**Evidence:**
In [HomeDocument.swift:82-93](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocument.swift#L82-L93):
```swift
func reidentified(homeID: String, name: String, modified: Date) -> HomeDocument {
    var object = body.objectValue ?? [:]
    object["home_id"] = .string(homeID)
    object["name"] = .string(name)
    var meta = object["meta"]?.objectValue ?? [:]
    meta["modified"] = .string(ISO8601DateFormatter.homeModel.string(from: modified))
    ...
    return HomeDocument(body: .object(object))
}
```
Nothing iterates or regenerates IDs for `floors`, `rooms`, `openings`, `objects`, `stairs`, or `profiles`.  
**Expected behavior:** While `EditorValidation` enforces ID uniqueness within a single `HomeModel`, entities across distinct homes within an account or dataset should possess distinct identities to prevent cross-home graph or routing collision.  
**Root cause:** `HomeDocument.reidentified` operates at the JSON envelope level for performance and to preserve unmodeled fields, deliberately touching only `home_id`, `name`, and `meta`.  
**Impact:** If both homes are synchronized to a backend database or compared in multi-home operations, child entity IDs collide. Checklists or logs keyed by entity ID without home ID namespace risk cross-talk.  
**Recommended improvement:** Implement an entity ID remapping pass during duplication that assigns fresh UUIDs while preserving internal topological relationships (e.g., `opening.room_id`, `stairs.from.room_id`, `profile.bedroom_room_id`).  
**Dependencies:** Entity relationship graph.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Medium  

---

### [MEDIUM] Deleting a home leaves orphaned data across five auxiliary stores
**Domain:** State Lifecycle & Storage Cleanliness  
**Location:** [HomeLibrary.swift:70-85](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeLibrary.swift#L70-L85)  
**Observed behavior:** When `HomeLibrary.delete(homeID:)` executes, only `<homeID>.homeplan.json` and the Assistant conversation thread are deleted. Five other stores retaining state keyed by `homeID` are ignored.  
**Evidence:**
In [HomeLibrary.swift:72-83](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeLibrary.swift#L72-L83):
```swift
try store.delete(homeID: homeID)
deleted = true
editor?.homeWasDeleted(homeID: homeID)
let threadDeletion = Result { try conversations?.deleteConversation(homeID: homeID) }
try deletionObserver?.homeWasDeletedLocally(homeID: homeID)
try threadDeletion.get()
```
The following remain orphaned:
1. `ChecklistStateStore`: UserDefaults `"checklistState.<home_id>"` ([ChecklistStateStore.swift:25](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ChecklistStateStore.swift#L25))
2. `MeetingPointStore`: UserDefaults `"export.meetingPoint.<home_id>"` ([MeetingPointStore.swift:29](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/MeetingPointStore.swift#L29))
3. `ScanFreshnessStore`: UserDefaults `"readiness.wallEdgeCount.<home_id>"` ([ScanFreshnessStore.swift:20](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/ScanFreshnessStore.swift#L20))
4. `ScoreCache`: Disk `<Caches>/ScoreCache/<home_id>.json` ([ScoreCache.swift:14](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ScoreCache.swift#L14))
5. `RoutePlanCache`: Disk `<Documents>/RouteCache/<home_id>.*.routeplan.v2.json` ([APIClient+Cache.swift:132](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Cache.swift#L132))  
**Expected behavior:** `HomeLibrary.delete` should trigger cleanup across all auxiliary stores associated with `homeID`.  
**Root cause:** Each subsystem was developed independently under a modular scope lock, treating its storage as non-critical device-local metadata.  
**Impact:** Gradual accumulation of stale files in `<Documents>/RouteCache/` and `<Caches>/ScoreCache/`, plus permanent bloating of UserDefaults plist. If a home is re-created with the same fixed fixture ID, it inherits stale checklist ticks and meeting points.  
**Recommended improvement:** Introduce a `HomeDeletionCoordinator` or add an explicit purge routine to `HomeLibrary.delete` that removes UserDefaults keys and disk cache files.  
**Dependencies:** `ChecklistStateStore`, `MeetingPointStore`, `ScanFreshnessStore`, `ScoreCache`, `RoutePlanCache`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small  

---

### [MEDIUM] `ScoreCache` lacks `HomeID` validation, permitting unconstrained path construction
**Domain:** Storage & Security  
**Location:** [ScoreCache.swift:13-15](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ScoreCache.swift#L13-L15)  
**Observed behavior:** `ScoreCache.file(for:)` appends `homeID` directly to its cache directory without verifying `HomeID.isValid(homeID)`.  
**Evidence:**
In [ScoreCache.swift:13-15](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ScoreCache.swift#L13-L15):
```swift
private func file(for homeID: String) -> URL {
    directory.appendingPathComponent("\(homeID).json")
}
```
Contrast with [HomeDocumentStore.swift:318-321](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift#L318-L321) and [ConversationStore.swift:101-104](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ConversationStore.swift#L101-L104), which explicitly validate `HomeID.validate(homeID)`.  
**Expected behavior:** `ScoreCache` should enforce `HomeID.isValid` or `HomeID.validate` before resolving file paths.  
**Root cause:** Inconsistent adoption of `HomeID.validate` across early and peripheral utility stores.  
**Impact:** A maliciously crafted `home_id` containing path traversal characters (`../`) could write or remove files outside `<Caches>/ScoreCache/`.  
**Recommended improvement:** Add `try HomeID.validate(homeID)` or guard with `HomeID.isValid` in `ScoreCache.file(for:)`.  
**Dependencies:** `HomeID`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small  

---

### [MEDIUM] `UndoStack` maintains unbounded memory growth during continuous editing
**Domain:** Editor State & Memory Management  
**Location:** [UndoStack.swift:22-46](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/UndoStack.swift#L22-L46)  
**Observed behavior:** `UndoStack` retains full `Commit` objects containing two full `HomeModel` snapshot copies (`before` and `after`) in `past: [HomeModelStore.Commit]` and `future: [HomeModelStore.Commit]`. There is no maximum stack size or pruning mechanism.  
**Evidence:**
In [UndoStack.swift:22-23, 45](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/UndoStack.swift#L22-L23):
```swift
private var past: [HomeModelStore.Commit] = []
private var future: [HomeModelStore.Commit] = []
...
past.append(commit)
```
In [HomeModelStore.swift:28-32](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/HomeModelStore.swift#L28-L32):
```swift
struct Commit: Sendable {
    let action: EditAction
    let before: HomeModel
    let after: HomeModel
}
```
**Expected behavior:** An undo stack in a mobile environment should enforce a reasonable bounded depth (e.g., 50 or 100 entries) to prevent unbounded heap consumption.  
**Root cause:** Omission of a capacity cap when designing the pure Foundation undo stack.  
**Impact:** In complex homes with many vertices and objects, dozens of non-coalesced edits (e.g., adding/renaming rooms, adding/configuring openings, adding furniture objects) keep thousands of object allocations alive in RAM, risking memory pressure and OS termination on older iOS devices.  
**Recommended improvement:** Introduce a `maxDepth` limit (e.g. 50) that removes the oldest elements from `past` when exceeded (`if past.count > maxDepth { past.removeFirst() }`).  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small  

---

### [LOW] Synchronous directory enumeration and file decoding on `@MainActor` in `HomeDocumentStore`
**Domain:** Main Thread Performance & I/O  
**Location:** [HomeDocumentStore.swift:114-156](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift#L114-L156), [HomeLibrary.swift:60-65](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeLibrary.swift#L60-L65)  
**Observed behavior:** `HomeLibrary.refresh()` synchronously calls `store.summaries(reusing: summaryEntries)`. While it performs incremental caching via file modification dates, any cold launch or refresh with uncached files performs synchronous file reads and JSON decoding directly on the main thread.  
**Evidence:**
In [HomeLibrary.swift:57-65](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeLibrary.swift#L57-L65):
```swift
/// Re-lists the library. Synchronous on purpose: the first screen, the delete and duplicate
/// sheets and the new-home flow all read `homes` on the next line.
func refresh() {
    let listing = store.summaries(reusing: summaryEntries)
    summaryEntries = listing.entries
    if homes != listing.summaries { homes = listing.summaries }
}
```
**Expected behavior:** Heavy disk I/O should execute asynchronously off the main thread, dispatching results back to `@MainActor`.  
**Root cause:** Synchronous API design chosen to simplify synchronous SwiftUI view state dependencies.  
**Impact:** On devices with many homes or slower flash storage, cold launch and autosave refresh can produce main-thread frame drops (micro-stutters).  
**Recommended improvement:** Retain the synchronous fast path when all files match `summaryEntries`, but dispatch uncached file reads to a cooperative background task.  
**Dependencies:** `HomeLibrary`.  
**Verification status:** Verified by source inspection.  
**Confidence:** Medium  
**Effort:** Medium  

---

### [OBSERVATION] The production adapter `HomeDocumentSyncRepository` has zero automated test execution
**Domain:** Test Harness & Architecture Seam  
**Location:** [HomeDocumentSyncRepositoryTests.swift:1-18](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_planTests/HomeDocumentSyncRepositoryTests.swift#L1-L18)  
**Observed behavior:** As explicitly documented by the codebase author, `HomeDocumentSyncRepository` has never been executed by automated testing because it resides in `Persistence/` (not symlinked into `tools/editorcore`), and CI/dev environments lack an installed iOS simulator runtime.  
**Evidence:**
In [HomeDocumentSyncRepositoryTests.swift:5-17](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_planTests/HomeDocumentSyncRepositoryTests.swift#L5-L17):
```swift
// ─── THIS FILE HAS NEVER EXECUTED ─────────────────────────────────────────────────────────
// It needs `xcodebuild test`, and the machine S8.4 was written on cannot run a simulator.
// ...
// `Persistence/` is not symlinked into the SwiftPM package, so `swift test` cannot reach
// `HomeDocumentSyncRepository` at all. `SyncManagerTests` exercises `InMemoryHomeRepository`...
```
**Expected behavior:** The real filesystem-backed sync adapter should be compiled and tested in the standalone macOS package harness.  
**Root cause:** Architectural split: `Sync/` was kept pure Foundation and symlinked into `tools/editorcore`, while `Persistence/` was considered an app-target module.  
**Impact:** Critical edge cases in `HomeDocumentSyncRepository` (such as timestamp preservation on pull, open home editor collision, and undecodable file isolation) are tested only against an in-memory test double in `tools/editorcore`.  
**Recommended improvement:** Symlink `HomeDocumentStore.swift` and `HomeDocumentSyncRepository.swift` into `tools/editorcore` so `HomeDocumentSyncRepositoryTests.swift` executes on macOS via `swift test`.  
**Dependencies:** `tools/editorcore/Package.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small  

---

## 5. Positive Findings

1. **Robust Schema Versioning & Forward Migration:**
   - [SchemaMigrator.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/SchemaMigrator.swift) provides clean, numeric-component version comparisons (`1.10` > `1.2`).
   - Forward migration step pipeline (`1.0` → `1.1` → `2.0` → `2.1`) automatically upgrades older documents upon load and writes them back to disk so migrations happen exactly once.
   - Documents newer than the supported build throw `PersistenceError.documentTooNew`, preventing silent data degradation or data truncation.
2. **Defensive Corruption Isolation:**
   - In [HomeDocumentStore.swift:124-149](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift#L124-L149), malformed or unreadable home files are skipped during `list()`, ensuring that one corrupt file never hides valid homes or crashes the home catalog.
   - In [ConversationStore.swift:121-125](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ConversationStore.swift#L121-L125), corrupt conversation files are quarantined to `<homeID>.unreadable-<UUID>.json` rather than deleted or overwritten, preserving conversational history for debugging while cleanly resetting the screen.
3. **Strict Path Traversal Protection:**
   - [HomeID.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/HomeID.swift) restricts IDs to ASCII alphanumeric characters, hyphens, and underscores up to 64 bytes, disallowing dots (`.`), slashes (`/`), and control characters.
   - [HomeDocumentStore.swift:318-321](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift#L318-L321) enforces `HomeID.validate` across all load, save, delete, and duplicate calls.
4. **Crash-Safe Fallback Storage:**
   - In [HomeDocumentStore.swift:56-68](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift#L56-L68), `launchStore()` replaces historical force-tries (`try!`). If `<Documents>/Homes` cannot be accessed, the app falls back to a temporary directory with `storageUnavailable = true`, preventing launch crashes while displaying a prominent warning banner.
5. **Deterministic Conflict Resolution & Re-identifying Loser:**
   - In [SyncReconciler.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/SyncReconciler.swift), sync decisions are pure functions over value types. Monotonic revision counters track server progression, and conflicts are settled deterministically via `meta.modified`.
   - When a local change loses a conflict, [SyncManager.swift:401-405](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/SyncManager.swift#L401-L405) preserves the losing local copy under `<Home Name> (this device)` before pulling the winner, guaranteeing zero silent data loss.
6. **Starter Home Verbatim Timestamp Seeding:**
   - [FixtureSeeder.swift:98-113](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Onboarding/FixtureSeeder.swift#L98-L113) seeds demo fixtures with their original fixed timestamps (2026-07-10) rather than `Date()`, specifically preventing factory demo homes from clobbering real edited homes in cloud sync tiebreakers.

---

## 6. Systemic Issues and Root Causes

1. **Partial Cleanup from Codebase Trimming:**
   - When features are trimmed for demos or presentation constraints (e.g. cutting Accounts/Sync on 2026-10-02), commenting out integration seams in UI layers (`ContentView.swift`) while leaving backend subsystems instantiated (`escape_planApp.swift`) leaves dormant, half-connected state machines with subtle failure modes.
2. **Inconsistent Auxiliary Store Architecture:**
   - Peripheral stores (`ChecklistStateStore`, `MeetingPointStore`, `ScanFreshnessStore`, `ScoreCache`) were added incrementally without an overarching lifecycle management protocol. Each store manages its own keys independently, leading to data leaks when homes are deleted.
3. **Decoupled Package Test Harness:**
   - Maintaining `tools/editorcore` without symlinking `Persistence/` creates a verification divide: developers trust passing tests in `EditorCore`, unaware that production filesystem adapters (`HomeDocumentSyncRepository`) remain unexecuted.

---

## 7. Unverified Assumptions

1. **iOS Simulator Absence:**
   - Because `xcrun simctl list runtimes` reports no installed simulator runtime, UI-level persistence tests (`PersistenceTests`, `OfflineIntegrityTests`, `HomeDocumentSyncRepositoryTests`) could not be executed at runtime via `xcodebuild test`.
   - Assumption verified via static source audit and isolated unit execution in `/tmp/test-editorcore`.
2. **Keychain Protection Class at Background Sync:**
   - `KeychainTokenStore` uses `kSecAttrAccessibleAfterFirstUnlock`. This allows background sync execution after the first device unlock, but runtime background invocation could not be directly observed without a physical device.

---

## 8. Areas Requiring Further Investigation

1. **Large Library Directory Enumeration Profiling:**
   - Profiling `HomeDocumentStore.summaries` on a physical device with 50+ homes to measure main-thread latency during app launch.
2. **Offline Preparedness Score Reconciliation:**
   - Evaluating whether `ReadinessStore` should calculate a basic heuristic preparedness score locally when the backend `/score` endpoint is unreachable, rather than either displaying a stale score or showing a backend failure banner.

---

## 9. Recommended Priorities

### Immediate (Pre-Submission / Priority 1):
1. **Fix `A07-01`:** Re-enable or cleanly conditionalize `library.deletionObserver = syncRepository` in `ContentView.swift` so tombstones are properly tracked.
2. **Fix `A07-02`:** Add `HomeFingerprint` checking to `ScoreCache` so edited homes do not serve stale scores or point to invalid hazard objects.
3. **Fix `A07-05`:** Add `HomeID.isValid` check to `ScoreCache.file(for:)` to eliminate path traversal risk.

### Short-Term (Priority 2):
4. **Fix `A07-04`:** Implement unified home deletion cleanup across `ChecklistStateStore`, `MeetingPointStore`, `ScanFreshnessStore`, `ScoreCache`, and `RoutePlanCache`.
5. **Fix `A07-06`:** Cap `UndoStack` history depth to a maximum of 50 or 100 commits to safeguard against unbounded memory growth.
6. **Fix `A07-03`:** Implement child entity ID remapping during home duplication in `HomeDocumentStore.duplicate`.

### Medium-Term (Priority 3):
7. **Fix `A07-08`:** Symlink `HomeDocumentStore` and `HomeDocumentSyncRepository` into `tools/editorcore` so all persistence integration tests run in the macOS package harness.
8. **Fix `A07-07`:** Move uncached filesystem reads in `HomeDocumentStore.summaries` off the main actor.

---

## 10. User Journey Audit: Save → Navigate → Kill → Relaunch & Error Behaviors

### 10.1 Standard Save → Navigate → Kill → Relaunch Lifecycle
1. **Save:**
   - The user draws or modifies a room in `HouseScreen`. `store.dispatch(action)` reduces onto a draft copy and validates against `EditorValidation`.
   - Upon commit, `newStore.onCommit` calls `autosave`. `HouseEditorSessionController.save` verifies disk state via `checkDisk()`, stamps `meta.modified` to whole seconds, and writes to `<Documents>/Homes/<home_id>.homeplan.json` using atomic replacement (`Data.write(options: .atomic)`).
   - Invalidation clears cached routes and dispatches background fetch to `/routes`.
2. **Navigate:**
   - User switches tabs (e.g., to Tasks or Home). `HouseScreen.disappear()` unregisters `openHomeID` in `syncRepository`.
   - `HomeScreen` observes `readiness.activeHome`, which re-reads the updated summary.
   - `ActiveHomeMemory` persists the active home ID in UserDefaults (`readiness.activeHomeID`).
3. **Kill:**
   - The user force-quits the application.
   - In-memory state (`UndoStack` history, current selection, viewport camera angle) is terminated.
   - Persisted on disk: `homeplan.json`, UserDefaults (`readiness.activeHomeID`, checklist ticks, meeting point, scan freshness), and caches (`RoutePlanCache`, `ScoreCache`).
4. **Relaunch:**
   - `escape_planApp.init()` opens `HomeDocumentStore`.
   - `ActiveHomeMemory` reads `readiness.activeHomeID` and restores the previously active home.
   - `ContentView.task` triggers `readiness.load()`. If offline, `ScoreCache` loads the cached score; if online, a fresh `/score` request is dispatched.
   - `HouseScreen` rebuilds from the saved document; undo/redo buttons start disabled (`canUndo = false`).

### 10.2 Error Behaviors
- **Document Unreadable / Malformed:**
  - `HomeDocumentStore.list()` skips corrupt files, leaving them intact on disk.
  - If the active home is unreadable, `ReadinessStore.load()` sets `scoreFailure = .localLoad(error)`, displaying an explanatory local load error rather than blaming network connection.
- **Schema Version Mismatch:**
  - Older schemas (1.0, 1.1, 2.0) are automatically migrated to 2.1 on read and saved back.
  - Documents with newer schemas trigger `PersistenceError.documentTooNew`, displaying a friendly message instructing the user to update the app without altering the file.
- **Storage Directory Unreachable:**
  - Fallback temporary store initializes with `storageUnavailable = true`.
  - Non-dismissible top banner alerts user across all tabs: *"Storage unavailable. Changes won't be saved."*
- **Offline Outage:**
  - Route view falls back to `RoutePlanCache` if fingerprint matches, presenting an offline banner with the timestamp of the cached plan.
  - If fingerprint does not match, routes gracefully clear and present a `BackendFailure` banner with a retry button.
