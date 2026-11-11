//
//  TaskEditor.swift
//  Remidor
//
//  Created by n9ine on 26.10.2026.
//

import SwiftUI

/// Which box of an edit starts with the keyboard.
enum EditFocus { case title, notes }

/// Edits a reminder in place, in the shared box, starting from its own values.
struct TaskEditor: View {
    let item: ReminderItem
    let model: TaskModel
    var focus: EditFocus = .title
    let onDone: () -> Void

    @State private var draft: QuickAddDraft

    init(item: ReminderItem, model: TaskModel, focus: EditFocus = .title, onDone: @escaping () -> Void) {
        self.item = item
        self.model = model
        self.focus = focus
        self.onDone = onDone
        _draft = State(initialValue: QuickAddDraft(editing: item, model: model))
    }

    var body: some View {
        ReminderBox(draft: draft, placeholder: "Title", confirmTitle: "Save", fallbackTitle: item.title, initialFocus: focus,
                    onConfirm: { request in
                        model.update(item, to: request)
                        onDone()
                    }, onCancel: onDone)
            .padding(.horizontal, 2)
    }
}
