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
    @State private var isAdding = false
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
            QuickAddControls(draft: draft, showCalendar: $showCalendar)

            if !rows.isEmpty {
                Divider().padding(.vertical, 2)
                QuickSelectList(rows: rows, selection: $selection, onActivate: activate, onComplete: model.completeOnly)
                    .transition(.opacity)
            }

            // The dropdown shows its own banner under the list; the hotkey box shows it here.
            if onPickTask != nil {
                if let completed = model.undoBannerItem {
                    UndoBanner(item: completed, canUndo: model.undoBannerCanUndo) { model.undoComplete(completed) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let message = model.errorMessage {
                    ErrorBanner(message: message, onDismiss: model.dismissError)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(undoShortcut)
        .animation(.snappy(duration: 0.44), value: model.undoBannerItem?.id)
        .animation(.snappy(duration: 0.44), value: model.errorMessage)
        .onChange(of: draft.text) { selection = 0 }
        .onChange(of: rows.count) { selection = min(selection, max(rows.count - 1, 0)) }
        .onChange(of: model.lists.map(\.id)) { draft.reparse() }
        .onAppear {
            if autofocus { Task { @MainActor in focusTrigger += 1 } }
        }
        .animation(.snappy(duration: 0.44), value: suggestions.map(\.id))
        .animation(.snappy(duration: 0.44), value: draft.pickedTags)
        .animation(.snappy(duration: 0.44), value: showCalendar)
    }

    /// ⌘Z undoes the last completed task. While something is typed it is left alone, so it still
    /// undoes typing as usual.
    private var undoShortcut: some View {
        Button("Undo completion") { model.undoLast() }
            .keyboardShortcut("z", modifiers: .command)
            // Not while the banner shows a repeating task, which can't be undone: ⌘Z must not undo an older one.
            .disabled(draft.text.isEmpty == false || model.recentlyCompleted.isEmpty
                      || (model.undoBannerItem != nil && !model.undoBannerCanUndo))
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
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
                color: draft.color(for:),
                focusTrigger: focusTrigger,
                onSubmit: submit,
                onShiftSubmit: completeHighlighted,
                onTab: { _ = absorbTyped(); return true },
                onMove: move
            )
            .frame(maxWidth: .infinity)
            if !draft.title.isEmpty {
                Button("Add", action: submit)
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
        .animation(.snappy(duration: 0.3), value: draft.title.isEmpty)
    }

    // MARK: Quick select

    /// "Add …" for the typed title, followed by the open tasks that match it (dates and other tokens are ignored).
    private func quickRows(suggestions: [QuickAddDraft.Suggestion]) -> [QuickRow] {
        guard onPickTask != nil, suggestions.isEmpty else { return [] }
        // Grouped like the dropdown: Today and the other smart lists, then each list with its sections.
        let query = draft.title.lowercased()
        let tasks = model.sections.flatMap { section in
            section.items
                .filter { query.isEmpty || $0.title.lowercased().contains(query) }
                .map { QuickRow.task($0, in: section.list) }
        }
        return (draft.title.isEmpty ? [] : [.add(draft.title)]) + tasks
    }

    private func activate(_ row: QuickRow) {
        switch row {
        case .add: addCurrent()
        case .task(let item, _): onPickTask?(item)
        }
    }

    /// Shift + Return checks off the highlighted task.
    private func completeHighlighted() {
        let rows = quickRows(suggestions: draft.suggestions)
        guard rows.indices.contains(selection), case .task(let item, _) = rows[selection] else { return }
        model.completeOnly(item)
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
        // Return pressed twice in a row must not add the reminder twice.
        guard !isAdding, let request = draft.request else { return }
        isAdding = true
        Task {
            defer { isAdding = false }
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

struct SuggestionList: View {
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
