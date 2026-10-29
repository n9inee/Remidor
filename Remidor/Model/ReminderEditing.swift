//
//  ReminderEditing.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import EventKit
import Foundation

/// Changes to a reminder's due date, made through EventKit's public API.
enum ReminderEditing {
    /// Sets or clears the due date. A due time gets an alert at that time, like the Reminders app does.
    /// An alert that sat exactly on the old due time moves with it; any other alert is left alone.
    nonisolated static func setDue(_ date: Date?, hasTime: Bool, on reminder: EKReminder) {
        let calendar = Calendar.current
        if let components = reminder.dueDateComponents, components.hour != nil, let oldDue = calendar.date(from: components) {
            for alarm in reminder.alarms ?? [] where alarm.absoluteDate == oldDue { reminder.removeAlarm(alarm) }
        }
        guard let date else {
            reminder.dueDateComponents = nil
            return
        }
        let parts: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        reminder.dueDateComponents = calendar.dateComponents(parts, from: date)
        if hasTime { reminder.addAlarm(EKAlarm(absoluteDate: date)) }
    }

    /// The start of the day after `now`. Not a fixed 24 hours on, since a day is 23 or 25 hours long when the clocks change.
    nonisolated static func startOfTomorrow(after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }

    /// The first day of next week: the next `weekStart` (1 is Sunday ... 7 is Saturday) after today.
    nonisolated static func nextWeekStart(_ weekStart: Int, from now: Date = Date()) -> Date {
        let today = Calendar.current.startOfDay(for: now)
        return day(weekStart, onOrAfter: Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    /// The coming weekend: today when it is the first day of the weekend, otherwise the next one.
    nonisolated static func weekend(startingOn weekendStart: Int, from now: Date = Date()) -> Date {
        day(weekendStart, onOrAfter: Calendar.current.startOfDay(for: now))
    }

    private nonisolated static func day(_ weekday: Int, onOrAfter start: Date) -> Date {
        let calendar = Calendar.current
        let ahead = (weekday - calendar.component(.weekday, from: start) + 7) % 7
        return calendar.date(byAdding: .day, value: ahead, to: start) ?? start
    }

    /// The day with a time on it for when a time is first turned on: the next full hour today, 9:00 on any other day.
    nonisolated static func withDefaultTime(on day: Date, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hour = calendar.isDate(day, inSameDayAs: now) ? min(calendar.component(.hour, from: now) + 1, 23) : 9
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    /// The same time of day on another day. A reminder without a time simply gets the new day.
    nonisolated static func moving(_ due: Date?, hasTime: Bool, toDay day: Date) -> (date: Date, hasTime: Bool) {
        let calendar = Calendar.current
        guard hasTime, let due else { return (calendar.startOfDay(for: day), false) }
        let time = calendar.dateComponents([.hour, .minute], from: due)
        let moved = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day)
        return (moved ?? day, true)
    }

    /// Like `moving`, but never lands in the past: a time that has already gone by on that day is dropped.
    nonisolated static func rescheduling(_ due: Date?, hasTime: Bool, toDay day: Date, now: Date = Date()) -> (date: Date, hasTime: Bool) {
        let moved = moving(due, hasTime: hasTime, toDay: day)
        guard moved.hasTime, moved.date < now else { return moved }
        return (Calendar.current.startOfDay(for: day), false)
    }
}
