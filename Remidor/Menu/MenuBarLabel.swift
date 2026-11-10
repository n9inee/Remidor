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
            if model.showMenuBarCount, model.menuBarCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                    Text("\(model.menuBarCount)").monospacedDigit()
                }
            } else {
                Image(systemName: "checklist")
            }
        case .choosing(let item):
            Text(shortened(item.title))
        case .running(let item, _):
            // A paused timer shows a pause sign, so the frozen time doesn't look like a hung app.
            HStack(spacing: 4) {
                if model.isPaused { Image(systemName: "pause.fill") }
                Text("\(shortened(item.title))  \(formatRemaining(model.remaining))")
                    .monospacedDigit()
            }
        case .onBreak:
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer")
                Text(formatRemaining(model.remaining)).monospacedDigit()
            }
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
