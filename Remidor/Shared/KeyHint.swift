//
//  KeyHint.swift
//  Remidor
//
//  Created by n9ine on 10.11.2026.
//

import SwiftUI

/// A line of small print that says what Return does on the highlighted reminder, so the keys can be found.
struct KeyHint: View {
    var body: some View {
        Text("↩ starts the timer  ·  ⇧↩ checks it off")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.opacity)
            .accessibilityLabel("Return starts the timer. Shift Return checks the reminder off.")
    }
}
