//
//  DeferredDeletes.swift
//  Remidor
//
//  Created by n9ine on 10.11.2026.
//

import Foundation

/// Deletions that are only hidden so far. Reminders can't bring a deleted reminder back, so a delete waits for its
/// undo window: until it is carried out, Undo just shows the reminders again.
struct DeferredDeletes {
    /// A deleted reminder and its sub-tasks, parent first.
    struct Batch: Equatable {
        let ids: [String]
        let title: String
    }

    private var batches: [String: Batch] = [:]

    /// Everything that is hidden while it waits.
    var hiddenIDs: Set<String> { Set(batches.values.flatMap(\.ids)) }

    var isEmpty: Bool { batches.isEmpty }

    /// Puts a reminder and its sub-tasks on hold. Deleting the same one again replaces the earlier wait.
    mutating func hold(root: String, subtasks: [String], title: String) {
        batches[root] = Batch(ids: [root] + subtasks, title: title)
    }

    /// Takes a batch out because it was undone. Nil when it was already carried out or undone.
    mutating func undo(root: String) -> Batch? {
        batches.removeValue(forKey: root)
    }

    /// Takes a batch out to carry it out for good. Nil when it was undone in the meantime.
    mutating func release(root: String) -> Batch? {
        batches.removeValue(forKey: root)
    }

    /// Every batch still waiting, for when the app quits, keyed by the deleted reminder.
    mutating func releaseAll() -> [(root: String, batch: Batch)] {
        let all = batches.map { (root: $0.key, batch: $0.value) }
        batches.removeAll()
        return all
    }
}
