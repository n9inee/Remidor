//
//  ReminderOrdering.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import Foundation

extension Array where Element == ReminderItem {
    /// Sorted by the user's chosen order; ties fall back to due date, then title.
    func sorted(by order: SortOrder) -> [ReminderItem] {
        sorted { a, b in
            switch order {
            case .dueDate: Self.isOrdered(a.due, b.due) { Self.byTitle(a, b) }
            case .priority: Self.byPriority(a, b) { Self.isOrdered(a.due, b.due) { Self.byTitle(a, b) } }
            case .title: Self.byTitle(a, b)
            case .creationDate: Self.isOrdered(a.created, b.created) { Self.byTitle(a, b) }
            }
        }
    }

    /// Due date and time first, then priority, then title. Used by Today and Scheduled.
    func sortedByDueTime() -> [ReminderItem] {
        sorted { a, b in
            Self.isOrdered(a.due, b.due) { Self.byPriority(a, b) { Self.byTitle(a, b) } }
        }
    }

    /// Puts each sub-task directly under its parent. A sub-task whose parent isn't in this list stays top-level.
    func nestingSubtasks() -> [ReminderItem] {
        let ids = Set(map(\.id))
        func hasParentHere(_ item: ReminderItem) -> Bool { item.parentID.map(ids.contains) ?? false }

        let children = Dictionary(grouping: filter(hasParentHere)) { $0.parentID! }
        var result: [ReminderItem] = []
        var visited = Set<String>()

        func add(_ item: ReminderItem, depth: Int) {
            guard visited.insert(item.id).inserted else { return }
            var copy = item
            copy.depth = depth
            result.append(copy)
            for child in children[item.id] ?? [] { add(child, depth: depth + 1) }
        }
        for item in self where !hasParentHere(item) { add(item, depth: 0) }
        // Items whose parents point at each other have no top level; show them rather than drop them.
        for item in self where !visited.contains(item.id) { add(item, depth: 0) }
        return result
    }

    // MARK: Comparison helpers

    private static func byTitle(_ a: ReminderItem, _ b: ReminderItem) -> Bool {
        a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    private static func byPriority(_ a: ReminderItem, _ b: ReminderItem, then fallback: () -> Bool) -> Bool {
        a.priorityRank != b.priorityRank ? a.priorityRank < b.priorityRank : fallback()
    }

    /// Earlier dates first, dated before undated, `fallback` when equal.
    private static func isOrdered(_ a: Date?, _ b: Date?, then fallback: () -> Bool) -> Bool {
        switch (a, b) {
        case let (x?, y?) where x != y: x < y
        case (_?, nil): true
        case (nil, _?): false
        default: fallback()
        }
    }
}
