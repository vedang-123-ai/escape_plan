//  UndoStack.swift — undo/redo built on HomeModelStore's before/after Commit snapshots.
//
//  @Observable (like HomeModelStore) so canUndo/canRedo drive toolbar button state reactively.
//  Undo/redo never re-run a reducer: they call `store.replaceModel` with a captured snapshot,
//  which is exactly why `Commit` carries both `before` and `after`.
//
//  Continuous drags (dragVertex/dragEdge/dragRoom/dragOpening) dispatch on every gesture
//  `.changed` event — one drag can be 100+ commits. Coalescing them by matching the action's
//  subject (same room/opening id) can't tell "still dragging" from "let go and immediately
//  started a new drag on the same thing," so the gesture driver explicitly brackets the group
//  instead: `beginCoalescing` captures the pre-drag snapshot, `endCoalescing` pushes ONE Commit
//  covering the whole gesture (or nothing, if nothing actually changed).

import Foundation
import Observation

// Not @MainActor-annotated, matching HomeModelStore's own convention: "main-actor UI state" by
// documented contract, not enforced by the type system, so tests can call it synchronously.
@Observable
final class UndoStack {

    private var past: [HomeModelStore.Commit] = []
    private var future: [HomeModelStore.Commit] = []

    /// Set while a continuous-drag gesture is in progress. `latestAction`/`latestAfter` are
    /// updated by `recordCommit` as the gesture progresses; nil until the first commit arrives.
    private var coalescing: (before: HomeModel, latestAction: EditAction?, latestAfter: HomeModel)?

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    var undoLabel: String? { past.last?.action.undoLabel }
    var redoLabel: String? { future.last?.action.undoLabel }

    /// Wire this to `HomeModelStore.onCommit`. A commit that arrives while coalescing updates the
    /// in-progress group instead of pushing a new entry; otherwise it pushes immediately. Either
    /// way, a fresh commit invalidates whatever was undone.
    func recordCommit(_ commit: HomeModelStore.Commit) {
        future.removeAll()

        if let group = coalescing {
            coalescing = (before: group.before, latestAction: commit.action, latestAfter: commit.after)
            return
        }
        past.append(commit)
    }

    /// Call when a continuous-drag gesture begins.
    func beginCoalescing(snapshot: HomeModel) {
        coalescing = (before: snapshot, latestAction: nil, latestAfter: snapshot)
    }

    /// Call when the gesture ends. Pushes one Commit covering the whole gesture, or nothing if no
    /// dispatch during the gesture was ever accepted (before == after).
    func endCoalescing() {
        guard let group = coalescing else { return }
        coalescing = nil
        guard let action = group.latestAction, group.before != group.latestAfter else { return }
        past.append(HomeModelStore.Commit(action: action, before: group.before, after: group.latestAfter))
    }

    /// Drops all history (both directions) and any in-progress coalescing group. Used when the
    /// edited home is deleted out from under the editor — its snapshots describe a document
    /// that no longer exists, so replaying them would resurrect it.
    func reset() {
        past.removeAll()
        future.removeAll()
        coalescing = nil
    }

    /// Applies the top of the undo stack via `store.replaceModel` and moves it to the redo stack.
    /// Returns whether anything applied, so the caller knows whether to bump revision/autosave.
    @discardableResult
    func undo(on store: HomeModelStore) -> Bool {
        guard let commit = past.popLast() else { return false }
        guard store.replaceModel(commit.before).didApply else {
            past.append(commit)
            return false
        }
        future.append(commit)
        return true
    }

    @discardableResult
    func redo(on store: HomeModelStore) -> Bool {
        guard let commit = future.popLast() else { return false }
        guard store.replaceModel(commit.after).didApply else {
            future.append(commit)
            return false
        }
        past.append(commit)
        return true
    }
}
