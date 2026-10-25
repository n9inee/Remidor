//
//  UpdateBanner.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// "Remidor 1.2.0 is available", with a button that opens the release page.
struct UpdateBanner: View {
    let update: AvailableUpdate
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
            Text("Remidor \(update.version) is available")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("View") { NSWorkspace.shared.open(update.url) }
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide until a newer version comes out")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.14)))
    }
}
