//
//  NewListForm.swift
//  Remidor
//
//  Created by n9ine on 26.10.2026.
//

import SwiftUI

/// A name box and a row of colours for making a new list. Used in the dropdown and in Settings.
struct NewListForm: View {
    let model: TaskModel
    let onDone: () -> Void

    @State private var color = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(TaskModel.listColors.enumerated()), id: \.offset) { index, swatch in
                    Button { color = index } label: {
                        Circle().fill(Color(nsColor: swatch)).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(color == index ? 0.9 : 0), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colour \(index + 1)")
                }
            }
            NameField(placeholder: "List name", onSubmit: { name in
                if model.createList(named: name, color: TaskModel.listColors[color]) { onDone() }
            }, onCancel: onDone)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
