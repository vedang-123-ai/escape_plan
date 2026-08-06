//  UnifiedSceneController+Evacuation.swift
//  Renderer/Evacuation
//
//  The one integration hook the House screen needs. The coordinator is retained as an
//  Objective-C associated object because UnifiedSceneController intentionally has no stored
//  evacuation state and SCNView holds its renderer delegate weakly.

import ObjectiveC.runtime

private nonisolated(unsafe) var evacuationPlaybackCoordinatorKey: UInt8 = 0

extension UnifiedSceneController {

    /// Binds renderer layers to the existing playback model, which remains the sole clock.
    ///
    /// - Parameters:
    ///   - staticPeopleLayer: A provider rather than a captured layer because `onRebuild`
    ///     replaces that layer. The coordinator asks again after every rebuild.
    ///   - suspendOrdinaryRoutes: Clears/hides the route solved before the fire was introduced.
    ///     It is called again after a scene rebuild and should therefore be idempotent.
    ///   - restoreOrdinaryRoutes: Re-renders that route after the timeline is cleared.
    ///   - onIssues: Receives unresolved timeline references from every renderer layer.
    ///
    /// Calling this again first performs a complete, ownership-safe unbind of the old bridge.
    @discardableResult
    func bindEvacuationPlayback(
        _ playback: EvacuationPlaybackModel,
        staticPeopleLayer: @escaping EvacuationPlaybackCoordinator.StaticPeopleLayerProvider,
        suspendOrdinaryRoutes: EvacuationPlaybackCoordinator.RouteLayerAction? = nil,
        restoreOrdinaryRoutes: EvacuationPlaybackCoordinator.RouteLayerAction? = nil,
        onIssues: EvacuationPlaybackCoordinator.IssueHandler? = nil
    ) -> EvacuationPlaybackCoordinator {
        unbindEvacuationPlayback()

        let coordinator = EvacuationPlaybackCoordinator(
            controller: self,
            playback: playback,
            staticPeopleLayerProvider: staticPeopleLayer,
            suspendOrdinaryRoutes: suspendOrdinaryRoutes,
            restoreOrdinaryRoutes: restoreOrdinaryRoutes,
            issueHandler: onIssues
        )
        objc_setAssociatedObject(
            self,
            &evacuationPlaybackCoordinatorKey,
            coordinator,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        coordinator.start()
        return coordinator
    }

    /// Removes the renderer delegate bridge and all nodes it owns, then restores the original
    /// static people, ordinary route, camera, renderer delegate, and rebuild callback.
    func unbindEvacuationPlayback() {
        evacuationPlaybackCoordinator?.clear()
        objc_setAssociatedObject(
            self,
            &evacuationPlaybackCoordinatorKey,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    /// Exposed read-only for an explicit “resume automatic framing” control. Ordinary playback
    /// should never call it; a manual scene gesture owns the camera until the user opts back in.
    var evacuationPlaybackCoordinator: EvacuationPlaybackCoordinator? {
        objc_getAssociatedObject(self, &evacuationPlaybackCoordinatorKey)
            as? EvacuationPlaybackCoordinator
    }
}
