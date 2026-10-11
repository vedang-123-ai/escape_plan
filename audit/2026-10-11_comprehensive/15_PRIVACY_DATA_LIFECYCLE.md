# Audit Report 15: Privacy and Data Lifecycle

**Domain:** Privacy, Data Lifecycle, Storage, Transmission, Logging, and Regulatory Compliance  
**Auditor:** Agent 15 (Senior Privacy & Security Auditor)  
**Date:** 2026-10-11  
**Target Repository:** Escape Plan (iOS App + Python/FastAPI Backend)  
**Output Target:** `audit/2026-10-11_comprehensive/15_PRIVACY_DATA_LIFECYCLE.md`  

---

## 1. Executive Summary

This audit evaluates the complete privacy posture, data lifecycle, transmission footprint, local and cloud persistence, logging safeguards, and regulatory compliance of the Escape Plan system. Escape Plan combines an iOS application (SwiftUI/SceneKit/RoomPlan) and a hosted Python/FastAPI backend (Render/MongoDB/Anthropic Claude API).

### Key Architectural Strengths
1. **Unusual Candor in Disclosures:** Unlike conventional mobile applications that employ evasive marketing jargon, `escape_plan/Auth/AccountPrivacy.swift` contains an explicit inventory pinning the exact schema and request fields transmitted to compute endpoints (`/score`, `/routes`, `/evacuate`, `/convert`, `/chat`, `/build`).
2. **Strict Backend Logging Hygiene:** The backend expressly clamps `pymongo` command logging to `INFO` level (`backend/app/main.py:82-83`), preventing home geometries, room polygons, and household compositions from leaking into server logs during database queries. Backend configuration secrets enforce `repr=False` (`backend/app/config.py:33-38`).
3. **No Third-Party Analytics or Tracking:** Neither the iOS client nor the FastAPI backend integrates tracking SDKs or ad networks (e.g., Firebase, Google Analytics, TelemetryDeck, Mixpanel).
4. **Metadata Stripping on Imported Images:** Import Plan photo ingestion enforces downscaling and re-encodes photos via ImageIO without copying EXIF or GPS metadata (`escape_plan/Networking/ImagePreparation.swift:57-77`).
5. **Robust Password Hashing & Per-User Tokens:** Account authentication uses state-of-the-art Argon2id password hashing (`backend/app/auth/passwords.py`) and standard HMAC-SHA256 JWTs with explicit claim validation and expiry enforcement (`backend/app/auth/tokens.py`).

### High-Severity Privacy & Compliance Deficiencies
1. **Missing Apple Privacy Manifest (`PrivacyInfo.xcprivacy`):** The repository completely lacks a privacy manifest. The app accesses required-reason APIs (`NSPrivacyAccessedAPICategoryUserDefaults` and `NSPrivacyAccessedAPICategoryFileTimestamp`), making App Store submission subject to immediate rejection or compliance warnings under Apple's 2024 mandates.
2. **Total File Sharing Exposure (`UIFileSharingEnabled = YES`):** In `project.pbxproj`, `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are enabled. This exposes all documents in `<Documents>`—including private floor plans, occupant names, children's bedroom locations, disability flags, and unencrypted chat logs—to the iOS Files app and iTunes/Finder USB file sharing.
3. **Silent Deletion Failure on Expired Tokens (False Deletion Claim):** In `AuthSession.deleteAccount()`, receiving an HTTP 401 response is interpreted as "already deleted" and reported to the user as successful erasure. If a user's token expires (60-minute TTL), attempting account deletion leaves all cloud homes and user records intact in MongoDB while telling the user their data was permanently erased.
4. **Children's Personal Information (COPPA Exposure):** The app permits profiling children (`ProfileTag.child`) with real names, bedroom locations, and disability flags, and transmits these to cloud compute endpoints without an age gate, parental consent mechanism, or COPPA disclosure.
5. **Under-Declaration of Sensitive Health/Disability Data:** The app captures disability tags (`mobility_limited`, `hearing_impaired`, `vision_impaired`) and transmits them in every `/score`, `/routes`, and `/evacuate` payload, falling squarely under Apple's App Store "Sensitive Info" category, which has not yet been declared in submission documentation.
6. **Orphaned Sensitive Strings on Home Deletion:** Deleting a home deletes the `.homeplan.json` file and chat log, but leaves user free-text meeting points (which may contain real street addresses/landmarks) and checklist completion dates permanently in `UserDefaults`.

---

## 2. Scope and Files Inspected

### iOS Source Files Inspected
- `escape_plan/Auth/AccountPrivacy.swift`: Transparency inventory and user-facing privacy copy.
- `escape_plan/Auth/TokenStore.swift` & `escape_plan/Auth/KeychainTokenStore.swift`: Keychain storage and security attributes.
- `escape_plan/Auth/AuthSession.swift` & `escape_plan/Auth/AuthClient.swift`: Client auth session management and deletion flows.
- `escape_plan/Networking/APIClient.swift`: Base URLs, shared bearer token loading, and network requests.
- `escape_plan/Networking/APIClient+*.swift` (`+Score.swift`, `+Routes.swift`, `+Evacuate.swift`, `+Convert.swift`, `+Chat.swift`, `+Build.swift`, `+Analyze.swift`, `+Cache.swift`): Wire payloads and endpoints.
- `escape_plan/Networking/ImagePreparation.swift`: Photo downscaling, JPEG encoding, EXIF/GPS metadata stripping.
- `escape_plan/Persistence/HomeDocumentStore.swift`: Local home JSON storage layout in `Documents/Homes/`.
- `escape_plan/Persistence/ConversationStore.swift`: Chat storage layout in `Documents/Assistant/`.
- `escape_plan/Persistence/ChecklistStateStore.swift`: Checklist state storage in `UserDefaults`.
- `escape_plan/Persistence/DeviceIdentity.swift`: Device UUID storage in `UserDefaults`.
- `escape_plan/Persistence/ScoreCache.swift`: Score breakdown cache in `Caches/ScoreCache/`.
- `escape_plan/Persistence/HomeLibrary.swift`: Home deletion and duplication cascades.
- `escape_plan/Capture/Export/ScanStore.swift` & `ScanCleanup.swift`: RoomPlan scan file persistence and sweeping.
- `escape_plan/Export/MeetingPointStore.swift`: Meeting point string persistence in `UserDefaults`.
- `escape_plan/Export/ResponderSnapshotExtractor.swift`, `ResponderSnapshotJSON.swift`, `ResponderSnapshotStore.swift`: Fire department export generation, redaction, and caching.
- `escape_plan/Export/EscapePlanPDF.swift`: PDF generation and responder snapshot formatting.
- `escape_plan/Screens/ConsentSheet.swift` & `ShareWithFireDepartmentCard.swift`: Consent UI and activity controller invocation.
- `escape_plan/Screens/ProfileEditorView.swift`: Occupant name, tags, and bedroom assignment.
- `escape_plan/Screens/SettingsScreen.swift`: Privacy disclosure display, connection checks, server configuration.
- `escape_plan/RootView.swift` & `escape_plan/escape_planApp.swift`: App lifecycle and startup session handling.
- `escape_plan.xcodeproj/project.pbxproj`: Build configurations, permissions, file sharing flags, synchronized groups.

### Backend Source Files Inspected
- `backend/app/main.py`: Route declarations, lifespan context, logging setup, and pymongo log pinning.
- `backend/app/config.py`: Environment settings, secret masking (`repr=False`), budget parameters.
- `backend/app/database.py`: AsyncMongoClient connection lifecycle and URI sanitization.
- `backend/app/api_auth.py`: `/auth/register`, `/auth/login`, `/auth/me`, `/homes` endpoints and deletion logic.
- `backend/app/api_chat.py`: `/chat` request validation, history limits, and service invocation.
- `backend/app/cloud_repo.py`: MongoDB repository operations (`users`, `homes`), index creation, hard deletes.
- `backend/app/cloud_models.py`: Database document schemas for users and stored homes.
- `backend/app/auth/passwords.py`: Argon2id hashing and verification implementation.
- `backend/app/auth/tokens.py`: PyJWT issue, verification, claim enforcement, and secret resolution.
- `backend/app/ai/chat/service.py`: Claude prompt generation, rules, citations, and system context formatting.
- `backend/app/ai/chat/summary.py`: Extraction of home structure vs profiles for Claude.
- `backend/app/ai/builder.py`: `/build` tool loop, Claude vision invocation, prompt caching.
- `backend/app/limits.py`: Payload boundaries, token ceilings, character limits.
- `backend/requirements.txt`: Backend dependency inventory.

### Documentation Inspected
- `audit/2026-10-11_comprehensive/_AUDIT_BRIEF.md`: Core audit rules and constraints.
- `docs/tracker/notes/2026-10-01-s11-16-privacy-truth.md`: Pre-existing privacy audit notes.
- `docs/tracker/BLOCKERS.md`: Documented blockers regarding App Store privacy labels and deletion behaviors.
- `docs/submission/written-answers-draft.md`, `app-description.md`, `checklist.md`, `judge-access.md`: Public and submission privacy claims.

---

## 3. Methods and Checks Performed

1. **Complete Data Lifecycle Mapping:** Traced every entity (HomeModel, Room, Opening, Profile, Pet, Scan, ChatMessage, ChecklistItem, MeetingPoint, Credentials, JWT) from creation in UI, to local storage, network transmission, cloud persistence, and deletion.
2. **Network Endpoint Payload Audit:** Exhaustively checked all `URLRequest` constructions in Swift and cross-referenced each field against FastAPI Pydantic models in Python.
3. **Third-Party AI Transmission Verification:** Traced backend calls to the Anthropic SDK (`client.messages.create`) to determine exactly what resident data reaches Anthropic's servers.
4. **Local Persistence Inspection:** Verified data written to `FileManager` (Documents vs Caches vs Temp), `UserDefaults`, and iOS Keychain (`Security.framework`).
5. **File Sharing & Permissions Audit:** Inspected `project.pbxproj` for Info.plist generation, permission usage descriptions, file-sharing entitlements, and required-reason API declarations.
6. **Logging Hygiene Assessment:** Audited all instances of `os_log`, `Logger`, and `print()` in Swift, and `logging.getLogger()` in Python, verifying sensitive-field masking and log levels.
7. **Deletion and Tombstone Consistency Analysis:** Traced client and server operations upon account deletion and home deletion to verify whether data is purged or orphaned.
8. **Statutory and Platform Policy Cross-Checks:** Assessed compliance with Apple App Store Review Guidelines (Guideline 5.1 - Privacy, 5.1.1 Data Collection, Required-Reason APIs), COPPA (15 U.S.C. §§ 6501–6506), and OWASP credential handling guidelines.

---

## 4. Findings (with Evidence)

```
## [HIGH] A15-01: Missing Apple Privacy Manifest (PrivacyInfo.xcprivacy) for Required-Reason APIs
**Domain:** Regulatory & Platform Compliance  **Location:** `escape_plan.xcodeproj/project.pbxproj` / Target `escape_plan`
**Observed behavior:**
The repository contains no `PrivacyInfo.xcprivacy` file anywhere in its directory tree. The Xcode project (`escape_plan.xcodeproj/project.pbxproj`) defines `GENERATE_INFOPLIST_FILE = YES` but does not reference or include any privacy manifest. However, the app directly invokes multiple APIs designated by Apple as "Required Reason APIs":
1. `NSPrivacyAccessedAPICategoryUserDefaults`: Used extensively across `escape_plan/Networking/APIClient.swift:59`, `escape_plan/Persistence/ChecklistStateStore.swift:18`, `escape_plan/Export/MeetingPointStore.swift:23`, `escape_plan/Readiness/ActiveHomeMemory.swift:17`, `escape_plan/Readiness/ScanFreshnessStore.swift:14`, and `escape_plan/Persistence/DeviceIdentity.swift:23`.
2. `NSPrivacyAccessedAPICategoryFileTimestamp`: Used in `escape_plan/Persistence/HomeDocumentStore.swift:95-96` and `escape_plan/Capture/Export/ScanCleanup.swift:50-53` (`fileManager.attributesOfItem(atPath:)` and `contentsOfDirectory(at:includingPropertiesForKeys:)`).

**Evidence:**
A full filesystem search across the repository confirms zero privacy manifests:
`find . -name "*.xcprivacy"` returns no files.
In `escape_plan/Persistence/ChecklistStateStore.swift:21-25`:
```swift
init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
}
```
In `escape_plan/Persistence/HomeDocumentStore.swift:94-98`:
```swift
struct SummaryEntry: Equatable, Sendable {
    let modificationDate: Date?
    let fileSize: Int?
    let summary: HomeSummary?
}
```

**Expected behavior:**
Under Apple App Store submission rules in effect since May 1, 2024, every app and third-party SDK using Required-Reason APIs must include a `PrivacyInfo.xcprivacy` manifest declaring the API categories and valid reason codes (e.g., `CA92.1` for accessing app-container UserDefaults, and `C617.1` for file timestamps inside the app container).

**Root cause:**
The privacy manifest was never authored during project scaffolding or subsequent privacy remediation sprints.

**Impact:**
App Store Connect rejects builds missing required-reason declarations (errors ITMS-91053, ITMS-91054) or flags them during App Review, blocking submission.

**Recommended improvement:**
Create `escape_plan/PrivacyInfo.xcprivacy` in the main app target. Declare:
- `NSPrivacyAccessedAPITypes`:
  - `NSPrivacyAccessedAPIType`: `NSPrivacyAccessedAPICategoryUserDefaults`, `NSPrivacyAccessedAPITypeReasons`: `["CA92.1"]`
  - `NSPrivacyAccessedAPIType`: `NSPrivacyAccessedAPICategoryFileTimestamp`, `NSPrivacyAccessedAPITypeReasons`: `["C617.1"]`
- `NSPrivacyTracking`: `false`
- `NSPrivacyCollectedDataTypes`: Declare collected categories (User Content, Sensitive Info).

**Dependencies:** None.
**Verification status:** Verified by source inspection
**Confidence:** High   **Effort:** Small (15 minutes to generate plist)
```

---

```
## [HIGH] A15-02: UIFileSharingEnabled Exposes Private Floor Plans, Child Profiles, and Chat Logs via Files App and Finder
**Domain:** Local Storage & Data Exposure  **Location:** `escape_plan.xcodeproj/project.pbxproj:560,578` / `escape_plan/Persistence/HomeDocumentStore.swift:31-39`
**Observed behavior:**
The Xcode project enables document sharing in place and iTunes file sharing:
```
INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES;
INFOPLIST_KEY_UIFileSharingEnabled = YES;
```
Because `HomeDocumentStore` saves all homes to `<Documents>/Homes/<home_id>.homeplan.json` and `ConversationStore` saves chat logs to `<Documents>/Assistant/<home_id>.json`, every document stored in the app's Documents folder is exposed directly in the iOS Files app under "On My iPhone -> Escape Plan" and can be copied off the device via a USB cable using Mac Finder or PC iTunes without passcode/app authentication.

**Evidence:**
In `escape_plan.xcodeproj/project.pbxproj:559-563`:
```
GENERATE_INFOPLIST_FILE = YES;
INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES;
INFOPLIST_KEY_NSCameraUsageDescription = "Escape Plan uses the camera and LiDAR scanner to measure the rooms, doors and windows of your home so it can map your fire escape routes.";
INFOPLIST_KEY_UIFileSharingEnabled = YES;
```
In `escape_plan/Persistence/HomeDocumentStore.swift:31-38`:
```swift
let documents = try fileManager.url(
    for: .documentDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)
try self.init(directory: documents.appendingPathComponent("Homes", isDirectory: true),
              fileManager: fileManager)
```
In `escape_plan/Persistence/ConversationStore.swift:82-89`:
```swift
let documents = try fileManager.url(
    for: .documentDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)
let directory = documents.appendingPathComponent("Assistant", isDirectory: true)
```

**Expected behavior:**
Unless an app is an explicit document viewer/editor intended for external desktop file syncing, sensitive private household records, child profiles, and AI conversation histories should be saved in `Application Support` (`.applicationSupportDirectory`), which is sandboxed and inaccessible to Files.app or desktop file browsing. Only deliberately exported artifacts (such as exported PDFs) should enter public directories or share sheets.

**Root cause:**
During early development (Sprint S1.4), developers enabled `UIFileSharingEnabled` to easily pull scan fixtures and sample JSON files off test devices via Finder (`ScanStore.swift:7-8`). This debug setting was never removed before release configuration.

**Impact:**
Any person with physical access to an unlocked phone, or who connects the device to a computer that has been trusted, can copy all floor plans, family members' names, children's sleeping quarters, disability tags, and AI assistant chat logs in cleartext JSON.

**Recommended improvement:**
1. In `project.pbxproj`, set `INFOPLIST_KEY_UIFileSharingEnabled = NO` and `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = NO` for Release builds (or remove both).
2. Migrate `HomeDocumentStore` and `ConversationStore` to use `.applicationSupportDirectory` instead of `.documentDirectory`.
3. Provide explicit user-driven export actions (e.g. `UIDocumentPickerViewController` or `ShareSheet`) when the user explicitly chooses to export a plan.

**Dependencies:** May affect developer fixture extraction workflows if not replaced by an explicit debug export button.
**Verification status:** Verified by source inspection
**Confidence:** High   **Effort:** Small
```

---

```
## [HIGH] A15-03: Account Deletion Falsely Reports Successful Erasure When Server Returns 401 on Expired Token
**Domain:** Retention, Deletion, and Privacy Claims  **Location:** `escape_plan/Auth/AuthSession.swift:259-285` / `backend/app/api_auth.py:165-185`
**Observed behavior:**
When a signed-in user taps "Delete Account", `AuthSession.deleteAccount()` executes `DELETE /auth/me`. If the user's JWT has expired (tokens expire after 60 minutes per `JWT_ACCESS_TTL_MINUTES = 60`), the backend rejects the request with HTTP 401 Unauthorized (`detail: "Could not validate credentials"`).
`AuthSession.deleteAccount()` explicitly catches `AuthFailure` with kind `.invalidCredentials` and treats it as SUCCESS:
```swift
catch let authFailure as AuthFailure {
    // A 401 means the account is already gone — someone deleted it from another
    // device, or the token aged out. Either way there is nothing left to delete, so
    // ending the session locally is the correct outcome...
    guard authFailure.kind == .invalidCredentials else { ... }
}
```
The method returns `true`, logs the user out locally, and shows the confirmation that the account and all cloud homes have been erased permanently (`AccountPrivacy.deletionSummary`). In reality, the server never deleted the account or the homes. They remain permanently stored in MongoDB.

**Evidence:**
In `escape_plan/Auth/AuthSession.swift:268-278`:
```swift
do {
    try await client.deleteAccount(token: token)
} catch let authFailure as AuthFailure {
    guard authFailure.kind == .invalidCredentials else {
        failure = authFailure
        return false
    }
} catch {
    failure = AuthFailure.networkFailure
    return false
}
discardStoredSession()
return true
```
In `backend/app/auth/tokens.py:83-86` & `backend/app/api_auth.py:107-112`:
```python
# Expired token raises AuthTokenError -> _UNAUTHORIZED (HTTP 401)
if not token:
    raise _UNAUTHORIZED
try:
    user_id = decode_access_token(token)
except AuthTokenError:
    raise _UNAUTHORIZED
```

**Expected behavior:**
If the token is expired or invalid, the app must not falsely assure the user that their server data was permanently erased. It should prompt the user to re-authenticate with their password so that `DELETE /auth/me` can be authenticated and executed against the database.

**Root cause:**
The client erroneously equated "token rejected / expired" with "the account was already deleted on another device".

**Impact:**
Violation of Apple App Store Review Guideline 5.1.1(v) (Account Deletion) and privacy promises (`AccountPrivacy.deletionSummary`). Users believe their personal data (email, floor plans, family names) is gone, while it remains stored on the backend.

**Recommended improvement:**
Check `token.isExpired()` prior to initiating deletion. If expired or if a 401 is received, prompt the user to re-enter their password to re-authenticate and complete genuine server-side account deletion. Only discard the local session and display deletion confirmation when the backend returns HTTP 204 No Content.

**Dependencies:** Relates to documented note in `BLOCKERS.md:1216-1222`.
**Verification status:** Verified by source inspection
**Confidence:** High   **Effort:** Medium
```

---

```
## [HIGH] A15-04: Children's Personally Identifiable Information Collected and Transmitted Without COPPA Disclosure or Consent Mechanism
**Domain:** Child Privacy (COPPA) & Vulnerable Population Data  **Location:** `escape_plan/Screens/ProfileEditorView.swift:47-57,133` / `escape_plan/Models/HomeModel.swift:220-244` / `backend/app/main.py:360,638`
**Observed behavior:**
The application allows users to create household profiles with the explicit tag `Child` (`ProfileTag.child`). For each child, the user enters the child's name, their specific bedroom in the house, and any associated mobility or sensory impairment tags.
Whenever the user computes an escape route, runs an evacuation simulation, or calculates a readiness score, this child profile—including their name, tags, and bedroom location—is serialized into `HomeModel` and transmitted across the network to `POST /score`, `POST /routes`, and `POST /evacuate` on the backend server.
The application contains:
- No age verification or age gate.
- No notice or disclosure regarding the Children's Online Privacy Protection Act (COPPA).
- No verifiable parental consent mechanism.

**Evidence:**
In `escape_plan/Screens/ProfileEditorView.swift:132-140`:
```swift
var displayName: String {
    switch self {
    case .child: return "Child"
    case .elderly: return "Elderly"
    case .mobility_limited: return "Limited Mobility"
    case .pet: return "Pet"
    case .hearing_impaired: return "Hearing Impaired"
    case .vision_impaired: return "Vision Impaired"
    }
}
```
In `escape_plan/Models/HomeModel.swift:220-225`:
```swift
struct Profile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var tags: [ProfileTag]
    var bedroom_room_id: String
```
In `escape_plan/Networking/APIClient+Score.swift:16`:
```swift
ScoreRequest(home: home, checklist_state: checklistState)
```
Targeted search for COPPA or age gating returns zero results across all documentation, iOS code, and backend code.

**Expected behavior:**
Under COPPA (15 U.S.C. §§ 6501–6506; 16 CFR Part 312), online services that collect personal information from or about children under age 13 (including names, physical location indicators, and persistent identifiers) must provide prominent notice of what information is collected, how it is used, and obtain verifiable parental consent. While the app is framed for family use, collecting children's names and exact bedroom layouts creates severe regulatory liability if not addressed with explicit terms and parental consent disclosures.

**Root cause:**
The profile feature was designed strictly from a physical routing constraint perspective (e.g. child routing penalties for windows) without consideration of federal children's online privacy regulations.

**Impact:**
FTC COPPA enforcement risks, Apple App Store guideline scrutiny (Guideline 1.3 - Kids Category and Guideline 5.1.4 - Kids Privacy), and state privacy law exposure (e.g., California Age-Appropriate Design Code).

**Recommended improvement:**
1. Add an explicit Terms of Service and Privacy Policy gate stating the app is directed to adults / parents acting as heads of household.
2. In the profile creation screen, provide a privacy advisory stating that pseudonyms or initials (e.g., "Child 1", "E.Y.") may be used instead of full legal names.
3. If profile names are only needed locally for UI differentiation, strip occupant names from network payloads sent to compute endpoints (sending only anonymous IDs and routing constraint tags).

**Dependencies:** Requires updating `ProfileEditorView` copy and compute request serializers.
**Verification status:** Verified by source inspection
**Confidence:** High   **Effort:** Medium
```

---

```
## [MEDIUM] A15-05: Apple App Store Privacy Nutrition Label Under-Declares "Sensitive Info" (Disability and Medical Flags Transmitted in Compute Payloads)
**Domain:** App Store Privacy Questionnaire  **Location:** `escape_plan/Auth/AccountPrivacy.swift:56-85` / `docs/tracker/BLOCKERS.md:1200-1206`
**Observed behavior:**
The application captures health and medical vulnerability data via `ProfileTag`:
- `.mobility_limited` (wheelchair, physical impairment)
- `.hearing_impaired` (inability to hear smoke alarms)
- `.vision_impaired` (inability to see smoke/exits)
Under Apple's App Store privacy questionnaire taxonomy, "Sensitive Info" specifically includes "health, disability, or biometric data".
In Escape Plan, every call to `/score`, `/routes`, and `/evacuate` transmits the full `HomeModel`, which carries these disability tags along with occupant names and room assignments.
While `docs/tracker/BLOCKERS.md:1200-1206` acknowledges that "health-related vulnerability tags" leave the device, neither the submission materials in `docs/submission/` nor any App Store Connect questionnaire draft accounts for the mandatory declaration of "Sensitive Info -> Health & Medical / Physical condition" linked to user content.

**Evidence:**
In `docs/tracker/BLOCKERS.md:1200-1206`:
```markdown
- [ ] **S11.13: the App Store privacy label must match this copy.** Data that leaves the device, signed out: home layout
      and room names; household composition — member names, **health-related vulnerability tags** (elderly,
      mobility-limited, hearing- or vision-impaired, child, pet), where each sleeps; checklist progress...
```
In `escape_plan/Auth/AccountPrivacy.swift:68-73`:
```swift
Disclosure(
    text: "The whole home, every time the server works something out for you: the "
        + "floor plan and room names, the names you gave household members and pets, "
        + "their tags (child, elderly, pet, mobility-limited, hearing- or "
        + "vision-impaired) and the room each one sleeps in.",
    keys: ["home"])
```

**Expected behavior:**
When submitting an app to the App Store, the developer must answer Apple's privacy questionnaire accurately. If disability or mobility limitations are collected and transmitted (even for stateless routing computation), "Sensitive Info" must be selected under Data Types, categorized under App Functionality, and marked as Linked to User (when accounts are used) or Not Linked to User (when anonymous).

**Root cause:**
The privacy questionnaire task was deferred in `BLOCKERS.md` and has not been formalized in `docs/submission/`.

**Impact:**
Misrepresenting data collection in App Store Connect violates developer terms and causes rejection during App Review or subsequent developer audit.

**Recommended improvement:**
Complete the official App Store Privacy Questionnaire draft in `docs/submission/` declaring:
1. **User Content:** Other User Content (Home floor plans, room names, chat messages).
2. **Sensitive Info:** Physical condition / disability flags (`mobility_limited`, `hearing_impaired`, `vision_impaired`).
3. **Contact Info:** Email (if accounts/sync active).
4. **Usage:** App Functionality only. Tracking: No.

**Dependencies:** Depends on submission owner S11.13.
**Verification status:** Verified by source inspection
**Confidence:** High   **Effort:** Small
```

---

```
## [MEDIUM] A15-06: Local Home Deletion Leaves Orphaned Sensitive Data (Meeting Point Free-Text, Checklist State) in UserDefaults
**Domain:** Data Lifecycle & Retention  **Location:** `escape_plan/Persistence/HomeLibrary.swift:70-85` / `escape_plan/Export/MeetingPointStore.swift:29-45` / `escape_plan/Persistence/ChecklistStateStore.swift:4-8`
**Observed behavior:**
When a resident deletes a home in the app via `HomeLibrary.delete(homeID:)`:
- The primary document `<Documents>/Homes/<home_id>.homeplan.json` is deleted.
- The assistant conversation `<Documents>/Assistant/<home_id>.json` is deleted.
- A deletion tombstone is recorded in `SyncState.json`.
However, auxiliary data persisted in `UserDefaults` is NEVER purged:
1. `export.meetingPoint.<home_id>`: User free-text describing their outside emergency meeting point (e.g., "Under the oak tree at 124 Elm Street", "Corner of 4th and Main").
2. `checklistState.<home_id>`: Dictionary of checklist item completions and completion dates.
3. `readiness.scanFreshnessDismissed.<home_id>`: Scan freshness dismissal flag.
4. `Caches/ScoreCache/<home_id>.json`: Disk-cached score breakdowns are not deleted unless `ReadinessStore.clearScore` happens to be invoked.

**Evidence:**
In `escape_plan/Persistence/ChecklistStateStore.swift:7-8`:
```swift
// Trade-off, documented in docs/decisions.md: state doesn't travel with export/import, and a
// deleted home leaves an orphaned (tiny, harmless) entry behind.
```
In `escape_plan/Persistence/HomeLibrary.swift:70-85`:
```swift
func delete(homeID: String) -> Bool {
    var deleted = false
    perform {
        try store.delete(homeID: homeID)
        deleted = true
        editor?.homeWasDeleted(homeID: homeID)
        let threadDeletion = Result { try conversations?.deleteConversation(homeID: homeID) }
        try deletionObserver?.homeWasDeletedLocally(homeID: homeID)
        try threadDeletion.get()
    }
    return deleted
}
```
Notice `HomeLibrary.delete` never calls `MeetingPointStore`, `ChecklistStateStore`, or `ScoreCache`.

**Expected behavior:**
When a user deletes a home, all associated data—including free-text location descriptions in `MeetingPointStore` and task timestamps—should be deleted from `UserDefaults` and disk caches.

**Root cause:**
The original developers treated orphaned `UserDefaults` keys as a "tiny, harmless trade-off" (`ChecklistStateStore.swift:8`) without considering that `MeetingPointStore` contains sensitive user-authored physical location strings.

**Impact:**
Residual personal data remains on the device indefinitely in `Library/Preferences/<bundle-id>.plist`. If a home ID is ever re-used or if the defaults plist is inspected, historical location and checklist data persists.

**Recommended improvement:**
In `HomeLibrary.delete(homeID:)`, add clean-up invocations:
```swift
MeetingPointStore().setMeetingPoint("", forHomeID: homeID)
ChecklistStateStore().clear(homeID: homeID) // implement defaults.removeObject(forKey:)
ScanFreshnessStore().clear(homeID: homeID)
try? ScoreCache().remove(homeID: homeID)
```

**Dependencies:** None.
**Verification status:** Verified by source inspection
**Confidence:** High   **Effort:** Small
```

---

```
## [MEDIUM] A15-07: Shared Backend Bearer Token Bundled in Plaintext App Bundle and Persisted in Unencrypted UserDefaults
**Domain:** Secret Management & Credential Storage  **Location:** `escape_plan/Networking/APIClient.swift:42,75,190-196` / `escape_plan.xcodeproj/project.pbxproj`
**Observed behavior:**
The app authenticates requests to compute endpoints using a shared bearer token. This token is bundled into the application bundle via `BackendConfig.local.json` (`APIClient.bundledBearerToken()`). Furthermore, if a user enters or modifies a token in Settings, `APIClient.overrideBearerToken()` writes the token directly into `UserDefaults.standard` under the key `"APIClient.bearerToken"`.
`UserDefaults` is stored as an unencrypted XML/binary plist on disk (`Library/Preferences/<bundle-id>.plist`).

**Evidence:**
In `escape_plan/Networking/APIClient.swift:72-77`:
```swift
func overrideBearerToken(_ token: String) {
    bearerToken = token
    isTokenOverridden = true
    defaults.set(token, forKey: Self.bearerTokenDefaultsKey)
    defaults.set(true, forKey: Self.tokenOverriddenDefaultsKey)
}
```
In `escape_plan/Auth/KeychainTokenStore.swift:4-7`:
```swift
// the shared backend bearer token lives in UserDefaults (Networking/APIClient.swift), which
// is fine for a value that ships in the build and is not a per-user credential. A JWT that
// authenticates one person's account is not that, so it does not go in UserDefaults.
```

**Expected behavior:**
All secrets and authentication tokens—even shared deployment tokens—should be stored in the iOS Keychain rather than cleartext `UserDefaults`. In addition, client-embedded tokens should be treated as fundamentally public client identifiers rather than true server secrets.

**Root cause:**
The developers distinguished between per-user JWTs (which they properly stored in `KeychainTokenStore`) and the build's shared bearer token, assuming `UserDefaults` was sufficient for a build-shipped token.

**Impact:**
Any backup, jailbroken device inspection, or extraction of the application sandbox easily yields the backend bearer token, enabling unauthorized third parties to call the hosted backend directly.

**Recommended improvement:**
1. Migrate bearer token storage to the iOS Keychain (reusing `TokenStore` architecture).
2. Continue enforcing rate limits and daily call budgets on the backend based on client IP headers (`cf-connecting-ip`) rather than relying on the bearer token as an authorization barrier.

**Dependencies:** None.
**Verification status:** Verified by source inspection
**Confidence:** High   **Effort:** Small
```

---

```
## [LOW] A15-08: Missing Hosted Public Privacy Policy URL Required for TestFlight and App Store Submission
**Domain:** Policy & Submission Readiness  **Location:** `docs/submission/judge-access.md:49,112`
**Observed behavior:**
The repository does not contain an external, publicly hosted Privacy Policy document or URL. While the app contains clear in-app disclosure text (`AccountPrivacy.swift`), Apple Developer Program guidelines and TestFlight external testing rules require a valid, publicly accessible HTTPS URL to a Privacy Policy before external testing or App Store submission can be approved.

**Evidence:**
In `docs/submission/judge-access.md:112`:
```markdown
2. Write a short privacy policy page (it can be adapted from the app's Settings "What leaves this iPhone?" text) and...
```
A search across all repository documentation confirms that no hosted URL has been deployed or configured.

**Expected behavior:**
A static privacy policy page matching the app's disclosures in `AccountPrivacy.swift` must be hosted on a public web server (e.g. GitHub Pages or on the backend's Render domain at `/privacy`) and linked in the App Store Connect metadata.

**Root cause:**
Submission preparation is currently in draft status (`written-answers-draft.md`).

**Impact:**
External TestFlight beta review and final App Store submission are blocked until an active URL is provided.

**Recommended improvement:**
Publish the text of `AccountPrivacy.swift` as a clean HTML/Markdown page hosted at `https://escape-plan-backend.onrender.com/privacy` or on GitHub Pages, and record the URL in `docs/submission/`.

**Dependencies:** Requires backend or web hosting deployment.
**Verification status:** Verified by source inspection
**Confidence:** High   **Effort:** Small (1 hour)
```

---

```
## [OBSERVATION] A15-09: "Share with Fire Department" Snapshot Has No Network Recipient and Redacts Names by Default
**Domain:** Data Sharing & Third-Party Disclosure  **Location:** `escape_plan/Screens/ConsentSheet.swift` / `escape_plan/Export/ShareWithFireDepartmentCard.swift` / `escape_plan/Export/ResponderSnapshotExtractor.swift`
**Observed behavior:**
The feature marketed as "Share with your fire department" does NOT connect to any municipal CAD (Computer-Aided Dispatch) system, fire department portal, or backend transmission endpoint.
Instead, it:
1. Presents an explicit `ConsentSheet` every single time it is triggered.
2. Excludes occupant names by default (`includeOccupantNames = false`), listing vulnerable occupants strictly by count and room (e.g., "1 occupant(s) — Bedroom 2").
3. Writes `ResponderSnapshot.pdf` and `ResponderSnapshot.json` to `<Caches>/ResponderSnapshots/`.
4. Opens standard iOS `UIActivityViewController` (`ShareSheet`), leaving it entirely to the resident to choose how to transmit the files (AirDrop, Messages, Mail, or Save to Files).
5. In the generated PDF (`EscapePlanPDF.swift:220-235`), occupant names are NEVER rendered, even if the user checks "Include occupant names" (names appear only in `ResponderSnapshot.json` if explicitly opted in).

**Evidence:**
In `escape_plan/Screens/ConsentSheet.swift:58-60`:
```swift
Text("This is a prevention and readiness snapshot, not a tool for firefighters to use mid-fire. Nothing is ever sent automatically — you pick the app (AirDrop, Messages, Files) each time you share.")
```
In `escape_plan/Export/ResponderSnapshotExtractor.swift:39-45`:
```swift
let vulnerableList = vulnerableCounts.map {
    ResponderSnapshotJSON.VulnerableOccupant(
        count: $0.value.count,
        roomName: $0.value.roomName,
        floorLevel: $0.value.level,
        names: consent.includeOccupantNames ? $0.value.names.sorted() : nil)
}
```
In `escape_plan/Export/ShareWithFireDepartmentCard.swift:109-120`:
```swift
.background(ShareSheet(urls: $shareURLs))
...
shareURLs = try exporter.writeResponderSnapshot(preview: preview, consent: consent)
```

**Expected behavior:**
This behavior matches the claims in `ConsentSheet.swift` and `docs/tracker/notes/2026-10-01-s11-16-privacy-truth.md`. It demonstrates strong privacy-by-design by avoiding unintended data exfiltration and requiring active user mediation.

**Impact:**
Positive privacy design. However, users or judges who read "Share with your fire department" might anticipate an automated emergency service integration; the clear disclaimers in `ConsentSheet` and on the snapshot card are vital to prevent misunderstanding.

**Recommended improvement:**
Maintain the current architecture. Consider rendering occupant names in the PDF when opted in, or explicitly updating the consent copy to clarify that names are only included in the accompanying JSON file.

**Dependencies:** None.
**Verification status:** Verified by source inspection
**Confidence:** High   **Effort:** None
```

---

## 5. Positive Findings

1. **Explicit Privacy Disclosure Code Coverage:** In `escape_plan/Auth/AccountPrivacy.swift`, the disclosure strings are maintained as Foundation-level enums backed by unit tests (`AccountPrivacyTests.swift`). The test suite serializes real request payloads and verifies that every top-level key sent to the server is accounted for in user-facing disclosures.
2. **Robust EXIF and GPS Stripping in ImagePreparation:** When users pick photos for Import Plan (`/build`), `ImagePreparation.photo` (`escape_plan/Networking/ImagePreparation.swift:57-77`) renders the image onto a clean white `CGContext` and encodes fresh JPEG data using ImageIO without attaching `kCGImagePropertyGPSDictionary` or `kCGImagePropertyExifDictionary`. Unit test `ImagePreparationTests.testLocationMetadataIsNotSent` verifies this behavior.
3. **No PII Forwarded to Anthropic in `/chat`:** While the entire `HomeModel` is sent to the Escape Plan backend in `POST /chat`, the backend's chat service (`backend/app/ai/chat/summary.py:16-36`) only extracts structural floor and room geometry (floor names, room types, exits, stairs) to construct Claude's system prompt. Because the iOS client does not populate `profiles` in `ChatRequest`, resident names and disability flags are never passed to Anthropic.
4. **pymongo Wire-Level Logging Protection:** In `backend/app/main.py:82-83`, loggers `"pymongo"`, `"pymongo.command"`, `"pymongo.connection"`, and `"pymongo.serverSelection"` are clamped to `logging.INFO`. This prevents accidental elevation of root log levels to `DEBUG` from dumping entire user home documents and street addresses into hosted server logs.
5. **Argon2id Password Storage & Timing Oracle Defense:** The backend implements Argon2id password hashing (`backend/app/auth/passwords.py`) with OWASP-compliant memory and time cost parameters. In `/auth/login` (`backend/app/api_auth.py:50-55`), non-existent emails are verified against a dummy Argon2id hash to eliminate timing oracles during user enumeration.
6. **Hard Deletes on Server:** Database deletion operations (`UserRepository.delete` and `HomeRepository.delete_for_user` in `backend/app/cloud_repo.py:109-118,157-181`) execute immediate hard deletes (`delete_one`, `delete_many`), avoiding uncollected soft-deleted records in the database.
7. **Ephemeral Raw Scan Cleanup:** `ScanCleanup.swift` implements automatic sweeping of raw RoomPlan capture artifacts (`raw.roomplan.json`, `apple-raw.json`, `scan.usdz`), deleting them after conversion or purging them if older than 7 days in Release builds.

---

## 6. Systemic Issues and Root Causes

1. **Development Convenience Artifacts Remaining in Production Configuration:**
   - Enabling `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` in `project.pbxproj` was done to facilitate pulling test fixtures via Finder during early LiDAR development. Leaving it enabled compromises sandbox isolation.
   - Leaving the shared bearer token in `BackendConfig.local.json` inside a synchronized project group bundles the token into production `.app` archives.
2. **Disconnected Client and Server Deletion Semantics:**
   - The client assumed that an HTTP 401 response meant an account had already been deleted elsewhere, overlooking standard token expiration (60-minute TTL). This created a critical failure mode where account deletion silently fails while reporting success.
3. **Regulatory Privacy Oversight for Child Data (COPPA):**
   - Profiles were conceived purely as routing constraints (e.g. limiting stair traversal for mobility impairments or adjusting egress speeds for children). The legal implications of transmitting child names and bedroom locations to cloud infrastructure were not cross-checked against FTC COPPA standards.
4. **Deferred Documentation and Manifest Alignment:**
   - Apple's 2024 Privacy Manifest (`PrivacyInfo.xcprivacy`) mandate was never integrated into the Xcode project, despite the app relying heavily on `UserDefaults` and file timestamps.

---

## 7. Unverified Assumptions

1. **MongoDB Atlas Snapshot & Backup Retention:** `AccountPrivacy.deletionSummary` claims that deleting an account erases every home "straight away and permanently". The code verifies that hard deletes occur in the active database collection (`backend/app/cloud_repo.py:179-181`). However, whether the production MongoDB Atlas cluster has automated continuous backups or daily snapshots enabled (and the retention duration of those snapshots) cannot be verified from the codebase alone.
2. **Render Infrastructure Request Logs:** The app disclosure claims: "Like any server, ours records when each request arrived and from which internet address." The exact log retention window on Render's platform dashboard is an infrastructure setting outside repo inspection.
3. **Anthropic API Server-Side Data Retention:** Prompts sent to Anthropic's Claude API are governed by Anthropic's commercial API terms (which stipulate that API inputs are not used for model training and are retained for 30 days for trust and safety before deletion). This behavior is an external vendor policy, not code-enforced.

---

## 8. Areas Requiring Further Investigation

1. **Live Atlas Cluster Configuration:** Verify whether the deployed MongoDB Atlas cluster is on the M0 free tier (which maintains no automated backup snapshots) or an M10+ tier with continuous backup retention.
2. **App Store Connect Privacy Questionnaire Submission:** Before submitting the binary, verify that the questionnaire in App Store Connect precisely mirrors the findings in this report, specifically including "Sensitive Info" for disability tags.
3. **Simulator vs Physical Device Keychain Persistence:** On real iOS devices, Keychain items with `kSecAttrAccessibleAfterFirstUnlock` persist across app reinstallation. `AuthSession.purgeKeychainOnFirstLaunch()` attempts to detect reinstalls via a `UserDefaults` flag (`auth.hasLaunchedBefore.v1`), which should be validated on a physical device.

---

## 9. Recommended Priorities

| Priority | Finding ID | Action Item | Target File(s) | Estimated Effort |
|:---|:---|:---|:---|:---|
| **P0** | **A15-01** | Create and bundle `PrivacyInfo.xcprivacy` declaring `UserDefaults` (`CA92.1`) and `FileTimestamp` (`C617.1`) to prevent App Store rejection. | `escape_plan/PrivacyInfo.xcprivacy`, `project.pbxproj` | Small (< 1 hour) |
| **P0** | **A15-02** | Remove or set `UIFileSharingEnabled = NO` and migrate sensitive home/chat documents from `Documents/` to `Application Support/`. | `project.pbxproj`, `HomeDocumentStore.swift`, `ConversationStore.swift` | Medium (2–3 hours) |
| **P1** | **A15-03** | Fix `AuthSession.deleteAccount()`: re-authenticate on 401 instead of falsely reporting successful deletion on expired tokens. | `escape_plan/Auth/AuthSession.swift` | Medium (2 hours) |
| **P1** | **A15-04** | Implement COPPA parental advisory / disclaimer in `ProfileEditorView` and allow pseudonymous initials for children; strip names from compute payloads. | `ProfileEditorView.swift`, `APIClient+*.swift`, `docs/submission/` | Medium (3 hours) |
| **P1** | **A15-05** | Update App Store Privacy Label draft in `docs/submission/` to include "Sensitive Info" (health/disability tags). | `docs/submission/`, `docs/playbook/S11-13.md` | Small (1 hour) |
| **P2** | **A15-06** | Purge orphaned `MeetingPointStore` and `ChecklistStateStore` keys in `UserDefaults` when a home is deleted in `HomeLibrary.delete()`. | `escape_plan/Persistence/HomeLibrary.swift` | Small (1 hour) |
| **P2** | **A15-07** | Move client bearer token overrides from plaintext `UserDefaults` to iOS Keychain. | `escape_plan/Networking/APIClient.swift` | Small (1–2 hours) |
| **P2** | **A15-08** | Host public Privacy Policy page on backend or GitHub Pages and document URL for TestFlight/App Store submission. | `backend/app/main.py` or docs site | Small (1 hour) |
