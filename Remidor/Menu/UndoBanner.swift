//
//  UndoBanner.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// "Completed …  Undo ⌘Z", shown for a few seconds after a task is checked off. A repeating task
/// can't be undone, so its banner just says so.
struct UndoBanner: View {
    let item: ReminderItem
    var canUndo = true
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Completed “\(item.title)”").lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if canUndo {
                Button(action: onUndo) {
                    HStack(spacing: 5) {
                        Label("Undo", systemImage: "arrow.uturn.backward").font(.callout.weight(.medium))
                        Text("⌘Z").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else {
                Label("Repeats", systemImage: "repeat").font(.caption).foregroundStyle(.secondary)
                    .help("Repeating tasks move to their next date and can't be undone here")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
    }
}
