//
//  QuickAddDraft.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import AppKit
import Foundation
import Observation

/// The reminder being typed in the quick-add box: the text, the choices made with the buttons, and
/// what the two add up to. Typed tokens always win over button choices, so the buttons show what
/// will actually be saved.
@MainActor @Observable
final class QuickAddDraft {
    struct Suggestion: Identifiable {
        let label: String
        var listID: String?
        var tag: String?
        var flag = false
        var id: String { label }
    }

    @ObservationIgnored private let model: TaskModel

    var text = "" {
        didSet { if text != oldValue { reparse() } }
    }
    /// The parse of `text`, refreshed only when the text changes.
    private(set) var parsed = QuickAddParser.Result()

    var pickedDate: Date?
    var pickedHasTime = false
    var pickedPriority: Int?
    var pickedFlag = false
    var pickedListID: String?
    var pickedTags: [String] = []
    var pickedRecurrence: Recurrence?

    /// While the text is exactly this, nothing in it counts as typed. Used when editing a reminder, so
    /// that words in its title, like "at 5", don't change its date until the text is touched.
    @ObservationIgnored private var untouchedText: String?

    init(model: TaskModel) {
        self.model = model
    }

    /// The list this draft always goes to, for adding in place to a list, a section or under a parent. Typed
    /// `~lists` are then just text, and the list button is left out.
    var lockedListID: String?

    /// A draft for adding to one particular list.
    convenience init(adding listID: String, model: TaskModel) {
        self.init(model: model)
        lockedListID = listID
        pickedListID = listID
    }

    /// A draft that starts as an existing reminder.
    convenience init(editing item: ReminderItem, model: TaskModel) {
        self.init(model: model)
        untouchedText = item.title
        text = item.title
        pickedDate = item.due
        pickedHasTime = item.dueHasTime
        pickedPriority = item.priority == 0 ? nil : item.priority
        pickedFlag = item.isFlagged
        pickedListID = item.listID
        pickedRecurrence = item.recurrence
        reparse()
    }

    /// The color a recognized piece of the text is drawn in.
    func color(for token: QuickAddParser.Token) -> NSColor {
        switch token.kind {
        case .date: .systemBlue
        case .priority: .systemOrange
        case .flag: .systemYellow
        case .tag: .systemPurple
        case .list: list.map { NSColor($0.color) } ?? .systemGreen
        case .recurrence: .systemTeal
        }
    }

    // MARK: What will be saved

    var realLists: [ReminderList] { model.lists.filter { !$0.isSmart } }
    var title: String { parsed.title }
    var due: Date? { parsed.due ?? pickedDate }
    var hasTime: Bool { parsed.due != nil ? parsed.hasTime : pickedHasTime }
    var priority: Int? { parsed.priority ?? pickedPriority }
    var flagged: Bool { parsed.flagged || pickedFlag }
    var recurrence: Recurrence? { parsed.recurrence ?? pickedRecurrence }

    var list: ReminderList? {
        let lists = realLists
        if let lockedListID, let match = lists.first(where: { $0.id == lockedListID }) { return match }
        if let name = parsed.listName, let match = lists.first(where: { $0.title == name }) { return match }
        if let id = pickedListID, let match = lists.first(where: { $0.id == id }) { return match }
        return lists.first { $0.id == model.defaultListID }
    }

    var request: NewReminder? { request(fallbackTitle: nil) }

    /// What to save. A reminder being edited keeps its old title when the box was emptied.
    func request(fallbackTitle: String?) -> NewReminder? {
        let title = title.isEmpty ? (fallbackTitle ?? "") : title
        guard !title.isEmpty else { return nil }
        let fullTitle = ([title] + pickedTags.map { "#" + $0 }).joined(separator: " ")
        return NewReminder(title: fullTitle, due: due, hasTime: hasTime, priority: priority, flagged: flagged,
                           listID: list?.id, recurrence: recurrence)
    }

    /// Call when the available lists change, since list names are part of the parse.
    func reparse() {
        if text == untouchedText {
            // The title as it is, with nothing in it read as a date, priority or the like.
            var untouched = QuickAddParser.Result()
            untouched.title = text
            parsed = untouched
        } else {
            parsed = QuickAddParser.parse(text, listNames: lockedListID == nil ? realLists.map(\.title) : [])
        }
    }

    func reset() {
        text = ""
        pickedDate = nil
        pickedHasTime = false
        pickedPriority = nil
        pickedFlag = false
        pickedListID = nil
        pickedTags = []
        pickedRecurrence = nil
    }

    // MARK: Autocomplete

    /// Lists or tags matching the `~` or `#` currently being typed.
    var suggestions: [Suggestion] {
        guard let token = QuickAddParser.activeToken(in: text) else { return [] }
        let query = token.query.lowercased()
        if token.trigger == "*" {
            return query.isEmpty && !pickedFlag ? [Suggestion(label: "Flag", flag: true)] : []
        }
        if token.trigger == "~" {
            guard lockedListID == nil else { return [] }
            return realLists
                .filter { query.isEmpty || $0.title.lowercased().contains(query) }
                .prefix(5)
                .map { Suggestion(label: $0.title, listID: $0.id) }
        }
        let typed = Set(text.lowercased().split(separator: " ").map(String.init))
        return model.allTags
            .filter { tag in
                (query.isEmpty || tag.lowercased().hasPrefix(query))
                    && !typed.contains("#" + tag.lowercased())
                    && !pickedTags.contains(tag)
            }
            .prefix(5)
            .map { Suggestion(label: "#" + $0, tag: $0) }
    }

    /// An accepted suggestion leaves the text box and becomes a chip, so the box holds only the title.
    func apply(_ suggestion: Suggestion) {
        guard let token = QuickAddParser.activeToken(in: text) else { return }
        text.removeSubrange(token.range)
        text = text.trimmingCharacters(in: .whitespaces)
        if let id = suggestion.listID { pickedListID = id }
        if let tag = suggestion.tag, !pickedTags.contains(tag) { pickedTags.append(tag) }
        if suggestion.flag { pickedFlag = true }
    }

    /// Turns everything recognized in the text (date, priority, list, tags) into chips. A newly typed
    /// date, priority or list replaces the earlier one; tags accumulate. Returns false if nothing was recognized.
    func commitTyped() -> Bool {
        let result = parsed
        guard !result.tokens.isEmpty else { return false }
        if let date = result.due { pickedDate = date; pickedHasTime = result.hasTime }
        if let priority = result.priority { pickedPriority = priority }
        if result.flagged { pickedFlag = true }
        if let recurrence = result.recurrence { pickedRecurrence = recurrence }
        if let name = result.listName, let match = realLists.first(where: { $0.title == name }) { pickedListID = match.id }

        let nsText = text as NSString
        for token in result.tokens where token.kind == .tag {
            let tag = String(nsText.substring(with: token.range).dropFirst())
            if !pickedTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { pickedTags.append(tag) }
        }
        removeTokens(where: { _ in true })
        return true
    }

    /// Takes the first open suggestion and everything recognized in the text onto the chips, which is what Tab
    /// and Return do before anything else. Returns false if there was nothing to take in.
    @discardableResult
    func absorbTyped() -> Bool {
        var absorbed = false
        if let first = suggestions.first {
            apply(first)
            absorbed = true
        }
        if commitTyped() { absorbed = true }
        return absorbed
    }

    // MARK: Button choices

    func setDate(_ date: Date, hasTime: Bool? = nil) {
        takeOverTypedDate()
        pickedDate = date
        if let hasTime { pickedHasTime = hasTime }
    }

    func setTime(_ enabled: Bool) {
        let current = due ?? Date()
        takeOverTypedDate()
        pickedDate = current
        pickedHasTime = enabled
    }

    func clearDate() {
        takeOverTypedDate()
        pickedDate = nil
        pickedHasTime = false
    }

    func setPriority(_ priority: Int?) {
        removeTokens(of: .priority)
        pickedPriority = priority
    }

    /// The flag button: flags the reminder, or removes the flag (typed `*` included).
    func toggleFlag() {
        let wasFlagged = flagged
        removeTokens(of: .flag)
        pickedFlag = !wasFlagged
    }

    /// The repeat button. A repeat needs a date to start from, so today is used when there is none.
    func setRecurrence(_ recurrence: Recurrence?) {
        takeOverTypedDate()
        removeTokens(of: .recurrence)
        pickedRecurrence = recurrence
        guard let recurrence else { return }
        let start = due ?? Calendar.current.startOfDay(for: Date())
        pickedDate = recurrence.firstOccurrence(onOrAfter: start, hasTime: hasTime)
    }

    func setList(_ id: String) {
        removeTokens(of: .list)
        pickedListID = id
    }

    /// A button choice replaces whatever was typed for that field.
    private func takeOverTypedDate() {
        guard parsed.due != nil else { return }
        pickedDate = parsed.due
        pickedHasTime = parsed.hasTime
        removeTokens(of: .date)
    }

    private func removeTokens(of kind: QuickAddParser.Kind) {
        removeTokens { $0.kind == kind }
    }

    private func removeTokens(where isIncluded: (QuickAddParser.Token) -> Bool) {
        let targets = parsed.tokens.filter(isIncluded)
        guard !targets.isEmpty else { return }
        let remaining = NSMutableString(string: text)
        for token in targets.sorted(by: { $0.range.location > $1.range.location }) {
            remaining.replaceCharacters(in: token.range, with: "")
        }
        text = (remaining as String).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
