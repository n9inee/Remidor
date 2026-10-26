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
        guard let key = firstUUID(in: "\(parentObjectID)"),
              key != reminder.calendarItemIdentifier.uppercased() else { return nil }
        return known[key]
    }

    /// Whether the reminder is flagged in the Reminders app.
    nonisolated static func isFlagged(_ reminder: EKReminder) -> Bool {
        guard let rem = reminderObject(of: reminder),
              let context = object(rem, "flaggedContext"),
              context.responds(to: NSSelectorFromString("flagged")) else { return false }
        return (context.value(forKey: "flagged") as? Bool) ?? false
    }

    /// A ReminderKit save request, the object that collects changes and writes them together.
    nonisolated private static func saveRequest(in store: EKEventStore) -> NSObject? {
        guard let reminderStore = object(store, "reminderStore"),
              let remStore = object(reminderStore, "remStore"),
              let requestClass = NSClassFromString("REMSaveRequest") as? NSObject.Type,
              let allocated = requestClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
              allocated.responds(to: NSSelectorFromString("initWithStore:")) else { return nil }
        return allocated.perform(NSSelectorFromString("initWithStore:"), with: remStore)?.takeUnretainedValue() as? NSObject
    }

    nonisolated private static func commit(_ request: NSObject) -> Bool {
        let save = NSSelectorFromString("saveSynchronouslyWithError:")
        guard request.responds(to: save), let implementation = request.method(for: save) else { return false }
        typealias SaveFunction = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
        var error: NSError?
        return unsafeBitCast(implementation, to: SaveFunction.self)(request, save, &error)
    }

    /// A change item for an object, through which it can be edited in the request.
    nonisolated private static func changeItem(_ selector: String, for object: NSObject, in request: NSObject) -> NSObject? {
        guard request.responds(to: NSSelectorFromString(selector)) else { return nil }
        return request.perform(NSSelectorFromString(selector), with: object)?.takeUnretainedValue() as? NSObject
    }

    /// Flags or unflags a reminder that has already been saved. Returns false if that wasn't possible.
    nonisolated static func setFlagged(_ flagged: Bool, for reminder: EKReminder, in store: EKEventStore) -> Bool {
        guard let rem = reminderObject(of: reminder),
              let request = saveRequest(in: store),
              let change = changeItem("updateReminder:", for: rem, in: request),
              let context = object(change, "flaggedContext"),
              context.responds(to: NSSelectorFromString("setFlagged:")) else { return false }

        context.setValue(flagged, forKey: "flagged")
        return commit(request)
    }

    /// Moves a reminder next to another one in the list's own arrangement, the order shown by
    /// Manual sorting. Both must be in the same list. Returns false if that wasn't possible.
    nonisolated static func move(_ reminder: EKReminder, nextTo anchor: EKReminder, after: Bool, in store: EKEventStore) -> Bool {
        guard let rem = reminderObject(of: reminder),
              let anchorRem = reminderObject(of: anchor),
              let list = object(rem, "list"),
              let request = saveRequest(in: store),
              let listChange = changeItem("updateList:", for: list, in: request),
              let moving = changeItem("updateReminder:", for: rem, in: request),
              let target = changeItem("updateReminder:", for: anchorRem, in: request) else { return false }

        let insert = NSSelectorFromString(after ? "insertReminderChangeItem:afterReminderChangeItem:"
                                                : "insertReminderChangeItem:beforeReminderChangeItem:")
        guard listChange.responds(to: insert) else { return false }
        _ = listChange.perform(insert, with: moving, with: target)
        return commit(request)
    }

    // MARK: Manual order and sections

    /// The position of every reminder in the arrangement the user made in the Reminders app, by upper-cased
    /// `calendarItemIdentifier`.
    nonisolated static func manualOrder(of calendar: EKCalendar) -> [String: Int] {
        guard let list = object(calendar, "backingObject").flatMap({ object($0, "REMObject") }),
              let ordering = object(list, "reminderIDsOrdering") else { return [:] }
        var order: [String: Int] = [:]
        // Each entry is a ReminderKit object ID, which reads like x-apple-reminderkit://REMCDReminder/<UUID>.
        for (index, id) in ((ordering as? NSOrderedSet)?.array ?? []).enumerated() {
            if let uuid = firstUUID(in: "\(id)") { order[uuid] = order[uuid] ?? index }
        }
        return order
    }

    /// A named group inside a list, like "Food" in a shopping list.
    struct ListSection {
        let id: String
        let title: String
        let index: Int
    }

    /// Looks up which section of its list a reminder belongs to.
    final class SectionLookup {
        fileprivate let dataView: NSObject
        fileprivate let sections: [String: ListSection]

        fileprivate init(dataView: NSObject, sections: [String: ListSection]) {
            self.dataView = dataView
            self.sections = sections
        }

        func section(of reminder: EKReminder) -> ListSection? {
            guard let id = ReminderKit.reminderObject(of: reminder).flatMap({ ReminderKit.object($0, "remObjectID") }),
                  let section = ReminderKit.call(dataView, "fetchListSectionWithReminderID:error:", with: id),
                  let uuid = ReminderKit.sectionUUID(section) else { return nil }
            return sections[uuid]
        }
    }

    /// The sections of every list that has any, ready to look reminders up in. nil if there are none or
    /// ReminderKit doesn't answer.
    nonisolated static func sectionLookup(for calendars: [EKCalendar], in store: EKEventStore) -> [String: SectionLookup] {
        guard let reminderStore = object(store, "reminderStore"),
              let remStore = object(reminderStore, "remStore"),
              let viewClass = NSClassFromString("REMListSectionsDataView") as? NSObject.Type,
              let allocated = viewClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
              allocated.responds(to: NSSelectorFromString("initWithStore:")),
              let dataView = allocated.perform(NSSelectorFromString("initWithStore:"), with: remStore)?.takeUnretainedValue() as? NSObject
        else { return [:] }

        var lookups: [String: SectionLookup] = [:]
        for calendar in calendars {
            guard let list = object(calendar, "backingObject").flatMap({ object($0, "REMObject") }),
                  let context = object(list, "sectionContext"),
                  context.responds(to: NSSelectorFromString("hasSections")),
                  (context.value(forKey: "hasSections") as? Bool) == true,
                  let found = call(remStore, "fetchListSectionsForListSectionContext:error:", with: context) as? [NSObject]
            else { continue }
            var sections: [String: ListSection] = [:]
            for (index, section) in found.enumerated() {
                guard let uuid = sectionUUID(section),
                      let title = object(section, "storage").flatMap({ $0.value(forKey: "displayName") as? String })
                else { continue }
                sections[uuid] = ListSection(id: uuid, title: title, index: index)
            }
            if !sections.isEmpty { lookups[calendar.calendarIdentifier] = SectionLookup(dataView: dataView, sections: sections) }
        }
        return lookups
    }

    nonisolated fileprivate static func sectionUUID(_ section: NSObject) -> String? {
        object(section, "remObjectID").flatMap { firstUUID(in: "\($0)") }
    }

    nonisolated private static func firstUUID(in text: String) -> String? {
        guard let match = uuidPattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range]).uppercased()
    }

    /// Calls `selector(argument, error:)`, which returns an object. nil on failure, including the normal
    /// "this reminder isn't in a section" answer.
    nonisolated fileprivate static func call(_ target: NSObject, _ selector: String, with argument: NSObject) -> NSObject? {
        let sel = NSSelectorFromString(selector)
        guard target.responds(to: sel), let implementation = target.method(for: sel) else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>) -> AnyObject?
        var error: NSError?
        return unsafeBitCast(implementation, to: Function.self)(target, sel, argument, &error) as? NSObject
    }

    /// Makes a reminder the last sub-task of another one. Both must be in the same list, the parent must
    /// not be a sub-task itself, and the reminder must not have sub-tasks of its own.
    nonisolated static func makeSubtask(_ child: EKReminder, of parent: EKReminder, in store: EKEventStore) -> Bool {
        guard let childRem = reminderObject(of: child),
              let parentRem = reminderObject(of: parent),
              let request = saveRequest(in: store),
              let childChange = changeItem("updateReminder:", for: childRem, in: request),
              let parentChange = changeItem("updateReminder:", for: parentRem, in: request),
              let context = object(parentChange, "subtaskContext"),
              context.responds(to: NSSelectorFromString("addReminderChangeItem:")) else { return false }
        _ = context.perform(NSSelectorFromString("addReminderChangeItem:"), with: childChange)
        return commit(request)
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
