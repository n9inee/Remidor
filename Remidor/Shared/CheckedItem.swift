//
//  CheckedItem.swift
//  Remidor
//
//  Created by n9ine on 29.10.2026.
//

import SwiftUI

/// A menu choice that shows the system checkmark when it is the one in use.
struct CheckedItem: View {
    let title: String
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Toggle(title, isOn: Binding(get: { checked }, set: { _ in action() }))
    }
}
