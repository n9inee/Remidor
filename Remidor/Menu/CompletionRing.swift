//
//  CompletionRing.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// A hollow circle, like the one in the Reminders app. It fills and shows a checkmark on hover,
/// and clicking it completes the task.
struct CompletionRing: View {
    let color: Color
    var checkColor: Color = .white
    var size: CGFloat = 16
    var hitSize: CGFloat = 22
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.5)
                Circle().fill(color.opacity(hovering ? 1 : 0))
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(checkColor)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: size, height: size)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.3), value: hovering)
        .help("Mark as done")
        .accessibilityLabel("Mark as done")
    }
}
