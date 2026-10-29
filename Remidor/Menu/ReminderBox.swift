//
//  ReminderBox.swift
//  Remidor
//
//  Created by n9ine on 27.10.2026.
//

import SwiftUI

/// The quick-add box drawn in place of a row or under a heading: the title with everything that can be typed
/// in it, the date, repeat, priority, flag and list buttons, and Cancel and a confirm button. Editing a
/// reminder and adding one share it. Only what is done with the result differs.
struct ReminderBox: View {
    @Bindable var draft: QuickAddDraft
    let placeholder: String
    let confirmTitle: String
    /// Kept as the title when the box was emptied, for a reminder that already has one.
    var fallbackTitle: String?
    var isBusy = false
    let onConfirm: (NewReminder) -> Void
    let onCancel: () -> Void

    @State private var showCalendar = false
    @State private var focusTrigger = 1

    var body: some View {
        let suggestions = draft.suggestions
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HighlightedTextField(
                    text: $draft.text,
                    placeholder: placeholder,
                    tokens: draft.parsed.tokens,
                    color: draft.color(for:),
                    focusTrigger: focusTrigger,
                    onSubmit: confirm,
                    onTab: absorb
                )
                .frame(maxWidth: .infinity)
            }
            .frame(height: 24)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))

            if !suggestions.isEmpty {
                SuggestionList(suggestions: suggestions) { suggestion in
                    draft.apply(suggestion)
                    focusTrigger += 1
                }
            }

            QuickAddControls(draft: draft, showCalendar: $showCalendar)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).controlSize(.small)
                Button(confirmTitle, action: confirm)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || (fallbackTitle == nil && draft.title.isEmpty && draft.text.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(.vertical, 4)
        .onExitCommand(perform: onCancel)
        .animation(.snappy(duration: 0.3), value: showCalendar)
        .animation(.snappy(duration: 0.3), value: suggestions.map(\.id))
        .transition(.opacity)
    }

    /// Takes in the open suggestion and everything recognized in the text, so it all ends up on the chips.
    /// Returns false when there was nothing to take in, which lets Tab move on.
    private func absorb() -> Bool {
        let absorbed = draft.absorbTyped()
        if absorbed { focusTrigger += 1 }
        return absorbed
    }

    private func confirm() {
        _ = absorb()
        guard !isBusy, let request = draft.request(fallbackTitle: fallbackTitle) else { return }
        onConfirm(request)
    }
}
