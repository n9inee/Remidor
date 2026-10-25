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
    enum Kind { case date, priority, flag, list, tag }

    struct Token {
        let range: NSRange   // UTF-16 range in the original input
        let kind: Kind
    }

    struct Result {
        var title = ""
        var priority: Int?      // EventKit scale: 1 high, 5 medium, 9 low
        var flagged = false
        var listName: String?   // canonical name of the matched list
        var due: Date?
        var hasTime = false
        var tokens: [Token] = []
    }

    // MARK: Parsing

    static func parse(_ input: String, listNames: [String]) -> Result {
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

        if let found = parseRelativeDate(in: masked as String) ?? parseDate(in: masked) {
            result.due = found.date
            result.hasTime = found.hasTime
            claim(found.range, .date, strip: true)
        }

        let title = NSMutableString(string: input)
        for range in stripped.sorted(by: { $0.location > $1.location }) {
            title.replaceCharacters(in: range, with: "")
        }
        result.title = (title as String).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return result
    }

    // MARK: Dates

    private typealias DateMatch = (date: Date, hasTime: Bool, range: NSRange)

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Shorthand the system date detector doesn't understand.
    private static let shorthand: [String: String] = [
        "tmr": "tomorrow", "tmrw": "tomorrow", "tmrrw": "tomorrow", "tmmrw": "tomorrow", "tmw": "tomorrow",
        "tomo": "tomorrow", "tomm": "tomorrow", "2moro": "tomorrow", "2morrow": "tomorrow", "2mrw": "tomorrow",
        "tdy": "today", "2day": "today", "2dy": "today", "tonite": "tonight",
        "nxt": "next", "wk": "week", "wks": "weeks",
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

    /// "in 20 min", "in 2h", "in 3 days": the system detector misses most of these.
    private static func parseRelativeDate(in text: String) -> DateMatch? {
        let pattern = #"(?i)(?<!\S)in\s+(\d+)\s*(minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|wks?|w)(?!\S)"#
        guard let match = matches(pattern, in: text).first else { return nil }
        let ns = text as NSString
        let amount = Int(ns.substring(with: match.range(at: 1))) ?? 0
        let unit = ns.substring(with: match.range(at: 2)).lowercased()
        let (component, hasTime): (Calendar.Component, Bool) = switch unit.first {
        case "m": (.minute, true)
        case "h": (.hour, true)
        case "d": (.day, false)
        default: (.weekOfYear, false)
        }
        guard amount > 0, let date = Calendar.current.date(byAdding: component, value: amount, to: Date()) else { return nil }
        return (date, hasTime, match.range)
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
        guard let found = detector.firstMatch(in: detection, range: NSRange(location: 0, length: det.length)),
              var date = found.date else { return nil }

        // Absorb an "at 8" / "at 5:30pm" the detector left behind.
        var detRange = found.range
        let tail = det.substring(from: NSMaxRange(detRange))
        if let t = tail.range(of: #"^\s+at\s+\d{1,2}(?::\d{2})?(?:\s*(?:am|pm))?\b"#, options: [.regularExpression, .caseInsensitive]) {
            detRange.length += tail.distance(from: tail.startIndex, to: t.upperBound)
        }
        guard let first = spans.first(where: { $0.end > detRange.location }),
              let last = spans.last(where: { $0.start < NSMaxRange(detRange) }) else { return nil }
        var original = NSRange(location: first.original.location, length: NSMaxRange(last.original) - first.original.location)
        let phrase = det.substring(with: detRange)

        // Explicit "at N" times. A bare hour guesses 1-6 as pm, 7-11 as am and 12 as noon.
        var hasTime = firstMatch(#"\d\s?(am|pm)\b|\d:\d\d|\bnoon\b|\bmidnight\b|\bin \d+\s?(minutes?|hours?)\b|\btonight\b|\bmorning\b|\bevening\b|\bafternoon\b"#, in: phrase) != nil
        if let at = firstMatch(#"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#, in: phrase) {
            let p = phrase as NSString
            var hour = Int(p.substring(with: at.range(at: 1))) ?? 0
            let minute = group(at, 2, in: p).flatMap { Int($0) } ?? 0
            if let meridiem = group(at, 3, in: p)?.lowercased() {
                hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
            } else if (1...6).contains(hour) {
                hour += 12
            }
            if hour < 24, minute < 60,
               let withTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) {
                date = withTime
                hasTime = true
            }
        }

        // Pull in a connector right before the date ("on friday", "by tomorrow").
        let before = masked.substring(to: original.location)
        if let connector = matches(#"\b(on|at|by|due|before)\s+$"#, in: before).first {
            original = NSRange(location: connector.range.location, length: NSMaxRange(original) - connector.range.location)
        }
        return (date, hasTime, original)
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
