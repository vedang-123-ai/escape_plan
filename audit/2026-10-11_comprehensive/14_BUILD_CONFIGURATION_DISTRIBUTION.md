# Domain 14: Build Configuration, Packaging & Distribution Audit

**Auditor:** Agent 14 (Build Configuration & Distribution)  
**Date:** 2026-10-11  
**Project:** Escape Plan (`escape_plan.xcodeproj`)  
**Host Toolchain:** Xcode 27.0 (Build 27A266a), macOS 26A434, iOS SDK 27.0  
**DerivedData Isolation:** `/tmp/audit-dd-14`  
**Evidence Log:** `audit/2026-10-11_comprehensive/evidence/14_build_runs.md`

---

## 1. Executive Summary

A comprehensive, end-to-end investigation of the build system, Xcode project configuration, packaging pipeline, target schemes, entitlements, and distribution readiness was conducted for the Escape Plan repository.

### Key Takeaways
1. **Real-Device & Archive Builds are Hard-Blocked (Critical Defect):**  
   While simulator builds succeed, compiling for a physical device (`generic/platform=iOS`) and archiving (`xcodebuild archive`) fail immediately with a compilation error in `escape_plan/Capture/RoomCaptureController.swift:118:23`: `cannot assign to property: 'configuration' is a 'let' constant`. Because the affected code is isolated behind `#if canImport(RoomPlan) && !targetEnvironment(simulator)`, local developer type-checking scripts (`scripts/typecheck-ios.sh`) and GitHub Actions CI (`gate.yml`) only compile against the simulator SDK and never detected this fatal defect. **The project cannot currently be submitted to TestFlight or the App Store, nor run on any physical device.**

2. **Plaintext Secret Bundling in Release IPA:**  
   Because the Xcode project uses Xcode 16's `PBXFileSystemSynchronizedRootGroup` for the `escape_plan` target, any file located inside the `escape_plan/` directory is automatically packaged into the `.app` bundle root. Consequently, `BackendConfig.local.json` (which contains the shared backend bearer token) is packaged directly into production Release builds as plaintext. Any user or attacker downloading the IPA can extract this token. Furthermore, internal documentation (`CLAUDE.md`, `README.md`) is also packaged into the production bundle.

3. **Clean-Build Breakage in Release Mode:**  
   `BackendConfig.local.json` is gitignored. In a clean repository clone on a CI runner or fresh workstation, this file does not exist. While Debug builds permit entering a bearer token or server URL via Settings, Release builds compile out the Advanced section using `#if DEBUG` and hardcode `honorOverrides = false`. On a clean Release build, `bearerToken` defaults to `""`, permanently disabling all authenticated endpoints (scoring, pathfinding analysis, AI floor plan generation) with no user-facing recovery mechanism.

4. **Distribution Readiness & Compliance:**  
   The project has no external CocoaPods, Carthage, or SPM binary dependencies (relying entirely on system frameworks and a lightweight internal test package `tools/editorcore`). App icon assets are modern and complete (1024x1024 single icon with iOS 18 dark and tinted variants). The deployment target is iOS 17.0, and newer iOS 18 / iOS 26 APIs are properly guarded with `#available` checks. However, `ITSAppUsesNonExemptEncryption` is omitted, and the build produces multiple actor-isolation warnings that will become hard errors in Swift 6 mode.

---

## 2. Scope and Files Inspected

### Project Configuration & Schemes
- `escape_plan.xcodeproj/project.pbxproj` (lines 1–584; PBXProject, PBXNativeTarget, XCBuildConfiguration, PBXFileSystemSynchronizedRootGroup)
- `escape_plan.xcodeproj/xcshareddata/xcschemes/escape_plan.xcscheme` (Scheme build/test/launch/profile/analyze/archive actions)
- `escape_plan.xcodeproj/project.xcworkspace/contents.xcworkspacedata`

### CI & Deployment Blueprints
- `.github/workflows/gate.yml` (Jobs: `backend`, `ios-typecheck`, `nightly-gate`, `ios-tests`)
- `render.yaml` (Backend deployment configuration, autoDeployTrigger, environment variable declarations)
- `scripts/typecheck-ios.sh` (CLI typecheck harness without simulator runtime)
- `scripts/s13-acceptance.sh` (Legacy automated screenshot/acceptance harness)
- `scripts/clean.sh` (Build artifact cleanup)
- `scripts/make_app_icon.swift` (App icon generation script)

### App Manifest, Assets, and Configuration
- `escape_plan/Assets.xcassets/AppIcon.appiconset/Contents.json` & image files
- `escape_plan/Assets.xcassets/LaunchBackground.colorset/Contents.json`
- `escape_plan/Assets.xcassets/AccentColor.colorset/Contents.json`
- `escape_plan/BackendConfig.local.json` (Presence, git tracking, JSON structure without secret printing)
- `.gitignore` (Lines 18–22)

### Target Code & Availability Intersections
- `escape_plan/Capture/RoomCaptureController.swift` (Lines 20–135; RoomPlan session lifecycle & compiler mutation defect)
- `escape_plan/Capture/Export/RoomPlanScanSource.swift` (RoomPlan model conformances & availability)
- `escape_plan/Capture/Views/ScanFlowView.swift` (Non-LiDAR runtime fallbacks)
- `escape_plan/Screens/BuildFromPlanView.swift` (Photo/PDF intake without LiDAR; PhotosUI integration)
- `escape_plan/Screens/GlassControls.swift` (iOS 26 Liquid Glass availability branching)
- `escape_plan/Screens/HouseScreen.swift` (iOS 18 scroll geometry availability)
- `escape_plan/Networking/APIClient.swift` (BaseURL, bearer token resolution, bundle extraction, debug overrides)
- `escape_plan/Screens/SettingsScreen.swift` (Debug vs Release UI availability, `#if DEBUG` gates)
- `escape_plan/escape_planApp.swift` (Launch arguments, demo seeding, score caching)
- `escape_plan/Auth/KeychainTokenStore.swift` (Keychain entitlements & data protection query)
- `tools/editorcore/Package.swift` (Internal SPM test package specification)

---

## 3. Methods and Checks Performed

1. **Xcode Configuration Inspection:**  
   Inspected all target settings, configurations (`Debug`, `Release`), build phases, synchronized root groups, and compiler flags in `project.pbxproj`.
2. **Xcodebuild Matrix Execution:**  
   Executed command-line builds using `-derivedDataPath /tmp/audit-dd-14` across the following dimensions:
   - Target scheme enumeration (`xcodebuild -list`)
   - Generic iOS device build - Debug (`destination "generic/platform=iOS"`)
   - Generic iOS device build - Release (`destination "generic/platform=iOS"`)
   - Generic iOS device archive (`xcodebuild archive`)
   - iOS Simulator build - Debug (`destination "platform=iOS Simulator,name=iPhone 18 Pro"`)
   - iOS Simulator build - Release (`destination "platform=iOS Simulator,name=iPhone 18 Pro"`)
   - iOS Simulator test targets build (`xcodebuild build-for-testing`)
   - SwiftPM tests (`swift test --package-path tools/editorcore`)
   - Shell typecheck script (`scripts/typecheck-ios.sh`)
3. **App Bundle Content Auditing:**  
   Inspected the assembled application bundle (`/tmp/audit-dd-14/Build/Products/Release-iphonesimulator/escape_plan.app`) using `ls -la`, `plutil -p`, and `xcrun assetutil --info Assets.car` to verify resource copying, generated `Info.plist`, compiled assets, and secret leakage.
4. **Git Tracking & Secret Handling Verification:**  
   Ran `git check-ignore` and `git ls-files` against `BackendConfig.local.json`. Inspected its JSON structure programmatically without printing sensitive credential values.
5. **API & Deployment Target Compatibility Analysis:**  
   Audited codebase for usage of `RoomPlan`, `PhotosUI`, `SceneKit`, `Observation`, `UserNotifications`, and checked `@available` / `#available` blocks against `IPHONEOS_DEPLOYMENT_TARGET = 17.0`.

---

## 4. Findings (with Evidence)

### A14-01 [CRITICAL] Real-Device Build and Archive Blocked by Compiler Mutation Error in RoomCaptureController
**Domain:** Build Configuration & Distribution  
**Location:** [RoomCaptureController.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift#L116-L120)  
**Observed behavior:**  
Executing `xcodebuild build` for `generic/platform=iOS` (Debug or Release) or executing `xcodebuild archive` fails with exit code 65:
```text
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift:118:23: error: cannot assign to property: 'configuration' is a 'let' constant
116 |         installDelegateIfNeeded()
117 |         let configuration = RoomCaptureSession.Configuration()
118 |         configuration.isCoachingEnabled = true
    |                       `- error: cannot assign to property: 'configuration' is a 'let' constant
119 |         roomCaptureView.captureSession.run(configuration: configuration)
```
**Evidence:**  
In `escape_plan/Capture/RoomCaptureController.swift`:
```swift
    func startSingleRoomScan(roomID: String) {
        reset()
        recheckRoomID = roomID
        #if canImport(RoomPlan) && !targetEnvironment(simulator)
        installDelegateIfNeeded()
        let configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        roomCaptureView.captureSession.run(configuration: configuration)
        phase = .scanning
        #else
        phase = .failed("Scanning requires a LiDAR-equipped device.")
        #endif
    }
```
Contrast with `startScanningRoom()` at line 101, which correctly uses `var configuration = RoomCaptureSession.Configuration()`.  
Exact build output recorded in [14_build_runs.md](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/audit/2026-10-11_comprehensive/evidence/14_build_runs.md#L30-L55).  
**Expected behavior:**  
The real-device code path must compile cleanly, allowing archives and physical device installations to succeed.  
**Root cause:**  
`RoomCaptureSession.Configuration` is a value type (`struct`). Instantiating it with `let` prevents property mutation. Because this code is gated by `#if canImport(RoomPlan) && !targetEnvironment(simulator)`, it was completely bypassed on simulator builds and in `scripts/typecheck-ios.sh`.  
**Impact:**  
Total blocker for TestFlight, App Store distribution, and physical device testing. The app cannot be packaged for release.  
**Recommended improvement:**  
Change `let configuration = RoomCaptureSession.Configuration()` to `var configuration = RoomCaptureSession.Configuration()` at line 117. Update CI to include a generic device build check (`-destination "generic/platform=iOS"`).  
**Dependencies:** None.  
**Verification status:** Verified by automated test.  
**Confidence:** High. **Effort:** Small (1-character edit, but requires CI update).

---

### A14-02 [HIGH] Plaintext Bundling of Shared Secret `BackendConfig.local.json` in Release App Bundle via Synchronized Groups
**Domain:** Security & Distribution Packaging  
**Location:** [project.pbxproj](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan.xcodeproj/project.pbxproj#L33-L37), [APIClient.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient.swift#L185-L196)  
**Observed behavior:**  
The Release build `.app` bundle includes `BackendConfig.local.json` in plaintext at the bundle root:
`-rw-r--r-- 1 anish wheel 65 Oct 11 00:24 BackendConfig.local.json`  
Inspection confirms this file contains the live `bearer_token` key and value.  
**Evidence:**  
Inspection of `/tmp/audit-dd-14/Build/Products/Release-iphonesimulator/escape_plan.app/`:
```text
-rw-r--r--   1 anish  wheel        65 Oct 11 00:24 BackendConfig.local.json
```
In `escape_plan.xcodeproj/project.pbxproj`:
```text
27C930C33001895C002825E5 /* escape_plan */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    path = escape_plan;
    sourceTree = "<group>";
};
```
And in `escape_plan/Networking/APIClient.swift`:
```swift
    static func bundledBearerToken() -> String? {
        guard let url = Bundle.main.url(forResource: "BackendConfig.local", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["bearer_token"] as? String
    }
```
**Expected behavior:**  
Sensitive API tokens or shared backend credentials should never ship as plaintext files inside an unencrypted client application bundle.  
**Root cause:**  
Xcode 16's `PBXFileSystemSynchronizedRootGroup` copies all loose files in the target folder into the bundle root as resources. Placing `BackendConfig.local.json` inside `escape_plan/` causes Xcode to treat it as an app bundle asset automatically.  
**Impact:**  
Anyone who downloads the app or inspects the IPA can view the shared backend bearer token, bypassing backend caller verification or abusing paid AI backend quotas.  
**Recommended improvement:**  
Move `BackendConfig.local.json` outside the synchronized root group (e.g. to `Configuration/`), or exclude it from the target membership, or inject API tokens during CI/build via code generation or secure keychain bootstrapping.  
**Dependencies:** None.  
**Verification status:** Verified by automated test.  
**Confidence:** High. **Effort:** Medium.

---

### A14-03 [HIGH] Clean-Build Breakage of Authenticated Backend Features in Release Mode (CI / New Clone Divergence)
**Domain:** Build Configuration & Distribution  
**Location:** [APIClient.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient.swift#L130-L136), [SettingsScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/SettingsScreen.swift#L58-L131), [.gitignore](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/.gitignore#L20-L21)  
**Observed behavior:**  
In a clean repository checkout (e.g., CI runner or new developer environment), `BackendConfig.local.json` does not exist because it is ignored by git. In Release builds, `APIClient` sets `bearerToken = ""` because launch arguments and user overrides are ignored. Furthermore, the Advanced server configuration section in `SettingsScreen` is conditionally compiled with `#if DEBUG`, preventing users from entering a token in the UI.  
**Evidence:**  
In `escape_plan/Networking/APIClient.swift:130-136`:
```swift
        if !honorOverrides {
            // Release: only the bundled token. Launch arguments and stored overrides are DEBUG tools.
            bearerToken = bundledToken() ?? ""
            isTokenOverridden = false
        }
```
In `escape_plan/Screens/SettingsScreen.swift:58`:
```swift
        #if DEBUG
        footnote("Escape Plan is already set up to use its own server...")
        section("Advanced") {
            row("Server address") { ... }
            row("Access token") { ... }
        }
        ...
        #endif
```
`git check-ignore escape_plan/BackendConfig.local.json` confirms the file is ignored.  
**Expected behavior:**  
A clean clone built in Release mode should either fail fast with a descriptive pre-build error if a mandatory credential file is absent, or provide a supported mechanism for release configuration.  
**Root cause:**  
The build architecture assumes an unversioned local file will always be manually placed onto the filesystem prior to archiving, while completely stripping token entry UI in Release builds.  
**Impact:**  
Clean builds produce a crippled application where `/score`, `/chat`, `/analyze`, and `/build` endpoints fail with HTTP 401 Unauthorized, with no UI for the user or tester to configure access.  
**Recommended improvement:**  
Add a pre-build build phase script or scheme pre-action that validates required configuration files, or document the exact provisioning steps for CI and TestFlight packaging.  
**Dependencies:** Finding A14-02.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Medium.

---

### A14-04 [MEDIUM] Unintended Internal Documentation Bundled into Shipping App Package
**Domain:** Packaging & Distribution  
**Location:** [escape_plan.app](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan), [project.pbxproj](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan.xcodeproj/project.pbxproj#L33-L37)  
**Observed behavior:**  
The assembled Release `.app` bundle contains internal development documentation files:
- `CLAUDE.md` (5,613 bytes from `escape_plan/CLAUDE.md`)
- `README.md` (6,944 bytes from `escape_plan/Capture/README.md`)  
**Evidence:**  
Inspection of `/tmp/audit-dd-14/Build/Products/Release-iphonesimulator/escape_plan.app/`:
```text
-rw-r--r--   1 anish  wheel      5613 Oct 11 00:24 CLAUDE.md
-rw-r--r--   1 anish  wheel      6944 Oct 11 00:24 README.md
```
**Expected behavior:**  
Internal development guidelines, AI prompt rules, and architecture notes should not be packaged into the customer-facing binary bundle.  
**Root cause:**  
`PBXFileSystemSynchronizedRootGroup` includes all files residing in `escape_plan/` unless an explicit file exclusion rule or `.xcodeignore` pattern is configured.  
**Impact:**  
Exposes internal architectural documentation and development prompts to end users via IPA extraction; increases bundle size.  
**Recommended improvement:**  
Move `CLAUDE.md` and module `README.md` files outside `escape_plan/` (e.g. into `docs/` or repo root), or configure target resource exclusions in the PBXFileSystemSynchronizedRootGroup.  
**Dependencies:** None.  
**Verification status:** Verified by automated test.  
**Confidence:** High. **Effort:** Small.

---

### A14-05 [MEDIUM] Missing `ITSAppUsesNonExemptEncryption` Export Compliance Key
**Domain:** App Store & TestFlight Distribution  
**Location:** [project.pbxproj](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan.xcodeproj/project.pbxproj#L427-L460)  
**Observed behavior:**  
Neither the generated `Info.plist` settings nor the project build settings define `ITSAppUsesNonExemptEncryption`.  
**Evidence:**  
Inspection of built `Info.plist` from `Release-iphonesimulator/escape_plan.app/Info.plist`:
```text
plutil -p Info.plist | grep -i ITSAppUsesNonExemptEncryption  # (exited 1, no match)
```
In `project.pbxproj`:
```text
INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;  # (absent in both Debug and Release)
```
**Expected behavior:**  
Applications using standard HTTPS networking and iOS Keychain encryption should specify `ITSAppUsesNonExemptEncryption = NO` to avoid manual export compliance questionnaire prompts on every TestFlight build upload.  
**Root cause:**  
Omission during transition to Xcode's automatic `GENERATE_INFOPLIST_FILE = YES`.  
**Impact:**  
Automated CI deployments to TestFlight will stall in "Missing Compliance" state, requiring manual administrative intervention in App Store Connect before testers can install new builds.  
**Recommended improvement:**  
Add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;` to the target build settings in `project.pbxproj`.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** Small.

---

### A14-06 [LOW] Swift Concurrency & MainActor Isolation Warnings on Modern Toolchains
**Domain:** Build Configuration & Compiler Health  
**Location:** [APIClient.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient.swift#L123), [ReadinessStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift#L64), [HomeDocumentStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift#L373), `escape_planTests/*`  
**Observed behavior:**  
Building the app and test targets produces numerous compiler warnings related to actor isolation:
```text
APIClient.swift:123:50: warning: call to main actor-isolated static method 'bundledBearerToken()' in a synchronous nonisolated context [#ActorIsolatedCall]
ReadinessStore.swift:64:46: warning: main actor-isolated static property 'demoHomeID' can not be referenced from a nonisolated context
ReadinessStore.swift:284:24: warning: call to main actor-isolated static method 'isCancellation' in a synchronous nonisolated context [#ActorIsolatedCall]
RoutePlanTests.swift:16:38: warning: main actor-isolated conformance of 'RoutePlan' to 'Decodable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode [#IsolatedConformances]
```
**Evidence:**  
Build logs in [14_build_runs.md](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/audit/2026-10-11_comprehensive/evidence/14_build_runs.md#L90-L115).  
**Expected behavior:**  
Static helpers and Codable data models should be explicitly marked `nonisolated` or decoupled from `@MainActor` defaults to ensure warning-free compilation under strict concurrency checks.  
**Root cause:**  
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` was enabled globally on the project, making all types `@MainActor` by default without marking pure data models and helper functions as `nonisolated`.  
**Impact:**  
While compiling as warnings under Swift 5 language mode, these issues will immediately become hard compilation errors when upgrading to the Swift 6 language mode.  
**Recommended improvement:**  
Annotate static helper utilities and model conformances (`Decodable`, `Encodable`) with `nonisolated`.  
**Dependencies:** None.  
**Verification status:** Verified by automated test.  
**Confidence:** High. **Effort:** Medium.

---

### A14-07 [OBSERVATION] Intentional Discrepancy in `UIFileSharingEnabled` Between Debug and Release
**Domain:** Build Configuration & Security  
**Location:** [project.pbxproj](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan.xcodeproj/project.pbxproj#L405), [docs/decisions.md](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/docs/decisions.md#L61)  
**Observed behavior:**  
`INFOPLIST_KEY_UIFileSharingEnabled` and `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace` are set to `YES` in Debug configuration but omitted in Release configuration.  
**Evidence:**  
In `project.pbxproj`:
- Debug (XCBuildConfiguration 27C930E8): Lines 401, 405 set both keys to `YES`.
- Release (XCBuildConfiguration 27C930E9): Lines 427–460 omit both keys.  
Decision log in `docs/decisions.md` (2026-10-03, S11.40):
"UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace are removed from the Release build only; Debug keeps both. The stores stay in Documents: no move to Application Support. With file sharing off, Documents is not visible in the Files app or Finder, which closes AUD-008."  
**Expected behavior:**  
Consistent and deliberate document visibility according to the security specification.  
**Root cause:**  
Intentional security hardening implemented on 2026-10-03 to prevent end-user exposure of home floor plans and chat history through Finder/Files in production.  
**Impact:**  
Positive security posture; does not constitute a defect.  
**Recommended improvement:**  
None required; documentation and implementation are in sync.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** None.

---

### A14-08 [OBSERVATION] Multi-Modal Non-LiDAR Device Capability Handling
**Domain:** Target Capabilities & Hardware Requirements  
**Location:** [project.pbxproj](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan.xcodeproj/project.pbxproj#L423), [RoomCaptureController.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift#L84-L90), [ScanFlowView.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Capture/Views/ScanFlowView.swift#L174-L193), [BuildFromPlanView.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/BuildFromPlanView.swift#L11-L65)  
**Observed behavior:**  
`UIRequiredDeviceCapabilities` does not include `lidar` or `arkit`. The app installs on all iPhone and iPad hardware running iOS 17+. Devices without LiDAR gracefully disable RoomPlan camera scanning and provide two complete fallback paths: "Build Manually" and "Import Plan" (floor plan photo/PDF intake).  
**Evidence:**  
1. `UIRequiredDeviceCapabilities` is absent in `project.pbxproj`, allowing universal installation.  
2. `RoomCaptureController.isSupported` performs runtime checks via `RoomCaptureSession.isSupported`.  
3. `ScanFlowView` presents an informative warning banner: *"This device doesn't have LiDAR, so scanning is unavailable. You can still build your home in the editor."*  
4. `BuildFromPlanView` uses SwiftUI `PhotosPicker` (out-of-process picker needing no photo library entitlement) and `fileImporter` to allow floor plan image/PDF intake.  
**Expected behavior:**  
Broad device availability with progressive hardware enhancement for LiDAR-equipped Pro devices.  
**Root cause:**  
Intentional multi-modal intake architecture.  
**Impact:**  
Significantly increases reachable user base without crashing or stranding non-Pro iPhone/iPad users.  
**Recommended improvement:**  
None. Architectural approach is robust.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High. **Effort:** None.

---

## 5. Positive Findings

1. **Zero External SPM / Binary Dependencies:**  
   The application target does not link any third-party closed-source binaries or external package dependencies. All UI and rendering logic relies on Apple first-party SDKs (SwiftUI, SceneKit, RoomPlan). This dramatically reduces supply-chain attack surface and ensures fast build times.
2. **Robust Multi-Platform Test Harness (`tools/editorcore`):**  
   The team created a pure Foundation-based test harness package that symlinks model and business logic files into a headless macOS package. This allows running 656 unit tests in under 5 seconds (`swift test`) without needing an iOS Simulator runtime booted.
3. **App Icon Completeness:**  
   The asset catalog provides a pristine 1024x1024 universal icon asset along with Dark and Tinted variants, fully complying with modern iOS 18/26 appearance customization.
4. **Clean Launch Screen Configuration:**  
   Rather than relying on legacy LaunchScreen storyboards or unmanaged nibs, the project utilizes Xcode's modern `INFOPLIST_KEY_UILaunchScreen_Generation = YES` with a native `LaunchBackground` asset color set.
5. **No Test Hooks or Launch Argument Leaks in Release:**  
   All launch argument bypasses (`-TEST_SEED_DEMO_HOME`, `UITEST_CANNED_SCORE`) and Settings server override fields are strictly guarded by `#if DEBUG`. In Release builds, launch arguments and UserDefaults overrides are completely ignored by `APIClient`.
6. **Compliant Photo Picker Integration:**  
   The photo import workflow in `BuildFromPlanView` utilizes the modern SwiftUI `PhotosPicker`, which operates out-of-process via system UI and correctly eliminates the need for `NSPhotoLibraryUsageDescription`.

---

## 6. Systemic Issues and Root Causes

1. **Simulator-Only Testing Bias:**  
   The primary systemic flaw across the project's engineering operations is that all local scripts (`scripts/typecheck-ios.sh`) and CI pipelines (`.github/workflows/gate.yml`) exclusively target the iOS Simulator (`-target arm64-apple-ios-simulator`). Because `#if !targetEnvironment(simulator)` guards device-only code paths, compile breaks in device-specific code (such as RoomPlan hardware interaction in Finding A14-01) can remain hidden indefinitely.
2. **Synchronized Group Side Effects:**  
   The migration to Xcode 16's `PBXFileSystemSynchronizedRootGroup` simplified file additions but introduced unintended packaging side effects. Any non-code file (such as secret config files or internal documentation markdown files) placed into the root folder is automatically bundled into the shipping binary without warning.

---

## 7. Unverified Assumptions

1. **Production Code Signing Identity:**  
   The project configures `DEVELOPMENT_TEAM = 94AD5J95YF` and `CODE_SIGN_STYLE = Automatic`. Because audit rules strictly prohibit modifying project settings or accessing remote developer portal credentials, the existence of valid App Store distribution certificates and provisioning profiles for Team ID `94AD5J95YF` could not be verified online. (Verification status: Inferred but not verified).
2. **Render Production Backend Token Match:**  
   We verified that `BackendConfig.local.json` contains a bearer token key, but we did not verify against the live deployed Render environment whether this token currently matches the active `BACKEND_BEARER_TOKEN` environment variable on production. (Verification status: Inferred but not verified).

---

## 8. Areas Requiring Further Investigation

1. **TestFlight Automated Upload Pipeline:**  
   Currently, `.github/workflows/gate.yml` has no job to create an `.xcarchive` or upload to TestFlight via `altool` or `notarytool`. Investigating the addition of an automated TestFlight deployment lane once Finding A14-01 is resolved is recommended.
2. **Crash Reporting and Symbolication (`dSYM` Uploads):**  
   The Release configuration specifies `DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"`, which generates dSYMs. However, there is no post-archive phase or service (e.g. Firebase Crashlytics or Sentry) configured to extract or upload dSYMs.

---

## 9. Recommended Priorities

| Priority | Finding ID | Description | Estimated Effort |
|---|---|---|---|
| **P0** | **A14-01** | Fix `let` -> `var` mutation compiler error in `RoomCaptureController.swift:118` to unblock device & archive builds | 5 minutes |
| **P0** | **A14-02** | Move `BackendConfig.local.json` out of synchronized group to prevent shipping plaintext bearer token in IPA | 1 hour |
| **P1** | **A14-03** | Resolve clean-build credential provisioning for Release builds so authenticated features work | 2 hours |
| **P1** | **A14-05** | Add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;` to build settings for TestFlight compliance | 5 minutes |
| **P2** | **A14-04** | Exclude `CLAUDE.md` and module `README.md` from the target app bundle resources | 15 minutes |
| **P2** | **A14-06** | Annotate static utilities and model conformances with `nonisolated` to resolve Swift concurrency warnings | 2 hours |
| **P3** | — | Update CI (`gate.yml`) to include a `generic/platform=iOS` build step to prevent future device regressions | 30 minutes |
