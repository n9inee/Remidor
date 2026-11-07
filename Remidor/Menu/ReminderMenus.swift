//
//  ReminderMenus.swift
//  Remidor
//
//  Created by n9ine on 08.11.2026.
//

import SwiftUI

/// The Date, Priority, Flag and List choices of a reminder's right-click menu, shared by the dropdown and the quick box.
struct ReminderAttributeMenus: View {
    let item: ReminderItem
    let model: TaskModel

    /// Whether the reminder is due on that day, which ticks the matching choice in the Date menu.
    private func isDue(on day: Date) -> Bool {
        item.due.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
    }

    var body: some View {
        Menu("Date") {
            // One tick only: the first of these that matches, so Today wins when the weekend starts today.
            let choices = model.rescheduleChoices
            let current = choices.first { isDue(on: $0.day) }?.title
            ForEach(choices, id: \.title) { choice in
                CheckedItem(title: choice.title, checked: choice.title == current) { model.setDay(item, to: choice.day) }
            }
            if item.due != nil {
                Divider()
                Button("Remove Date") { model.setDue(item, to: nil, hasTime: false) }
            }
        }
        Menu("Priority") {
            ForEach([("None", 0), ("Low", 9), ("Medium", 5), ("High", 1)], id: \.1) { name, value in
                CheckedItem(title: name, checked: item.priorityBucket == value) { model.setPriority(item, to: value) }
            }
        }
        Button(item.isFlagged ? "Remove Flag" : "Flag") { model.setFlag(item, to: !item.isFlagged) }
        Menu("List") {
            ForEach(model.lists.filter { !$0.isSmart }) { list in
                CheckedItem(title: list.title, checked: list.id == item.listID) { model.move(item, toListID: list.id) }
            }
        }
    }
}

/// Asked inline, in the row, because a pop-up dialog would close the menu panel.
struct DeleteConfirmation: View {
    let item: ReminderItem
    let model: TaskModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Delete “\(item.title)”?", systemImage: "trash")
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Text(warning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", action: onDone)
                Spacer()
                Button("Delete") {
                    onDone()
                    model.delete(item)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
        .padding(.vertical, 2)
    }

    private var warning: String {
        let subtasks = model.subtaskCount(of: item)
        let also = subtasks == 0 ? "" : subtasks == 1 ? " Its sub-task goes too." : " Its \(subtasks) sub-tasks go too."
        return (item.isRepeating
                ? "This also removes all its repeats from Reminders."
                : "It will be removed from Reminders.") + also + " This can't be undone."
    }
}
