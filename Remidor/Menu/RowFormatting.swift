//
//  RowFormatting.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

private let tagExpression = try? NSRegularExpression(pattern: #"(?<!\S)#[\p{L}\p{N}_-]+"#)
private let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

/// The title with `#tags` in purple, matching how they look in the add-reminder box.
func taggedTitle(_ title: String) -> AttributedString {
    var result = AttributedString(title)
    let range = NSRange(title.startIndex..., in: title)
    for match in tagExpression?.matches(in: title, range: range) ?? [] {
        guard let bounds = attributedRange(of: match.range, in: title, result: result) else { continue }
        result[bounds].foregroundColor = .purple
        result[bounds].font = .body.weight(.medium)
    }
    return result
}

/// Plain text with URLs turned into links.
func linkified(_ text: String) -> AttributedString {
    var result = AttributedString(text)
    let range = NSRange(text.startIndex..., in: text)
    for match in linkDetector?.matches(in: text, range: range) ?? [] {
        guard let url = match.url, let bounds = attributedRange(of: match.range, in: text, result: result) else { continue }
        result[bounds].link = url
    }
    return result
}

private func attributedRange(of range: NSRange, in text: String, result: AttributedString) -> Range<AttributedString.Index>? {
    guard let swiftRange = Range(range, in: text),
          let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
          let upper = AttributedString.Index(swiftRange.upperBound, within: result) else { return nil }
    return lower..<upper
}

func priorityMarks(_ priority: Int) -> String {
    switch priority {
    case 1...4: "!!! "
    case 5: "!! "
    case 6...9: "! "
    default: ""
    }
}

/// Priority marks in `markColor` followed by the title with its tags highlighted.
func rowTitle(_ item: ReminderItem, markColor: Color) -> AttributedString {
    var marks = AttributedString(priorityMarks(item.priority))
    marks.foregroundColor = markColor
    marks.font = .body.bold()
    return marks + taggedTitle(item.title)
}

/// "Today, 8:00 PM", "Tomorrow", "Mon, Oct 26". Date-only reminders show no time, like the Reminders app.
func describeDue(_ date: Date, hasTime: Bool, includeWeekday: Bool = true) -> String {
    let calendar = Calendar.current
    let day: String
    if calendar.isDateInToday(date) {
        day = "Today"
    } else if calendar.isDateInTomorrow(date) {
        day = "Tomorrow"
    } else if calendar.isDateInYesterday(date) {
        day = "Yesterday"
    } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
        day = includeWeekday
            ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated))
    } else {
        day = date.formatted(.dateTime.day().month(.abbreviated).year())
    }
    return hasTime ? day + ", " + date.formatted(date: .omitted, time: .shortened) : day
}

func dueText(_ item: ReminderItem) -> String? {
    item.due.map { describeDue($0, hasTime: item.dueHasTime) }
}

/// "Today", "Tomorrow", a weekday for the rest of the week, then "Mon, Nov 2". The title over a day in Next Up.
func dayHeading(for date: Date, now: Date = Date()) -> String {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
    switch days {
    case 0: return "Today"
    case 1: return "Tomorrow"
    case 2...6: return date.formatted(.dateTime.weekday(.wide))
    default:
        return calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// A reminder with a time is overdue once that time has passed; a date-only one once its day has.
func isOverdue(_ item: ReminderItem) -> Bool {
    guard let due = item.due else { return false }
    if item.dueHasTime { return due < Date() }
    let calendar = Calendar.current
    return calendar.startOfDay(for: due) < calendar.startOfDay(for: Date())
}
