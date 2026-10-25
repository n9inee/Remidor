//
//  MenuBarLabel.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// What the menu bar shows: an icon, or the current task with its countdown or a checkmark.
struct MenuBarLabel: View {
    let model: TaskModel

    var body: some View {
        switch model.phase {
        case .idle:
            Image(systemName: "checklist")
        case .choosing(let item):
            Text(shortened(item.title))
        case .running(let item, _):
            Text("\(shortened(item.title))  \(formatRemaining(model.remaining))")
                .monospacedDigit()
        case .finished(let item):
            HStack(spacing: 4) {
                Text(shortened(item.title))
                Image(systemName: "checkmark.circle.fill")
            }
        }
    }

    private func shortened(_ title: String) -> String {
        title.count > 28 ? String(title.prefix(27)) + "…" : title
    }
}
