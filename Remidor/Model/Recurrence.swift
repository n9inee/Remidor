//
//  Recurrence.swift
//  Remidor
//
//  Created by n9ine on 26.10.2026.
//

import EventKit
import Foundation

/// How a reminder repeats: every so many days, weeks, months or years, on certain weekdays for weekly ones.
struct Recurrence: Equatable {
    /// How often a repeat comes round.
    enum Frequency: Equatable {
        case daily, weekly, monthly, yearly
    }

    var frequency: Frequency
    var interval = 1
    /// For weekly repeats: 1 is Sunday through 7 is Saturday. Empty means "the same day each time".
    var weekdays: [Int] = []

    static let weekdaysOnly = Recurrence(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])
    static let weekendsOnly = Recurrence(frequency: .weekly, weekdays: [1, 7])

    // MARK: Text

    private static let shortNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// "Daily", "Every Sunday", "Every 2 weeks" and so on.
    var label: String {
        switch frequency {
        case .daily: return interval == 1 ? "Daily" : "Every \(interval) days"
        case .monthly: return interval == 1 ? "Monthly" : "Every \(interval) months"
        case .yearly: return interval == 1 ? "Yearly" : "Every \(interval) years"
        case .weekly:
            let days = weekdays.sorted()
            if interval == 1 {
                if days.isEmpty { return "Weekly" }
                if days == Self.weekdaysOnly.weekdays { return "Weekdays" }
                if days == Self.weekendsOnly.weekdays { return "Weekends" }
            }
            let names = days.compactMap { Self.shortNames.indices.contains($0) ? Self.shortNames[$0] : nil }.joined(separator: ", ")
            let base = interval == 1 ? "Every" : "Every \(interval) weeks:"
            return names.isEmpty ? "Every \(interval) weeks" : "\(base) \(names)"
        }
    }

    /// The label without the leading "Every", for places with little room.
    var shortLabel: String {
        label.hasPrefix("Every ") ? String(label.dropFirst("Every ".count)) : label
    }

    // MARK: EventKit

    init(frequency: Frequency, interval: Int = 1, weekdays: [Int] = []) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.weekdays = weekdays.sorted()
    }

    init?(rule: EKRecurrenceRule) {
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: return nil
        }
        interval = max(rule.interval, 1)
        weekdays = frequency == .weekly ? (rule.daysOfTheWeek ?? []).map(\.dayOfTheWeek.rawValue).sorted() : []
    }

    func makeRule() -> EKRecurrenceRule {
        let ekFrequency: EKRecurrenceFrequency = switch frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let days = weekdays.compactMap(EKWeekday.init(rawValue:)).map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(recurrenceWith: ekFrequency, interval: interval,
                                daysOfTheWeek: days.isEmpty ? nil : days,
                                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                daysOfTheYear: nil, setPositions: nil, end: nil)
    }

    // MARK: Dates

    /// The first day on or after `date` that fits the repeat's weekdays, keeping the time of day.
    /// Repeats without weekdays leave the date alone.
    func firstOccurrence(onOrAfter date: Date, hasTime: Bool) -> Date {
        guard frequency == .weekly, !weekdays.isEmpty else { return date }
        let calendar = Calendar.current
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            return hasTime ? day : calendar.startOfDay(for: day)
        }
        return date
    }
}
