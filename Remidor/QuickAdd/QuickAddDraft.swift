//
//  QuickAddDraft.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

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
    var pickedListID: String?
    var pickedTags: [String] = []

    init(model: TaskModel) {
        self.model = model
    }

    // MARK: What will be saved

    var realLists: [ReminderList] { model.lists.filter { !$0.isSmart } }
    var title: String { parsed.title }
    var due: Date? { parsed.due ?? pickedDate }
    var hasTime: Bool { parsed.due != nil ? parsed.hasTime : pickedHasTime }
    var priority: Int? { parsed.priority ?? pickedPriority }

    var list: ReminderList? {
        let lists = realLists
        if let name = parsed.listName, let match = lists.first(where: { $0.title == name }) { return match }
        if let id = pickedListID, let match = lists.first(where: { $0.id == id }) { return match }
        return lists.first { $0.id == model.defaultListID }
    }

    var request: NewReminder? {
        guard !title.isEmpty else { return nil }
        let fullTitle = ([title] + pickedTags.map { "#" + $0 }).joined(separator: " ")
        return NewReminder(title: fullTitle, due: due, hasTime: hasTime, priority: priority, listID: list?.id)
    }

    /// Call when the available lists change, since list names are part of the parse.
    func reparse() {
        parsed = QuickAddParser.parse(text, listNames: realLists.map(\.title))
    }

    func reset() {
        text = ""
        pickedDate = nil
        pickedHasTime = false
        pickedPriority = nil
        pickedListID = nil
        pickedTags = []
    }

    // MARK: Autocomplete

    /// Lists or tags matching the `~` or `#` currently being typed.
    var suggestions: [Suggestion] {
        guard let token = QuickAddParser.activeToken(in: text) else { return [] }
        let query = token.query.lowercased()
        if token.trigger == "~" {
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
    }

    /// Turns everything recognized in the text (date, priority, list, tags) into chips. A newly typed
    /// date, priority or list replaces the earlier one; tags accumulate. Returns false if nothing was recognized.
    func commitTyped() -> Bool {
        let result = parsed
        guard !result.tokens.isEmpty else { return false }
        if let date = result.due { pickedDate = date; pickedHasTime = result.hasTime }
        if let priority = result.priority { pickedPriority = priority }
        if let name = result.listName, let match = realLists.first(where: { $0.title == name }) { pickedListID = match.id }

        let nsText = text as NSString
        for token in result.tokens where token.kind == .tag {
            let tag = String(nsText.substring(with: token.range).dropFirst())
            if !pickedTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { pickedTags.append(tag) }
        }
        removeTokens(where: { _ in true })
        return true
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
        let remaining = NSMutableString(string: text)
        for token in parsed.tokens.filter(isIncluded).sorted(by: { $0.range.location > $1.range.location }) {
            remaining.replaceCharacters(in: token.range, with: "")
        }
        text = (remaining as String).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
