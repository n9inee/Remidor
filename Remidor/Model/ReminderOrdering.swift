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
            case .manual: a.manualIndex != b.manualIndex ? a.manualIndex < b.manualIndex : Self.byTitle(a, b)
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

    /// Groups the items by the section they sit in, keeping the order inside each section. Items that
    /// aren't in a section come last.
    func groupedBySection() -> [ReminderItem] {
        func rank(_ item: ReminderItem) -> Int { item.sectionIndex < 0 ? .max : item.sectionIndex }
        return enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// Without the sub-tasks of the parents that are folded shut.
    func hidingFoldedSubtasks(_ folded: Set<String>) -> [ReminderItem] {
        guard !folded.isEmpty else { return self }
        return filter { item in item.depth == 0 || !(item.parentID.map(folded.contains) ?? false) }
    }

    /// Puts each sub-task directly under its parent. A sub-task whose parent isn't in this list stays top-level.
    func nestingSubtasks() -> [ReminderItem] {
        let ids = Set(map(\.id))
        func hasParentHere(_ item: ReminderItem) -> Bool { item.parentID.map(ids.contains) ?? false }

        let children = Dictionary(grouping: filter(hasParentHere)) { $0.parentID! }
        var result: [ReminderItem] = []
        var visited = Set<String>()

        func add(_ item: ReminderItem, depth: Int, in parent: ReminderItem? = nil) {
            guard visited.insert(item.id).inserted else { return }
            var copy = item
            copy.depth = depth
            copy.childCount = children[item.id]?.count ?? 0
            // A sub-task sits in its parent's section.
            if let parent {
                copy.sectionIndex = parent.sectionIndex
                copy.sectionTitle = parent.sectionTitle
                copy.sectionID = parent.sectionID
            }
            result.append(copy)
            for child in children[item.id] ?? [] { add(child, depth: depth + 1, in: copy) }
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

/// One row of a list as shown in the dropdown: a section's heading or a reminder.
enum ListEntry: Identifiable {
    case heading(ReminderKit.ListSection, count: Int, folded: Bool)
    /// The title over the reminders that are in no section, which come after all the sections.
    case noSection
    case item(ReminderItem)

    var id: String {
        switch self {
        case .heading(let section, _, _): "section:" + section.id
        case .noSection: "section:none"
        case .item(let item): item.id
        }
    }
}

extension ReminderSection {
    /// The rows in the order shown: each section's heading with its reminders under it, then the reminders
    /// that are in no section under a heading of their own. Folded sections show only their heading. Lists
    /// without sections are plain reminders.
    func entries(foldedParents: Set<String>, foldedSections: Set<String>) -> [ListEntry] {
        let visible = items.hidingFoldedSubtasks(foldedParents)
        guard !list.isSmart, !sections.isEmpty else { return visible.map(ListEntry.item) }
        let known = Set(sections.map(\.id))
        var result: [ListEntry] = []
        for section in sections {
            let inside = visible.filter { $0.sectionID == section.id }
            let folded = foldedSections.contains(section.id)
            result.append(.heading(section, count: inside.count, folded: folded))
            if !folded { result += inside.map(ListEntry.item) }
        }
        let loose = visible.filter { !($0.sectionID.map(known.contains) ?? false) }
        if !loose.isEmpty {
            result.append(.noSection)
            result += loose.map(ListEntry.item)
        }
        return result
    }
}
