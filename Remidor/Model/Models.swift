//
//  Models.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// An open reminder as shown in the menu.
struct ReminderItem: Identifiable, Equatable {
    let id: String
    var title: String
    var listID: String
    var listTitle: String
    var listColor: Color
    var due: Date?
    var dueHasTime = false          // false for date-only reminders
    var isRepeating = false         // completing a repeating reminder moves it to its next date instead
    var recurrence: Recurrence?     // how it repeats, when that fits the shapes Remidor knows
    var isFlagged = false
    var priority = 0                // EventKit scale: 0 none, 1-4 high, 5 medium, 6-9 low
    var created: Date?
    var notes: String?
    var url: URL?
    var tags: [String] = []         // Reminders tags, without the leading #
    var parentID: String?           // id of the parent reminder, for sub-tasks
    var depth = 0                   // 0 = top level, 1 = sub-task
    var childCount = 0              // open sub-tasks directly below this reminder
    var manualIndex = Int.max       // position in the list's own arrangement in Reminders
    var sectionIndex = -1           // position of the list section it sits in, -1 for none
    var sectionTitle: String?       // name of that section
    var sectionID: String?          // identifies that section

    /// Lower sorts first; reminders without a priority come last.
    var priorityRank: Int { priority == 0 ? 10 : priority }

    /// High (1), medium (5), low (9) or none (0).
    var priorityBucket: Int { priorityLevel(of: priority) }
}

/// Reminders counts 1-4 as high, 5 as medium and 6-9 as low, and only ever writes 1, 5 and 9. Other apps can
/// write the values in between, so this maps any of them to the level it counts as: 1, 5, 9 or 0 for none.
func priorityLevel(of priority: Int) -> Int {
    switch priority {
    case 1...4: 1
    case 5: 5
    case 6...9: 9
    default: 0
    }
}

/// How a typed date such as 5.10. is read: day first (5 October) or month first (10 May).
enum DateOrder: String, CaseIterable, Identifiable {
    case dayFirst, monthFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dayFirst: "Day first (31.12.2026)"
        case .monthFirst: "Month first (12/31/2026)"
        }
    }

    /// The order the Mac's region writes dates in.
    static var systemDefault: DateOrder {
        let template = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: .current) ?? "M/d/y"
        if let day = template.firstIndex(of: "d"), let month = template.firstIndex(of: "M"), day < month { return .dayFirst }
        return .monthFirst
    }
}

/// A list shown in the dropdown: one of the Reminders lists or a built-in smart list.
struct ReminderList: Identifiable {
    let id: String
    let title: String
    let color: Color
    var isSmart = false

    /// The SF Symbol shown next to the list's name.
    var symbol: String {
        if id == SmartList.flagged.id { return "flag.fill" }
        return isSmart ? "sparkles" : "list.bullet"
    }
}

/// A list with the reminders it shows, and its sections if it has any.
struct ReminderSection: Identifiable {
    let list: ReminderList
    let items: [ReminderItem]
    /// The list's own sections, empty ones included, in order. Only regular lists have them.
    var sections: [ReminderKit.ListSection] = []
    var id: String { list.id }
    /// How many of its reminders are late.
    var overdueCount: Int { items.filter { isOverdue($0) }.count }
}

/// Built-in lists that EventKit doesn't expose; Remidor recreates them from due dates.
enum SmartList {
    static let today = ReminderList(id: "smart.today", title: "Today", color: .blue, isSmart: true)
    static let scheduled = ReminderList(id: "smart.scheduled", title: "Scheduled", color: .red, isSmart: true)
    static let nextUp = ReminderList(id: "smart.nextup", title: "Next Up", color: .purple, isSmart: true)
    static let flagged = ReminderList(id: "smart.flagged", title: "Flagged", color: .orange, isSmart: true)
    static let all = ReminderList(id: "smart.all", title: "All", color: .gray, isSmart: true)
    static let allLists = [today, nextUp, scheduled, flagged, all]

    /// The fewest reminders that aren't late yet Next Up shows after the late ones, rounded up to whole days.
    static let nextUpCount = 5

    /// Whether a reminder can be added straight to the list. Scheduled and Next Up can't, since they only show what has a date.
    static func canAdd(to list: ReminderList) -> Bool {
        list.id != scheduled.id && list.id != nextUp.id
    }

    /// Smart lists that always sort by due time, then priority.
    static func sortsByTime(_ list: ReminderList) -> Bool {
        list.id == today.id || list.id == nextUp.id || list.id == scheduled.id
    }
}

/// How reminders are ordered within a list.
enum SortOrder: String, CaseIterable, Identifiable {
    case manual, dueDate, priority, title, creationDate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .dueDate: "Due date"
        case .priority: "Priority"
        case .title: "Title"
        case .creationDate: "Creation date"
        }
    }
}

/// What the quick-add box asks the model to create.
struct NewReminder {
    let title: String
    let due: Date?
    let hasTime: Bool
    let priority: Int?
    let flagged: Bool
    let listID: String?
    var recurrence: Recurrence?
}

/// The focus-timer flow shown in the menu bar.
enum Phase: Equatable {
    case idle
    case choosing(ReminderItem)
    case running(ReminderItem, end: Date)
    case finished(ReminderItem)
}
