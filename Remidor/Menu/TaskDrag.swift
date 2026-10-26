//
//  TaskDrag.swift
//  Remidor
//
//  Created by n9ine on 26.10.2026.
//

import SwiftUI

/// A reminder being carried around the dropdown with the mouse.
struct TaskDrag {
    var item: ReminderItem
    /// The list section it was picked up in.
    var sectionID: String
    /// Where the mouse was when it was picked up, and where it is now, measured in the scrolled content.
    var start: CGPoint
    var location: CGPoint

    /// How far the row has been carried. It includes any scrolling done on the way.
    var translation: CGSize { CGSize(width: location.x - start.x, height: location.y - start.y) }
}

/// What letting go of a carried reminder would do.
enum DropAction {
    /// Takes the place next to a reminder of the same list, which puts the list in manual order.
    case reorder(target: ReminderItem, after: Bool)
    /// Moves to another list, where it is sorted like the rest.
    case move(ReminderList)
    /// Dropped on Flagged.
    case flag
    /// Dropped on Today.
    case today
    /// Dropped on the middle of another reminder: becomes its sub-task.
    case subtask(of: ReminderItem)

    var label: String {
        switch self {
        case .reorder: ""
        case .move: "Move here"
        case .flag: "Flag it"
        case .today: "Due today"
        case .subtask: "Make sub-task"
        }
    }
}

/// Where each list name and row currently is, so a drag can find what is under the mouse. A plain
/// reference, because these positions change all the time and nothing needs redrawing for it.
final class RowFrames {
    var headers: [String: CGRect] = [:]
    var rows: [String: CGRect] = [:]
}

/// Reaches the AppKit scroll view behind the list. It reads the mouse position in the scrolled content,
/// which SwiftUI's own drag gesture reports badly while the dragged row moves, and scrolls the list
/// when a reminder is carried to its top or bottom edge.
final class ScrollHandle {
    weak var scrollView: NSScrollView?

    private var documentHeight: CGFloat { scrollView?.documentView?.bounds.height ?? 0 }
    private var isFlipped: Bool { scrollView?.documentView?.isFlipped ?? true }

    /// The mouse in content coordinates, with y growing downward from the top of the content.
    var pointer: CGPoint? {
        guard let scrollView, let window = scrollView.window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = scrollView.contentView.convert(inWindow, from: nil)
        return CGPoint(x: point.x, y: isFlipped ? point.y : documentHeight - point.y)
    }

    /// How far down the content has been scrolled.
    var offset: CGFloat {
        guard let clip = scrollView?.contentView else { return 0 }
        return isFlipped ? clip.bounds.origin.y : documentHeight - clip.bounds.maxY
    }

    var viewportHeight: CGFloat { scrollView?.contentView.bounds.height ?? 0 }

    /// Scrolls by `delta` points (positive goes down), never past either end.
    func scroll(by delta: CGFloat) {
        guard let scrollView else { return }
        let target = min(max(offset + delta, 0), max(documentHeight - viewportHeight, 0))
        var origin = scrollView.contentView.bounds.origin
        origin.y = isFlipped ? target : documentHeight - viewportHeight - target
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
