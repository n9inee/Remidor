//
//  TaskComposer.swift
//  Remidor
//
//  Created by n9ine on 27.10.2026.
//

import SwiftUI

/// Adds a reminder in place, in the shared box, to one particular list, section or parent. The list is
/// already decided, so there is no list button and a typed `~list` stays plain text.
struct TaskComposer: View {
    let model: TaskModel
    let listID: String
    var parent: ReminderItem?
    var sectionID: String?
    let placeholder: String
    let onDone: () -> Void

    @State private var draft: QuickAddDraft
    @State private var adding = false

    init(model: TaskModel, listID: String, parent: ReminderItem? = nil, sectionID: String? = nil, placeholder: String, onDone: @escaping () -> Void) {
        self.model = model
        self.listID = listID
        self.parent = parent
        self.sectionID = sectionID
        self.placeholder = placeholder
        self.onDone = onDone
        _draft = State(initialValue: Self.makeDraft(for: listID, model: model))
    }

    /// A smart list has no list of its own: a reminder added there goes to the default list, with what the
    /// smart list shows already set, the flag for Flagged and today's date for Today.
    private static func makeDraft(for listID: String, model: TaskModel) -> QuickAddDraft {
        guard let smart = SmartList.allLists.first(where: { $0.id == listID }) else {
            return QuickAddDraft(adding: listID, model: model)
        }
        let draft = model.defaultListID.map { QuickAddDraft(adding: $0, model: model) } ?? QuickAddDraft(model: model)
        if smart.id == SmartList.flagged.id { draft.pickedFlag = true }
        if smart.id == SmartList.today.id { draft.pickedDate = Calendar.current.startOfDay(for: Date()) }
        return draft
    }

    var body: some View {
        ReminderBox(draft: draft, placeholder: placeholder, confirmTitle: "Add", isBusy: adding,
                    onConfirm: add, onCancel: onDone)
    }

    private func add(_ request: NewReminder) {
        adding = true
        Task {
            defer { adding = false }
            if await model.addReminder(request, parent: parent, sectionID: sectionID) { onDone() }
        }
    }
}
