//
//  DropResolver.swift
//  Remidor
//
//  Created by n9ine on 26.10.2026.
//

import SwiftUI

/// What letting go would do, and the area to light up for it.
struct DropTarget {
    let action: DropAction
    let rect: CGRect
}

/// Works out what is under the mouse while something is carried around the dropdown. It only reads the
/// lists and where everything is drawn, so it can be tested without any views.
struct DropResolver {
    let sections: [ReminderSection]
    let collapsedLists: Set<String>
    let collapsedParents: Set<String>
    let collapsedSections: Set<String>
    let frames: RowFrames
    let hasSubtasks: (ReminderItem) -> Bool
    var now = Date()

    // MARK: Reminders

    func target(moving: ReminderItem, at location: CGPoint) -> DropTarget? {
        for section in sections {
            if let rect = frames.headers[section.id], rect.contains(location) {
                return action(for: moving, on: section.list, row: nil, fraction: 0.5).map { DropTarget(action: $0, rect: rect) }
            }
            guard !collapsedLists.contains(section.id) else { continue }
            for entry in section.entries(foldedParents: collapsedParents, foldedSections: collapsedSections) {
                switch entry {
                case .heading(let info, _, _):
                    // A section's heading takes reminders of its own list, and moves those of other lists over.
                    guard !section.list.isSmart, let rect = frames.headings[section.id + "|" + info.id], rect.contains(location) else { continue }
                    if moving.listID != section.list.id { return DropTarget(action: .move(section.list), rect: frames.headers[section.id] ?? rect) }
                    guard moving.sectionID != info.id else { return nil }
                    return DropTarget(action: .section(id: info.id, title: info.title), rect: rect)
                case .noSection:
                    // The title over reminders without a section takes reminders of its own list out of their section.
                    guard !section.list.isSmart, let rect = frames.headings[section.id + "|none"], rect.contains(location) else { continue }
                    if moving.listID != section.list.id { return DropTarget(action: .move(section.list), rect: frames.headers[section.id] ?? rect) }
                    guard moving.sectionID != nil else { return nil }
                    return DropTarget(action: .section(id: nil, title: nil), rect: rect)
                case .item(let item):
                    guard let rect = frames.rows[section.id + "|" + item.id], rect.contains(location) else { continue }
                    let fraction = rect.height > 0 ? (location.y - rect.minY) / rect.height : 0.5
                    guard let result = action(for: moving, on: section.list, row: item, fraction: fraction) else { return nil }
                    switch result {
                    case .reorder, .subtask, .promote:
                        return DropTarget(action: result, rect: rect)
                    case .section(let id, _):
                        // Moving to another section lights up that section's heading.
                        let heading = id.flatMap { frames.headings[section.id + "|" + $0] }
                        return DropTarget(action: result, rect: heading ?? frames.headers[section.id] ?? rect)
                    default:
                        // Moving to a list, flagging and Today belong to the list, so its name lights up, not the reminder.
                        return DropTarget(action: result, rect: frames.headers[section.id] ?? rect)
                    }
                }
            }
        }
        return nil
    }

    /// `fraction` is how far down the row the mouse is: the edges place the reminder before or after it,
    /// the middle makes it a sub-task.
    private func action(for moving: ReminderItem, on list: ReminderList, row target: ReminderItem?, fraction: CGFloat) -> DropAction? {
        if list.isSmart {
            let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
            if list.id == SmartList.flagged.id { return moving.isFlagged ? nil : .flag }
            if list.id == SmartList.today.id { return (moving.due ?? .distantFuture) < endOfToday ? nil : .today }
            return nil   // Scheduled and All take nothing
        }
        if moving.listID != list.id { return .move(list) }
        let isChild = moving.parentID != nil

        // The list's name: out of its section, or out of its parent.
        guard let target else {
            if isChild { return .promote(nextTo: nil, after: true) }
            return moving.sectionID == nil ? nil : .section(id: nil, title: nil)
        }
        guard moving.id != target.id, target.parentID == nil else { return nil }

        let middle = (0.28...0.72).contains(fraction)
        if isChild {
            if target.id == moving.parentID { return middle ? nil : .promote(nextTo: target, after: fraction >= 0.5) }
            return middle ? .subtask(of: target) : .promote(nextTo: target, after: fraction >= 0.5)
        }
        if moving.sectionID != target.sectionID { return .section(id: target.sectionID, title: target.sectionTitle) }
        if middle, !hasSubtasks(moving) { return .subtask(of: target) }
        return .reorder(target: target, after: fraction >= 0.5)
    }

    // MARK: Sections

    /// Where a carried section would land among the other sections of its list, and where to draw the line.
    func sectionSlot(moving section: ReminderKit.ListSection, in listID: String, at location: CGPoint) -> (index: Int, lineY: CGFloat)? {
        guard let list = sections.first(where: { $0.id == listID }) else { return nil }
        let others = list.sections.filter { $0.id != section.id }
        let rects = others.compactMap { frames.headings[list.id + "|" + $0.id] }
        guard rects.count == others.count else { return nil }
        let index = rects.filter { $0.midY < location.y }.count
        if index < rects.count { return (index, rects[index].minY - 3) }
        // After the last section: below its reminders.
        let prefix = list.id + "|"
        let bottom = (frames.rows.filter { $0.key.hasPrefix(prefix) }.map(\.value.maxY) + rects.map(\.maxY)).max() ?? 0
        return (index, bottom + 2)
    }

    // MARK: Lists

    /// Where a carried list would land: next to which other list, and where to draw the line.
    func listSlot(moving listID: String, at location: CGPoint) -> (target: String, after: Bool, lineY: CGFloat)? {
        let others = sections.filter { $0.id != listID }
        let rects = others.compactMap { frames.headers[$0.id] }
        guard !others.isEmpty, rects.count == others.count else { return nil }
        let index = rects.filter { $0.midY < location.y }.count
        if index < others.count { return (others[index].id, false, rects[index].minY - 6) }
        // After the last list: below everything it shows.
        let everything = frames.rows.values.map(\.maxY) + frames.headings.values.map(\.maxY) + rects.map(\.maxY)
        return (others[others.count - 1].id, true, (everything.max() ?? 0) + 3)
    }
}
