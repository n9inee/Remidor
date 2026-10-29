//
//  QuickAddParser.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import Foundation

/// Turns "call mom fri at 5pm !!! * ~Family #phone" into a title, due date, priority, flag and list, and
/// reports where each recognized piece sits in the input so the UI can highlight it.
enum QuickAddParser {
    /// What a recognized piece of the text sets.
    enum Kind { case date, priority, flag, list, tag, recurrence }

    /// A recognized piece of the text.
    struct Token {
        let range: NSRange   // UTF-16 range in the original input
        let kind: Kind
    }

    /// What the text adds up to: the title that is left and everything taken out of it.
    struct Result {
        var title = ""
        var priority: Int?      // EventKit scale: 1 high, 5 medium, 9 low
        var flagged = false
        var listName: String?   // canonical name of the matched list
        var due: Date?
        var hasTime = false
        var recurrence: Recurrence?
        var tokens: [Token] = []
    }

    // MARK: Parsing

    static func parse(_ input: String, listNames: [String], weekStart: Int = 2, weekendStart: Int = 7,
                      dateOrder: DateOrder = .dayFirst) -> Result {
        let ns = input as NSString
        let masked = NSMutableString(string: input)   // recognized pieces are blanked out as they're claimed
        var result = Result()
        var stripped: [NSRange] = []                  // pieces removed from the title

        func claim(_ range: NSRange, _ kind: Kind, strip: Bool) {
            result.tokens.append(Token(range: range, kind: kind))
            if strip { stripped.append(range) }
            masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }

        // ~List or ~"My List": only claimed when it matches a real list.
        for match in matches(#"(?<!\S)~(?:"([^"]+)"|(\S+))"#, in: masked as String) {
            let typed = (group(match, 1, in: ns) ?? group(match, 2, in: ns) ?? "").lowercased()
            let list = listNames.first { $0.lowercased() == typed }
                ?? (typed.isEmpty ? nil : listNames.first { $0.lowercased().hasPrefix(typed) })
            if let list, result.listName == nil {
                result.listName = list
                claim(match.range, .list, strip: true)
            }
        }

        // #tags stay in the title but are highlighted.
        for match in matches(#"(?<!\S)#[\p{L}\p{N}_-]+"#, in: masked as String) {
            claim(match.range, .tag, strip: false)
        }

        // A standalone !, !! or !!! sets low, medium or high priority.
        for match in matches(#"(?<!\S)!{1,3}(?!\S)"#, in: masked as String) {
            result.priority = match.range.length >= 3 ? 1 : match.range.length == 2 ? 5 : 9
            claim(match.range, .priority, strip: true)
        }

        // A standalone * flags the reminder.
        for match in matches(#"(?<!\S)\*(?!\S)"#, in: masked as String) {
            result.flagged = true
            claim(match.range, .flag, strip: true)
        }

        // "every sunday", "every 2 weeks", "ev day": claimed before the date, which would read the weekday.
        if let found = parseRecurrence(in: masked as String) {
            result.recurrence = found.recurrence
            claim(found.range, .recurrence, strip: true)
        }

        if let found = parseWeekPhrase(in: masked as String, weekStart: weekStart, weekendStart: weekendStart)
            ?? parseRelativeDate(in: masked as String) ?? parseEndOf(in: masked as String)
            ?? parseNumericDate(in: masked as String, order: dateOrder) ?? parseDate(in: masked)
            ?? parseBareTime(in: masked as String) {
            result.due = found.date
            result.hasTime = found.hasTime
            claim(found.range, .date, strip: true)
        }

        // A repeat needs a first date: the next matching weekday, or today.
        if let recurrence = result.recurrence {
            let base = result.due ?? Date()
            let hasTime = result.due != nil && result.hasTime
            if recurrence.frequency == .weekly, !recurrence.weekdays.isEmpty {
                result.due = recurrence.firstOccurrence(onOrAfter: base, hasTime: hasTime)
            } else if result.due == nil {
                result.due = Calendar.current.startOfDay(for: base)
            }
            result.hasTime = hasTime
        }

        let title = NSMutableString(string: input)
        for range in stripped.sorted(by: { $0.location > $1.location }) {
            title.replaceCharacters(in: range, with: "")
        }
        result.title = (title as String).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return result
    }

    // MARK: Repeats

    private static let everyWord = #"(?<!\S)(?:every|evry|ev)\s+"#
    private static let dayName = #"(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday|s)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)s?"#
    private static let unitWord = #"(?:days?|weeks?|months?|years?)"#
    private static let shortUnit = #"(?:days?|d|weeks?|wks?|w|months?|mos?|years?|yrs?|y)"#
    private static let wordEnd = #"(?![\p{L}\p{N}])"#

    private static func frequency(ofUnit unit: String) -> Recurrence.Frequency {
        switch unit.lowercased().first {
        case "d": .daily
        case "w": .weekly
        case "m": .monthly
        default: .yearly
        }
    }

    /// "every day", "every 3 weeks", "every other month", "every sunday", "every mon and thu", "every weekday".
    private static func parseRecurrence(in text: String) -> (recurrence: Recurrence, range: NSRange)? {
        let ns = text as NSString
        func find(_ pattern: String) -> NSTextCheckingResult? {
            regex(everyWord + pattern + wordEnd, options: .caseInsensitive)?
                .firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        }

        if let m = find("(\\d+)\\s*(" + shortUnit + ")"), let amount = Int(ns.substring(with: m.range(at: 1))), amount > 0 {
            return (Recurrence(frequency: frequency(ofUnit: ns.substring(with: m.range(at: 2))), interval: amount), m.range)
        }
        let dayList = "(" + dayName + "(?:(?:\\s*,\\s*|\\s+and\\s+|\\s*&\\s*|\\s*/\\s*|\\s+)" + dayName + ")*)"
        if let m = find("other\\s+" + dayList) {
            return (Recurrence(frequency: .weekly, interval: 2, weekdays: weekdayNumbers(in: ns.substring(with: m.range(at: 1)))), m.range)
        }
        if let m = find("other\\s+(" + unitWord + ")") {
            return (Recurrence(frequency: frequency(ofUnit: ns.substring(with: m.range(at: 1))), interval: 2), m.range)
        }
        if let m = find("(weekdays?|weekends?)") {
            let isWeekend = ns.substring(with: m.range(at: 1)).lowercased().hasPrefix("weekend")
            return (isWeekend ? .weekendsOnly : .weekdaysOnly, m.range)
        }
        if let m = find(dayList) {
            return (Recurrence(frequency: .weekly, weekdays: weekdayNumbers(in: ns.substring(with: m.range(at: 1)))), m.range)
        }
        if let m = find("(" + unitWord + ")") {
            return (Recurrence(frequency: frequency(ofUnit: ns.substring(with: m.range(at: 1)))), m.range)
        }
        return nil
    }

    /// The weekdays named in "mon and thu", without repeats.
    private static func weekdayNumbers(in names: String) -> [Int] {
        let lowered = names.lowercased()
        let days = matches(dayName, in: lowered).compactMap { weekdayNumber(of: (lowered as NSString).substring(with: $0.range)) }
        return Array(Set(days))
    }

    /// 1 for Sunday through 7 for Saturday.
    private static func weekdayNumber(of name: String) -> Int? {
        ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7][String(name.lowercased().prefix(3))]
    }

    // MARK: Dates

    private typealias DateMatch = (date: Date, hasTime: Bool, range: NSRange)

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Shorthand the system date detector doesn't understand.
    private static let shorthand: [String: String] = [
        "tmr": "tomorrow", "tmrw": "tomorrow", "tmrrw": "tomorrow", "tmmrw": "tomorrow", "tmw": "tomorrow",
        "tomo": "tomorrow", "tomm": "tomorrow", "2moro": "tomorrow", "2morrow": "tomorrow", "2mrw": "tomorrow",
        "tdy": "today", "2day": "today", "2dy": "today", "tonite": "tonight",
        "nxt": "next", "wk": "week", "wks": "weeks", "noon": "12pm", "midnight": "12am",
        "tue": "tuesday", "tues": "tuesday", "thu": "thursday", "thur": "thursday", "thurs": "thursday", "fri": "friday",
    ]
    /// Weekday abbreviations that are also ordinary words, so they only count after one of these.
    private static let weekdayAfter: Set<String> = ["on", "next", "this", "nxt", "by", "every"]
    private static let weekdays = ["mon": "monday", "wed": "wednesday", "sat": "saturday", "sun": "sunday"]
    /// Unit abbreviations that only count right after a number.
    private static let units = ["min": "minutes", "mins": "minutes", "hr": "hours", "hrs": "hours", "h": "hours"]

    private static func normalise(_ word: String, previous: String) -> String {
        let key = word.lowercased()
        if let full = shorthand[key] { return full }
        if let full = weekdays[key], weekdayAfter.contains(previous) { return full }
        if let full = units[key], previous.first?.isNumber == true { return full }
        return word
    }

    private static let numberWords = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                      "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12]

    /// "next week" and "weekend": the days chosen in Settings, like the buttons.
    private static func parseWeekPhrase(in text: String, weekStart: Int, weekendStart: Int) -> DateMatch? {
        let nextWeek = #"(?i)(?<!\S)(?:next|nxt)\s+(?:week|wk)(?![\p{L}\p{N}])"#
        let weekend = #"(?i)(?<!\S)(?:(?:this|next|nxt)\s+)?weekend(?![\p{L}\p{N}])"#
        if let match = matches(nextWeek, in: text).first {
            return (ReminderEditing.nextWeekStart(weekStart), false, match.range)
        }
        if let match = matches(weekend, in: text).first {
            return (ReminderEditing.weekend(startingOn: weekendStart), false, match.range)
        }
        return nil
    }

    /// "in 20 min", "in 2h", "in 3 days", "in two weeks", "in a month", "in half an hour": the system
    /// detector misses most of these.
    private static func parseRelativeDate(in text: String) -> DateMatch? {
        let ns = text as NSString
        let digits = #"(?i)(?<!\S)in\s+(\d+)\s*(minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|wks?|w|months?|mos?|years?|yrs?|y)(?!\S)"#
        let words = #"(?i)(?<!\S)in\s+(an?|one|two|three|four|five|six|seven|eight|nine|ten|twelve)\s+(minutes?|mins?|hours?|hrs?|days?|weeks?|wks?|months?|years?)(?!\S)"#
        let half = #"(?i)(?<!\S)in\s+half\s+an?\s+hour(?!\S)"#

        var amount = 0
        var unit = ""
        var range = NSRange(location: NSNotFound, length: 0)
        if let match = matches(digits, in: text).first {
            amount = Int(ns.substring(with: match.range(at: 1))) ?? 0
            unit = ns.substring(with: match.range(at: 2)).lowercased()
            range = match.range
        } else if let match = matches(words, in: text).first {
            amount = numberWords[ns.substring(with: match.range(at: 1)).lowercased()] ?? 0
            unit = ns.substring(with: match.range(at: 2)).lowercased()
            range = match.range
        } else if let match = matches(half, in: text).first {
            guard let date = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) else { return nil }
            return (date, true, match.range)
        }
        guard range.location != NSNotFound else { return nil }

        // "m" is minutes and "mo" months, so a single letter is only read as minutes.
        let (component, hasTime): (Calendar.Component, Bool) = switch unit {
        case "m", "min", "mins", "minute", "minutes": (.minute, true)
        case _ where unit.hasPrefix("mo"): (.month, false)
        case _ where unit.first == "h": (.hour, true)
        case _ where unit.first == "d": (.day, false)
        case _ where unit.first == "y": (.year, false)
        default: (.weekOfYear, false)
        }
        guard amount > 0, amount <= 1000, let date = Calendar.current.date(byAdding: component, value: amount, to: Date()) else { return nil }
        return (hasTime ? date : Calendar.current.startOfDay(for: date), hasTime, range)
    }

    /// "end of the month", "end of year", "eom": the last day of this month or year.
    private static func parseEndOf(in text: String) -> DateMatch? {
        let pattern = #"(?i)(?<!\S)(?:end\s+of\s+(?:the\s+|this\s+)?(month|year)|(eom|eoy))(?![\p{L}\p{N}])"#
        guard let match = matches(pattern, in: text).first else { return nil }
        let ns = text as NSString
        let word = (group(match, 1, in: ns) ?? group(match, 2, in: ns) ?? "").lowercased()
        let calendar = Calendar.current
        let unit: Calendar.Component = word == "year" || word == "eoy" ? .year : .month
        guard let interval = calendar.dateInterval(of: unit, for: Date()),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return nil }
        return (calendar.startOfDay(for: last), false, match.range)
    }

    private static func parseDate(in masked: NSMutableString) -> DateMatch? {
        guard let detector else { return nil }
        let text = masked as String

        // Build the string handed to the detector, remembering which input words each part came from.
        var detection = ""
        var spans: [(original: NSRange, start: Int, end: Int)] = []
        var previous = ""
        for word in matches(#"\S+"#, in: text) {
            let raw = (text as NSString).substring(with: word.range)
            let punctuation = raw.range(of: #"[.,;:!?]+$"#, options: .regularExpression).map { String(raw[$0]) } ?? ""
            let core = String(raw.dropLast(punctuation.count))
            if !detection.isEmpty { detection += " " }
            let start = (detection as NSString).length
            detection += normalise(core, previous: previous) + punctuation
            spans.append((word.range, start, (detection as NSString).length))
            previous = core.lowercased()
        }
        let det = detection as NSString
        let whole = NSRange(location: 0, length: det.length)
        guard var found = detector.firstMatch(in: detection, range: whole), var date = found.date else { return nil }

        // The detector sometimes takes a word in front of the date along ("finish by friday" comes out as a time
        // on the wrong day), so the match starts at the first word that belongs to a date.
        let skipped = leadingNoise(in: det.substring(with: found.range))
        if skipped > 0 {
            let rest = NSRange(location: found.range.location + skipped, length: found.range.length - skipped)
            guard rest.length > 0, let again = detector.firstMatch(in: detection, range: rest), let againDate = again.date else { return nil }
            found = again
            date = againDate
        }

        // Absorb an "at 8" / "at 5:30pm" the detector left behind.
        var detRange = found.range
        let tail = det.substring(from: NSMaxRange(detRange))
        if let t = tail.range(of: #"^\s+at\s+\d{1,2}(?::\d{2})?(?:\s*(?:am|pm))?\b"#, options: [.regularExpression, .caseInsensitive]) {
            detRange.length += tail.distance(from: tail.startIndex, to: t.upperBound)
        }
        guard let first = spans.first(where: { $0.end > detRange.location }),
              let last = spans.last(where: { $0.start < NSMaxRange(detRange) }) else { return nil }
        let original = NSRange(location: first.original.location, length: NSMaxRange(last.original) - first.original.location)
        let phrase = det.substring(with: detRange)
        // Numbers with dots, slashes or dashes are read by `parseNumericDate`, which also rejects days that don't exist.
        if firstMatch(#"\d\s*[/.-]\s*\d"#, in: phrase) != nil { return nil }

        // Explicit "at N" times.
        var hasTime = firstMatch(#"\d\s?(am|pm)\b|\d:\d\d|\bin \d+\s?(minutes?|hours?)\b|\btonight\b|\bmorning\b|\bevening\b|\bafternoon\b"#, in: phrase) != nil
        if let at = firstMatch(#"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#, in: phrase) {
            let p = phrase as NSString
            let hour = hour24(Int(p.substring(with: at.range(at: 1))) ?? 0, meridiem: group(at, 3, in: p))
            let minute = group(at, 2, in: p).flatMap { Int($0) } ?? 0
            if hour < 24, minute < 60,
               let withTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) {
                date = withTime
                hasTime = true
            }
        }

        let today = Calendar.current.startOfDay(for: Date())
        if date < today, firstMatch(monthName, in: phrase) != nil, firstMatch(#"\b\d{4}\b"#, in: phrase) == nil {
            // "oct 5" typed after the 5th of October means next year's.
            date = Calendar.current.date(byAdding: .year, value: 1, to: date) ?? date
        } else if hasTime, firstMatch(dayInfo, in: phrase) == nil {
            date = rolledForward(date)
        }
        return (date, hasTime, withConnector(original, in: masked as String))
    }

    // MARK: Numbers and bare times

    private static let monthName = #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b"#
    /// Anything that names a day, so that a time on its own can be told apart.
    private static let dayInfo = #"\b(today|tonight|tomorrow|yesterday|this|next|last|ago|morning|afternoon|evening|mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b|\d\s*[/.-]\s*\d"#

    /// Words a date can start with. A word with a digit in it counts too.
    private static let dateWords: Set<String> = Set(
        ["on", "at", "by", "due", "before", "in", "next", "nxt", "this", "last", "the", "a", "an", "today", "tonight", "tomorrow",
         "yesterday", "noon", "midnight", "morning", "afternoon", "evening", "night", "half", "end", "eod",
         "mon", "monday", "tue", "tues", "tuesday", "wed", "wednesday", "thu", "thur", "thurs", "thursday", "fri", "friday",
         "sat", "saturday", "sun", "sunday",
         "jan", "january", "feb", "february", "mar", "march", "apr", "april", "may", "jun", "june", "jul", "july",
         "aug", "august", "sep", "sept", "september", "oct", "october", "nov", "november", "dec", "december"])

    /// How many characters at the start of a detected phrase come before its first date word.
    private static func leadingNoise(in phrase: String) -> Int {
        let ns = phrase as NSString
        for word in matches(#"\S+"#, in: phrase) {
            let text = ns.substring(with: word.range).lowercased().trimmingCharacters(in: .punctuationCharacters)
            if dateWords.contains(text) || text.contains(where: \.isNumber) { return word.range.location }
        }
        return ns.length
    }

    /// The hour (0-23) for a typed time. Without am/pm, 1-6 count as pm, 7-11 as am and 12 as noon.
    private static func hour24(_ hour: Int, meridiem: String?) -> Int {
        if let meridiem { return hour % 12 + (meridiem.lowercased() == "pm" ? 12 : 0) }
        return (1...6).contains(hour) ? hour + 12 : hour
    }

    /// A time that has already gone by today, with no day named, means its next turn: tomorrow.
    private static func rolledForward(_ date: Date) -> Date {
        let calendar = Calendar.current
        guard date < Date(), calendar.isDateInToday(date) else { return date }
        return calendar.date(byAdding: .day, value: 1, to: date) ?? date
    }

    /// Pulls in a connector right before the date ("on friday", "by tomorrow").
    private static func withConnector(_ range: NSRange, in text: String) -> NSRange {
        let before = (text as NSString).substring(to: range.location)
        guard let connector = matches(#"\b(on|at|by|due|before)\s+$"#, in: before).first else { return range }
        return NSRange(location: connector.range.location, length: NSMaxRange(range) - connector.range.location)
    }

    /// "at 8" or "at 5:30pm" with no day: today, or tomorrow once the time has gone by.
    private static func parseBareTime(in text: String) -> DateMatch? {
        let pattern = #"(?i)(?<!\S)at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?![\p{L}\p{N}:])"#
        guard let match = matches(pattern, in: text).first else { return nil }
        let ns = text as NSString
        let hour = hour24(Int(ns.substring(with: match.range(at: 1))) ?? 0, meridiem: group(match, 3, in: ns))
        let minute = group(match, 2, in: ns).flatMap { Int($0) } ?? 0
        guard hour < 24, minute < 60, let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) else { return nil }
        return (rolledForward(date), true, match.range)
    }

    /// "31.12.2026", "31.12.", "12/31/2026", "12/31" and "2026-12-31", with the day or month first as chosen.
    /// A date with no year is the next one still to come. The trailing dot is what tells "5.10." from a number like 2.5.
    private static func parseNumericDate(in text: String, order: DateOrder) -> DateMatch? {
        let edge = #"(?<![\p{L}\p{N}./-])"#
        let patterns = [
            edge + #"(\d{4})-(\d{1,2})-(\d{1,2})(?![\p{L}\p{N}])"#,                // 2026-12-31
            edge + #"(\d{1,2})\.(\d{1,2})\.(\d{4}|\d{2})?(?![\p{L}\p{N}])"#,        // 31.12.2026, 31.12.
            edge + #"(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?(?![\p{L}\p{N}/])"#,       // 12/31/2026, 12/31
            edge + #"(\d{1,2})-(\d{1,2})-(\d{4})(?![\p{L}\p{N}])"#,                 // 31-12-2026
        ]
        let ns = text as NSString
        var best: (range: NSRange, date: Date)?
        for (index, pattern) in patterns.enumerated() {
            guard let match = matches(pattern, in: text).first, best == nil || match.range.location < best!.range.location else { continue }
            let first = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let second = Int(ns.substring(with: match.range(at: 2))) ?? 0
            let third = group(match, 3, in: ns).flatMap { Int($0) }
            let date: Date?
            if index == 0 {
                date = makeDate(day: third ?? 0, month: second, year: first)
            } else {
                let year = third.map { $0 < 100 ? 2000 + $0 : $0 }
                // The chosen order first; a date that only works the other way round is read that way.
                let (day, month) = order == .dayFirst ? (first, second) : (second, first)
                date = makeDate(day: day, month: month, year: year) ?? makeDate(day: month, month: day, year: year)
            }
            if let date { best = (match.range, date) }
        }
        guard let best else { return nil }

        // A time right after it: "5.10. at 5pm", "12/31 17:30".
        var range = best.range
        var date = best.date
        var hasTime = false
        let tail = ns.substring(from: NSMaxRange(range))
        let timePattern = #"^\s+(at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?![\p{L}\p{N}:])"#
        if let t = regex(timePattern, options: .caseInsensitive)?.firstMatch(in: tail, range: NSRange(location: 0, length: (tail as NSString).length)) {
            let tailNS = tail as NSString
            let explicit = group(t, 1, in: tailNS) != nil || group(t, 3, in: tailNS) != nil || group(t, 4, in: tailNS) != nil
            let hour = hour24(Int(tailNS.substring(with: t.range(at: 2))) ?? 0, meridiem: group(t, 4, in: tailNS))
            let minute = group(t, 3, in: tailNS).flatMap { Int($0) } ?? 0
            if explicit, hour < 24, minute < 60, let withTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) {
                date = withTime
                hasTime = true
                range.length += t.range.length
            }
        }
        return (date, hasTime, withConnector(range, in: text))
    }

    /// The date with those parts, if there is such a day. Without a year it is the next one that isn't past.
    private static func makeDate(day: Int, month: Int, year: Int?) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let thisYear = calendar.component(.year, from: today)
        for candidate in (year.map { [$0] } ?? Array(thisYear...(thisYear + 4))) {
            guard let date = calendar.date(from: DateComponents(year: candidate, month: month, day: day)),
                  calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month else { continue }
            if year != nil || date >= today { return date }
        }
        return nil
    }

    // MARK: Autocomplete

    /// The `~list`, `#tag` or `*` being typed at the end of the input, if any.
    static func activeToken(in input: String) -> (trigger: Character, query: String, range: Range<String.Index>)? {
        guard let match = matches(#"(?<!\S)([~#*])("[^"]*|[^\s"]*)$"#, in: input).first,
              let range = Range(match.range, in: input),
              let trigger = group(match, 1, in: input as NSString)?.first else { return nil }
        let query = (group(match, 2, in: input as NSString) ?? "").replacingOccurrences(of: "\"", with: "")
        return (trigger, query, range)
    }

    /// The `#tags` found in reminder titles, without duplicates.
    static func tags(in titles: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for title in titles {
            for match in matches(#"(?<!\S)#([\p{L}\p{N}_-]+)"#, in: title) {
                if let tag = group(match, 1, in: title as NSString), seen.insert(tag.lowercased()).inserted { result.append(tag) }
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: Regex helpers

    /// Only ever used from the main thread while typing.
    nonisolated(unsafe) private static var compiled: [String: NSRegularExpression] = [:]

    /// Compiling a pattern is the slow part, so each one is compiled only once.
    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(options.rawValue):\(pattern)"
        if let cached = compiled[key] { return cached }
        let expression = try? NSRegularExpression(pattern: pattern, options: options)
        compiled[key] = expression
        return expression
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        regex(pattern)?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? []
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        regex(pattern, options: .caseInsensitive)?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: NSString) -> String? {
        guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound else { return nil }
        return text.substring(with: match.range(at: index))
    }
}
