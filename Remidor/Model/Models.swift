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
}

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

struct ReminderSection: Identifiable {
    let list: ReminderList
    let items: [ReminderItem]
    var id: String { list.id }
}

/// Built-in lists that EventKit doesn't expose; Remidor recreates them from due dates.
enum SmartList {
    static let today = ReminderList(id: "smart.today", title: "Today", color: .blue, isSmart: true)
    static let scheduled = ReminderList(id: "smart.scheduled", title: "Scheduled", color: .red, isSmart: true)
    static let flagged = ReminderList(id: "smart.flagged", title: "Flagged", color: .orange, isSmart: true)
    static let all = ReminderList(id: "smart.all", title: "All", color: .gray, isSmart: true)
    static let allLists = [today, scheduled, flagged, all]

    /// Smart lists that always sort by due time, then priority.
    static func sortsByTime(_ list: ReminderList) -> Bool {
        list.id == today.id || list.id == scheduled.id
    }
}

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
