//
//  ReminderKit.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import EventKit
import Foundation

/// Sub-tasks, tags and flags aren't part of EventKit's public API. Every `EKReminder` wraps a ReminderKit
/// object, reachable through the `backingObject` / `REMObject` keys, that knows its parent reminder
/// and its hashtags, and a flag. Reading is defensive: when a key is missing, a reminder simply counts
/// as a top-level, untagged, unflagged task. Writing a flag goes through ReminderKit's own save request,
/// the same path EventKit uses to save a reminder.
enum ReminderKit {
    nonisolated private static func object(_ owner: NSObject, _ key: String) -> NSObject? {
        guard owner.responds(to: NSSelectorFromString(key)) else { return nil }
        return owner.value(forKey: key) as? NSObject
    }

    nonisolated private static func reminderObject(of reminder: EKReminder) -> NSObject? {
        object(reminder, "backingObject").flatMap { object($0, "REMObject") }
    }

    /// A UUID, as it appears in a ReminderKit object ID.
    nonisolated private static let uuidPattern = try? NSRegularExpression(
        pattern: "[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}")

    /// The `calendarItemIdentifier` of the reminder's parent, if that parent was fetched too.
    /// `known` maps every fetched identifier, upper-cased, to its original spelling, which keeps the
    /// lookup quick for long lists.
    nonisolated static func parentIdentifier(of reminder: EKReminder, known: [String: String]) -> String? {
        guard let rem = reminderObject(of: reminder),
              let parent = object(rem, "parentReminder"),
              parent.responds(to: NSSelectorFromString("remObjectID")),
              let parentObjectID = parent.value(forKey: "remObjectID") else { return nil }
        // The object ID reads like x-apple-reminderkit://REMCDReminder/<UUID>, and the UUID is the
        // parent's calendarItemIdentifier.
        let description = "\(parentObjectID)"
        guard let match = uuidPattern?.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let range = Range(match.range, in: description) else { return nil }
        let key = String(description[range]).uppercased()
        guard key != reminder.calendarItemIdentifier.uppercased() else { return nil }
        return known[key]
    }

    /// Whether the reminder is flagged in the Reminders app.
    nonisolated static func isFlagged(_ reminder: EKReminder) -> Bool {
        guard let rem = reminderObject(of: reminder),
              let context = object(rem, "flaggedContext"),
              context.responds(to: NSSelectorFromString("flagged")) else { return false }
        return (context.value(forKey: "flagged") as? Bool) ?? false
    }

    /// Flags or unflags a reminder that has already been saved. Returns false if that wasn't possible.
    nonisolated static func setFlagged(_ flagged: Bool, for reminder: EKReminder, in store: EKEventStore) -> Bool {
        guard let rem = reminderObject(of: reminder),
              let reminderStore = object(store, "reminderStore"),
              let remStore = object(reminderStore, "remStore"),
              let requestClass = NSClassFromString("REMSaveRequest") as? NSObject.Type,
              let allocated = requestClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
              allocated.responds(to: NSSelectorFromString("initWithStore:")),
              let request = allocated.perform(NSSelectorFromString("initWithStore:"), with: remStore)?.takeUnretainedValue() as? NSObject,
              request.responds(to: NSSelectorFromString("updateReminder:")),
              let change = request.perform(NSSelectorFromString("updateReminder:"), with: rem)?.takeUnretainedValue() as? NSObject,
              let context = object(change, "flaggedContext"),
              context.responds(to: NSSelectorFromString("setFlagged:")) else { return false }

        context.setValue(flagged, forKey: "flagged")

        let save = NSSelectorFromString("saveSynchronouslyWithError:")
        guard request.responds(to: save), let implementation = request.method(for: save) else { return false }
        typealias SaveFunction = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> Bool
        var error: NSError?
        return unsafeBitCast(implementation, to: SaveFunction.self)(request, save, &error)
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
