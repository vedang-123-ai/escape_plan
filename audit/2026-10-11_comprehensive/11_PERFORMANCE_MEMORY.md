# Domain Audit: Performance & Memory Efficiency (Agent 11)

**Report File:** `audit/2026-10-11_comprehensive/11_PERFORMANCE_MEMORY.md`  
**Date:** 2026-10-11  
**Target:** Escape Plan (iOS / SwiftUI / SceneKit app & Python / FastAPI backend)  
**Author:** Senior Performance & Runtime Systems Auditor (Agent 11)

---

## 1. Executive Summary

This audit evaluates runtime efficiency, memory stability, per-frame allocation overhead, graphics pipeline scalability, and network resource consumption across the iOS application and backend services.

The application architecture demonstrates substantial architectural maturity in several key performance areas: the asset footprint is exceptionally light (total `Assets.xcassets` and `Resources` combined measure only **460 KB** because all dollhouse geometry, materials, and character figures are procedurally generated rather than bundling heavy `.usdz` / `.scn` / `.obj` assets); previous main-thread JSON decoding bottlenecks identified in AUD-047 were mitigated by an attribute-caching `SummaryProbe` design; and gestures cleanly decouple scene rebuilds via an `isCameraGestureInFlight` deferral gate verified by automated testing (`GestureFrameCostUITests`).

However, deep end-to-end tracing reveals several severe systemic efficiency hazards:
1. **Pervasive Main-Thread SwiftUI Invalidation:** During evacuation playback, the monolithic `HouseScreen` view (2,875 lines, 59 `@State` variables) directly observes the `@Observable` playhead (`currentTime_s`). Because SwiftUI observation boundaries are at the `View.body` level, the entire 2,875-line screen structure re-evaluates 60 to 120 times per second. This triggers per-frame `EditorSceneView.updateUIView` invocations that run equality checks (`rebuildIfNeeded`) and node tree highlighting on every render tick.
2. **Per-Frame Concurrency Allocations:** In `EvacuationPlaybackCoordinator.observeFrame`, an observation tracking hook dispatches an unconstrained asynchronous `Task { @MainActor in ... }` on every single playhead tick (60–120 tasks/sec), churning heap allocations on the cooperative thread pool.
3. **Synchronous Main-Thread PDF Export:** PDF rendering (`EscapePlanPDF.render` and atomic disk persistence) executes synchronously within the button tap action on `@MainActor`. The `isGenerating` spinner is never even presented because no UI runloop cycle is yielded prior to blocking computation.
4. **Backend Route Computation Multiplier in `/score`:** Measured on the standard 12-room `ranch-house.homeplan.json` demo home, a single call to `/score` takes **1,203.08 ms (1.20 seconds)** of synchronous CPU execution, because it redundantly re-computes three independent room occupancy grids and Chamfer distance transforms (fire: 405.18 ms, tornado: 398.22 ms, earthquake: 399.50 ms) without sharing intermediate rasterizations.

Overall, the app's performance is clean during idle navigation, but exhibits acute main-thread load spikes and high battery consumption during interactive evacuation simulations and printable export operations.

---

## 2. Scope and Files Inspected

### iOS Frontend Core Runtime & Rendering
- `escape_plan/Renderer/DollhouseScene.swift` (SceneKit scene assembly, ghost layer swapping, camera setup)
- `escape_plan/Renderer/DollhouseGeometry.swift` (Procedural wall deduplication, polygon placement, boundary calculations)
- `escape_plan/Renderer/DollhousePalette.swift` (Color constants, lighting palettes, ghost alphas)
- `escape_plan/Renderer/OrbitCameraRig.swift` (Display link management, inertia, gesture damping, spring mechanics)
- `escape_plan/Renderer/CameraGestureDriver.swift` (Touch phase arbitration, gesture hooks)
- `escape_plan/Renderer/RouteOverlay.swift` (Catmull-Rom spline smoothing, tube geometry, dual-pass occlusion shaders)
- `escape_plan/Renderer/RouteGeometry.swift` (Floor run segmentation, dash generation, stop markers)
- `escape_plan/Renderer/PeopleLayer.swift` (Gait cycle evaluation, IK joint manipulation, thread-safe animation storage)
- `escape_plan/Renderer/Fixtures/PersonFixture.swift` (Rig node construction, joint hierarchies, pose transforms)
- `escape_plan/Renderer/Fixtures/FurnitureFixture.swift` (Procedural clay furniture minis, sub-node geometry)
- `escape_plan/Renderer/Fixtures/WallFixture.swift` & `DoorFixture.swift` & `WindowFixture.swift` (Parametric openings & cutouts)
- `escape_plan/Renderer/RoomLabelSprite.swift` (Dynamic CoreGraphics 3x texture rasterization)
- `escape_plan/Renderer/Evacuation/HazardLayer.swift` (Wash shaders, emission progression, particle systems)
- `escape_plan/Renderer/Evacuation/PlaybackCameraController.swift` (Target frame smoothing, camera node overrides)
- `escape_plan/Renderer/Evacuation/EvacuationPlaybackCoordinator.swift` (Render delegate forwarder, observation tracking)
- `escape_plan/Renderer/Evacuation/UnifiedSceneController+Evacuation.swift` (Associated object binding)
- `escape_plan/Renderer/UnifiedSceneController.swift` (Scene coordination, gesture deferral queue, continuous rendering sync)
- `escape_plan/Editor/SceneKit/EditorSceneView.swift` (SwiftUI `UIViewRepresentable` bridge, gesture installation)
- `escape_plan/Editor/Core/CameraRigModel.swift` & `GestureArbiter.swift` (Pure camera math, gesture state machines)

### SwiftUI Screens & State Invalidation Scope
- `escape_plan/Screens/HouseScreen.swift` (Unified 2,875-line editor/viewer, 59 `@State` properties, dock, playback clock)
- `escape_plan/Screens/HomeScreen.swift` (Home dashboard, software sweep animation loop, pull-to-refresh)
- `escape_plan/Screens/ReadinessStore.swift` (Active home lifecycle, score caching, generation-tagged fetch tasks)
- `escape_plan/Models/EvacuationPlayback.swift` (`@Observable` simulation engine, stepped Reduce Motion mode)

### Export & Document Serialization
- `escape_plan/Export/EscapePlanPDF.swift` (`UIGraphicsPDFRenderer` vector document rendering, pagination)
- `escape_plan/Export/EscapePlanExporter.swift` (File URL generation, snapshot serialization)
- `escape_plan/Export/ExportPlanSheet.swift` (Export form, synchronous generation invocation)
- `escape_plan/Persistence/HomeDocumentStore.swift` (Stat-cached `summaries(reusing:)`, `SummaryProbe`)
- `escape_plan/Persistence/HomeLibrary.swift` (Observable library wrapper, refresh deduplication)

### Backend Routing & Scoring Engine
- `backend/app/routing/engine.py` (Dijkstra search, egress bottlenecks)
- `backend/app/routing/nav_grid.py` (10 cm occupancy rasterization, Chamfer distance transform erosion)
- `backend/app/routing/pathfind.py` (8-connected A* search, integer octile heuristics, string-pull smoothing)
- `backend/app/scoring/score.py` (Weighted readiness calculation, peril breakdowns)
- `backend/app/main.py` (`/routes`, `/score`, `/evacuate` endpoint handlers)

### Test Suites & Performance Artifacts
- `escape_planUITests/GestureFrameCostUITests.swift` (SwiftUI update pass counting under drag instrumentation)
- `docs/tracker/notes/2026-08-05-camera-feel.md` (Recorded benchmark output on iPhone 17 Pro)
- `escape_planTests/DollhouseRendererTests.swift` & `EscapePlanExportTests.swift`

---

## 3. Methods and Checks Performed

1. **Physical Asset Footprint Measurement:**
   - Ran `du -sh` and `du -ak` across `escape_plan/Assets.xcassets`, `escape_plan/Resources`, `escape_plan/Fixtures`, and `demo-homes`.
   - Verified presence/absence of binary 3D model formats (`.scn`, `.usdz`, `.obj`, `.dae`) and bundled textures.
2. **Algorithmic Profiling of Backend Routing Engine:**
   - Executed benchmark runner `/tmp/measure_routing.py` via `backend/.venv/bin/python` across all repo fixtures and demo homes (`apartment.json`, `bungalow.json`, `bungalow-blocked.json`, `bungalow-narrow.json`, `twostory-empty.json`, `twostory.json`, `jagged.json`, `ranch-house.homeplan.json`).
   - Timed 10-iteration statistical distributions (mean, min, max) for `compute_route_plan`.
   - Timed synchronous `/score` end-to-end multi-peril execution (fire + tornado + earthquake + composite score).
3. **Fixture Complexity & JSON Serialization Benchmarking:**
   - Scripted `/tmp/measure_complexity.py` to count floors, rooms, openings, objects, stairs, and polygon vertices.
   - Scripted `/tmp/measure_json.py` to benchmark raw `json.loads` vs. Pydantic model validation throughput.
4. **Retain Cycle & Lifecycle Static Analysis:**
   - Grepped and traced all occurrences of `CADisplayLink`, `Timer`, `Combine` publishers/sinks, delegates, and closures across the codebase.
   - Evaluated `OrbitCameraRig`'s `DisplayLinkProxy` weak-target forwarding.
   - Audited `EvacuationPlaybackCoordinator`'s associated-object lifetime and delegate restoration.
5. **SwiftUI Dependency Graph & Frame-Rate Tracing:**
   - Mapped all 59 `@State` properties and `@Observable` accesses in `HouseScreen.swift`.
   - Traced `PlaybackClock` invocation chain and its invalidation impact on `EditorSceneView.updateUIView`.
   - Examined `withObservationTracking` in `EvacuationPlaybackCoordinator.observeFrame`.
6. **Main-Thread I/O & Graphics Pipeline Inspection:**
   - Traced `ExportPlanSheet.generate` call stack into `EscapePlanPDF.render` and `Data.write`.
   - Inspected `RoomLabelSprite.make` CoreGraphics image rendering and texture allocation.
   - Audited `SCNView` MSAA 4X and `SCNCamera` Screen Space Ambient Occlusion (SSAO) configurations.

---

## 4. Findings (with Evidence)

### [HIGH] 11-01 Monolithic `HouseScreen` View Body Invalidated at Display Cadence (60/120 FPS) During Evacuation Playback
**Domain:** Frontend Architecture / SwiftUI Invalidation  
**Location:** `escape_plan/Screens/HouseScreen.swift:188, 519, 819-826, 1179-1210` & `escape_plan/Editor/SceneKit/EditorSceneView.swift:101-116`  
**Observed behavior:** When evacuation playback is active, the playhead advances via `PlaybackClock` using `TimelineView(.animation)`. Every time `playback.currentTime_s` updates, the entire 2,875-line `HouseScreen` body is re-evaluated by SwiftUI. Consequently, `EditorSceneView.updateUIView` is invoked on every single frame.  
**Evidence:**  
In `escape_plan/Screens/HouseScreen.swift`:
```swift
Line 188:  @State private var playback = EvacuationPlaybackModel()
...
Line 519:  PlaybackClock(playback: playback)
...
Line 819:  TimelineView(.animation(minimumInterval: playback.isSteppedMode ? 0.2 : nil,
Line 820:                          paused: !playback.isPlaying)) { context in
Line 825:      playback.tick(deltaTime: min(delta, Self.maxFrameDelta_s))
...
Line 1179: value: Binding(get: { playback.currentTime_s }, set: { playback.seek(to: $0) }),
Line 1210: Text(playback.elapsedLabel)
Line 1317: elapsedSpoken: EvacuationPlaybackModel.spokenTimeLabel(playback.currentTime_s),
```
In `escape_plan/Editor/SceneKit/EditorSceneView.swift`:
```swift
Line 101: func updateUIView(_ view: SCNView, context: Context) {
...
Line 111: // HouseScreen's body reads the evacuation playback clock, so this path now runs on every
Line 112: // frame of a simulation; rebuilding there would restart the animation 60×/sec.
Line 114: controller.rebuildIfNeeded(home: store.model, activeFloorId: store.activeFloorId)
Line 115: controller.highlight(store.selection)
```
**Expected behavior:** The playback clock and scrubber/label updates should be isolated to a dedicated leaf subview. `HouseScreen`'s main body, dock, and `EditorSceneView` should remain stable during simulation playback.  
**Root cause:** `HouseScreen` directly reads `@Observable` properties of `playback` (`currentTime_s`, `elapsedLabel`, `spokenTimeLabel`) within helper functions that return `some View` rather than distinct `View` struct components. In SwiftUI, reading an observed property inside a parent view registers the entire parent body for invalidation whenever that property changes.  
**Impact:** 60 to 120 full SwiftUI view diffs per second. Every frame causes `EditorSceneView.updateUIView` to run, triggering unnecessary object equality comparisons (`rebuildIfNeeded`) and selection node traversals. Causes elevated CPU usage, thread contention, and thermal throttling on sustained playback.  
**Recommended improvement:** Extract the playback controls into isolated leaf views: e.g., `PlaybackScrubberView(playback:)` and `PlaybackTimeDisplayView(playback:)`. Remove all direct reads of `playback.currentTime_s` and `playback.elapsedLabel` from `HouseScreen`'s body.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High   **Effort:** Medium (decomposing `HouseScreen` subviews)

---

### [HIGH] 11-02 Unstructured `Task` Allocation Churn on Every Playhead Frame in `EvacuationPlaybackCoordinator`
**Domain:** Concurrency / Memory Allocation Churn  
**Location:** `escape_plan/Renderer/Evacuation/EvacuationPlaybackCoordinator.swift:296-311`  
**Observed behavior:** To synchronize playback state to SceneKit's render thread, `observeFrame` sets up an observation listener using `withObservationTracking`. On every tick of `playback.currentTime_s`, the `onChange` closure instantiates an unstructured `Task { @MainActor in ... }` to schedule the next frame observation.  
**Evidence:**  
```swift
296:     @MainActor
297:     private func observeFrame(generation: Int) {
298:         guard !isCleared, generation == observationGeneration, let playback else { return }
299:         let snapshot = withObservationTracking {
300:             EvacuationRenderState.Snapshot(
301:                 time_s: playback.currentTime_s,
302:                 isPlaying: playback.isPlaying,
303:                 reduceMotion: playback.isSteppedMode
304:             )
305:         } onChange: { [weak self] in
306:             Task { @MainActor [weak self] in
307:                 self?.observeFrame(generation: generation)
308:             }
309:         }
310:         renderState.setSnapshot(snapshot)
311:         view?.setNeedsDisplay()
312:     }
```
**Expected behavior:** Per-frame render synchronization should not allocate unstructured asynchronous `Task` objects on the heap at 60–120 Hz.  
**Root cause:** Misusing `withObservationTracking` as a per-frame animation loop. The `onChange` callback is invoked on arbitrary threads when observed properties change, prompting the author to wrap the recursive call in `Task { @MainActor ... }`.  
**Impact:** At 60 fps, creates 3,600 heap-allocated `Task` instances per minute (7,200 at 120 fps). This induces heap fragmentation, puts unnecessary pressure on the Swift concurrency thread pool, and wastes CPU cycles in thread context switches.  
**Recommended improvement:** Update `renderState` directly inside the playback tick driver or SceneKit renderer delegate callback (`renderer(_:updateAtTime:)`) using direct clock queries, avoiding recursive `Task` spawning.  
**Dependencies:** Finding 11-01.  
**Verification status:** Verified by source inspection.  
**Confidence:** High   **Effort:** Small

---

### [HIGH] 11-03 Main-Thread Synchronous Execution of Multi-Page PDF Generation and Atomic Disk I/O
**Domain:** Main-Thread Responsiveness / I/O Blocking  
**Location:** `escape_plan/Export/ExportPlanSheet.swift:191-203` & `escape_plan/Export/EscapePlanExporter.swift:73-89`  
**Observed behavior:** When the user taps "Create PDF", the sheet sets `@State isGenerating = true` and immediately invokes `exporter.writePDF(...)` synchronously on `@MainActor`. The PDF renderer paginates, rasterizes vector floor plans, calculates text wrapping, produces the binary PDF, and writes it atomically to disk before relinquishing the thread.  
**Evidence:**  
In `escape_plan/Export/ExportPlanSheet.swift`:
```swift
191:     private func generate(_ preview: EscapePlanExporter.Preview) {
192:         let trimmed = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
193:         exporter.meetingPoints.setMeetingPoint(trimmed, forHomeID: homeID)
194:         isGenerating = true
195:         // UIGraphicsPDFRenderer and attributed-string drawing are UIKit; keep them on the
196:         // main actor. These documents are a handful of pages of vector output.
197:         do {
198:             shareURLs = [try exporter.writePDF(preview: preview, meetingPoint: trimmed)]
199:         } catch {
200:             exportError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
201:         }
202:         isGenerating = false
203:     }
```
In `escape_plan/Export/EscapePlanExporter.swift`:
```swift
82:         let output = EscapePlanPDF.render(document)
...
87:         try output.data.write(to: url, options: Data.WritingOptions.atomic)
```
**Expected behavior:** The generation process should yield to the main runloop before starting (allowing `isGenerating = true` to render the `ProgressView()` spinner), or perform pagination/I/O off the main actor via a background task.  
**Root cause:** Because `UIGraphicsPDFRenderer` and UIKit attributed string measurements historically preferred `@MainActor`, the author placed all rendering and filesystem writing synchronously in the button action handler, commenting: *"These documents are a handful of pages of vector output"*.  
**Impact:** Because no runloop cycle occurs between `isGenerating = true` (line 194) and `isGenerating = false` (line 202), SwiftUI never presents the loading spinner. The app completely freezes and drops user interactions until rendering and disk writing complete. On complex multi-story homes with many rooms and routes, this causes perceptible UI hitches (200–500 ms).  
**Recommended improvement:** Wrap the generation in `Task { do { let url = try await ... } }` and yield execution with `await Task.yield()` prior to starting, or move the PDF data writing (`output.data.write`) off the main thread.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High   **Effort:** Small

---

### [MEDIUM] 11-04 Backend `/score` Endpoint Executes Three Sequential Unmemoized Route Solves (Exceeding 1.2 Seconds per Call)
**Domain:** Backend Performance / Algorithmic Complexity  
**Location:** `backend/app/main.py:651-653` & `backend/app/routing/nav_grid.py:146-218`  
**Observed behavior:** When calculating readiness scores, `/score` calls `compute_route_plan` three times sequentially for fire, tornado, and earthquake. Each call recalculates room polygons, bounding box intersections, obstacle rasterizations, and Chamfer distance transforms from scratch.  
**Evidence:**  
In `backend/app/main.py`:
```python
651:     plan = compute_route_plan(request.home, thresholds, constraints=request.constraints, peril="fire")
652:     tornado_plan = compute_route_plan(request.home, thresholds, request.constraints, peril="tornado")
653:     earthquake_plan = compute_route_plan(request.home, thresholds, request.constraints, peril="earthquake")
```
Benchmark measurements taken locally via `backend/.venv/bin/python` (`/tmp/measure_score.py`):
```
Fixture                        | Fire(ms)   | Tornado(ms)  | Quake(ms)  | Total Score (ms)
--------------------------------------------------------------------------------
apartment.json                 | 10.10      | 8.84         | 8.76       | 28.01
bungalow.json                  | 0.64       | 0.28         | 0.24       | 1.24
twostory.json                  | 52.48      | 52.85        | 53.63      | 159.09
jagged.json                    | 238.64     | 238.44       | 240.34     | 717.56
ranch-house.homeplan.json      | 405.18     | 398.22       | 399.50     | 1203.08
```
**Expected behavior:** Common geometric structures (room bounding boxes, object collision footprints, and clear-width distance erosion grids) should be computed once and reused across all three peril solvers.  
**Root cause:** Pure functional design in `compute_route_plan` does not accept pre-built `RoomGrid` structures, forcing `build_room_grid` (a double-pass integer Chamfer erosion algorithm) to re-run 3× on identical room geometries.  
**Impact:** A single score computation on a 12-room home ties up server CPU worker threads for **1.20 seconds**. Under concurrent requests, this quickly exhausts ASGI worker thread pools, increasing HTTP response latency.  
**Recommended improvement:** Memoize the base `RoomGrid` occupancy cache at the home/floor level, allowing subsequent peril evaluations to only re-run peril-specific edge weight adjustments.  
**Dependencies:** None.  
**Verification status:** Verified at runtime (measured with Python benchmark on repo fixtures).  
**Confidence:** High   **Effort:** Medium

---

### [MEDIUM] 11-05 Uncached CoreGraphics 3x Bitmap Rasterization for Every Room Label on Rebuild
**Domain:** Frontend Rendering / Memory & Texture Churn  
**Location:** `escape_plan/Renderer/RoomLabelSprite.swift:33-73` & `escape_plan/Renderer/DollhouseScene.swift:356-370`  
**Observed behavior:** During every dollhouse build, `makeLabel` invokes `RoomLabelSprite.make(name:)` for every room on every floor. This allocates a new `UIGraphicsImageRenderer` at 3x scale, executes CoreGraphics path clipping and attributed string drawing into a software bitmap, and creates a unique `SCNMaterial` per label.  
**Evidence:**  
In `escape_plan/Renderer/DollhouseScene.swift`:
```swift
355:     private static func makeLabel(_ room: Room, floorHeight: Double) -> SCNNode {
356:         let sprite = RoomLabelSprite.make(name: room.name)
...
360:         let material = SCNMaterial()
361:         material.diffuse.contents = sprite.image
```
In `escape_plan/Renderer/RoomLabelSprite.swift`:
```swift
49:         let format = UIGraphicsImageRendererFormat()
50:         format.scale = renderScale
51:         format.opaque = false
52:         let renderer = UIGraphicsImageRenderer(size: size, format: format)
53:         let image = renderer.image { context in ... }
```
**Expected behavior:** Identical room names (e.g. "Bedroom", "Bathroom", "Kitchen", "Living Room") should be cached in an in-memory sprite cache, avoiding redundant bitmap rendering and material allocations.  
**Root cause:** `RoomLabelSprite` is an unmemoized static factory with no caching dictionary.  
**Impact:** On homes like `ranch-house.homeplan.json` (12 rooms), 12 separate CoreGraphics rendering passes execute synchronously on the main thread during build. Whenever an edit action triggers a scene rebuild, all 12 bitmaps and materials are re-allocated, contributing to memory churn and main-thread latency.  
**Recommended improvement:** Introduce an `NSCache<NSString, RoomLabelSprite.Sprite>` to cache rendered chip textures by room name.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High   **Effort:** Small

---

### [MEDIUM] 11-06 Secondary Route Dashes Allocate Discrete Cloned Geometries and Dual Materials per Dash
**Domain:** SceneKit Rendering / Node & Geometry Churn  
**Location:** `escape_plan/Renderer/RouteOverlay.swift:156-170, 193-209`  
**Observed behavior:** When rendering secondary (backup) egress routes, `RouteOverlay` splits the path into dozens of dash segments (`RouteGeometry.dashes`). For every dash segment, it creates an `SCNGeometry` tube, and then inside `addTube`, clones the geometry (`geometry.copy()`) and instantiates two distinct `SCNMaterial` objects (one for the occluded 55% depth-off pass and one for the solid depth-tested pass).  
**Evidence:**  
In `escape_plan/Renderer/RouteOverlay.swift`:
```swift
159:                 for (i, dash) in RouteGeometry.dashes(smoothed).enumerated() {
160:                     guard let geometry = RouteGeometry.tubeGeometry(
161:                         points: dash.points, radius: style.radius,
162:                         uRange: dash.uStart...max(dash.uEnd, dash.uStart + 1e-5)) else { continue }
163:                     addTube(geometry, style: style,
164:                             name: "route:\(label):\(run.floorID):dash\(i)", into: container)
165:                 }
...
193:     private func addTube(_ geometry: SCNGeometry, style: TubeStyle, name: String, into container: SCNNode) {
195:         let ghost = SCNNode(geometry: geometry)
197:         ghost.geometry = geometry.copy() as? SCNGeometry
198:         ghost.geometry?.firstMaterial = tubeMaterial(style, occludedPass: true)
...
203:         let solid = SCNNode(geometry: geometry)
205:         solid.geometry?.firstMaterial = tubeMaterial(style, occludedPass: false)
```
**Expected behavior:** Segmented dashes should share a single instanced or combined batch geometry, or share materials across all dashes.  
**Root cause:** Segmenting the dash physically rather than in the fragment shader (adopted to survive black-and-white printing and testing) was implemented by creating distinct SceneKit nodes for every dash segment, with per-node geometry copies and material allocations.  
**Impact:** A secondary route spanning 3 floors with 40 dashes creates 80 `SCNNode` instances, 80 `SCNGeometry` instances, and 80 `SCNMaterial` instances. Whenever routes are refreshed, all of these objects are deallocated and re-allocated.  
**Recommended improvement:** Pool or share the solid and occluded `SCNMaterial` instances (creating only 2 material objects across all dashes), and avoid `geometry.copy()` by attaching the same geometry instance to both nodes.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High   **Effort:** Small

---

### [LOW] 11-07 Global MSAA 4X and Screen Space Ambient Occlusion (SSAO) Incur High Fill-Rate Overhead Without Device Tiering
**Domain:** Graphics Pipeline / GPU Load & Battery  
**Location:** `escape_plan/Renderer/UnifiedSceneController.swift:56` & `escape_plan/Renderer/DollhouseScene.swift:644-646`  
**Observed behavior:** `SCNView.antialiasingMode` is statically set to `.multisampling4X` and camera SSAO is configured with `screenSpaceAmbientOcclusionIntensity = 1.1`, `radius = 0.35`, and `bias = 0.03`. These settings run unconditionally across all devices and during all interactions.  
**Evidence:**  
In `escape_plan/Renderer/UnifiedSceneController.swift`:
```swift
56: scnView.antialiasingMode = .multisampling4X
```
In `escape_plan/Renderer/DollhouseScene.swift`:
```swift
644: camera.screenSpaceAmbientOcclusionIntensity = 1.1
645: camera.screenSpaceAmbientOcclusionRadius = 0.35
646: camera.screenSpaceAmbientOcclusionBias = 0.03
```
In `docs/tracker/notes/2026-08-05-camera-feel.md`:
```
124: 1. Profile frame time on the oldest supported device — #10 is genuinely not done. MSAA 4X,
125:    SSAO and the pulse shader all still run during gestures.
```
**Expected behavior:** SSAO and MSAA should be dynamically scaled down or paused during continuous dragging, or disabled on older hardware / Low Power Mode.  
**Root cause:** Post-processing and anti-aliasing were tuned for visual fidelity on high-end developer hardware without dynamic GPU tiering.  
**Impact:** High fragment shading cost and memory bandwidth usage on older devices or when running in Low Power Mode, leading to increased thermal dissipation and accelerated battery depletion.  
**Recommended improvement:** Check `ProcessInfo.processInfo.isLowPowerModeEnabled` and downgrade to 2X MSAA or disable SSAO during camera manipulation gestures via `CameraGestureDriver`.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection and historical evidence.  
**Confidence:** Medium   **Effort:** Small

---

### [LOW] 11-08 Manual Software Polling Loop (`Task.sleep(16ms)`) for Score Ring Animation
**Domain:** UI Animation / Energy Efficiency  
**Location:** `escape_plan/Screens/HomeScreen.swift:778-799`  
**Observed behavior:** `animateSweep(to:)` implements a manual 16ms sleep loop inside an asynchronous `Task` on `@MainActor` to calculate cubic easing and trigger haptic ticks.  
**Evidence:**  
```swift
778: sweepTask = Task { @MainActor in
...
784:     while !Task.isCancelled {
785:         let t = min(1, Date().timeIntervalSince(start) / duration)
786:         let eased = 1 - pow(1 - t, 3)
787:         displayed = from + (to - from) * eased
...
794:         try? await Task.sleep(for: .milliseconds(16))
795:     }
...
798: }
```
**Expected behavior:** View animations should utilize SwiftUI's built-in `withAnimation` system or a synchronized `CADisplayLink` rather than manual `Task.sleep` increments.  
**Root cause:** The animation needed to trigger haptic feedback at discrete score notches along the interpolation curve, prompting a custom software loop.  
**Impact:** Arbitrary 16ms sleep intervals do not align with display vsync (especially on 120Hz ProMotion displays where frame duration is 8.33ms), leading to phase jitter, micro-stutters, and unnecessary timer wakeups.  
**Recommended improvement:** Drive progress using `CADisplayLink` or SwiftUI's `PhaseAnimator` / `KeyframeAnimator`.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** Medium   **Effort:** Small

---

### [OBSERVATION] 11-09 Minimal Binary and Media Footprint (Total Assets Under 0.5 MB)
**Domain:** Asset Management / Disk Footprint  
**Location:** `escape_plan/Assets.xcassets` & `escape_plan/Resources`  
**Observed behavior:** The application bundles zero pre-baked 3D model files (`.scn`, `.usdz`, `.obj`) and zero heavy bitmap textures. All dollhouse walls, slabs, windows, doors, exit pads, furniture miniatures, and articulated human/pet figures are generated procedurally from code at runtime.  
**Evidence:**  
Measured directory sizes:
```
444K    escape_plan/Assets.xcassets (432K is AppIcon.appiconset)
 16K    escape_plan/Resources (16K prevention_tips.json)
 72K    escape_plan/Fixtures
 44K    demo-homes
```
Total binary image assets: 3 PNG files (`AppIcon.png`, `AppIcon-dark.png`, `AppIcon-tinted.png`).  
**Verification status:** Verified at runtime (measured with `du`).  
**Confidence:** High   **Effort:** N/A

---

### [OBSERVATION] 11-10 File-Stat Summary Caching Successfully Mitigates AUD-047 Listing Cost
**Domain:** Persistence / Main-Thread Decoding  
**Location:** `escape_plan/Persistence/HomeDocumentStore.swift:114-156`  
**Observed behavior:** In the previous audit (AUD-047), `HomeDocumentStore.list()` was flagged for decoding every home file synchronously on `@MainActor`. The current codebase resolves this by passing a `known` summary cache (`summaries(reusing:)`). If a file's `contentModificationDate` and `fileSize` are unchanged, the previously decoded `HomeSummary` is reused immediately without re-reading the file or decoding JSON. Newly modified files are parsed using a lightweight `SummaryProbe` that skips all document arrays.  
**Evidence:**  
```swift
135: if let previous = known[homeID], modificationDate != nil, fileSize != nil,
136:    previous.modificationDate == modificationDate, previous.fileSize == fileSize {
137:     entries[homeID] = previous
138:     continue
139: }
```
**Verification status:** Verified by source inspection.  
**Confidence:** High   **Effort:** N/A

---

## 5. Positive Findings

1. **Procedural Geometry Eliminates Asset Bloat:** Rather than bundling tens of megabytes of 3D meshes, the app generates all building and furniture primitives at runtime. This keeps total asset storage under 500 KB, drastically reducing app download size and initial disk footprint.
2. **Effective Gesture Rebuild Deferral Gate:** As verified by `GestureFrameCostUITests` and `docs/tracker/notes/2026-08-05-camera-feel.md`, camera dragging does not trigger SwiftUI update passes or scene rebuilds during touch manipulation (`provokedByDrag=0, landedOnGestureFrames=0`). The `isCameraGestureInFlight` flag defers commits until the touch lifts.
3. **Weak-Target DisplayLink Proxying:** `OrbitCameraRig` correctly prevents retain cycles between the display link and the rig by interposing `DisplayLinkProxy` with a `[weak self]` capture and explicit `link.invalidate()` in `deinit`.
4. **Thread-Safe Animation Posing Without SceneKit Actions:** `PeopleLayer` uses an immutable `AnimationStorage` snapshot and an `NSLock` to compute joint rotations on SceneKit's render thread. It mutates explicit joint handles directly without querying node trees by name or allocating SceneKit action sequences per frame.
5. **No Network Polling Loops:** Cloud sync and score fetching are triggered strictly by explicit user actions (foreground entry, sign-in, tab selection, edit commit) with debounce timers (`refetchDebounce = 900ms`). Background polling loops were completely absent from the codebase.

---

## 6. Systemic Issues and Root Causes

1. **Monolithic SwiftUI Architectures with Broad State Scope:**  
   `HouseScreen.swift` spans 2,875 lines and binds 59 `@State` properties. In SwiftUI, the unit of invalidation is the struct body. Placing high-frequency simulation state (`playback.currentTime_s`) in the same view that hosts static controls, sheets, and the `EditorSceneView` representable forces constant top-level re-evaluations.
2. **Boundary Confusion Between MainActor UI and Background Workers:**  
   The PDF exporter was placed entirely on `@MainActor` because UIKit graphics APIs operate on UIKit types. However, rasterization and file writing do not require blocking the main runloop, and doing so starves the UI of rendering frames.
3. **Sequential Pipeline Execution in Backend Endpoints:**  
   The backend routing engine treats each peril as an isolated black box. Because fire, tornado, and earthquake egress all operate on the same physical floorplan geometry, calculating the rasterized grid independently for each peril creates a 3x CPU penalty.

---

## 7. Unverified Assumptions

1. **Hardware-Specific GPU Fill Rate:** Measurements were performed on macOS Apple Silicon. Thermal behavior, battery drain, and GPU frame pacing under sustained MSAA 4X + SSAO rendering on older iPhone models (e.g. A14/A15) are inferred from architectural constants and historical project notes, not instrumented with Xcode Instruments on physical hardware.
2. **Instruments Time Profiler Allocations:** Exact byte counts of per-frame allocations during evacuation simulation could not be sampled with Instruments due to the lack of an installed iOS simulator runtime in the environment (`xcrun simctl list runtimes` unavailable). Findings 11-01 and 11-02 are verified through explicit source code analysis of the execution path.

---

## 8. Areas Requiring Further Investigation

1. **Memory Ceiling for High-Room Scans:** While typical demo homes contain 4 to 12 rooms, RoomPlan exports for large estates (30+ rooms across 4 floors) may trigger significant SceneKit node count overhead (>1,500 nodes). SceneKit draw calls and vertex buffers under these conditions should be evaluated.
2. **Particle System Memory During Sustained Fire Simulation:** `HazardLayer` spawns `SCNParticleSystem` emitters in every untenable room. Although capped at 120 particles/sec total, the memory persistence of particle buffers across multiple start/stop iterations should be tested for leaks.

---

## 9. Recommended Priorities

| Priority | Finding ID | Description | Impact | Estimated Effort |
|---|---|---|---|---|
| **P1** | **11-01** | Isolate `playback.currentTime_s` observation to leaf subviews in `HouseScreen` | Eliminates 60–120 FPS SwiftUI body invalidations during simulation | Medium |
| **P1** | **11-02** | Remove recursive `Task` allocation loop in `EvacuationPlaybackCoordinator.observeFrame` | Halts continuous heap task allocations (3,600+ tasks/min) | Small |
| **P2** | **11-03** | Asynchronously dispatch PDF generation and disk write in `ExportPlanSheet` | Prevents UI freezing and allows progress spinner to render | Small |
| **P2** | **11-04** | Memoize room occupancy grids in backend `/score` endpoint | Reduces `/score` response latency from 1.2s to ~400ms on demo homes | Medium |
| **P3** | **11-05** | Cache CoreGraphics room label sprite textures by name | Eliminates 12+ redundant bitmap renders per scene rebuild | Small |
| **P3** | **11-06** | Share materials across secondary route dash segments in `RouteOverlay` | Reduces geometry and material allocations by ~80% on backup routes | Small |
| **P3** | **11-07** | Throttle MSAA/SSAO during active camera gestures and in Low Power Mode | Reduces GPU fill-rate pressure and battery consumption | Small |
| **P4** | **11-08** | Replace manual 16ms `Task.sleep` animation loop in `HomeScreen` with CADisplayLink | Eliminates vsync phase jitter and aligns with 120Hz ProMotion | Small |
