# Cross-Feature and Cross-Layer Consistency Audit

**Audit Date:** 2026-10-11  
**Auditor:** Agent 17 (Cross-Feature Consistency Specialist)  
**Target File:** `audit/2026-10-11_comprehensive/17_CROSS_FEATURE_CONSISTENCY.md`  
**Repository:** `/Users/anish/Documents/Congressional App Challenge/Escape-Plan`  

---

## 1. Executive Summary

This audit evaluated cross-feature and cross-layer consistency across the Escape Plan system, spanning the iOS client (SwiftUI, SceneKit, SwiftPM), the backend service (Python, FastAPI, Pydantic), the JSON Schema specifications, and user-facing artifacts (PDF exports, responder snapshots, VoiceOver narration, and documentation).

The inspection revealed multiple critical breaks where independent layers developed in parallel without end-to-end contract enforcement. Most notably:
1. **Silent Data Omission in PDF Exports:** The primary printable escape plan PDF completely omits the user's preparedness score and computed storm safe room because `writePDF` fails to load the local score cache, whereas the secondary responder snapshot exporter does.
2. **Asymmetric Validation Bricking Homes:** `EditorValidation.swift` enforces a strict opening non-overlap invariant that neither the backend Pydantic models nor JSON Schema validate. Scanned or AI-generated homes with touching/overlapping parametric openings are successfully processed by the backend and persisted locally, but permanently crash the House Editor session upon opening, bricking the home from editing.
3. **Misleading Score Explanations:** When a home suffers a critical structural defect (e.g., zero viable exit routes for an occupant), the score engine caps the score at 40 (deducting 60 points), yet attributes the deduction entirely to a minor 5-point checklist item (e.g. testing smoke alarms) because non-scoring structural findings are excluded from component explanation generation.
4. **Peril Naming Discrepancies and Unreachable Routing:** The routing engine and `/routes` endpoint identify the storm peril as `"tornado"`, while the scoring engine, `/score` endpoint, and checklist identify it as `"severe_weather"`. Furthermore, while complete routing algorithms for tornadoes and earthquakes exist on the backend, the iOS client hardcodes route fetching to `"fire"`, rendering multi-peril routing dead code.
5. **Loss of Scoring State Across Sync:** Checklist completion states are saved in local device `UserDefaults` rather than the synced home document or backend cloud store. Synchronizing a home to a second device causes the second device to display a zero-progress checklist and an altered preparedness score.

---

## 2. Scope and Files Inspected

### iOS Client (`escape_plan/`)
- **Models:**
  - `escape_plan/Models/HomeModel.swift`
  - `escape_plan/Models/Enums.swift`
  - `escape_plan/Models/ScoreModels.swift`
  - `escape_plan/Models/RoutePlan.swift`
  - `escape_plan/Models/AnalyzeModels.swift`
  - `escape_plan/Models/EvacuationTimeline.swift`
  - `escape_plan/Models/ChecklistItem+Objects.swift`
  - `escape_plan/Models/FixtureLoader.swift`
- **Editor & Validation:**
  - `escape_plan/Editor/Core/EditorValidation.swift`
  - `escape_plan/Editor/Core/HomeModelStore.swift`
  - `escape_plan/Editor/Core/OpeningPlacement.swift`
  - `escape_plan/Editor/Core/HouseEditorSessionController.swift`
- **Screens:**
  - `escape_plan/Screens/HomeScreen.swift`
  - `escape_plan/Screens/HouseScreen.swift`
  - `escape_plan/Screens/ScoreScreen.swift`
  - `escape_plan/Screens/ProfileEditorView.swift`
  - `escape_plan/Screens/SettingsScreen.swift`
  - `escape_plan/Screens/ReadinessStore.swift`
  - `escape_plan/Screens/RouteFindingViews.swift`
  - `escape_plan/Screens/TaskComponents.swift`
- **Persistence & Sync:**
  - `escape_plan/Persistence/ChecklistStateStore.swift`
  - `escape_plan/Persistence/ScoreCache.swift`
  - `escape_plan/Persistence/SchemaMigrator.swift`
  - `escape_plan/Persistence/HomeDocumentStore.swift`
  - `escape_plan/Sync/SyncReconciler.swift`
  - `escape_plan/Sync/CloudHomeModels.swift`
  - `escape_plan/Sync/HomeFingerprint.swift`
- **Export & Narration:**
  - `escape_plan/Export/EscapePlanExporter.swift`
  - `escape_plan/Export/EscapePlanDocument.swift`
  - `escape_plan/Export/EscapePlanPDF.swift`
  - `escape_plan/Export/RouteNarration.swift`
  - `escape_plan/Export/ResponderSnapshotExtractor.swift`
  - `escape_plan/Export/ResponderSnapshotJSON.swift`
  - `escape_plan/Export/ResponderSnapshotStore.swift`
- **Renderer & Fixtures:**
  - `escape_plan/Renderer/HomeThumbnail.swift`
  - `escape_plan/Renderer/FixtureLibrary.swift`
  - `escape_plan/Renderer/Evacuation/MockTimeline.swift`
  - `escape_plan/Renderer/Fixtures/FixtureKit.swift`

### Backend (`backend/app/`)
- `backend/app/models.py`
- `backend/app/main.py`
- `backend/app/limits.py`
- `backend/app/validate.py`
- `backend/app/schema_migrator.py`
- `backend/app/cloud_models.py`
- `backend/app/scoring/score.py`
- `backend/app/scoring/checklist.py`
- `backend/app/scoring/findings.py`
- `backend/app/routing/plan.py`
- `backend/app/routing/engine.py`
- `backend/app/routing/egress.py`
- `backend/app/routing/hazard.py`
- `backend/app/routing/profiles.py`
- `backend/app/routing/diff.py`
- `backend/app/routing/obstructions.py`
- `backend/app/corpus/egress_thresholds.json`

### Schema & Specs
- `schema/homemodel.schema.json`
- `docs/preparedness-score-weights.md`
- `docs/profile-constraint-mappings.md`
- `docs/demo/claims-ledger-v2.md`

---

## 3. Methods and Checks Performed

1. **Terminology Tracing:** Systematic search for discrepancies across routing, scoring, and UI contexts regarding `route` vs `exit` vs `egress`, `peril` vs `hazard`, `preparedness score` vs `readiness score`, and `"safe"` vs `"ready"`.
2. **Data Definition Lockstep Analysis:** Compared numeric constants and thresholds across Swift, Python, JSON schema, and corpus files (e.g. egress opening minimums, score weights, high-severity score caps, walking speeds, stair factors).
3. **Cross-Layer Validation Audit:** Compared validation invariants across `EditorValidation.swift`, `backend/app/models.py`, `backend/app/limits.py`, and `schema/homemodel.schema.json`.
4. **Data Continuity Across Screens and Exports:** Traced the propagation of scores, routes, and hazards from backend computation through local caches to `HomeScreen`, `HouseScreen`, `ScoreScreen`, printable PDF, and responder snapshot JSON.
5. **Conversion and Routing Parity Check:** Evaluated on-device scanning and caching mechanisms against backend conversion and routing pipelines.
6. **Schema Versioning Audit:** Compared schema version definitions and migration pipelines across `homemodel.schema.json`, `SchemaMigrator.swift`, and `backend/app/schema_migrator.py`.
7. **Dead Code and Target Membership Scan:** Conducted a global type reference scan across the iOS codebase to detect unreachable symbols, dead endpoints, and mock code compiled into production targets.

---

## 4. Findings (with Evidence)

### [CRITICAL] A17-01 Exported Printable PDF Silently Omits Readiness Score and Safe Room
**Domain:** Export / UI Parity  
**Location:** [EscapePlanExporter.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/EscapePlanExporter.swift#L77-L82), [EscapePlanPDF.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/EscapePlanPDF.swift#L266-L280)  
**Observed behavior:** When exporting the printable escape plan PDF, the readiness score and computed storm safe room are missing from the document.  
**Evidence:**  
In `EscapePlanExporter.swift`:
```swift
77: let document = EscapePlanDocument(home: preview.home,
78:                                   plan: preview.plan,
79:                                   routesComputedAt: preview.routesComputedAt,
80:                                   meetingPoint: meetingPoint,
81:                                   generatedAt: now)
82: let output = EscapePlanPDF.render(document)
```
In `writePDF`, `document.scoreResponse` is never initialized (defaults to `nil`).  
In contrast, `writeResponderSnapshot` explicitly populates it:
```swift
115: if let cache = try? ScoreCache() {
116:     document.scoreResponse = cache.load(homeID: preview.home.id)
117: }
```
In `EscapePlanPDF.swift`:
```swift
266: if let score = document.scoreResponse?.score {
267:     blocks.append(Block(text: "Composite Readiness Score: \(score)/100", font: .systemFont(ofSize: 10), gray: 0.1, spacingBefore: 4))
268: }
269: var safeRoomName: String? = nil
270: if let srItem = document.scoreResponse?.checklist.first(where: { $0.category == .safe_room }) {
...
278:     blocks.append(Block(text: "Computed Storm Safe Room: \(name)", font: .systemFont(ofSize: 10), gray: 0.1, spacingBefore: 2))
279: }
```
Because `document.scoreResponse` is `nil` in `writePDF`, the blocks for Composite Readiness Score and Computed Storm Safe Room are silently skipped on all printable escape plans.  
**Expected behavior:** The exported PDF plan should display the home's composite readiness score and computed storm safe room from `ScoreCache`, matching what the user sees in the app's UI.  
**Root cause:** `EscapePlanExporter.writePDF` failed to load `ScoreCache` when assembling `EscapePlanDocument`, while `writeResponderSnapshot` correctly did.  
**Impact:** Physical printed escape plans given to families lack the composite readiness score and storm refuge location that the application promises to generate.  
**Recommended improvement:** Update `EscapePlanExporter.writePDF` to load `ScoreCache().load(homeID: preview.home.id)` and assign it to `document.scoreResponse`.  
**Dependencies:** `ScoreCache.swift`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Small  

---

### [HIGH] A17-02 Asymmetric Opening Overlap Rule Bricks Home Models in House Editor
**Domain:** Validation Parity / Editor  
**Location:** [EditorValidation.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/EditorValidation.swift#L416-L432), [HouseScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L2324-L2331), [backend/app/models.py](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/models.py#L413-L435)  
**Observed behavior:** Homes with overlapping or touching opening parametric ranges (`wall_segment.t0...t1`) are valid under backend Pydantic models and JSON Schema, but are rejected on load by the iOS House Editor, permanently locking the user out of editing.  
**Evidence:**  
In `EditorValidation.swift`:
```swift
416: private static func validateOpeningOverlaps(on floor: Floor) -> [ValidationIssue] {
...
425:     for (a, b) in zip(sorted, sorted.dropFirst())
426:     where a.wall_segment.t1 > b.wall_segment.t0 + Geometry.epsilon {
427:         issues.append(.init(.openingPlacement, entityId: b.id,
428:                             "overlaps opening '\(a.id)' on the same wall..."))
429:     }
```
In `HouseScreen.swift`:
```swift
2301: let newStore = try HomeModelStore(model: model)
...
2324: } catch HomeModelStore.StoreError.invalidInitialModel(let issues) {
...
2330:     loadError = "This home has a problem the editor can't open: \(Self.sentence(issues.first?.message ?? "unknown"))"
```
In `backend/app/models.py`, `Opening._check` validates room IDs and wall segment association, but contains no check for overlapping t-ranges on the same wall segment. JSON schema also contains no such constraint.  
**Expected behavior:** Validation invariants must be consistent between backend generation (`/build`, `/convert`) and client-side editing. If an opening overlap is illegal, the backend and converter must reject/resolve it before persisting. If minor overlaps are acceptable approximations in room scanning, the editor should issue a soft warning rather than throwing in `HomeModelStore.init` and aborting editor initialization.  
**Root cause:** Client editor validation implemented an extra strict geometric constraint that was never mirrored into the backend model validators or the JSON schema.  
**Impact:** If a scan conversion or AI-built plan produces two doors or a door and a window on the same wall whose intervals intersect, the home document is saved to disk but cannot be opened in the House tab. The user is trapped with an un-editable home and no mechanism to repair it in-app.  
**Recommended improvement:** Add opening overlap validation to backend `app.models.Floor._check` and ensure `/convert` cleanses overlapping segments. Make `HomeModelStore` gracefully isolate or flag invalid openings instead of refusing to initialize.  
**Dependencies:** `backend/app/models.py`, `escape_plan/Editor/Core/HomeModelStore.swift`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Medium  

---

### [HIGH] A17-03 Disconnected Score Component Attribution on High-Severity Structural Failures
**Domain:** Scoring / Explanations  
**Location:** [backend/app/scoring/score.py](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/scoring/score.py#L126-L168), [ScoreScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ScoreScreen.swift#L248-L285)  
**Observed behavior:** When a home has an unresolvable high-severity issue (such as an occupant with no viable egress route), the composite preparedness score is capped at 40 (costing 60 points), but the UI explains the score loss by highlighting an unrelated 5-point deduction (such as an unperformed alarm test).  
**Evidence:**  
In `backend/app/scoring/score.py`:
```python
134: if item.severity == "high":
135:     has_unresolved_high_severity = True
136:
137: if item.scoring:
138:     deduction = SEVERITY_DEDUCTIONS.get(item.severity, 5.0)
139:     sub_scores_raw[peril] -= deduction
140:
141:     # We track the single largest deduction across all perils
142:     if deduction > largest_deduction_value:
143:         largest_deduction_value = deduction
144:         largest_deduction_item = item
...
153: if has_unresolved_high_severity:
154:     composite_raw = min(composite_raw, COMPOSITE_CAP_HIGH_SEVERITY)
```
Engine findings such as `no_viable_route` have `scoring=False` and `severity="high"`. Because `largest_deduction_item` is strictly populated inside `if item.scoring:`, `largest_deduction_item` never points to the high-severity finding that triggered `COMPOSITE_CAP_HIGH_SEVERITY` (40.0).  
In `ScoreScreen.swift`:
```swift
248: /// The backend sends 0 or 1 component: the single largest unresolved deduction...
256: let cost = "−\(formatted(deduction(component))) points"
```
The screen renders the score as 40, and directly beneath it attributes the loss to "−5 points: Smoke alarm in bedroom".  
**Expected behavior:** When `COMPOSITE_CAP_HIGH_SEVERITY` binds and drops the composite score to 40, the `components` list returned by `/score` should identify the high-severity finding that triggered the cap as the primary reason for the score reduction.  
**Root cause:** Score component extraction only inspects items flagged `scoring: true`, ignoring structural high-severity items flagged `scoring: false` that trigger the 40-point composite cap.  
**Impact:** Users are severely misled about what is dragging down their preparedness score. A user attempting to raise their score from 40 will replace smoke alarm batteries, find their score still stuck at 40, and receive no UI feedback that an occupant's bedroom lacks an exit route.  
**Recommended improvement:** When `has_unresolved_high_severity` caps the score, synthesize a `ScoreComponent` representing the high-severity finding that triggered the cap with `max_points = 100 - COMPOSITE_CAP_HIGH_SEVERITY`.  
**Dependencies:** `backend/app/scoring/score.py`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Small  

---

### [HIGH] A17-04 Cross-Peril Naming Collision and Unreachable Multi-Peril Routing
**Domain:** Routing / Scoring / Parity  
**Location:** [backend/app/routing/plan.py](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/routing/plan.py#L50), [backend/app/scoring/score.py](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/scoring/score.py#L49-L53), [HouseScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HouseScreen.swift#L1693)  
**Observed behavior:** The routing engine and scoring engine use conflicting identifiers for the storm hazard (`"tornado"` vs `"severe_weather"`). Furthermore, although the backend provides complete routing algorithms for tornado safe rooms and earthquake cover objects, the iOS application only ever fetches fire routes.  
**Evidence:**  
In `backend/app/routing/plan.py`:
```python
50: peril: Literal["fire", "tornado", "earthquake"] = "fire"
```
In `backend/app/scoring/score.py`:
```python
49: PERIL_BASIS: dict[str, PerilBasis] = {
50:     "fire": "code_quantified",
51:     "earthquake": "guidance_based",
52:     "severe_weather": "guidance_based",
53: }
```
In `escape_plan/Screens/HouseScreen.swift`:
```swift
1693: let result = try await apiClient.fetchRoutesCached(home: model,
1694:                                                    profileID: selectedProfileID)
```
`HouseScreen` omits the `peril` argument, which defaults to `nil` in `APIClient+Routes.swift` and normalizes to `"fire"`. There is no UI picker or journey in the app that ever invokes `fetchRoutesCached` with `peril: "tornado"` or `peril: "earthquake"`.  
**Expected behavior:** Hazard naming should be unified across the platform (`tornado` vs `severe_weather`). If non-fire routing is out of product scope (as stated in scope-lock docs: "the app draws fire evacuation routes only"), the backend `perils/tornado.py` and `perils/earthquake.py` modules and schema fields should either be integrated with UI selectors or clearly marked as un-wired backend spikes.  
**Root cause:** The routing engine and scoring engine were built in separate sprints with differing peril vocabularies (`tornado` in routing; `severe_weather` in scoring), and the iOS UI scope was locked to fire-only before UI selectors for other perils were connected.  
**Impact:** Architectural drift between routing and scoring layers; cache key collisions or misses if non-fire routes are ever queried; developer confusion regarding whether tornado/earthquake routing is supported.  
**Recommended improvement:** Standardize peril identifiers to a shared enum. If severe weather and earthquake routes are to remain unrendered in the UI, document the scope boundary explicitly in `APIClient+Routes.swift` and deprecate unused request parameters.  
**Dependencies:** `backend/app/routing/`, `backend/app/scoring/`, `escape_plan/Networking/`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Medium  

---

### [HIGH] A17-05 Asymmetric Checklist Done-State Storage Breaks Multi-Device Sync and Score Parity
**Domain:** Persistence / Cloud Sync / Scoring  
**Location:** [ChecklistStateStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Persistence/ChecklistStateStore.swift#L1-L25), [CloudHomeModels.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/CloudHomeModels.swift#L29-L43), [SyncReconciler.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Sync/SyncReconciler.swift)  
**Observed behavior:** When a user checks off readiness items on Device A and syncs to Device B via Cloud Sync, Device B shows all checklist items unchecked and calculates a lower preparedness score.  
**Evidence:**  
In `ChecklistStateStore.swift`:
```swift
4: // Stored in UserDefaults under "checklistState.<home_id>", NOT on the home document:
5: // the HomeModel schema is frozen (no checklist field without a schema_version bump)...
6: // Trade-off, documented in docs/decisions.md: state doesn't travel with export/import...
```
In `CloudHomeModels.swift`:
```swift
29: struct StoredHome: Decodable, Equatable, Identifiable, Sendable {
...
36:     let home: HomeModel
37:     let revision: Int
```
Neither `StoredHome` nor `HomeSyncRequestBody` includes checklist done-state.  
Because `SMOKE_ALARM_COMPONENT` and `PRACTICE_COMPONENT` in `backend/app/scoring/checklist.py` earn points when checked, the score computed on Device B differs from Device A for the exact same home.  
**Expected behavior:** Checklist done-state should be synced alongside the home model so that a user's preparedness progress is consistent across all authenticated devices.  
**Root cause:** `checklistState` was placed in local `UserDefaults` to avoid bumping `homemodel.schema.json` version, leaving the cloud sync service with no awareness of task completion states.  
**Impact:** Broken user experience across multiple devices. Syncing a home resets the user's checklist tasks and degrades their displayed score on secondary devices.  
**Recommended improvement:** Introduce an account-level or home-associated checklist sync entity in `CloudHomeModels` and `SyncReconciler`.  
**Dependencies:** Cloud Sync, `ChecklistStateStore.swift`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Medium  

---

### [MEDIUM] A17-06 Discrepancy between JSON Schema Contract and Backend/Editor Geometry Limits
**Domain:** Schema / Validation  
**Location:** [homemodel.schema.json](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/schema/homemodel.schema.json), [backend/app/models.py](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/models.py#L270-L330), [EditorValidation.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Editor/Core/EditorValidation.swift#L157-L200)  
**Observed behavior:** `schema/homemodel.schema.json` bills itself as the canonical contract of the system, yet omits dozens of hard size bounds enforced by `backend/app/models.py` and `EditorValidation.swift`.  
**Evidence:**  
In `backend/app/models.py` and `EditorValidation.swift`:
- `MAX_FLOORS = 8`
- `MAX_ROOMS = 200`
- `MAX_OPENINGS_PER_FLOOR = 400`
- `MAX_OBJECTS_TOTAL = 200`
- `MAX_COORD_M = 200.0`
- `MAX_POLYGON_VERTICES = 64`
- `MAX_ROOM_SPAN_M = 60.0`
- `MAX_OBJECT_SIZE_M = 50.0`
In `schema/homemodel.schema.json`:
- `floors`: No `maxItems`
- `floor.rooms`: Only `minItems: 1`, no `maxItems`
- `floor.openings`: No `maxItems`
- `floor.objects`: No `maxItems`
- `point`: No coordinate range limits
- `polygon`: No vertex count bounds
**Expected behavior:** `homemodel.schema.json` should reflect all structural bounds enforced by the Pydantic and Swift layers.  
**Root cause:** Size limits were introduced in sprint S11.25 into `backend/app/models.py` and mirrored into `EditorValidation.swift`, but were never back-ported into `schema/homemodel.schema.json`.  
**Impact:** External tools or third-party JSON validators validating payloads against `homemodel.schema.json` will consider documents valid that the backend API promptly rejects with 422 HTTP errors.  
**Recommended improvement:** Synchronize `homemodel.schema.json` with the S11.25 bounds in `models.py`.  
**Dependencies:** `schema/homemodel.schema.json`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Small  

---

### [MEDIUM] A17-07 Deceptive Sensory Tag Guidance in Profile Editor
**Domain:** Profile Constraints / UI  
**Location:** [ProfileEditorView.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ProfileEditorView.swift#L60-L62), [ProfileEditorView.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ProfileEditorView.swift#L150-L165), [backend/app/routing/profiles.py](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/routing/profiles.py#L40-L80)  
**Observed behavior:** Sighted users configuring a family member's profile are shown toggles for "Hearing Impaired" and "Vision Impaired" under the footer note: "Tags shape this person's escape routes — e.g. limited mobility avoids stairs and windows." However, neither tag alters routing in any way.  
**Evidence:**  
In `ProfileEditorView.swift`:
```swift
60: } header: {
61:     Text("Needs").accessibilityAddTraits(.isHeader)
62: } footer: {
63:     Text("Tags shape this person's escape routes — e.g. limited mobility avoids stairs and windows.")
64: }
```
In `backend/app/routing/profiles.py`:
```python
58: for tag in profile.tags:
59:     if tag == ProfileTag.mobility_limited:
60:         avoid_stairs = True
61:         avoid_windows = True
62:     elif tag == ProfileTag.elderly:
63:         stair_penalty_m = max(stair_penalty_m, ELDERLY_STAIR_PENALTY_M)
64:         max_sill_height_m = thresholds.window_max_sill_m
65:     elif tag == ProfileTag.child:
66:         window_penalty_m = max(window_penalty_m, CHILD_WINDOW_PENALTY_M)
```
Neither `hearing_impaired` nor `vision_impaired` is checked in `constraints_for_profile`.  
In `ProfileEditorView.swift`, only VoiceOver users get the hidden hint:
```swift
160: case .hearing_impaired: return "Changes no routing."
162: case .vision_impaired: return "Changes no routing."
```
**Expected behavior:** The visible UI should clearly explain what each tag affects (e.g. "Hearing Impaired adds alert device tasks to your checklist; Vision Impaired marks occupants on the emergency responder card; neither changes route paths").  
**Root cause:** Generalizing the profile editor UI without differentiating between routing tags (`mobility_limited`, `elderly`, `child`) and checklist/export tags (`hearing_impaired`, `vision_impaired`).  
**Impact:** Sighted family members configure sensory tags expecting tailored evacuation routes, but the app generates standard routes without explaining why.  
**Recommended improvement:** Update the section footer or per-toggle captions to specify which tags alter routes versus which affect checklist recommendations or responder cards.  
**Dependencies:** `ProfileEditorView.swift`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Small  

---

### [MEDIUM] A17-08 Orphaned Endpoints and Redundant Renderer Fixtures in App Target
**Domain:** Code Hygiene / Dead Features  
**Location:** [backend/app/main.py](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/main.py#L704), [APIClient+Convert.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/APIClient+Convert.swift#L58-L60), [HomeThumbnail.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Renderer/HomeThumbnail.swift#L1-L64), [FixtureLibrary.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Renderer/FixtureLibrary.swift#L1-L56)  
**Observed behavior:** Dead and abandoned features remain deployed in the backend and compiled in the client target:
1. `POST /diff_obstructions` and `backend/app/routing/diff.py` are active backend endpoints that were abandoned by the iOS client on 2026-10-02 (`APIClient+Convert.swift:58-60`).
2. `HomeThumbnail.swift` (64 lines of SceneKit offscreen rendering logic) is compiled into the app target but has 0 references across the entire project.
3. `FixtureLibrary.swift` and `FixtureLoader.swift` define redundant fixture loader implementations (`Fixture` vs `HomeFixture`).  
**Evidence:**  
In `APIClient+Convert.swift`:
```swift
58: // `Obstruction`, `DiffRequest`, `DiffResult` and `diffObstructions` (POST /diff_obstructions) left
59: // with the re-scan review, cut from the demo app 2026-10-02. The backend route is still deployed.
```
In `escape_plan/Renderer/HomeThumbnail.swift`:
`enum HomeThumbnail` has zero callers across all Swift files in `escape_plan/`, `escape_planTests/`, and `tools/`.  
**Expected behavior:** Dead endpoints should be deprecated or removed; unused rendering code should be eliminated; fixture loading should be consolidated into a single module.  
**Root cause:** Rapid iteration and scope cutoffs left uncalled server endpoints and abandoned view components without a cleanup pass.  
**Impact:** Unnecessary attack surface on the backend; binary bloat and maintenance overhead on the client.  
**Recommended improvement:** Remove `/diff_obstructions` or place behind admin flags; delete `HomeThumbnail.swift`; unify `FixtureLibrary.swift` and `FixtureLoader.swift`.  
**Dependencies:** `backend/app/main.py`, `escape_plan/Renderer/`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Small  

---

### [LOW] A17-09 Inconsistent Score and Storm Refuge Terminology across UI, Docs, and PDF
**Domain:** Terminology Consistency  
**Location:** [HomeScreen.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/HomeScreen.swift#L319), [EscapePlanPDF.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/EscapePlanPDF.swift#L267), [EscapePlanPDF.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/EscapePlanPDF.swift#L278)  
**Observed behavior:** The app uses conflicting names for its primary metric: "Preparedness Score" (Home, Score screen, Settings, backend weights doc) vs "Composite Readiness Score" (EscapePlanPDF) vs "Readiness Score" (claims ledger, demo script, responder snapshot). Furthermore, storm refuge rooms in stick-built houses are labeled "Computed Storm Safe Room" on PDF exports.  
**Evidence:**  
In `HomeScreen.swift:319`: `Text("Preparedness")`.  
In `EscapePlanPDF.swift:267`: `blocks.append(Block(text: "Composite Readiness Score: \(score)/100", ...))`.  
In `EscapePlanPDF.swift:278`: `blocks.append(Block(text: "Computed Storm Safe Room: \(name)", ...))`.  
FEMA P-320 and ICC 500 define a "Safe Room" specifically as an engineered structural shelter tested against 250 mph winds and missile impacts; an interior residential hallway or bathroom is an "interior shelter area" or "best available refuge area".  
**Expected behavior:** Harmonize metric terminology throughout the user interface, documentation, and printed exports. Replace "Safe Room" with "Storm Shelter Area" or "Severe Weather Refuge" on PDF exports for non-engineered residential spaces to adhere to FEMA definitions.  
**Root cause:** Divergent copy writing between the original product spec ("Readiness Score"), the S3.5 score redesign ("Preparedness Score"), and export drawing templates.  
**Impact:** Inconsistent brand language; potential regulatory or safety critique regarding misuse of FEMA "Safe Room" terminology.  
**Recommended improvement:** Standardize user-facing copy on "Readiness Score" or "Preparedness Score" uniformly; revise PDF text to "Severe Weather Shelter Area".  
**Dependencies:** UI strings, export templates  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Small  

---

### [LOW] A17-10 Unsynchronized Severity Enums between Backend and Swift Models
**Domain:** Type Consistency  
**Location:** [backend/app/scoring/checklist.py](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/scoring/checklist.py#L98), [ScoreModels.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Models/ScoreModels.swift#L112-L120), [AnalyzeModels.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Models/AnalyzeModels.swift#L30-L40)  
**Observed behavior:** Severity levels are defined inconsistently across the client and server. Backend `checklist.py` defines severities as `info`, `low`, `med`, `high`. In `ScoreModels.swift`, `ItemSeverity` defines only `info`, `high`, `unknown` (collapsing `low` and `med` to `info`), whereas `AnalyzeModels.swift` defines `high`, `med`, `low`, `unknown`.  
**Evidence:**  
In `backend/app/scoring/checklist.py:98`:
```python
severity: Literal["info", "low", "med", "high"] = "info"
```
In `ScoreModels.swift:112-120`:
```swift
enum ItemSeverity: String, Codable {
    case info
    case high
    case unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemSeverity(rawValue: raw) ?? .info
    }
}
```
**Expected behavior:** Client models should accurately represent all backend severity cases (`high`, `med`, `low`, `info`).  
**Root cause:** S6.7 score refactoring simplified `ItemSeverity` in `ScoreModels.swift` without reconciling it against `checklist.py` or `AnalyzeModels.swift`.  
**Impact:** Any checklist item assigned `med` or `low` severity on the backend is downgraded to `.info` on the client.  
**Recommended improvement:** Add `.med` and `.low` cases to `ItemSeverity` in `ScoreModels.swift`.  
**Dependencies:** `ScoreModels.swift`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Small  

---

### [OBSERVATION] A17-11 Test Scaffolding and Mocks Located within Production Target Directories
**Domain:** Target Configuration  
**Location:** [MockTimeline.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Renderer/Evacuation/MockTimeline.swift#L1-L383), [TokenStore.swift](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Auth/TokenStore.swift#L25-L60)  
**Observed behavior:** `MockTimeline.swift` (383 lines of mock timeline simulation) and test token stores (`InMemoryTokenStore`, `FailingTokenStore`, `UnreadableTokenStore`) are located inside the `escape_plan` production source tree under Xcode's `PBXFileSystemSynchronizedRootGroup`.  
**Evidence:**  
In `escape_plan.xcodeproj/project.pbxproj`:
```
27C930C33001895C002825E5 /* escape_plan */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    path = escape_plan;
};
```
While wrapped with `#if DEBUG`, these types are only utilized by unit tests in `escape_planTests/` and are never used by production application code.  
**Expected behavior:** Test mocks and doubles should reside in test target directories (`escape_planTests/`) rather than the main application bundle folder.  
**Root cause:** Synchronized file system root groups in Xcode 16 automatically include all nested folder files in target compilation.  
**Impact:** Unnecessary clutter in the production directory tree; slight risk of leaking mock scaffolding into preview or staging builds if build configurations change.  
**Recommended improvement:** Relocate `MockTimeline.swift` and mock token stores to `escape_planTests/Support/`.  
**Dependencies:** `project.pbxproj`, `escape_planTests`  
**Verification status:** Verified by source inspection  
**Confidence:** High  **Effort:** Small  

---

## 5. Positive Findings

1. **Strict Client-Server Calculation Discipline:** The iOS client strictly avoids computing or approximating routes, evacuation simulations, or preparedness scores on device. Route calculations are strictly delegated to `POST /routes`, timelines to `POST /evacuate`, and scores to `POST /score`. This guarantees mathematical determinism across all app surfaces.
2. **Robust Route Cache Invalidation:** `RoutePlanCache` incorporates a canonical `HomeFingerprint` calculated over the `HomeModel` (with volatile metadata zeroed out). This effectively prevents stale routes from being served when home geometry, doors, or furniture are edited.
3. **Resilient Lenient Decoding for Server Enums:** Enums that represent server-driven response data (`ChecklistCategory`, `WaypointKind`, `AgentFinding.Severity`) feature custom initializers that degrade gracefully to `.other` or `.unknown`. An unrecognized category returned by a newer server deployment will not crash the client decoding pipeline.
4. **Strict Schema Enums for Persistence Data:** Enums that model persistent user home geometry (`RoomType`, `OpeningKind`, `ObjectCategory`, `Source`) intentionally fail decoding when encountering unknown cases, avoiding silent data loss or corrupted re-encoding on disk.
5. **Shared Model Contracts with Tools:** The symlinked `tools/editorcore` package enables Foundation-only model verification without requiring an iOS simulator runtime, providing reliable CI coverage for core data structures.

---

## 6. Systemic Issues and Root Causes

1. **Siloed Feature Implementations Without End-to-End Export Verification:**  
   The export pipeline (`EscapePlanExporter`, `EscapePlanPDF`) was tested primarily for page layout and rendering stability rather than data continuity. Because tests asserted that PDF data was generated rather than verifying that specific data blocks (such as the score and safe room) were present in the output, `writePDF`'s failure to load `ScoreCache` went undetected.

2. **Asymmetric Growth of Validation Invariants:**  
   When the House Editor was enhanced with interactive opening placement, opening overlap checks were added directly to `EditorValidation.swift`. Because backend developers did not simultaneously add the check to `backend/app/models.py` or `homemodel.schema.json`, the client's editor became strictly more restrictive than the backend generator.

3. **Incomplete Scope-Lock Reconciliations:**  
   When the project scope was locked to "fire evacuation routes only," the decision was implemented on the iOS screen layer by simply not requesting non-fire routes. The backend routing engines (`tornado.py`, `earthquake.py`), request models, and cache keys were left in an intermediate state, creating naming collisions (`tornado` vs `severe_weather`) and orphaned capabilities.

4. **Schema Avoidance Leading to State Fragmentation:**  
   To avoid bumping `schema_version` from 2.1 to 2.2, checklist state was stored outside the `HomeModel` in local `UserDefaults`. This decision fundamentally severed checklist progress from the cloud sync pipeline, resulting in cross-device state inconsistency.

---

## 7. Unverified Assumptions

1. **Live Cloud Sync Multi-Device Runtime Behavior:**  
   Because the local test environment lacks active cloud credentials and an iOS simulator runtime, the desynchronization of checklist done-states was verified by exhaustive source inspection of `CloudHomeModels.swift`, `SyncReconciler.swift`, and `ChecklistStateStore.swift`, but not on two physical devices simultaneously.
2. **LiDAR Converter Scan Output Overlap Frequency:**  
   It is assumed that RoomPlan output processed by `/convert` rarely produces perfectly overlapping openings on synthetic clean scans, which explains why the `EditorValidation.swift` opening overlap crash has not blocked every test fixture.

---

## 8. Areas Requiring Further Investigation

1. **VoiceOver Narration vs 3D Scene Parity:**  
   Evaluate whether `RouteNarration.swift` provides equivalent directional fidelity to the SceneKit visual route overlay for complex multi-story structures with split-level landings.
2. **Offline Resilience During Long Disconnects:**  
   Investigate how `ScoreCache` and `RoutePlanCache` behave when a home's geometry is modified repeatedly offline, ensuring that stale scores are explicitly invalidated rather than presented indefinitely.

---

## 9. Recommended Priorities

1. **P0 (Immediate Fix):** Fix `EscapePlanExporter.swift:77` to load `ScoreCache` so printed PDF escape plans include the composite readiness score and computed storm safe room (`A17-01`).
2. **P0 (Immediate Fix):** Harmonize opening overlap validation between `EditorValidation.swift` and backend `models.py`, ensuring homes with touching openings can be opened and repaired in the House Editor (`A17-02`).
3. **P1 (High Priority):** Revise `backend/app/scoring/score.py` so that when `COMPOSITE_CAP_HIGH_SEVERITY` binds, the generated `ScoreComponent` clearly points to the high-severity structural defect rather than a 5-point minor task (`A17-03`).
4. **P1 (High Priority):** Sync checklist completion state via Cloud Sync or associate it with the synced home document to prevent score and task discrepancies across devices (`A17-05`).
5. **P2 (Medium Priority):** Align peril terminology across routing and scoring (`tornado` vs `severe_weather`), and clarify UI sensory tag hints in `ProfileEditorView` (`A17-04`, `A17-07`).
6. **P3 (Cleanup):** Remove deprecated backend `/diff_obstructions` endpoint and unreferenced client rendering artifacts (`A17-08`, `A17-11`).
