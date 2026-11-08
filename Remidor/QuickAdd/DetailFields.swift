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

    var body: some View {
        if draft.hasText {
            VStack(spacing: 4) {
                field("note.text") {
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(1...3)
                }
                field("link") {
                    TextField("Link", text: $draft.urlText)
                        .foregroundStyle(draft.linkIsInvalid ? Color.red : .primary)
                        .help(draft.linkIsInvalid ? "That isn't a web address." : "A link to keep with the reminder")
                }
            }
            .transition(RevealTransition())
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
