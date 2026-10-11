# Domain Audit: Location, Maps, Spatial Geometry & Geographic Context

**Audit Date:** 2026-10-11  
**Auditor ID:** Agent 08  
**Target Document:** `audit/2026-10-11_comprehensive/08_LOCATION_MAPS.md`  
**Repository:** `Escape-Plan`  
**Overall Domain Status:** Verified by source inspection and automated analysis. No active Location Services, MapKit, or GPS APIs exist in the codebase. Spatial geometry and 2D/3D coordinate transformations exhibit mathematical inversions between SceneKit, PDF projection, and RoomPlan capture.

---

## 1. Executive Summary

A comprehensive investigation of the `Escape-Plan` codebase was conducted to determine the presence, scope, and correctness of location services, geographic context mechanisms, and spatial coordinate systems across the iOS frontend, Python backend, schema contracts, and corpus.

### Key Conclusions:
1. **Zero Location Services Footprint:** The application does **not** link or import `CoreLocation`, `MapKit`, or any geocoding framework. No GPS coordinates (`latitude`/`longitude`), postal/ZIP codes, or external hazard lookup APIs (USGS, NWS, FEMA APIs) are queried dynamically. Info.plist declares only `NSCameraUsageDescription` (for RoomPlan LiDAR scanning). No location permissions are requested. Furthermore, privacy enforcement is proactive: picked floor-plan images pass through `ImagePreparation.photo`, which re-renders the bitmap and explicitly strips EXIF GPS metadata, pinned by unit test `testLocationMetadataIsNotSent`.
2. **Critical Spatial Coordinate Discrepancies:**
   - **Vertical Coordinate Inversion between 3D Dollhouse and 2D PDF:** `DollhouseGeometry.scenePoint` maps schema plan coordinates $(x, y)$ to SceneKit $(x, \text{elevation}, -y)$, positioning $+y$ toward the top of the viewport ($-z$). Conversely, `PlanProjection` maps $(x, y)$ directly to UIKit page points $(x, y)$ where $+y$ advances downward from the top-left origin. Consequently, the printable PDF floor plan is vertically flipped (mirrored across the horizontal axis) relative to the 3D dollhouse viewer.
   - **Chirality / Handedness Inversion in RoomPlan Scan Converter:** ARKit/RoomPlan world space is right-handed with $+Y$ up and $-Z$ forward. The backend converter projects world surfaces as `plan = (world.x, world.z)`. Because $(X, Z)$ has an inverted cross-product orientation relative to $(X, Y)$, this operation reflects the building across the horizontal axis, flipping room chirality (swapping left and right). While `_ensure_ccw` normalizes winding to counter-clockwise, reversing vertex order does not un-mirror the geometry.
3. **Regional Perils & Unreachable State-Specific Guidance:** The app hardcodes three perils: Fire, Earthquake, and Tornado. In `backend/corpus/prevention_tips.json`, a legal compliance tip regarding California water heater strapping (`ca-hsc-19211`, audience `"california"`) is provided. However, because the app has no region selection, ZIP code, or state setting, and `PreventionTipsFilter` strictly filters for `audience == .everyone`, California-specific guidance is dead code.
4. **Metric-Imperial Disconnect:** All corpus guidance is grounded in US model codes (2021 IRC, NFPA) citing imperial thresholds (inches and square feet). However, the PDF scale bar (`FloorPlanDrawing.swift`) and route narration distances (`RouteNarration.swift`) are hardcoded to meters (`m`) with no imperial conversion or user preference toggle.
5. **Geographic Limits Undeclared to Consumers:** While internal corpus documentation notes that the 2021 IRC is a model code with local jurisdiction variations, the consumer-facing user interface never states that the app is intended solely for US single-family residential dwellings or warns international users about the hardcoded "Call 911" instructions.

---

## 2. Scope and Files Inspected

### iOS Target (`escape_plan/`, `escape_plan.xcodeproj/`)
- `escape_plan.xcodeproj/project.pbxproj`: Inspected build settings, Info.plist generation keys (`INFOPLIST_KEY_*`), permissions, frameworks, and entitlements.
- `escape_plan/Models/Geometry.swift`: Coordinate types `Point` and `Polygon`.
- `escape_plan/Models/HomeModel.swift`: Contract structures (`Room`, `Opening`, `FloorObject`, `Floor`, `Stairs`, `Meta`).
- `escape_plan/Capture/RoomCaptureController.swift`: ARKit / RoomPlan capture session configuration, multi-room tracking, coordinate origin continuity.
- `escape_plan/Capture/Export/RawScanExport.swift`: RoomPlan export serialization format.
- `escape_plan/Networking/ImagePreparation.swift`: Bitmap re-encoding, EXIF/GPS stripping pipeline.
- `escape_plan/Auth/AccountPrivacy.swift`: Data upload disclosures and privacy declarations.
- `escape_plan/Screens/BuildFromPlanView.swift`: PhotosPicker handling and image intake.
- `escape_plan/Screens/SettingsScreen.swift`: Configuration options, server URL, absence of region/unit preferences.
- `escape_plan/Screens/HomeScreen.swift`: Prevention tips rendering and spotlight selection.
- `escape_plan/Screens/ConsentSheet.swift`: Privacy and data boundary disclosures.
- `escape_plan/Readiness/PreventionTip.swift`: Peril and audience enumerations (`Audience.california`).
- `escape_plan/Readiness/PreventionTipsFilter.swift`: Tip spotlight selection algorithms.
- `escape_plan/Readiness/LoadingTipRotator.swift`: Loading screen tip filtering.
- `escape_plan/Renderer/DollhouseGeometry.swift`: Plan-to-SceneKit coordinate transformation, wall deduplication, opening placements.
- `escape_plan/Renderer/DollhouseScene.swift`: 3D node construction, furniture rotations, camera setup.
- `escape_plan/Renderer/OrbitCameraRig.swift`: Camera rig orbit, pan, tilt, framing.
- `escape_plan/Renderer/UnifiedSceneController.swift`: Screen-to-world unprojection (`worldPoint`).
- `escape_plan/Renderer/RouteGeometry.swift`: 3D route tube generation, floor crossing segmentation.
- `escape_plan/Renderer/RouteOverlay.swift`: Visual styling, route waypoints.
- `escape_plan/Editor/SceneKit/SceneKitEditorBridge.swift`: Interactive touch arbitration, drag translations.
- `escape_plan/Editor/Core/CameraRigModel.swift`: Pure 3D camera vector mathematics.
- `escape_plan/Export/PlanProjection.swift`: Plan-to-page point projection, scale calculation.
- `escape_plan/Export/FloorPlanDrawing.swift`: CoreGraphics vector drawing, scale bar rendering, door/window glyphs.
- `escape_plan/Export/EscapePlanPDF.swift`: US Letter page layout, pagination, UIGraphicsPDFRenderer.
- `escape_plan/Export/RouteNarration.swift`: Step-by-step textual directions, distance formatting.

### Backend (`backend/app/`, `schema/`, `backend/corpus/`)
- `schema/homemodel.schema.json`: Schema contract v2.1 coordinate system definition.
- `backend/app/models.py`: Structural geometric validators, bounding box limits, coordinate bounds (`MAX_COORD_M`).
- `backend/app/convert/roomplan.py`: RoomPlan raw JSON parsing, matrix extraction, plan center projection.
- `backend/app/convert/geometry.py`: 2D polygon reconstruction, collinear merging, rectangularization, CCW normalization.
- `backend/app/convert/converter.py`: Full scan-to-HomeModel conversion pipeline.
- `backend/app/convert/README.md`: Documented assumptions on RoomPlan coordinates and transforms.
- `backend/app/routing/graph.py`: NavGraph topology, centroid calculations, opening midpoints, stair costs.
- `backend/app/routing/engine.py`: Dijkstra shortest path traversal, route waypoint construction, distance summation.
- `backend/app/routing/egress.py`: IRC threshold evaluations (windows, doors).
- `backend/app/routing/perils/earthquake.py`: Heavy cover object search and centroid distance.
- `backend/app/routing/perils/tornado.py`: Lowest floor interior shelter search, exterior wall exposure calculation.
- `backend/corpus/prevention_tips.json`: 43 curated safety tips with source citations and audience tags.
- `backend/corpus/egress_thresholds.json`: IRC 2021 model code thresholds (metric and imperial).
- `backend/corpus/egress-windows-irc.md`: Jurisdiction notes and model code context.
- `backend/corpus/earthquake-securing-home.md`: California Health and Safety Code references.

### Test Suites (`escape_planTests/`, `backend/tests/`)
- `escape_planTests/ImagePreparationTests.swift`: Location stripping assertions (`testLocationMetadataIsNotSent`).
- `escape_planTests/EscapePlanExportTests.swift`: PDF generation and PlanProjection scale checks.
- `backend/tests/test_routing.py`: Distance calculations and waypoint integrity.

---

## 3. Methods and Checks Performed

1. **Static Analysis of Framework Imports:**
   Executed global search for `CoreLocation`, `MapKit`, `CLLocation`, `CLGeocoder`, `latitude`, `longitude`, `GPS`, and `NSLocation` across all directories.
2. **Info.plist & Entitlements Audit:**
   Examined `escape_plan.xcodeproj/project.pbxproj` build configurations (`Debug`, `Release`) for declared privacy strings (`INFOPLIST_KEY_*`) and code signing entitlements.
3. **EXIF / Metadata Pipeline Verification:**
   Traced picked image bytes from `PhotosPicker` in `BuildFromPlanView.swift` through `ImagePreparation.swift` to verify stripping of image metadata dictionaries.
4. **Coordinate Mapping & Transformation Analysis:**
   Performed mathematical comparison of coordinate conventions across:
   - ARKit / RoomPlan 3D world space (`simd_float4x4` transform)
   - Converter 2D plan space (`roomplan.py`, `geometry.py`)
   - HomeModel 2D floor space (`schema/homemodel.schema.json`, `Geometry.swift`)
   - SceneKit 3D rendering space (`DollhouseGeometry.swift`, `UnifiedSceneController.swift`)
   - CoreGraphics / UIKit 2D drawing space (`PlanProjection.swift`, `FloorPlanDrawing.swift`)
5. **Egress Distance & Route Length Math:**
   Inspected path cost accumulation in `backend/app/routing/engine.py` and `graph.py` to evaluate Euclidean distances, stair traversal penalties, and imperial/metric presentation.
6. **Regional Peril & Hazard Corpus Trace:**
   Audited audience tagging in `prevention_tips.json`, tracking how audience filters (`.everyone`, `.california`) are consumed in `HomeScreen.swift`, `LoadingTipRotator.swift`, and `PreventionTipsFilter.swift`.
7. **External Safety Authority Fact-Checking:**
   Cross-referenced safety guidance and code citations with authoritative standards from FEMA, NFPA, USFA, American Red Cross, NOAA/NWS, USGS, and the International Code Council (ICC/IRC).

---

## 4. Findings (with Evidence)

### [HIGH] A08-01 Vertical Axis Inversion Between 3D SceneKit Dollhouse and 2D PDF Floor Plan Export
**Domain:** Spatial Geometry / 2D/3D Rendering  
**Location:** [PlanProjection.swift:9-13, 46-49](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/PlanProjection.swift#L9-L13) vs [DollhouseGeometry.swift:8-17](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Renderer/DollhouseGeometry.swift#L8-L17)  
**Observed behavior:**  
The 3D SceneKit viewport and the 2D PDF export render the home's vertical axis in opposite directions. A room positioned at the "top" (North) in the 3D dollhouse appears at the "bottom" (South) on the printable PDF document, resulting in a 180° vertical reflection between what the user sees on screen and what prints on paper.

**Evidence:**  
In `escape_plan/Renderer/DollhouseGeometry.swift:8-17`:
```swift
/// Coordinate mapping, fixed once here: the schema's floor-local plan frame (x, y) in meters maps
/// to SceneKit as **x → x, y → −z**, with **+y up** for height. Plan-north is −z, which means a
/// camera looking down −z sees the plan the same way up as the JSON reads.
enum DollhouseGeometry {
    static func scenePoint(_ p: Point, y: Double) -> SCNVector3 {
        SCNVector3(Float(p.x), Float(y), Float(-p.y))
    }
```
In `escape_plan/Editor/Core/CameraRigModel.swift:44, 88-94`:
The default camera yaw is 0 radians, placing the camera at positive $z$ looking toward $-z$. In this viewport:
- Plan $+y$ maps to SceneKit $-z$, which is further away from the camera, rendering toward the **TOP** of the screen.
- Plan $-y$ maps to SceneKit $+z$, which is closer to the camera, rendering toward the **BOTTOM** of the screen.

In `escape_plan/Export/PlanProjection.swift:9-13, 46-49`:
```swift
//  Frame: the schema's floor-local plan frame is (x, y) in metres. On paper we map
//  **x → page x (right), y → page y (down)** with a single uniform scale. No flip: UIKit's
//  page origin is top-left, so a plan printed this way reads the same way up as the JSON
//  vertex list — the same reasoning DollhouseGeometry uses when it maps plan +y to scene
//  −z so a top-down camera sees the plan "the same way up as the JSON reads".
...
    func point(_ p: Point) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(p.x) * scale,
                y: origin.y + CGFloat(p.y) * scale)
    }
```
In UIKit and `UIGraphicsPDFRenderer`, the coordinate origin $(0, 0)$ is at the top-left, and page $y$ advances **DOWNWARD**.
- Plan $+y$ maps to larger page $y$, rendering toward the **BOTTOM** of the printed page.
- Plan $-y$ maps to smaller page $y$, rendering toward the **TOP** of the printed page.

**Expected behavior:**  
The orientation of rooms, doors, and escape routes on the printed PDF floor plan should align identically with the top-down perspective shown in the interactive 3D dollhouse viewer. If a bedroom is at the top of the screen in the 3D view, it must appear at the top of the PDF.

**Root cause:**  
The author of `PlanProjection.swift` incorrectly assumed that mapping $+y \to +\text{page.y}$ in UIKit preserves visual orientation. Because UIKit's vertical axis points downward, mapping plan $+y$ directly to page $+y$ inverts the vertical direction compared to SceneKit, where plan $+y$ maps to $-z$ (upward in viewport perspective).

**Impact:**  
A user reviewing their escape route in the 3D viewer will find the printed plan posted on their wall vertically mirrored. During an evacuation drill or real emergency, this discrepancy causes spatial disorientation, as the left/right turns when exiting a room will conflict between the app and the printed plan.

**Recommended improvement:**  
Invert the vertical projection in `PlanProjection.swift` so that plan $+y$ maps toward the top of the page (decreasing page $y$):
```swift
func point(_ p: Point) -> CGPoint {
    CGPoint(x: origin.x + CGFloat(p.x - bounds.minX) * scale,
            y: origin.y + CGFloat(bounds.maxY - p.y) * scale)
}
```
Update all dependent glyph drawing in `FloorPlanDrawing.swift` (such as opening outward normals and door swing arcs) to ensure consistent handedness.

**Dependencies:** `FloorPlanDrawing.swift`, `PlanProjection.swift`, `EscapePlanExportTests.swift`  
**Verification status:** Verified by source inspection  
**Confidence:** High   **Effort:** Medium  

---

### [HIGH] A08-02 Chirality / Handedness Inversion in RoomPlan-to-Plan Projection Mirrors Scanned Architecture
**Domain:** ARKit/RoomPlan Conversion / Coordinate Systems  
**Location:** [roomplan.py:77-83](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/convert/roomplan.py#L77-L83), [README.md:52-54](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/convert/README.md#L52-L54), [geometry.py:192-194](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/convert/geometry.py#L192-L194)  
**Observed behavior:**  
When raw RoomPlan / ARKit scans are ingested by the backend converter, 3D world space coordinates $(world.x, world.y, world.z)$ are projected to 2D plan space as $(world.x, world.z)$. This direct projection reflects the floor plan across the horizontal axis, flipping the chirality (handedness) of the scanned home. Doors on the left side of a hallway in reality appear on the right side in the model.

**Evidence:**  
In `backend/app/convert/roomplan.py:77-79`:
```python
    @property
    def plan_center(self) -> PlanPoint:
        return (self.transform[12], self.transform[14])
```
`transform[12]` is $world.x$; `transform[14]` is $world.z$.
In `backend/app/convert/README.md:52-54`:
```markdown
### Coordinate conventions

- RoomPlan/ARKit world space is right-handed, **y-up**, meters.
- Floor-plan projection used here: `plan = (world.x, world.z)`. Winding is normalized
  to CCW afterward (the schema requires CCW), so the handedness flip is harmless.
```
In `backend/app/convert/geometry.py:192-194`:
```python
def _ensure_ccw(poly: list[Point]) -> list[Point]:
    return poly if signed_area(poly) > 0 else list(reversed(poly))
```

**Mathematical Proof of Defect:**  
1. In ARKit world space, the basis vectors are right-handed with $+Y$ up: looking down from the ceiling ($+Y$ looking toward $-Y$), $+X$ is Right and $-Z$ is Forward (North).
2. The standard 2D Cartesian floor-plan projection with $+u$ Right and $+v$ North requires:
   $$u = world.x, \quad v = -world.z$$
3. By setting $plan.x = world.x$ and $plan.y = world.z$, the converter uses the transformation matrix:
   $$T = \begin{pmatrix} 1 & 0 \\ 0 & -1 \end{pmatrix}$$
   relative to the upright plan. The determinant of this projection is $\det(T) = -1$, which represents a reflection (handedness flip).
4. While `_ensure_ccw` detects that the resulting polygon has clockwise winding and reverses the vertex list (`reversed(poly)`), reversing vertices of a reflected polygon merely reorders the edge traversal—it **cannot undo the spatial reflection**. The geometry remains a mirror image of the physical house.

**Expected behavior:**  
Floor plan projection must preserve physical chirality:
$$plan.x = world.x, \quad plan.y = -world.z$$
$$\text{along-wall direction} = (local\_x.x, -local\_x.z)$$

**Root cause:**  
The documentation explicitly reveals a misunderstanding of affine geometry: the author noted that `"the handedness flip is harmless"` because winding is forced to CCW afterward. A handedness flip in physical architecture swaps left and right.

**Impact:**  
Homes captured via LiDAR scanning produce mirrored floor plans where interior partitions, stairwells, and egress doors are reflected. A user navigating the resulting escape route will be instructed to make opposite turns.

**Recommended improvement:**  
Modify `backend/app/convert/roomplan.py` to project $plan.y = -world.z$:
```python
@property
def plan_center(self) -> PlanPoint:
    return (self.transform[12], -self.transform[14])

@property
def plan_direction(self) -> PlanPoint:
    dx, dz = self.transform[0], self.transform[2]
    norm = (dx * dx + dz * dz) ** 0.5
    if norm < 1e-9:
        return (1.0, 0.0)
    return (dx / norm, -dz / norm)
```
Recalibrate converter fixtures and test expectations accordingly.

**Dependencies:** `backend/app/convert/roomplan.py`, `backend/app/convert/geometry.py`, `backend/app/convert/converter.py`  
**Verification status:** Verified by source inspection and mathematical proof  
**Confidence:** High   **Effort:** Medium  

---

### [MEDIUM] A08-03 Regional Hazard Tip Dead Code: California Strapping Law Unreachable Due to Strict Audience Filtering
**Domain:** Regional Hazard Applicability  
**Location:** [PreventionTipsFilter.swift:20-28](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/PreventionTipsFilter.swift#L20-L28), [LoadingTipRotator.swift:29](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Readiness/LoadingTipRotator.swift#L29), [prevention_tips.json:198-203](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/prevention_tips.json#L198-L203)  
**Observed behavior:**  
The bundled safety tip repository contains jurisdiction-specific earthquake guidance for California (`eq-water-heater-california-law`), citing California Health & Safety Code § 19211. However, this tip is never displayed to any user anywhere in the application.

**Evidence:**  
In `backend/corpus/prevention_tips.json:198-204`:
```json
    {
      "id": "eq-water-heater-california-law",
      "peril": "earthquake",
      "topic": "securing",
      "text": "In California, bracing or strapping a residential water heater is required by law, not just recommended, and a seller must certify it in writing.",
      "cite": "ca-hsc-19211",
      "audience": "california"
    }
```
In `escape_plan/Readiness/PreventionTipsFilter.swift:20-28`:
```swift
    static func spotlight(_ all: [PreventionTip]) -> [PreventionTip] {
        PreventionTip.Peril.allCases.compactMap { peril in
            let forPeril = tips(all, peril: peril)
            return forPeril.first { $0.audience == .everyone } ?? forPeril.first
        }
    }
```
Because the `earthquake` peril contains multiple tips with `audience == "everyone"` (such as `eq-drop-cover-hold-on`, `eq-sturdy-table`), the spotlight selector always resolves an `.everyone` tip and never falls back.  
Furthermore, in `escape_plan/Readiness/LoadingTipRotator.swift:29`:
```swift
let everyone = tips.filter { $0.audience == .everyone }
```
`LoadingTipRotator` explicitly filters only for `.everyone`. There is no other view in the app that consumes `preventionTips`.

**Expected behavior:**  
Jurisdiction-specific legal guidance should either be surfaced to users in that jurisdiction (via state selection or onboarding setting) or general guidance should state regional applicability.

**Root cause:**  
The corpus author added `"audience": "california"`, but the app has no mechanism to determine or store user location, state, or region. Furthermore, UI presentation logic hardcodes filtering to `audience == .everyone`.

**Impact:**  
Dead code in both frontend and backend bundles. Users in California miss statutory compliance information regarding water heater strapping, while the app maintains unreachable logic.

**Recommended improvement:**  
Either:
1. Re-tag the tip audience to `"everyone"` and phrase it comparatively: *"In earthquake-prone states like California, bracing a water heater is required by law (CA Health & Safety Code § 19211); nationwide, FEMA recommends strapping to prevent post-quake gas fires."* (Authoritative source: FEMA P-50 / CA HSC § 19211, checked 2026-10-11).
2. Or implement a lightweight state selector in Settings allowing regional tip matching.

**Dependencies:** `backend/corpus/prevention_tips.json`, `escape_plan/Resources/prevention_tips.json`, `PreventionTipsFilter.swift`  
**Verification status:** Verified by source inspection  
**Confidence:** High   **Effort:** Small  

---

### [MEDIUM] A08-04 Metric-Only Scale Bar and Route Lengths in Consumer Artifacts Despite US Code & Paper Standards
**Domain:** Units & Measurement  
**Location:** [FloorPlanDrawing.swift:485-487](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/FloorPlanDrawing.swift#L485-L487), [RouteNarration.swift:169](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Export/RouteNarration.swift#L169), [egress_thresholds.json:3](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/egress_thresholds.json#L3)  
**Observed behavior:**  
All exported consumer artifacts display dimensions and distances strictly in metric units (meters), with no imperial conversion or user preference toggle, even though the app targets US residents, uses US Letter paper, and evaluates against US building codes codified in inches and feet.

**Evidence:**  
In `escape_plan/Export/FloorPlanDrawing.swift:485-487`:
```swift
    static func formattedMetres(_ metres: Double) -> String {
        metres == metres.rounded() ? "\(Int(metres)) m" : String(format: "%.1f m", metres)
    }
```
The scale bar printed on the PDF floor plan is hardcoded to render `X m`.  
In `escape_plan/Export/RouteNarration.swift:169`:
```swift
    static func summaryLine(for route: Route) -> String {
        var parts = [String(format: "About %.1f m", route.length_m)]
```
The step narration summary printed on the PDF and spoken via VoiceOver hardcodes `"About %.1f m"`.  
In `escape_plan/Export/EscapePlanPDF.swift:42`:
```swift
    static let pageSize = CGSize(width: 612, height: 792) // US Letter: 8.5 x 11 inches
```
In `backend/corpus/egress_thresholds.json:3, 7, 21`:
```json
"description": "Values are the 2021 IRC baseline; the HomeModel schema uses meters, so metric values are authoritative for computation and imperial values are the as-codified citations.",
"min_net_clear_opening_area": { "value_sqft": 5.7, "value_m2": 0.53 },
"min_net_clear_opening_height": { "value_in": 24, "value_m": 0.61 }
```

**Expected behavior:**  
For an app targeting the Congressional App Challenge and US households using US Letter paper and 2021 IRC citations, distances on printed plans and narration should support imperial units (feet/inches) either by default or via user locale (`Locale.current.measurementSystem`).

**Root cause:**  
The engineering decision to standardize the JSON schema and internal routing engine on SI units (meters) was extended directly into the presentation layer without a formatting adapter (`MeasurementFormatter`).

**Impact:**  
US homeowners, children, and elderly residents (who predominantly understand feet) have difficulty conceptualizing escape distances when told a route is "14.3 m", and cannot easily use a meter-denominated scale bar on a printed escape plan.

**Recommended improvement:**  
Introduce a locale-aware unit formatter using Foundation's `Measurement<UnitLength>`:
```swift
static func formatDistance(_ meters: Double) -> String {
    let measurement = Measurement(value: meters, unit: UnitLength.meters)
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .naturalScale
    formatter.numberFormatter.maximumFractionDigits = 0
    return formatter.string(from: measurement)
}
```
Provide an option in Settings to toggle between Imperial (Feet) and Metric (Meters), and render dual scale bars (feet / meters) on the PDF export.

**Dependencies:** `FloorPlanDrawing.swift`, `RouteNarration.swift`, `SettingsScreen.swift`  
**Verification status:** Verified by source inspection  
**Confidence:** High   **Effort:** Small  

---

### [LOW] A08-05 Absence of Declared Geographic Limits in UI Despite US-Specific Emergency Codes, Agencies, and Standards
**Domain:** Geographic Context & User Communication  
**Location:** [ConsentSheet.swift:30-55](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/ConsentSheet.swift#L30-L55), [SettingsScreen.swift:175](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Screens/SettingsScreen.swift#L175), [prevention_tips.json:41, 65](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/corpus/prevention_tips.json#L41)  
**Observed behavior:**  
The user interface contains no indication or disclaimer stating that the application's safety rules, egress thresholds, emergency procedures, and citations are specific to the United States.

**Evidence:**  
1. Emergency numbers:
   - `prevention_tips.json:41`: `"Get out first, then call 911 from outside."`
   - `prevention_tips.json:65`: `"...leave and call 911."`
   - `home-fire-escape-redcross.md:37`: `"- Call 911 once safely outside."`
   - `backend/tests/evals/cases.py: says_call_911_first`: Live chat grader enforces advising "call 911".
2. Standards bodies:
   - `SettingsScreen.swift:175`: `"FEMA · NFPA · Red Cross"`
   - `egress-windows-irc.md:15`: Notes that IRC is a US model code, but this note is in the internal markdown corpus and never shown in the iOS app.
3. Neither onboarding (`OnboardingView`), consent sheets (`ConsentSheet`), nor settings (`SettingsScreen`) communicate that the app assumes a US residential dwelling.

**Expected behavior:**  
Safety applications grounded in national model codes (2021 IRC, NFPA 72) and national emergency services ("911") should clearly state their jurisdictional applicability in their "About", settings, or initial onboarding disclosures.

**Root cause:**  
The project was designed specifically for the US Congressional App Challenge, leading to an implicit assumption that all users reside in the United States without explicitly encoding or declaring that boundary.

**Impact:**  
International users downloading the app may receive inappropriate advice regarding emergency response numbers (where 112, 999, or 000 apply) and building codes (where IRC requirements do not apply).

**Recommended improvement:**  
Add a brief jurisdictional statement to the About/Settings screen:
*"Escape Plan is grounded in United States fire, earthquake, and severe-weather standards (FEMA, NFPA, NOAA, 2021 IRC) and assumes North American emergency services (911). Local building codes and emergency numbers vary outside the US."*

**Dependencies:** `SettingsScreen.swift`, `ConsentSheet.swift`  
**Verification status:** Verified by source inspection  
**Confidence:** High   **Effort:** Small  

---

### [LOW] A08-06 Fixed Stair Traversal Cost Ignores Vertical Rise and Floor Height in Route Length Calculation
**Domain:** Route Geometry & Distance Calculation  
**Location:** [graph.py:38, 230-239](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/routing/graph.py#L38), [engine.py:211](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/backend/app/routing/engine.py#L211)  
**Observed behavior:**  
Traversing a flight of stairs adds a fixed constant of 6.0 meters (`STAIR_TRAVERSAL_COST`) to the route's total `length_m`, regardless of the staircase footprint dimensions, number of steps, or floor height.

**Evidence:**  
In `backend/app/routing/graph.py:38-40`:
```python
STAIR_TRAVERSAL_COST = 6.0
"""Meters-equivalent cost of traversing a staircase (deliberately > a typical
same-floor hop so ground-floor exits are preferred when comparable)."""
...
    for stair in annotated.stairs:
        edges.append(
            Edge(
                a=stair.from_.room_id,
                b=stair.to.room_id,
                weight=STAIR_TRAVERSAL_COST,
                kind=EdgeKind.stair,
                via=stair.id,
            )
        )
```
In `backend/app/routing/engine.py:211`:
```python
    length_m = sum(e.weight for e in result.edges)
```

**Expected behavior:**  
While using a penalty weight for pathfinding Dijkstra edge selection is sound engineering practice (to discourage stair travel when same-floor exits exist), the final calculated route length `length_m` presented to the user as `"About X.X m"` should represent physical travel distance:
$$\text{physical stair distance} \approx \sqrt{\text{run}^2 + \text{rise}^2}$$
where $\text{rise} = floor.height\_m$ and $\text{run}$ is the stair footprint span.

**Root cause:**  
The Dijkstra routing graph edge weight is reused directly as the physical travel distance in `Route.length_m = sum(e.weight for e in result.edges)`.

**Impact:**  
A stair flight between two floors with a 2.5m ceiling height adds 6.0m to the route length readout. Conversely, a tall commercial/loft floor with a 5.0m ceiling still adds only 6.0m. The reported route length is slightly inaccurate for multi-story homes.

**Recommended improvement:**  
Separate graph traversal edge cost (for pathfinding preference) from physical edge length:
Store `physical_length_m` on `Edge`, computing stair length from $\sqrt{\text{footprint\_length}^2 + \text{floor\_height}^2}$, and sum `physical_length_m` when populating `Route.length_m`.

**Dependencies:** `backend/app/routing/graph.py`, `backend/app/routing/engine.py`  
**Verification status:** Verified by source inspection  
**Confidence:** High   **Effort:** Small  

---

### [OBSERVATION] A08-07 Info.plist Permission Strings Accurately Reflect Zero Location Usage and Active EXIF GPS Stripping
**Domain:** Privacy / Permissions / Location Services  
**Location:** [project.pbxproj:402](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan.xcodeproj/project.pbxproj#L402), [ImagePreparation.swift:55-57](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_plan/Networking/ImagePreparation.swift#L55-L57), [ImagePreparationTests.swift:70-77](file:///Users/anish/Documents/Congressional%20App%20Challenge/Escape-Plan/escape_planTests/ImagePreparationTests.swift#L70-L77)  
**Observed behavior:**  
The application's Info.plist configuration accurately omits all location service keys (`NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysUsageDescription`). No code in the repository requests GPS access. Furthermore, when users import floor plans from their photo library, the app actively strips EXIF GPS metadata before network transmission.

**Evidence:**  
In `escape_plan.xcodeproj/project.pbxproj:400-409`:
Only `INFOPLIST_KEY_NSCameraUsageDescription` is declared:
```text
INFOPLIST_KEY_NSCameraUsageDescription = "Escape Plan uses the camera and LiDAR scanner to measure the rooms, doors and windows of your home so it can map your fire escape routes.";
```
In `escape_plan/Networking/ImagePreparation.swift:55-57`:
```swift
    /// Any photo ImageIO can decode (HEIC, JPEG, PNG, a Live Photo's still) → JPEG. EXIF
    /// orientation is applied to the pixels, and no metadata (GPS included) is copied across.
    static func photo(_ data: Data) throws -> PreparedImage {
```
In `escape_planTests/ImagePreparationTests.swift:70-77`:
```swift
    /// Location and camera metadata stay on the phone: the fixture carries GPS and EXIF, the
    /// output carries neither.
    func testLocationMetadataIsNotSent() throws {
        let tagged = try encodedFixture(width: 1200, height: 900, type: UTType.jpeg.identifier, withGPS: true)
        let inputProps = try XCTUnwrap(properties(of: tagged))
        XCTAssertNotNil(inputProps[kCGImagePropertyGPSDictionary], "fixture must carry GPS, or this proves nothing")
        let output = try XCTUnwrap(properties(of: try ImagePreparation.photo(tagged).data))
        XCTAssertNil(output[kCGImagePropertyGPSDictionary])
        XCTAssertNil((output[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal])
    }
```

**Verification status:** Verified by source inspection and automated test  
**Confidence:** High   **Effort:** None (positive finding)

---

## 5. Positive Findings

1. **Zero Unnecessary Permissions:** The app adheres to the principle of least privilege. Despite handling home layouts and photos, it requests no location permissions, contacts, calendar, or audio permissions.
2. **Proactive GPS Stripping:** User privacy regarding photo geolocations is actively defended. Rather than forwarding raw camera images to the AI plan builder, `ImagePreparation.photo` renders images onto an offscreen `CGContext` and re-encodes clean JPEGs, ensuring camera GPS coordinates and timestamps never leave the device.
3. **Pure-Function Geometry Decoupling:** `DollhouseGeometry.swift` and `PlanProjection.swift` are implemented as pure functions independent of UIKit views, SceneKit viewports, or network I/O. This architectural decision enables comprehensive unit testing of math and layout without requiring simulator runtimes.
4. **Deterministic Scale Bar Logic:** `PlanProjection.scaleBarMetres` dynamically selects standard human-readable intervals ($1, 2, 5, 10, 20\text{ m}$) that fit the available page width, preventing misleading fractional scale bars on printed floor plans.
5. **Robust Egress Clearance Annotator:** `backend/app/routing/egress.py` accurately models the 2021 IRC R310.2 emergency escape requirements, distinguishing grade-level floors ($level \le 0$) where minimum opening area is relaxed from $0.53\text{ m}^2$ ($5.7\text{ sq ft}$) to $0.465\text{ m}^2$ ($5.0\text{ sq ft}$).

---

## 6. Systemic Issues and Root Causes

### 1. Independent Coordinate System Assumptions
The project spans four distinct coordinate spaces without a single formal transformation specification:
- **ARKit/RoomPlan Space:** $+X$ Right, $+Y$ Up, $-Z$ Forward (Right-handed 3D).
- **HomeModel Schema Space:** $(x, y)$ in meters (2D Cartesian).
- **SceneKit Dollhouse Space:** $+X$ Right, $+Y$ Up, $+Z$ Toward Camera / Viewer (Right-handed 3D).
- **UIKit / CoreGraphics PDF Space:** $+X$ Right, $+Y$ Downward (Left-handed 2D screen/page).

Because each subsystem was developed in isolation with localized assumptions, contradictory transformations were introduced:
- `backend/app/convert/roomplan.py` mapped $(x, z) \to (x, y)$, flipping handedness and assuming CCW winding normalization made it harmless.
- `DollhouseGeometry.swift` assumed schema $+y$ was North and mapped $y \to -z$ in SceneKit.
- `PlanProjection.swift` mapped schema $+y \to +y$ on the page, inverting the visual layout relative to SceneKit.

### 2. Disconnect Between Statutory Modeling and Geographic Context
The safety corpus incorporates detailed regional and national standards (US IRC, NFPA, California Health & Safety Code § 19211, "Call 911"), but the application architecture treats location context as completely binary: either full GPS tracking or zero context. Because GPS tracking was rightly avoided for privacy, no alternative coarse contextual mechanism (such as an optional state/country picker) was introduced, causing regional rules to rot into dead code.

---

## 7. Unverified Assumptions

1. **Physical RoomPlan LiDAR Scanning Behavior at Runtime:**
   - *Assumption:* Apple's `RoomCaptureSession` outputs `CapturedStructure` transforms in standard column-major meters where local $X$ is along-wall and $Z$ is orthogonal.
   - *Status:* **Blocked by environment**. Xcode 27.0 in this environment lacks an installed iOS simulator runtime (`xcrun simctl list runtimes` reports no profiles), and RoomPlan requires physical LiDAR hardware (iPhone 12 Pro or later). The assumption was verified against synthetic test fixtures (`schema/fixtures/scans/`) and source code in `RoomPlanScanSource.swift`, but not verified on physical hardware in this audit pass.
2. **Third-Party CAD/Floor-Plan Import Orientation:**
   - *Assumption:* PDFs and images submitted to `BuildFromPlanView` have North or top-of-page aligned with standard architectural orientation.
   - *Status:* **Inferred but not verified**. Architectural floor plans frequently lack compass orientation or use site-specific project North.

---

## 8. Areas Requiring Further Investigation

1. **Obstruction Diff Route Coordinate Frame:**
   The backend retains `POST /diff_obstructions` (partially unreferenced in current UI). Future investigation should verify whether scan-differencing transforms align with current HomeModel coordinates when re-scanning rooms.
2. **First Responder Map Integration Feasibility:**
   While `docs/decisions.md` S6.9 ("Responder Snapshot") explicitly locks out direct integration with fire department CAD (Computer Aided Dispatch) systems for privacy reasons, first responder interviews could clarify whether exporting georeferenced spatial formats (such as GeoJSON or indoor mapping format IMDF) would be valuable if handled strictly via opt-in manual export.

---

## 9. Recommended Priorities

| Priority | Finding ID | Title | Estimated Effort | Target Release |
|:---:|:---:|:---|:---:|:---:|
| **P1** | **A08-01** | Fix Vertical Axis Inversion in `PlanProjection.swift` | Medium | Immediate |
| **P1** | **A08-02** | Correct Chirality / Handedness in `backend/app/convert/roomplan.py` | Medium | Immediate |
| **P2** | **A08-04** | Implement Locale-Aware Imperial (Feet) Option for Scale Bar & Route Lengths | Small | v2.2 |
| **P2** | **A08-03** | Resolve Dead Code in `prevention_tips.json` for California Strapping Tip | Small | v2.2 |
| **P3** | **A08-05** | Disclose US-Centric Jurisdiction & Emergency Limits in UI | Small | v2.2 |
| **P3** | **A08-06** | Separate Dijkstra Edge Traversal Weights from Physical Stair Travel Distance | Small | Backlog |

---

## Verification Label Index
- **A08-01:** Verified by source inspection
- **A08-02:** Verified by source inspection
- **A08-03:** Verified by source inspection
- **A08-04:** Verified by source inspection
- **A08-05:** Verified by source inspection
- **A08-06:** Verified by source inspection
- **A08-07:** Verified by source inspection and automated test
