//
//  TaskEditor.swift
//  Remidor
//
//  Created by n9ine on 26.10.2026.
//

import SwiftUI

/// Edits a reminder in place, in the shared box, starting from its own values.
struct TaskEditor: View {
    let item: ReminderItem
    let model: TaskModel
    let onDone: () -> Void

    @State private var draft: QuickAddDraft

    init(item: ReminderItem, model: TaskModel, onDone: @escaping () -> Void) {
        self.item = item
        self.model = model
        self.onDone = onDone
        _draft = State(initialValue: QuickAddDraft(editing: item, model: model))
    }

    var body: some View {
        ReminderBox(draft: draft, placeholder: "Title", confirmTitle: "Save", fallbackTitle: item.title,
                    onConfirm: { request in
                        model.update(item, to: request)
                        onDone()
                    }, onCancel: onDone)
            .padding(.horizontal, 2)
    }
}
