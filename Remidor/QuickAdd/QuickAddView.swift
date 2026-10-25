//
//  QuickAddView.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// The "add a reminder" box. In the hotkey panel it also lists open tasks, so one can be picked to work on.
struct QuickAddView: View {
    let model: TaskModel
    var autofocus = false
    var onAdded: (() -> Void)?
    /// When set, open tasks are listed under the box and one can be chosen with ↑ ↓ and Return.
    var onPickTask: ((ReminderItem) -> Void)?

    @State private var draft: QuickAddDraft
    @State private var showCalendar = false
    @State private var justAdded = false
    @State private var focusTrigger = 0
    @State private var selection = 0

    init(model: TaskModel, autofocus: Bool = false, onAdded: (() -> Void)? = nil, onPickTask: ((ReminderItem) -> Void)? = nil) {
        self.model = model
        self.autofocus = autofocus
        self.onAdded = onAdded
        self.onPickTask = onPickTask
        _draft = State(initialValue: QuickAddDraft(model: model))
    }

    var body: some View {
        let suggestions = draft.suggestions
        let rows = quickRows(suggestions: suggestions)

        VStack(alignment: .leading, spacing: 6) {
            inputField

            if !suggestions.isEmpty {
                SuggestionList(suggestions: suggestions) { suggestion in
                    draft.apply(suggestion)
                    focusTrigger += 1
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Always shown, so the box keeps its size when the first character is typed.
            QuickAddControls(draft: draft, showCalendar: $showCalendar, onAdd: submit)

            if !rows.isEmpty {
                Divider().padding(.vertical, 2)
                QuickSelectList(rows: rows, selection: $selection, onActivate: activate)
                    .transition(.opacity)
            }
        }
        .onChange(of: draft.text) { selection = 0 }
        .onChange(of: model.lists.map(\.id)) { draft.reparse() }
        .onAppear {
            if autofocus { Task { @MainActor in focusTrigger += 1 } }
        }
        .animation(.snappy(duration: 0.44), value: suggestions.map(\.id))
        .animation(.snappy(duration: 0.44), value: draft.pickedTags)
        .animation(.snappy(duration: 0.44), value: showCalendar)
    }

    private var inputField: some View {
        HStack(spacing: 6) {
            Image(systemName: justAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                .foregroundStyle(justAdded ? .green : Color.accentColor)
                .symbolEffect(.bounce, options: .speed(0.5), value: justAdded)
                .contentTransition(.symbolEffect(.replace))
            HighlightedTextField(
                text: $draft.text,
                placeholder: "Add a new Reminder! e. g. Call mom at 8pm tmrw !!!",
                tokens: draft.parsed.tokens,
                color: color(for:),
                focusTrigger: focusTrigger,
                onSubmit: submit,
                onTab: { _ = absorbTyped(); return true },
                onMove: move
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
    }

    private func color(for token: QuickAddParser.Token) -> NSColor {
        switch token.kind {
        case .date: .systemBlue
        case .priority: .systemOrange
        case .tag: .systemPurple
        case .list: draft.list.map { NSColor($0.color) } ?? .systemGreen
        }
    }

    // MARK: Quick select

    /// "Add …" for the typed title, followed by the open tasks that match it (dates and other tokens are ignored).
    private func quickRows(suggestions: [QuickAddDraft.Suggestion]) -> [QuickRow] {
        guard onPickTask != nil, suggestions.isEmpty else { return [] }
        var seen = Set<String>()
        let all = model.sections.flatMap(\.items).filter { seen.insert($0.id).inserted }
        let query = draft.title.lowercased()
        let matching = query.isEmpty ? all : all.filter { $0.title.lowercased().contains(query) }
        return (draft.title.isEmpty ? [] : [.add(draft.title)]) + matching.map(QuickRow.task)
    }

    private func activate(_ row: QuickRow) {
        switch row {
        case .add: addCurrent()
        case .task(let item): onPickTask?(item)
        }
    }

    private func move(_ delta: Int) -> Bool {
        let count = quickRows(suggestions: draft.suggestions).count
        guard count > 0 else { return false }
        selection = min(max(selection + delta, 0), count - 1)
        return true
    }

    // MARK: Actions

    /// Takes in everything still being typed: the open ~list / #tag suggestion first, then every
    /// recognized (coloured) token, which all move out of the text and onto the chips.
    /// Returns false if there was nothing to take in.
    private func absorbTyped() -> Bool {
        var absorbed = false
        if let first = draft.suggestions.first {
            draft.apply(first)
            absorbed = true
        }
        if draft.commitTyped() { absorbed = true }
        if absorbed { focusTrigger += 1 }
        return absorbed
    }

    /// Return takes in everything first, then acts on the highlighted row: adding the reminder, or
    /// starting the chosen task in the hotkey panel.
    private func submit() {
        let absorbed = absorbTyped()
        // Only metadata was typed, so there is no reminder to add yet and the highlighted row isn't meant.
        if absorbed && draft.title.isEmpty { return }

        let rows = quickRows(suggestions: draft.suggestions)
        if rows.indices.contains(selection) { activate(rows[selection]) } else { addCurrent() }
    }

    private func addCurrent() {
        guard let request = draft.request else { return }
        Task {
            guard await model.addReminder(request) else { return }
            draft.reset()
            showCalendar = false
            justAdded = true
            if let onAdded {
                try? await Task.sleep(for: .seconds(0.5))
                onAdded()
            } else {
                try? await Task.sleep(for: .seconds(1.5))
            }
            justAdded = false
        }
    }
}

private struct SuggestionList: View {
    let suggestions: [QuickAddDraft.Suggestion]
    let onSelect: (QuickAddDraft.Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button { onSelect(suggestion) } label: {
                    Text(suggestion.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
    }
}
