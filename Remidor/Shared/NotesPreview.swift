//
//  NotesPreview.swift
//  Remidor
//
//  Created by n9ine on 10.11.2026.
//

import SwiftUI

/// The first one or two lines of a reminder's notes, under its title. Each line stays on one line and is cut
/// with an ellipsis, so a row's height only depends on how many lines there are.
struct NotesPreview: View {
    let lines: [String]
    var color: Color = .secondary

    /// How tall the preview is, for rows that have a fixed height.
    static func height(for lines: [String]) -> CGFloat { CGFloat(lines.count) * 14 }

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).lineLimit(1).truncationMode(.tail)
                }
            }
            .font(.caption)
            .foregroundStyle(color)
            .accessibilityLabel("Notes: " + lines.joined(separator: ". "))
        }
    }
}
