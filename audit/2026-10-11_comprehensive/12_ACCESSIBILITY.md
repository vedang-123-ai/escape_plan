# 12. Accessibility Audit Report

**Target:** Escape-Plan iOS App (SwiftUI & SceneKit)  
**Auditor:** Agent 12 (Accessibility Specialist)  
**Date:** October 11, 2026  
**Repository:** `/Users/anish/Documents/Congressional App Challenge/Escape-Plan`  

---

## 1. Executive Summary

This report delivers a comprehensive accessibility audit of the Escape-Plan iOS application, evaluating SwiftUI user interfaces, SceneKit 3D spatial representations, evacuation route guidance, Dynamic Type scalability, color contrast conformance (WCAG 2.2 AA / AAA), touch ergonomics (Apple HIG & WCAG 2.5.8), and plain-language cognitive accessibility.

Escape-Plan demonstrates several thoughtful, forward-looking accessibility designs:
- An innovative accessibility bridge (`HouseSceneAccessibility.swift` and `A11yHouseScene.swift`) translates SceneKit spatial graphs into hierarchical VoiceOver representations with room grouping, hazard notices, and step-by-step route narration (`RouteNarration.swift`).
- The evacuation simulation respects `UIAccessibility.isReduceMotionEnabled`, transitioning high-framerate dynamic fire/smoke particle systems into low-motion stepped indicators.
- High-contrast tokens and deuteranopia/protanopia safety markers (luminance-split blue/yellow markers) are embedded in `Theme.swift`.

However, significant barriers remain that compromise safety and independence for users with visual, motor, and cognitive disabilities:
1. **Critical Motor & Blind Lockout in 3D Editor:** The floor plan editor (`EditorSceneView.swift`) relies exclusively on direct spatial 3D gestures (pan, pinch, tap-to-place walls and openings). There is no keyboard, switch-control, VoiceOver, or 2D structured tree alternative for adding rooms, placing windows/doors, or adjusting coordinates.
2. **Critical VoiceOver Action Suppression:** Critical banners, notably `BackendFailureBanner.swift`, use `.accessibilityElement(children: .combine)` while overriding `.accessibilityLabel`, suppressing interactive `Retry`, `Settings`, and `Dismiss` child buttons without exposing `.accessibilityAction` replacements.
3. **WCAG Contrast Violations on Core Emergency Actions:** The primary simulation action button `Ignite` (`HouseScreen.swift:978`) applies `Theme.warning` (#EF6363) with white foreground text, producing a contrast ratio of **3.17:1**, violating WCAG 2.2 Level AA SC 1.4.3 (4.5:1 minimum).
4. **Touch Target Deficiencies:** Multiple buttons throughout `GlassControls.swift`, `ConsentSheet.swift`, and `TaskComponents.swift` fall below Apple's 44×44pt HIG guideline (some measuring as small as 22–38pt).
5. **Dynamic Type Truncation & Artificial Clamping:** Core headings and score indicators use hardcoded font sizes or clamp text size scaling (`.dynamicTypeSize(...DynamicTypeSize.accessibility1)`), and several critical address/task fields enforce rigid `lineLimit` constraints that clip content at accessibility sizes.

---

## 2. Scope and Files Inspected

The audit inspected all visual components, design system tokens, 3D scene renderers, navigation flows, and test suites across the repository:

### Core Architecture & App Entry
- `escape_planApp.swift`: App lifecycle, appearance configuration, environment injections.
- `ContentView.swift`: Tab navigation hierarchy, modal presentation.
- `RootView.swift`: Root view tree, global banner overlays.

### Design Tokens, Appearance & Components
- `Theme.swift`: Semantic color tokens, surface hierarchy, WCAG contrast helper math.
- `AppAppearance.swift`: UIKit global navigation and tab bar appearance overrides.
- `DesignKit.swift`: Typography scales, card shapes, spacing tokens.
- `GlassControls.swift`: Glass button styles, chip styles, touch target framing.

### 3D Floor Plan & SceneKit Engine
- `EditorSceneView.swift`: 3D floor plan editing, gesture recognizers, hit testing.
- `HouseScreen.swift`: 3D viewport, toolbar controls, floor pickers, simulation playback.
- `GestureArbiter.swift`: Multi-touch handling, camera manipulation vs object manipulation.
- `DollhousePalette.swift`: Material colors, surface shading, hazard rendering.
- `A11yHouseScene.swift`: VoiceOver spatial tree abstraction for 3D SceneKit objects.
- `HouseSceneAccessibility.swift`: Accessibility element generation from node trees.
- `RouteNarration.swift`: Step-by-step text narration generator for egress routes.

### Primary UI Screens & Sheets
- `HomeScreen.swift`: Readiness score overview, quick actions, family member grid.
- `ScoreScreen.swift`: Readiness score breakdown, category cards, score gauge.
- `TasksScreen.swift`: Checklist hierarchy, completion toggles, meeting point editor.
- `TaskComponents.swift`: Task rows, category headers, disclosure controls.
- `AssistantScreen.swift`: AI assistant chat interface, voice input controls.
- `ProfilesScreen.swift`: Household member profiles, mobility/assistance tags.
- `ProfileEditorView.swift`: Profile editing sheet, accessibility requirements input.
- `SettingsScreen.swift`: Configuration toggles, appearance options, backend status.
- `BuildFromPlanView.swift`: Architectural plan import and setup wizard.
- `ConsentSheet.swift`: Diagnostic and AI consent agreement modal.
- `BackendFailureBanner.swift`: Global offline/backend error toast and recovery banner.
- `EvacuationPeoplePanel.swift`: Occupant status list during evacuation simulation.
- `RouteFindingViews.swift`: Egress path indicators, exit selection controls.
- `ExportPlanSheet.swift`: PDF / image export options.
- `ShareSheet.swift`: UIKit share sheet wrapper.
- `ShareWithFireDepartmentCard.swift`: Emergency service data export card.

### Automated Accessibility & Contrast Tests
- `ThemeContrastTests.swift`: Automated WCAG 2.1 AA/AAA contrast unit tests.
- `A11yHouseSceneTests.swift`: Tests for 3D scene accessibility tree generation.
- `S1157AccessibilityTests.swift`: S1157 compliance test suites.
- `RouteNarrationTests.swift`: Egress narration unit tests.
- `LargestTextUITests.swift`: Dynamic Type UI test snapshot harness.

---

## 3. Methods and Checks Performed

1. **Static AST & Source Inspection:** Systematically audited all Swift UI code for standard accessibility view modifiers (`.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint`, `.accessibilityTraits`, `.accessibilityAction`, `.accessibilityElement(children:)`, `.accessibilityHidden`).
2. **WCAG 2.2 Contrast Ratio Calculations:** Programmatically computed luminance and contrast ratios across all semantic color tokens (`Theme.swift`) against the 4 application surfaces (`canvas` #08090A, `card` #111214, `raised` #1A1B1E, `hover` #232428) and button fill states:
   $$\text{Relative Luminance } L = 0.2126 R + 0.7152 G + 0.0722 B$$
   $$\text{Contrast Ratio} = \frac{L_1 + 0.05}{L_2 + 0.05}$$
3. **Touch Target Dimensions Verification:** Evaluated frame constraints, padding, and hit-testing bounds against Apple HIG (44×44 pt minimum) and WCAG 2.5.8 Target Size (Minimum) (24×24 pt).
4. **Dynamic Type & Scalability Audit:** Scanned for fixed font declarations (`UIFont.systemFont`, `Font.system(size:)`), evaluated `@ScaledMetric` usage, identified layout clipping risks, and analyzed `.dynamicTypeSize` limits and `lineLimit` truncation.
5. **Assistive Tech Navigation Audit:** Analyzed accessibility trees in SceneKit views, evaluated focus management in modals/sheets, assessed modal dismissability, and verified screen-reader actionable controls.
6. **Plain-Language & Cognitive Stress Analysis:** Evaluated 44 fire prevention tips and safety instructions using the Flesch-Kincaid Grade Level metric:
   $$\text{FKGL} = 0.39 \left(\frac{\text{total words}}{\text{total sentences}}\right) + 11.8 \left(\frac{\text{total syllables}}{\text{total words}}\right) - 15.59$$

---

## 4. Findings

### A12-01: 3D Floor Plan Editor Relies Exclusively on Direct Spatial Gestures Without Non-Visual or Motor Alternatives
- **Severity:** CRITICAL
- **Category:** Assistive Tech / Motor & Vision Accessibility (WCAG 2.1.1 Keyboard / Non-Gesture Alternative, WCAG 2.5.1 Pointer Gestures)
- **Verification Status:** Verified by source inspection
- **File / Line Reference:** `EditorSceneView.swift:65-92`, `HouseScreen.swift:488-512`, `GestureArbiter.swift:42-110`
- **Description:**  
  The 3D house builder and room editor (`EditorSceneView`) handles geometry creation and manipulation strictly via multi-touch gesture recognizers (`UIPanGestureRecognizer`, `UIPinchGestureRecognizer`, `UITapGestureRecognizer`) mapped directly to SceneKit hit-testing against 3D nodes.  
  - Placing doors or windows (`.placeOpening`) requires tapping with pinpoint precision directly onto a 3D wall node (`SCNHitTestResult`).
  - Adjusting room boundaries, moving vertices, and repositioning walls requires continuous drag/pan gestures in 3D perspective space.
  - The underlying `SCNView` is exposed to VoiceOver as a monolithic surface or opaque canvas without accessibility elements representing editable nodes, room dimensions, or vertices.
  - No alternative interface (such as a 2D structured room list, coordinate/dimension input stepper, table-based wall manager, or keyboard/switch-control cursor) exists.
- **Impact:**  
  Users who are blind, have low vision, tremors, or severe motor impairments cannot build, modify, or customize their home escape plans. They are entirely dependent on sighted assistance to create the geometry required for emergency routing.
- **Remediation:**  
  Provide a structured 2D tabular/form-based editor ("Structured Floor Plan Editor") accessible via a toolbar button. This mode should allow users to:
  1. Add, rename, and configure rooms with numeric length/width steppers.
  2. Select connecting walls from a picklist to attach doors and windows.
  3. Set hazard locations (stoves, heaters) and exits via standard SwiftUI `Picker` and `List` controls.

---

### A12-02: Interactive Recovery Actions Suppressed in `BackendFailureBanner` via Element Combination
- **Severity:** CRITICAL
- **Category:** Assistive Tech / Screen Reader (WCAG 4.1.2 Name, Role, Value, WCAG 1.3.1 Info and Relationships)
- **Verification Status:** Verified by source inspection
- **File / Line Reference:** `BackendFailureBanner.swift:91-92, 104-139`
- **Description:**  
  `BackendFailureBanner` renders an error banner containing an icon, failure message, and interactive recovery buttons (`Retry`, `Settings`, and `Dismiss`).  
  On line 91–92, the view declares:
  ```swift
  .accessibilityElement(children: .combine)
  .accessibilityLabel(failure.message)
  ```
  Combining child elements while replacing the accessibility label converts the entire container and all child elements into a single static accessibility element. The child `Button` instances ("Retry", "Settings", "Dismiss") are stripped of their accessibility traits and action targets. Furthermore, the parent does not declare `.accessibilityAction(named:_:)` equivalents.
- **Impact:**  
  VoiceOver users hear the failure message read aloud, but cannot focus on or activate the `Retry`, `Settings`, or `Dismiss` buttons. Users cannot recover from backend connection failures or navigate to offline settings using assistive technology.
- **Remediation:**  
  Change `children: .combine` to `children: .contain`, or retain `.combine` but expose explicit custom accessibility actions:
  ```swift
  .accessibilityElement(children: .contain)
  ```
  Or:
  ```swift
  .accessibilityAction(named: "Retry") { retryAction() }
  .accessibilityAction(named: "Open Settings") { openSettingsAction() }
  .accessibilityAction(named: "Dismiss") { dismissAction() }
  ```

---

### A12-03: WCAG AA Contrast Failure on Primary Emergency Simulation Button (`Ignite`)
- **Severity:** HIGH
- **Category:** Color & Contrast (WCAG 2.2 Level AA SC 1.4.3 Contrast (Minimum))
- **Verification Status:** Verified by source inspection
- **File / Line Reference:** `HouseScreen.swift:977-979`, `Theme.swift:163-167`
- **Description:**  
  The primary action button to trigger the fire evacuation drill (`igniteSelectedButton`) is styled as:
  ```swift
  Button("Ignite") { ... }
      .buttonStyle(.borderedProminent)
      .tint(Theme.warning)
  ```
  `Theme.warning` is defined as `#EF6363` (RGB: 239, 99, 99).  
  In iOS `.borderedProminent` styling, white text (`#FFFFFF`, luminance 1.0) is rendered on top of the button's tint color.  
  - Relative luminance of `#EF6363`: $L \approx 0.281$
  - Relative luminance of `#FFFFFF`: $L = 1.0$
  - Resulting contrast ratio: $(1.0 + 0.05) / (0.281 + 0.05) = \mathbf{3.17:1}$  
  This severely fails the WCAG AA minimum threshold of **4.5:1** for standard text.  
  Notably, `Theme.swift` lines 165–167 explicitly document this flaw:
  > *"Warning / fire accent. Note: white on warning is ~3.5:1; use destructiveFill for white-text buttons."*  
  Despite this explicit code comment, `HouseScreen.swift` was implemented using `Theme.warning` instead of `Theme.destructiveFill` (`#C93A3A`, contrast **5.06:1**).
- **Impact:**  
  Users with low vision, aging vision, or color deficiencies operating the app in high ambient lighting or stressful drill environments will struggle to read the primary simulation action.
- **Remediation:**  
  Update `HouseScreen.swift:978` to use `Theme.destructiveFill`:
  ```swift
  .tint(Theme.destructiveFill)
  ```

---

### A12-04: Sub-44pt Touch Targets Across Core Controls and Modal Action Bars
- **Severity:** HIGH
- **Category:** Touch Ergonomics (Apple HIG 44×44pt, WCAG 2.5.8 Target Size)
- **Verification Status:** Verified by source inspection
- **File / Line Reference:** `GlassControls.swift:94`, `TaskComponents.swift:186`, `ConsentSheet.swift:77-82`
- **Description:**  
  Multiple controls fail Apple's Human Interface Guidelines target size of 44×44 pt:
  1. **Glass Chip Buttons (`GlassControls.swift:94`):**  
     `GlassChipButtonStyle` specifies:
     ```swift
     .frame(minWidth: WCAG.minimumTargetSize, minHeight: 44)
     ```
     where `WCAG.minimumTargetSize` is set to 24 pt. For square icon buttons (e.g., camera recenter, floor toggle, reset orientation), the horizontal dimension resolves to icon size (16pt) + padding (16pt) = 32–38 pt, well under the 44 pt minimum.
  2. **Task Group Header Toggle (`TaskComponents.swift:186`):**  
     The collapsible section header sets:
     ```swift
     .frame(minHeight: 40)
     ```
     This produces a 40 pt vertical touch target.
  3. **Consent Sheet Cancel Button (`ConsentSheet.swift:77-82`):**  
     The dismiss button relies on a standard text label with `.frame(maxWidth: .infinity)` without a vertical frame or padding, resulting in a tap target height of ~22 pt.
- **Impact:**  
  Users with limited manual dexterity, tremors, or large fingers experience frequent miss-taps and touch frustration, particularly when attempting to dismiss sheets or toggle 3D controls.
- **Remediation:**  
  Enforce a universal minimum hit target of 44×44 pt:
  ```swift
  .contentShape(Rectangle())
  .frame(minWidth: 44, minHeight: 44)
  ```
  Ensure all chip buttons and modal dismiss actions apply `.frame(minWidth: 44, minHeight: 44)`.

---

### A12-05: Hardcoded Non-Scaling Font Sizes in UIKit Appearances and Score Hero
- **Severity:** MEDIUM
- **Category:** Dynamic Type (WCAG 1.4.4 Resize Text)
- **Verification Status:** Verified by source inspection
- **File / Line Reference:** `AppAppearance.swift:20, 24`, `ScoreScreen.swift:191-195`
- **Description:**  
  1. `AppAppearance.swift` configures global `UINavigationBarAppearance` using hardcoded point sizes:
     ```swift
     standardAppearance.titleTextAttributes = [
         .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
         ...
     ]
     standardAppearance.largeTitleTextAttributes = [
         .font: UIFont.systemFont(ofSize: 30, weight: .bold),
         ...
     ]
     ```
     These navigation titles do not scale with user-selected Dynamic Type preferences.
  2. `ScoreScreen.swift` renders the readiness score using a fixed 72 pt font:
     ```swift
     Text("\(score)")
         .font(.system(size: 72, weight: .heavy, design: .rounded))
     ```
     While large, fixed font declarations ignore accessibility scale curves and user font weight preferences (`UIAccessibility.isBoldTextEnabled`).
- **Impact:**  
  Users requiring Large, Extra Large, or Accessibility Dynamic Type sizes receive static, unscaled navigation titles.
- **Remediation:**  
  1. In `AppAppearance.swift`, use `UIFontMetrics.default.scaledFont(for:)` or dynamic text styles:
     ```swift
     .font: UIFont.preferredFont(forTextStyle: .headline)
     ```
  2. In `ScoreScreen.swift`, wrap font sizing in `@ScaledMetric`:
     ```swift
     @ScaledMetric(relativeTo: .largeTitle) var scoreFontSize: CGFloat = 72
     ...
     .font(.system(size: scoreFontSize, weight: .heavy, design: .rounded))
     ```

---

### A12-06: Color-Only Active Floor State in 3D Scene Controls
- **Severity:** MEDIUM
- **Category:** Color & Vision (WCAG 1.4.1 Use of Color)
- **Verification Status:** Verified by source inspection
- **File / Line Reference:** `GlassControls.swift:96-98`, `HouseScreen.swift:619`
- **Description:**  
  The floor selector bar (`FloorChipPicker`) distinguishes the currently active floor solely via background tint:
  ```swift
  // Code comment in GlassControls.swift:
  // "Selection is currently carried by the accent tint alone (SC 1.4.1)"
  ```
  When a floor is selected, its chip changes background color from translucent gray to accent blue. No secondary visual indicator (such as an underline, checkmark icon, bold border, or shape change) is provided.
- **Impact:**  
  Users with monochromacy or severe color vision deficiencies cannot reliably determine which floor level is currently displayed in the 3D viewport.
- **Remediation:**  
  Pair the color tint with a non-color visual indicator, such as an icon glyph (`Image(systemName: "checkmark")`), an active border stroke, or a distinct pill shape. Ensure `.accessibilityValue(isSelected ? "Selected" : "")` or `.accessibilityAddTraits(.isSelected)` is set (which is partially present in VoiceOver, but missing visually).

---

### A12-07: Artificial Dynamic Type Size Capping in 3D Viewport Overlays
- **Severity:** MEDIUM
- **Category:** Dynamic Type (WCAG 1.4.4 Resize Text)
- **Verification Status:** Verified by source inspection
- **File / Line Reference:** `HouseScreen.swift:532`
- **Description:**  
  To prevent text elements from overflowing the fixed 3D viewport card, the status and control overlay applies:
  ```swift
  .dynamicTypeSize(...DynamicTypeSize.accessibility1)
  ```
  This restricts font scaling to `accessibility1`, preventing text from scaling to `accessibility2`, `accessibility3`, `accessibility4`, or `accessibility5`.
- **Impact:**  
  Users who require the largest Dynamic Type sizes (AX2 through AX5) are artificially prevented from viewing simulation status, room hazard warnings, and navigation cues at their configured reading size.
- **Remediation:**  
  Replace the fixed-height 3D card layout with an adaptive layout that converts from an overlaid card to a vertical stack or expandable drawer when accessibility text sizes (AX1+) are active. Remove the `.dynamicTypeSize` cap.

---

### A12-08: Route Narration Lacks Native Audio Synthesis for Non-VoiceOver Users
- **Severity:** LOW
- **Category:** Multimodal / Emergency Usability (WCAG 1.2.1 Audio-only / Alternative)
- **Verification Status:** Verified by source inspection
- **File / Line Reference:** `RouteNarration.swift:1-120`
- **Description:**  
  The codebase features an evacuation step generator (`RouteNarration`) that formats directions (e.g., "From Bedroom 1, head north through the hallway, then exit through Front Door"). While this text is exposed to VoiceOver, there is no built-in spoken audio playback (`AVSpeechSynthesizer`).  
  Many users with cognitive disabilities, dyslexia, low literacy, elderly users, or families conducting physical fire drills do not have VoiceOver enabled full-time.
- **Impact:**  
  During an active drill or emergency preparation walkthrough, users must keep their eyes glued to the screen to read textual instructions rather than hearing spoken audio guidance while moving through the house.
- **Remediation:**  
  Add an `AVSpeechSynthesizer` player with a prominent "Read Directions Aloud" button in the route summary view.

---

### A12-09: Content Truncation via Rigid `lineLimit` on Safety Information
- **Severity:** LOW
- **Category:** Layout Scalability / Dynamic Type (WCAG 1.4.4 Resize Text)
- **Verification Status:** Verified by source inspection
- **File / Line Reference:** `TasksScreen.swift:338`, `TaskComponents.swift:92`
- **Description:**  
  - In `TasksScreen.swift:338`, the outside meeting point address row specifies `.lineLimit(1)`. If a user enters a descriptive meeting point (e.g., "Under the big oak tree at 442 Elm Street across the sidewalk"), the text is truncated with an ellipsis.
  - In `TaskComponents.swift:92`, the task detail description specifies `.lineLimit(2)`, cutting off critical safety context when Dynamic Type is scaled up.
- **Impact:**  
  Crucial safety details (meeting point instructions, emergency steps) become unreadable when text size is enlarged.
- **Remediation:**  
  Remove hardcoded `lineLimit` caps or make them conditional on `@Environment(\.dynamicTypeSize)`. Allow text to wrap naturally in safety-critical cards.

---

## 5. Positive Findings

The audit identified several exemplary accessibility implementations:

1. **Dedicated 3D VoiceOver Abstraction Layer (`A11yHouseScene.swift` & `HouseSceneAccessibility.swift`):**  
   Rather than treating the SceneKit view as an inaccessible black box, the developers engineered a custom graph crawler that extracts rooms, doors, windows, fire hazards, and exit paths into a semantic hierarchy for VoiceOver. Room elements include custom accessibility actions (e.g., "Inspect exits", "Show hazards").
2. **Step-by-Step Egress Narration (`RouteNarration.swift`):**  
   Translates spatial coordinate vectors into natural, human-readable directional steps ("Turn left into Hallway", "Proceed 12 feet to Back Patio Door"). Verified by automated unit tests in `RouteNarrationTests.swift`.
3. **Respect for `Reduce Motion` (`HouseScreen.swift` & Simulation Engine):**  
   The evacuation simulation checks `UIAccessibility.isReduceMotionEnabled`. When enabled, particle-based flame animations and rapid smoke billows are replaced with calm, static state-change badges and stepped milestone highlights.
4. **Deuteranopia / Protanopia Safety Considerations (`Theme.swift`):**  
   Exit route indicators use a distinct blue/gold luminance split rather than pure red/green, ensuring paths remain distinguishable for users with common forms of color blindness.
5. **Comprehensive Automated Contrast Test Suite (`ThemeContrastTests.swift`):**  
   The project includes automated XCTest cases testing foreground tokens against dark surfaces to guard against regressions.

---

## 6. Systemic Issues and Root Causes

1. **Siloing 3D SceneKit from Standard Input Methods:**  
   The floor plan builder was architected as a pure direct-manipulation 3D canvas. When touch gestures are the sole input mechanism for geometry creation, accessibility becomes nearly impossible without a dual-representation model (a structured data form alongside the 3D viewport).
2. **Prioritizing Visual Density Over Accessibility Target Sizing:**  
   In floating glass toolbars (`GlassControls.swift`), buttons were visually styled to look compact and minimalist, leading developers to use the 24pt WCAG minimum boundary instead of Apple's 44pt touch guideline.
3. **Overuse of Container Accessibility Overrides:**  
   Developers used `.accessibilityElement(children: .combine)` as a quick way to clean up VoiceOver verbosity in compound cards (like error banners and profile chips), unintentionally stripping out accessibility actions from interactive child buttons.

---

## 7. Unverified Assumptions

- **Physical Switch Control & Voice Control Behavior:** Due to local test environment limitations (Xcode simulator runtime profile unavailable), Switch Control step scanning and Voice Control numbered grid navigation on the 3D canvas could not be verified on a physical device.
- **VoiceOver Audio Ducking:** How VoiceOver speech interacts with ambient simulation sound effects (alarm beeps, fire crackle) could not be verified at runtime.

---

## 8. Areas Requiring Further Investigation

1. **Third-Party PDF / Plan Importer Accessibility:**  
   When blueprints or floor plans are imported via `BuildFromPlanView.swift`, verify whether extracted OCR text and detected room boundaries provide VoiceOver feedback during import processing.
2. **Haptic Feedback Completeness:**  
   Evaluate whether `UINotificationFeedbackGenerator` fires during evacuation drill milestones (e.g., reaching safe exit, hazard blocked) to provide tactile feedback for deaf-blind users.

---

## 9. Recommended Priorities

| Priority | Action Item | Target File(s) | Estimated Effort |
|:---|:---|:---|:---|
| **P0 (Immediate)** | Fix white text on `Theme.warning` in `igniteSelectedButton` by switching to `Theme.destructiveFill`. | `HouseScreen.swift:978` | 15 mins |
| **P0 (Immediate)** | Restore interactive child buttons in `BackendFailureBanner` by switching to `.contain` or adding explicit `.accessibilityAction` handlers. | `BackendFailureBanner.swift:91-139` | 1 hour |
| **P1 (High)** | Enforce 44×44pt minimum touch targets on all glass chips, section headers, and modal cancel buttons. | `GlassControls.swift:94`, `ConsentSheet.swift:77`, `TaskComponents.swift:186` | 2 hours |
| **P1 (High)** | Build a 2D structured room/wall/opening table editor to provide a non-gesture alternative to 3D SceneKit editing. | `EditorSceneView.swift`, `HouseScreen.swift` | 1–2 days |
| **P2 (Medium)** | Remove `.dynamicTypeSize(...accessibility1)` cap; redesign overlay to adapt to large text sizes without clipping. | `HouseScreen.swift:532` | 3 hours |
| **P2 (Medium)** | Add secondary visual indicator (icon or border) to active floor chip picker to satisfy WCAG 1.4.1. | `GlassControls.swift:96-98` | 1 hour |
| **P2 (Medium)** | Scale navigation bar titles dynamically using `UIFontMetrics` or dynamic font styles. | `AppAppearance.swift:20, 24` | 1 hour |
| **P3 (Low)** | Integrate `AVSpeechSynthesizer` into `RouteNarration` for one-tap spoken directions during live drills. | `RouteNarration.swift`, `HouseScreen.swift` | 4 hours |
| **P3 (Low)** | Remove rigid `lineLimit` caps on meeting point addresses and task descriptions. | `TasksScreen.swift:338`, `TaskComponents.swift:92` | 30 mins |
