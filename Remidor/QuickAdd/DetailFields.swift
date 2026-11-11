//
//  DetailFields.swift
//  Remidor
//
//  Created by n9ine on 08.11.2026.
//

import SwiftUI

/// Two small boxes under the title, for notes and a link. They only show once something is typed in the title,
/// so an empty box stays as plain as it was. Every box that adds or edits a reminder has them.
struct DetailFields: View {
    @Bindable var draft: QuickAddDraft
    var onSubmit: () -> Void = {}
    /// Esc inside the notes, for a box that closes on it.
    var onCancel: (() -> Void)?
    /// Starts with the keyboard in the notes, for a reminder opened by clicking its notes.
    var focusNotes = false

    var body: some View {
        Reveal(shown: draft.hasText) {
            VStack(spacing: 4) {
                field("note.text") {
                    NotesEditor(text: $draft.notes, onCancel: onCancel, onSubmit: onSubmit, focusesOnAppear: focusNotes)
                        .frame(height: 52)
                        .overlay(alignment: .topLeading) {
                            if draft.notes.isEmpty {
                                Text("Notes").foregroundStyle(.tertiary).padding(.leading, 7).padding(.top, 4).allowsHitTesting(false)
                            }
                        }
                }
                field("link") {
                    TextField("Link", text: $draft.urlText)
                        .foregroundStyle(draft.linkIsInvalid ? Color.red : .primary)
                        .help(draft.linkIsInvalid ? "That isn't a web address." : "A link to keep with the reminder")
                }
            }
        }
    }

    private func field<Content: View>(_ icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 12)
            content().textFieldStyle(.plain).onSubmit(onSubmit)
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
    }
}
