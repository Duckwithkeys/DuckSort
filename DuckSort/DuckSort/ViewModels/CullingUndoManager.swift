//
//  CullingUndoManager.swift
//  PhotomatorSort
//
//  Manages bounded undo and redo stacks for rating, pick flag, and tag edits.
//

import Foundation

struct CullingState: Sendable {
    let photoSetID: UUID
    let rating: Int?
    let pick: Int?
    let tagIDs: Set<UUID>
}

struct CullingUndoManager: Sendable {
    private(set) var undoStack: [[CullingState]] = []
    private(set) var redoStack: [[CullingState]] = []
    let maxDepth: Int = 150

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func registerUndo(beforeStates: [CullingState]) {
        guard !beforeStates.isEmpty else { return }
        undoStack.append(beforeStates)
        redoStack.removeAll()
        if undoStack.count > maxDepth {
            undoStack.removeFirst()
        }
    }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    mutating func popUndo(pushingRedo currentStates: ([UUID]) -> [CullingState]) -> [CullingState]? {
        guard let before = undoStack.popLast() else { return nil }
        let ids = before.map(\.photoSetID)
        redoStack.append(currentStates(ids))
        return before
    }

    mutating func popRedo(pushingUndo currentStates: ([UUID]) -> [CullingState]) -> [CullingState]? {
        guard let after = redoStack.popLast() else { return nil }
        let ids = after.map(\.photoSetID)
        undoStack.append(currentStates(ids))
        return after
    }
}
