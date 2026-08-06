//  EvacuationPlaybackCoordinator.swift
//  Renderer/Evacuation
//
//  Bridges the main-actor EvacuationPlaybackModel into SceneKit's render callback without
//  creating a second clock. Observation copies only (time, playing, Reduce Motion) into a
//  lock-protected value. The renderer delegate reads that value and never reaches through the
//  @Observable model from SceneKit's private rendering thread.

import Foundation
import Observation
import SceneKit
import UIKit

/// The per-frame half of the coordinator. SceneKit may invoke its delegate away from the main
/// thread, so resource replacement, camera handoff, and frame application share one short lock.
/// No timeline geometry is built here: PeopleLayer, HazardLayer, and EvacuationTrackLayer are
/// configured on the main actor only when a timeline or dollhouse changes.
private nonisolated final class EvacuationRenderState {

    struct Snapshot: Equatable {
        let time_s: Double
        let isPlaying: Bool
        let reduceMotion: Bool

        init(time_s: Double = 0, isPlaying: Bool = false, reduceMotion: Bool = false) {
            self.time_s = time_s.isFinite ? max(0, time_s) : 0
            self.isPlaying = isPlaying
            self.reduceMotion = reduceMotion
        }
    }

    private struct Resources {
        let people: PeopleLayer
        let hazard: HazardLayer
        let camera: PlaybackCameraController
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()
    private var lastRenderedSnapshot: Snapshot?
    private var resources: Resources?

    func replace(people: PeopleLayer,
                 hazard: HazardLayer,
                 camera: PlaybackCameraController) {
        lock.lock()
        resources = Resources(people: people, hazard: hazard, camera: camera)
        lastRenderedSnapshot = nil
        lock.unlock()
    }

    func setSnapshot(_ newSnapshot: Snapshot) {
        lock.lock()
        snapshot = newSnapshot
        lock.unlock()
    }

    /// SceneKit calls this exactly once before each rendered frame. Holding the lock through the
    /// three updates prevents a rebuild on the main actor from detaching nodes halfway through a
    /// render callback. These updates mutate cached nodes/materials only and allocate no route
    /// or figure geometry.
    func renderFrame() {
        lock.lock()
        defer { lock.unlock() }
        guard let resources else { return }

        // A paused SCNView can still be redrawn for editor/camera reasons. Once this exact
        // instant has been applied there is no work to repeat. Playing frames intentionally
        // remain eligible because their SceneKit frame can race the next observation delivery.
        if !snapshot.isPlaying, lastRenderedSnapshot == snapshot { return }
        lastRenderedSnapshot = snapshot

        resources.people.update(time: snapshot.time_s,
                                reduceMotion: snapshot.reduceMotion)
        resources.hazard.update(time: snapshot.time_s,
                                reduceMotion: snapshot.reduceMotion)
        resources.camera.update(time: snapshot.time_s,
                                isPlaying: snapshot.isPlaying,
                                reduceMotion: snapshot.reduceMotion)
    }

    /// Returns true only when an automatic playback camera actually existed. The coordinator
    /// uses that answer so a gesture before any timeline is loaded does not disable a future tour.
    @MainActor
    @discardableResult
    func yieldAutomaticCamera() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let camera = resources?.camera else { return false }
        camera.userDidBeginManualControl()
        return true
    }

    @MainActor
    func resumeAutomaticCamera() {
        lock.lock()
        resources?.camera.resumeAutomaticFraming()
        lastRenderedSnapshot = nil
        lock.unlock()
    }

    /// Detaches only renderer-owned nodes. Waiting for an in-flight update under the same lock
    /// avoids clearing a SceneKit subtree while that update is writing its transforms.
    @MainActor
    func clearResources() {
        lock.lock()
        let removed = resources
        resources = nil
        lastRenderedSnapshot = nil
        // Acquiring the lock above waited for any in-flight frame to finish. Future frames see
        // `nil`, so SceneKit teardown can happen after unlocking without racing an update or
        // holding our lock across framework calls.
        lock.unlock()
        if let removed {
            removed.camera.clear()
            removed.hazard.clear()
            removed.people.clear()
        }
    }
}

/// Retains and forwards an SCNView delegate displaced by evacuation playback. SCNView's
/// `delegate` property is weak; retaining it here is necessary if it is to be restored later.
private nonisolated final class EvacuationRendererDelegateForwarder {
    private let lock = NSLock()
    private var delegate: (any SCNSceneRendererDelegate)?

    func preserve(_ candidate: (any SCNSceneRendererDelegate)?) {
        lock.lock()
        delegate = candidate
        lock.unlock()
    }

    func preservedDelegate() -> (any SCNSceneRendererDelegate)? {
        lock.lock()
        defer { lock.unlock() }
        return delegate
    }

    func update(_ renderer: any SCNSceneRenderer, time: TimeInterval) {
        preservedDelegate()?.renderer?(renderer, updateAtTime: time)
    }

    func didApplyAnimations(_ renderer: any SCNSceneRenderer, time: TimeInterval) {
        preservedDelegate()?.renderer?(renderer, didApplyAnimationsAtTime: time)
    }

    func didSimulatePhysics(_ renderer: any SCNSceneRenderer, time: TimeInterval) {
        preservedDelegate()?.renderer?(renderer, didSimulatePhysicsAtTime: time)
    }

    func didApplyConstraints(_ renderer: any SCNSceneRenderer, time: TimeInterval) {
        preservedDelegate()?.renderer?(renderer, didApplyConstraintsAtTime: time)
    }

    func willRender(_ renderer: any SCNSceneRenderer, scene: SCNScene, time: TimeInterval) {
        preservedDelegate()?.renderer?(renderer, willRenderScene: scene, atTime: time)
    }

    func didRender(_ renderer: any SCNSceneRenderer, scene: SCNScene, time: TimeInterval) {
        preservedDelegate()?.renderer?(renderer, didRenderScene: scene, atTime: time)
    }
}

/// Owns the evacuation-only SceneKit layers and binds them to one EvacuationPlaybackModel.
///
/// All lifecycle methods run on the main actor. Only the SCNSceneRendererDelegate callbacks
/// below are render-thread entry points, and they touch `renderState` rather than observable UI
/// state. The class opts out of the target's default MainActor isolation so that separation is
/// explicit and compiler-checkable.
nonisolated final class EvacuationPlaybackCoordinator: NSObject, SCNSceneRendererDelegate {

    typealias StaticPeopleLayerProvider = @MainActor () -> PeopleLayer?
    typealias RouteLayerAction = @MainActor () -> Void
    typealias IssueHandler = @MainActor ([String]) -> Void

    private let renderState = EvacuationRenderState()
    private let delegateForwarder = EvacuationRendererDelegateForwarder()

    private weak var controller: UnifiedSceneController?
    private weak var view: SCNView?
    private weak var playback: EvacuationPlaybackModel?

    private let staticPeopleLayerProvider: StaticPeopleLayerProvider
    private let suspendOrdinaryRoutes: RouteLayerAction?
    private let restoreOrdinaryRoutes: RouteLayerAction?
    private let issueHandler: IssueHandler?

    private var previousOnRebuild: ((DollhouseScene) -> Void)?
    private var trackLayer: EvacuationTrackLayer?
    private var currentTimeline: EvacuationTimeline?
    private var observedGestures: [UIGestureRecognizer] = []
    private var observationGeneration = 0
    private var ordinaryRoutesAreSuspended = false
    private var hasManualCameraOverride = false
    private var lastReportedIssues: [String]?
    private var isCleared = false

    @MainActor
    init(controller: UnifiedSceneController,
         playback: EvacuationPlaybackModel,
         staticPeopleLayerProvider: @escaping StaticPeopleLayerProvider,
         suspendOrdinaryRoutes: RouteLayerAction?,
         restoreOrdinaryRoutes: RouteLayerAction?,
         issueHandler: IssueHandler?) {
        self.controller = controller
        self.view = controller.scnView
        self.playback = playback
        self.staticPeopleLayerProvider = staticPeopleLayerProvider
        self.suspendOrdinaryRoutes = suspendOrdinaryRoutes
        self.restoreOrdinaryRoutes = restoreOrdinaryRoutes
        self.issueHandler = issueHandler
        self.previousOnRebuild = controller.onRebuild
        super.init()
    }

    /// Installs observation and the renderer delegate. Kept separate from init so `self` can be
    /// captured weakly by the rebuild callback only after NSObject initialization is complete.
    @MainActor
    func start() {
        guard !isCleared, let controller else { return }
        observationGeneration += 1
        let generation = observationGeneration

        observeManualCameraGestures()

        let previous = previousOnRebuild
        controller.onRebuild = { [weak self, weak controller] dollhouse in
            // RouteOverlay and the static PeopleLayer are rebuilt first. The evacuation layer
            // then attaches to the fresh dollhouse and re-hides those ordinary visuals.
            previous?(dollhouse)
            guard let self, let controller, let home = controller.currentHome else { return }
            self.sceneDidRebuild(dollhouse: dollhouse, home: home)
        }

        observeTimeline(generation: generation)
        observeFrame(generation: generation)
    }

    /// Explicit opt-in after a manual gesture. Playback ticks and dollhouse rebuilds never call
    /// this, so automatic framing cannot steal the camera back from OrbitCameraRig.
    @MainActor
    func resumeAutomaticCameraFraming() {
        guard !isCleared, currentTimeline != nil else { return }
        hasManualCameraOverride = false
        renderState.resumeAutomaticCamera()
        view?.setNeedsDisplay()
    }

    /// Stops observation by invalidating its generation, removes only evacuation-owned nodes,
    /// and restores every host hook displaced by `start()`.
    @MainActor
    func clear() {
        guard !isCleared else { return }
        isCleared = true
        observationGeneration += 1
        currentTimeline = nil

        removeSceneResources()
        staticPeopleLayerProvider()?.isVisible = true
        if ordinaryRoutesAreSuspended {
            restoreOrdinaryRoutes?()
            ordinaryRoutesAreSuspended = false
        }
        report([])

        for gesture in observedGestures {
            gesture.removeTarget(self, action: #selector(manualCameraGestureChanged(_:)))
        }
        observedGestures.removeAll(keepingCapacity: false)

        if let controller {
            controller.onRebuild = previousOnRebuild
        }
        if let view, (view.delegate as AnyObject?) === self {
            view.delegate = delegateForwarder.preservedDelegate()
        }
    }

    // MARK: - Observation (main actor only)

    @MainActor
    private func observeTimeline(generation: Int) {
        guard !isCleared, generation == observationGeneration, let playback else { return }
        let timeline = withObservationTracking {
            playback.timeline
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeTimeline(generation: generation)
            }
        }
        applyTimeline(timeline)
    }

    @MainActor
    private func observeFrame(generation: Int) {
        guard !isCleared, generation == observationGeneration, let playback else { return }
        let snapshot = withObservationTracking {
            EvacuationRenderState.Snapshot(
                time_s: playback.currentTime_s,
                isPlaying: playback.isPlaying,
                reduceMotion: playback.isSteppedMode
            )
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeFrame(generation: generation)
            }
        }
        renderState.setSnapshot(snapshot)
        view?.setNeedsDisplay()
    }

    @MainActor
    private func applyTimeline(_ timeline: EvacuationTimeline?) {
        currentTimeline = timeline
        guard let timeline else {
            removeSceneResources()
            staticPeopleLayerProvider()?.isVisible = true
            if ordinaryRoutesAreSuspended {
                restoreOrdinaryRoutes?()
                ordinaryRoutesAreSuspended = false
            }
            report([])
            restoreRendererDelegateIfOwned()
            view?.setNeedsDisplay()
            return
        }

        // A normal RouteOverlay was solved for a pre-fire world. Leaving it beneath the
        // hazard-aware timeline would visually endorse a path the engine may have rejected.
        suspendOrdinaryRoutes?()
        ordinaryRoutesAreSuspended = true
        staticPeopleLayerProvider()?.isVisible = false
        claimRendererDelegate()

        guard let controller,
              let dollhouse = controller.dollhouse,
              let home = controller.currentHome else {
            removeSceneResources()
            report(["evacuation playback is waiting for a built dollhouse"])
            return
        }
        configure(timeline: timeline, home: home, dollhouse: dollhouse)
    }

    @MainActor
    private func sceneDidRebuild(dollhouse: DollhouseScene, home: HomeModel) {
        guard !isCleared else { return }
        guard let timeline = currentTimeline else {
            staticPeopleLayerProvider()?.isVisible = true
            return
        }

        claimRendererDelegate()
        // The preserved rebuild callback may just have recreated both ordinary layers, so
        // reassert their simulation state even though the timeline itself did not change.
        suspendOrdinaryRoutes?()
        ordinaryRoutesAreSuspended = true
        staticPeopleLayerProvider()?.isVisible = false
        configure(timeline: timeline, home: home, dollhouse: dollhouse)
    }

    // MARK: - Setup-only scene configuration

    @MainActor
    private func configure(timeline: EvacuationTimeline,
                           home: HomeModel,
                           dollhouse: DollhouseScene) {
        removeSceneResources()

        guard let playbackView = controller?.scnView ?? view else {
            report(["evacuation playback lost its SceneKit view"])
            return
        }

        let people = PeopleLayer(dollhouse: dollhouse)
        let hazard = HazardLayer(dollhouse: dollhouse)
        let tracks = EvacuationTrackLayer(dollhouse: dollhouse)
        let camera = PlaybackCameraController(
            dollhouse: dollhouse,
            view: playbackView,
            manualCameraNode: controller?.rig.node,
            mode: .allActive
        )

        var issues: [String] = []
        issues += people.show(timeline: timeline, home: home, highlighted: nil)
        issues += hazard.show(timeline: timeline, home: home)
        issues += tracks.show(timeline: timeline, home: home)

        if hasManualCameraOverride {
            issues += camera.configure(timeline: timeline,
                                       figureNodes: people.figureNodesByProfileID)
        } else {
            issues += camera.begin(timeline: timeline,
                                   figureNodes: people.figureNodesByProfileID)
        }

        trackLayer = tracks
        renderState.replace(people: people, hazard: hazard, camera: camera)
        report(issues)
        view?.setNeedsDisplay()
    }

    @MainActor
    private func removeSceneResources() {
        // EvacuationTrackLayer is setup-only, so it is not stored in the render-thread bundle.
        trackLayer?.clear()
        trackLayer = nil
        renderState.clearResources()
    }

    @MainActor
    private func report(_ issues: [String]) {
        guard issues != lastReportedIssues else { return }
        lastReportedIssues = issues
        issueHandler?(issues)
    }

    // MARK: - Host delegate and camera handoff

    @MainActor
    private func claimRendererDelegate() {
        guard let view else { return }
        if let existing = view.delegate, (existing as AnyObject) !== self {
            delegateForwarder.preserve(existing)
        }
        view.delegate = self
    }

    @MainActor
    private func restoreRendererDelegateIfOwned() {
        guard let view, (view.delegate as AnyObject?) === self else { return }
        view.delegate = delegateForwarder.preservedDelegate()
    }

    @MainActor
    private func observeManualCameraGestures() {
        guard let view else { return }
        for gesture in view.gestureRecognizers ?? [] {
            gesture.addTarget(self, action: #selector(manualCameraGestureChanged(_:)))
            observedGestures.append(gesture)
        }
    }

    @MainActor @objc
    private func manualCameraGestureChanged(_ gesture: UIGestureRecognizer) {
        // Continuous gestures yield as soon as they begin. Discrete recognizers (tap and
        // double-tap) jump straight to `.ended`, which is UIKit's recognized state; those can
        // select/focus scene content and therefore count as manual ownership too.
        guard gesture.state == .began || gesture.state == .ended else { return }
        guard !hasManualCameraOverride else { return }
        guard renderState.yieldAutomaticCamera() else { return }
        hasManualCameraOverride = true
        view?.setNeedsDisplay()
    }

    // MARK: - SCNSceneRendererDelegate (SceneKit render thread)

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        delegateForwarder.update(renderer, time: time)
        renderState.renderFrame()
    }

    func renderer(_ renderer: any SCNSceneRenderer,
                  didApplyAnimationsAtTime time: TimeInterval) {
        delegateForwarder.didApplyAnimations(renderer, time: time)
    }

    func renderer(_ renderer: any SCNSceneRenderer,
                  didSimulatePhysicsAtTime time: TimeInterval) {
        delegateForwarder.didSimulatePhysics(renderer, time: time)
    }

    func renderer(_ renderer: any SCNSceneRenderer,
                  didApplyConstraintsAtTime time: TimeInterval) {
        delegateForwarder.didApplyConstraints(renderer, time: time)
    }

    func renderer(_ renderer: any SCNSceneRenderer,
                  willRenderScene scene: SCNScene,
                  atTime time: TimeInterval) {
        delegateForwarder.willRender(renderer, scene: scene, time: time)
    }

    func renderer(_ renderer: any SCNSceneRenderer,
                  didRenderScene scene: SCNScene,
                  atTime time: TimeInterval) {
        delegateForwarder.didRender(renderer, scene: scene, time: time)
    }
}
