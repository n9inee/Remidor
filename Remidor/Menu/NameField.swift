//
//  NameField.swift
//  Remidor
//
//  Created by n9ine on 26.10.2026.
//

import SwiftUI

/// A small text box with Save and Cancel, for naming a section or list in place.
struct NameField: View {
    let placeholder: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var focusTrigger = 1

    init(initial: String = "", placeholder: String, onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _text = State(initialValue: initial)
    }

    var body: some View {
        HStack(spacing: 6) {
            HighlightedTextField(text: $text, placeholder: placeholder, tokens: [], color: { _ in .clear },
                                 focusTrigger: focusTrigger, onSubmit: submit, onTab: { true }, selectsAllOnFocus: true)
                .frame(maxWidth: .infinity)
            Button("Cancel", action: onCancel).controlSize(.small)
            Button("Save", action: submit).controlSize(.small).buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(height: 24)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        .padding(.vertical, 3)
        .onExitCommand(perform: onCancel)
        .transition(.opacity)
    }

    private func submit() {
        let name = text.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { onSubmit(name) }
    }
}
