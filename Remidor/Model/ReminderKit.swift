//
//  ReminderKit.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import EventKit
import Foundation

/// Sub-tasks and tags aren't part of EventKit's public API. Every `EKReminder` wraps a ReminderKit
/// object, reachable through the `backingObject` / `REMObject` keys, that knows its parent reminder
/// and its hashtags. All lookups are defensive: when a key is missing, a reminder simply counts as
/// a top-level, untagged task.
enum ReminderKit {
    nonisolated private static func object(_ owner: NSObject, _ key: String) -> NSObject? {
        guard owner.responds(to: NSSelectorFromString(key)) else { return nil }
        return owner.value(forKey: key) as? NSObject
    }

    nonisolated private static func reminderObject(of reminder: EKReminder) -> NSObject? {
        object(reminder, "backingObject").flatMap { object($0, "REMObject") }
    }

    /// The `calendarItemIdentifier` of the reminder's parent, if it is a sub-task of one in `all`.
    nonisolated static func parentIdentifier(of reminder: EKReminder, among all: [EKReminder]) -> String? {
        guard let rem = reminderObject(of: reminder),
              let parent = object(rem, "parentReminder"),
              parent.responds(to: NSSelectorFromString("remObjectID")),
              let parentObjectID = parent.value(forKey: "remObjectID") else { return nil }
        // The object ID reads like x-apple-reminderkit://REMCDReminder/<UUID>, and the UUID is the
        // parent's calendarItemIdentifier.
        let description = "\(parentObjectID)"
        return all.first { $0 !== reminder && description.contains($0.calendarItemIdentifier) }?.calendarItemIdentifier
    }

    /// The reminder's tags, sorted by name.
    nonisolated static func tags(of reminder: EKReminder) -> [String] {
        guard let rem = reminderObject(of: reminder),
              rem.responds(to: NSSelectorFromString("hashtags")),
              let hashtags = rem.value(forKey: "hashtags") as? NSSet else { return [] }
        // A REMHashtag prints as "<REMHashtag: … name: queue, creation date: …>".
        let names = hashtags.allObjects.compactMap { tag -> String? in
            let description = "\(tag)"
            guard let range = description.range(of: #"name: .+?(?=, creation date|>)"#, options: .regularExpression) else { return nil }
            return String(description[range].dropFirst("name: ".count))
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
