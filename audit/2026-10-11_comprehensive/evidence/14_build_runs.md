# Build Runs and Xcode Verification Evidence (Domain 14)

**Audit Date:** 2026-10-11  
**Auditor:** Agent 14 (Build Configuration & Distribution)  
**Xcode Version:** Xcode 27.0 (Build 27A266a)  
**Host Platform:** macOS 26A434 (Darwin arm64)  
**SDKs:** iOS 27.0 (iphoneos27.0), iOS Simulator 27.0 (iphonesimulator27.0)  
**Isolated DerivedData Path:** `/tmp/audit-dd-14`

---

## 1. Scheme and Target Enumeration (`xcodebuild -list`)

### Command
```bash
xcodebuild -list -project escape_plan.xcodeproj
```

### Output
```text
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -list -project escape_plan.xcodeproj

Information about project "escape_plan":
    Targets:
        escape_plan
        escape_planTests
        escape_planUITests

    Build Configurations:
        Debug
        Release

    If no build configuration is specified and -scheme is not passed then "Release" is used.

    Schemes:
        escape_plan
```

---

## 2. Generic iOS Device Build - Debug Configuration

### Command
```bash
xcodebuild build -project escape_plan.xcodeproj -scheme escape_plan \
  -configuration Debug -destination "generic/platform=iOS" \
  -derivedDataPath /tmp/audit-dd-14 CODE_SIGNING_ALLOWED=NO
```

### Result
**Exit code: 65 (FAILED)**

### Diagnostic Output
```text
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift:64:46: warning: main actor-isolated static property 'demoHomeID' can not be referenced from a nonisolated context
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift:284:24: warning: call to main actor-isolated static method 'isCancellation' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift:118:23: error: cannot assign to property: 'configuration' is a 'let' constant
116 |         installDelegateIfNeeded()
117 |         let configuration = RoomCaptureSession.Configuration()
118 |         configuration.isCoachingEnabled = true
    |                       `- error: cannot assign to property: 'configuration' is a 'let' constant
119 |         roomCaptureView.captureSession.run(configuration: configuration)
120 |         phase = .scanning

** BUILD FAILED **

The following build commands failed:
	SwiftCompile normal arm64 Compiling\ RawScanExport.swift,\ RoomPlanScanSource.swift,\ ScanCleanup.swift,\ ScanExportBuilder.swift,\ ScanStore.swift,\ RoomCaptureViewRepresentable.swift,\ ScanFlowView.swift,\ RoomCaptureController.swift,\ CameraRigModel.swift,\ EditAction.swift
	SwiftCompile normal arm64 /Users/anish/Documents/Congressional\ App\ Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift
	Building project escape_plan with scheme escape_plan and configuration Debug
(3 failures)
```

---

## 3. Generic iOS Device Build - Release Configuration

### Command
```bash
xcodebuild build -project escape_plan.xcodeproj -scheme escape_plan \
  -configuration Release -destination "generic/platform=iOS" \
  -derivedDataPath /tmp/audit-dd-14 CODE_SIGNING_ALLOWED=NO
```

### Result
**Exit code: 65 (FAILED)**

### Diagnostic Output
```text
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift:118:23: error: cannot assign to property: 'configuration' is a 'let' constant
116 |         installDelegateIfNeeded()
117 |         let configuration = RoomCaptureSession.Configuration()
118 |         configuration.isCoachingEnabled = true
    |                       `- error: cannot assign to property: 'configuration' is a 'let' constant
119 |         roomCaptureView.captureSession.run(configuration: configuration)
120 |         phase = .scanning

** BUILD FAILED **

The following build commands failed:
	SwiftCompile normal arm64 Compiling\ RawScanExport.swift,\ RoomPlanScanSource.swift,\ ScanCleanup.swift,\ ScanExportBuilder.swift,\ ScanStore.swift,\ RoomCaptureViewRepresentable.swift,\ ScanFlowView.swift,\ RoomCaptureController.swift,\ CameraRigModel.swift,\ EditAction.swift
	SwiftCompile normal arm64 /Users/anish/Documents/Congressional\ App\ Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift
	Building project escape_plan with scheme escape_plan and configuration Release
(3 failures)
```

---

## 4. Archive Creation for Generic iOS Device (`xcodebuild archive`)

### Command
```bash
xcodebuild archive -project escape_plan.xcodeproj -scheme escape_plan \
  -configuration Release -destination "generic/platform=iOS" \
  -archivePath /tmp/escape_plan.xcarchive CODE_SIGNING_ALLOWED=NO
```

### Result
**Exit code: 65 (FAILED)**

### Diagnostic Output
```text
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift:118:23: error: cannot assign to property: 'configuration' is a 'let' constant

** ARCHIVE FAILED **

The following build commands failed:
	SwiftCompile normal arm64 Compiling\ RawScanExport.swift,\ RoomPlanScanSource.swift,\ ScanCleanup.swift,\ ScanExportBuilder.swift,\ ScanStore.swift,\ RoomCaptureViewRepresentable.swift,\ ScanFlowView.swift,\ RoomCaptureController.swift,\ CameraRigModel.swift,\ EditAction.swift
	SwiftCompile normal arm64 /Users/anish/Documents/Congressional\ App\ Challenge/Escape-Plan/escape_plan/Capture/RoomCaptureController.swift
	Archiving project escape_plan with scheme escape_plan
(3 failures)
```

---

## 5. iOS Simulator Build - Debug Configuration

### Command
```bash
xcodebuild build -project escape_plan.xcodeproj -scheme escape_plan \
  -configuration Debug -destination "platform=iOS Simulator,name=iPhone 18 Pro" \
  -derivedDataPath /tmp/audit-dd-14 CODE_SIGNING_ALLOWED=NO
```

### Result
**Exit code: 0 (SUCCESS)**

### Compiler Warnings Captured
```text
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Networking/APIClient.swift:123:50: warning: call to main actor-isolated static method 'bundledBearerToken()' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Onboarding/OnboardingState.swift:52:46: warning: main actor-isolated static property 'demoHomeID' can not be referenced from a nonisolated context
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift:373:22: warning: call to main actor-isolated static method 'parseHomeModelDate' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift:1067:50: warning: call to main actor-isolated static method 'peopleWithNoWayOut(in:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift:1942:9: warning: application of result builder 'ViewBuilder' disabled by explicit 'return' statement
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift:284:24: warning: call to main actor-isolated static method 'isCancellation' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift:297:37: warning: main actor-isolated property 'completedAt' can not be referenced from a nonisolated context
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift:64:46: warning: main actor-isolated static property 'demoHomeID' can not be referenced from a nonisolated context
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/escape_planApp.swift:60:13: warning: result of 'try?' is unused [#NoUsage]
2026-10-11 00:23:52.801 appintentsmetadataprocessor[52887:558134] warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

---

## 6. iOS Simulator Build - Release Configuration

### Command
```bash
xcodebuild build -project escape_plan.xcodeproj -scheme escape_plan \
  -configuration Release -destination "platform=iOS Simulator,name=iPhone 18 Pro" \
  -derivedDataPath /tmp/audit-dd-14 CODE_SIGNING_ALLOWED=NO
```

### Result
**Exit code: 0 (SUCCESS)**

### Compiler Warnings Captured
```text
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Networking/APIClient.swift:123:50: warning: call to main actor-isolated static method 'bundledBearerToken()' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Onboarding/OnboardingState.swift:52:46: warning: main actor-isolated static property 'demoHomeID' can not be referenced from a nonisolated context
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Persistence/HomeDocumentStore.swift:373:22: warning: call to main actor-isolated static method 'parseHomeModelDate' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift:1067:50: warning: call to main actor-isolated static method 'peopleWithNoWayOut(in:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift:1942:9: warning: application of result builder 'ViewBuilder' disabled by explicit 'return' statement
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift:284:24: warning: call to main actor-isolated static method 'isCancellation' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift:297:37: warning: main actor-isolated property 'completedAt' can not be referenced from a nonisolated context
/Users/anish/Documents/Congressional App Challenge/Escape-Plan/escape_plan/Screens/ReadinessStore.swift:64:46: warning: main actor-isolated static property 'demoHomeID' can not be referenced from a nonisolated context
2026-10-11 00:24:42.222 appintentsmetadataprocessor[54565:565082] warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

---

## 7. iOS Simulator Test Targets Build (`build-for-testing`)

### Command
```bash
xcodebuild build-for-testing -project escape_plan.xcodeproj -scheme escape_plan \
  -configuration Debug -destination "platform=iOS Simulator,name=iPhone 18 Pro" \
  -derivedDataPath /tmp/audit-dd-14 CODE_SIGNING_ALLOWED=NO
```

### Result
**Exit code: 0 (SUCCESS)**

---

## 8. SwiftPM Standalone Package Tests (`tools/editorcore`)

### Command
```bash
swift test --package-path tools/editorcore
```

### Result
**Exit code: 0 (SUCCESS)**
Executed 656 tests, 0 failures in 4.706 seconds.

---

## 9. iOS Target Typecheck Script (`scripts/typecheck-ios.sh`)

### Command
```bash
scripts/typecheck-ios.sh
```

### Result
**Exit code: 0 (SUCCESS)**
```text
Type-checking against iOS 17.0 (iPhoneSimulator27.0.sdk)
  ok    escape_plan        (169 files, -DDEBUG)
  ok    escape_plan        (169 files, release)
  ok    escape_planTests  (94 files)
  ok    escape_planUITests  (17 files)
```
*Note: This script uses `TARGET="arm64-apple-ios17.0-simulator"`. Because it targets the simulator, `#if !targetEnvironment(simulator)` evaluates to false, which is why the compiler error in `RoomCaptureController.swift:118` was not caught by this script.*

---

## 10. Built Product Bundle Inspection (`Release-iphonesimulator/escape_plan.app`)

### Files bundled in App Root
```text
AppIcon60x60@2x.png (120x120 PNG)
AppIcon76x76@2x~ipad.png (152x152 PNG)
Assets.car (281 KB, containing AccentColor, LaunchBackground, AppIcon)
BackendConfig.local.json (65 bytes, containing plaintext bearer_token)
CLAUDE.md (5.6 KB internal prompt/architecture instructions)
Info.plist (1.6 KB generated property list)
PkgInfo (8 bytes)
README.md (6.9 KB from escape_plan/Capture/README.md)
apartment.json (6.8 KB starter fixture)
bungalow-blocked.json (6.0 KB starter fixture)
bungalow-narrow.json (6.0 KB starter fixture)
bungalow.json (5.2 KB starter fixture)
escape_plan (Mach-O 64-bit arm64 executable)
jagged.json (14 KB starter fixture)
prevention_tips.json (15 KB starter fixture)
twostory-empty.json (9.7 KB starter fixture)
twostory.json (12 KB starter fixture)
```
