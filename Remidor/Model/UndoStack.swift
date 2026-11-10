//
//  UndoStack.swift
//  Remidor
//
//  Created by n9ine on 10.11.2026.
//

import Foundation

/// What the banner says about an edit or deletion that can still be taken back.
struct UndoNotice: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let icon: String
    let created = Date()
}

/// The edits and deletions that can still be undone, oldest first. The newest is the one the banner shows and
/// ⌘Z takes back; when it runs out or is undone, the one before it is next.
struct UndoStack {
    struct Entry {
        let notice: UndoNotice
        let undo: () -> Void
    }

    private(set) var entries: [Entry] = []

    var newest: UndoNotice? { entries.last?.notice }

    mutating func push(_ notice: UndoNotice, undo: @escaping () -> Void) {
        entries.append(Entry(notice: notice, undo: undo))
    }

    /// Takes one out, whether it was undone or ran out of time.
    @discardableResult
    mutating func remove(id: UUID) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.notice.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    mutating func popNewest() -> Entry? {
        entries.popLast()
    }
}
