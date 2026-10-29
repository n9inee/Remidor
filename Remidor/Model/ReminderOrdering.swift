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

    /// Everything late, then whole days of what is still to come: days are added until `minimum` reminders
    /// are showing, and a day is never cut short.
    func nextUp(minimum: Int, now: Date = Date()) -> [ReminderItem] {
        let dated = filter { $0.due != nil }.sortedByDueTime()
        let late = dated.filter { isOverdue($0, now: now) }
        let coming = dated.filter { !isOverdue($0, now: now) }
        let calendar = Calendar.current
        guard minimum > 0 else { return late }
        guard coming.count > minimum, let last = coming[minimum - 1].due else { return late + coming }
        // The last reminder that fits sets the final day; everything on that day comes along.
        let end = calendar.startOfDay(for: last)
        return late + coming.prefix { calendar.startOfDay(for: $0.due ?? .distantFuture) <= end }
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
    /// Sub-tasks keep the order of the list, unless `childOrder` names an order of their own for a parent.
    func nestingSubtasks(childOrder: (String) -> SortOrder? = { _ in nil }) -> [ReminderItem] {
        let ids = Set(map(\.id))
        func hasParentHere(_ item: ReminderItem) -> Bool { item.parentID.map(ids.contains) ?? false }

        var children = Dictionary(grouping: filter(hasParentHere)) { $0.parentID! }
        for (parent, items) in children {
            if let order = childOrder(parent) { children[parent] = items.sorted(by: order) }
        }
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
    /// A title over a group of reminders in Today, Next Up and Scheduled: "Overdue", a part of the day or a day. A label only: it can't be picked, folded or dragged.
    case day(title: String, isOverdue: Bool, key: String)

    var id: String {
        switch self {
        case .day(_, _, let key): "day:" + key
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
    func entries(foldedParents: Set<String>, foldedSections: Set<String>, now: Date = Date()) -> [ListEntry] {
        let visible = items.hidingFoldedSubtasks(foldedParents)
        if SmartList.sortsByTime(list) { return timeEntries(of: visible, now: now) }
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

    /// Today, Next Up and Scheduled: everything late under "Overdue", then a title for each part of the day (Today) or
    /// each day. A sub-task stays under its parent. A reminder goes under the title it belongs to wherever it sits in
    /// the list, so a title never shows twice.
    private func timeEntries(of visible: [ReminderItem], now: Date) -> [ListEntry] {
        let calendar = Calendar.current
        let byPartOfDay = list.id == SmartList.today.id
        var groups: [(key: String, title: String, late: Bool, items: [ReminderItem])] = []
        var current: Int?
        for item in visible {
            if item.depth == 0 || current == nil, let due = item.due {
                let late = isOverdue(item, now: now)
                let day = calendar.startOfDay(for: due)
                let (key, title): (String, String) = if late {
                    ("overdue", "Overdue")
                } else if byPartOfDay {
                    partOfDay(of: item)
                } else {
                    (String(day.timeIntervalSinceReferenceDate), dayHeading(for: day, now: now))
                }
                if let existing = groups.firstIndex(where: { $0.key == key }) {
                    current = existing
                } else {
                    groups.append((key, title, late, []))
                    current = groups.count - 1
                }
            }
            if let current { groups[current].items.append(item) }
        }
        // What is late always comes first, the others in the order they came.
        let ordered = groups.filter(\.late) + groups.filter { !$0.late }
        return ordered.flatMap { group in
            [ListEntry.day(title: group.title, isOverdue: group.late, key: group.key)] + group.items.map(ListEntry.item)
        }
    }

    /// Where a reminder due today sits in the day, as in the Reminders app.
    private func partOfDay(of item: ReminderItem) -> (key: String, title: String) {
        guard item.dueHasTime, let due = item.due else { return ("allday", "All-Day") }
        switch Calendar.current.component(.hour, from: due) {
        case ..<12: return ("morning", "Morning")
        case ..<17: return ("afternoon", "Afternoon")
        default: return ("tonight", "Tonight")
        }
    }
}
