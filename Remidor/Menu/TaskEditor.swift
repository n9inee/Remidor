//
//  TaskEditor.swift
//  Remidor
//
//  Created by n9ine on 26.10.2026.
//

import SwiftUI

/// Edits a reminder in place with the same box used for adding one: the title with everything that can
/// be typed in it, and the date, priority, flag and list buttons underneath.
struct TaskEditor: View {
    let item: ReminderItem
    let model: TaskModel
    let onDone: () -> Void

    @State private var draft: QuickAddDraft
    @State private var showCalendar = false
    @State private var focusTrigger = 1

    init(item: ReminderItem, model: TaskModel, onDone: @escaping () -> Void) {
        self.item = item
        self.model = model
        self.onDone = onDone
        _draft = State(initialValue: QuickAddDraft(editing: item, model: model))
    }

    var body: some View {
        let suggestions = draft.suggestions
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HighlightedTextField(
                    text: $draft.text,
                    placeholder: "Title",
                    tokens: draft.parsed.tokens,
                    color: draft.color(for:),
                    focusTrigger: focusTrigger,
                    onSubmit: save,
                    onTab: { _ = absorbTyped(); return true }
                )
                .frame(maxWidth: .infinity)
            }
            .frame(height: 22)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))

            if !suggestions.isEmpty {
                SuggestionList(suggestions: suggestions) { suggestion in
                    draft.apply(suggestion)
                    focusTrigger += 1
                }
            }

            QuickAddControls(draft: draft, showCalendar: $showCalendar)

            HStack {
                Spacer()
                Button("Cancel", action: onDone).controlSize(.small)
                Button("Save", action: save)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 6)
        .onExitCommand(perform: onDone)
        .animation(.snappy(duration: 0.4), value: showCalendar)
        .animation(.snappy(duration: 0.4), value: suggestions.map(\.id))
    }

    /// Takes in the open suggestion and everything recognized in the text, so it all ends up on the chips.
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

    private func save() {
        _ = absorbTyped()
        guard let request = draft.request(fallbackTitle: item.title) else { return }
        model.update(item, to: request)
        onDone()
    }
}
