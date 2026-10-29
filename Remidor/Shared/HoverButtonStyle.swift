//
//  HoverButtonStyle.swift
//  Remidor
//
//  Created by n9ine on 29.10.2026.
//

import SwiftUI

/// A plain button that lights up under the pointer and a little more while pressed, so small icons and
/// text buttons read as buttons.
struct HoverButtonStyle: ButtonStyle {
    var horizontal: CGFloat = 0
    var vertical: CGFloat = 0
    var radius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration, horizontal: horizontal, vertical: vertical, radius: radius)
    }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        let horizontal: CGFloat
        let vertical: CGFloat
        let radius: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, horizontal).padding(.vertical, vertical)
                .foregroundStyle(hovering || configuration.isPressed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .background(RoundedRectangle(cornerRadius: radius).fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.09 : 0)))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
