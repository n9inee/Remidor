//
//  TaskRow.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// One reminder in the list: a completion ring, title, due date and tags. It expands to show the
/// notes and details, and has a right-click menu.
struct TaskRow: View {
    let item: ReminderItem
    let model: TaskModel
    let start: () -> Void
    let done: () -> Void
    /// Tells the list when the edit box opens or closes.
    var onEditing: (Bool) -> Void = { _ in }
    @State private var hovering = false
    @State private var expanded = false
    @State private var confirmingDelete = false
    @State private var editing = false
    @State private var addingSubtask = false

    /// The order of the list this reminder is in, which its sub-tasks follow unless told otherwise.
    private var listOrder: SortOrder {
        model.lists.first { $0.id == item.listID }.map(model.sortOrder(for:)) ?? model.sortOrder
    }

    private var hasDetails: Bool { item.notes != nil || item.url != nil || !item.tags.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editing {
                TaskEditor(item: item, model: model) { editing = false }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if confirmingDelete {
                deleteConfirmation
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                header
                if addingSubtask {
                    TaskComposer(model: model, listID: item.listID, parent: item, placeholder: "New sub-task") {
                        withAnimation(.snappy(duration: 0.2)) { addingSubtask = false }
                    }
                    .padding(.leading, 20).padding(.trailing, 6)
                }
                if expanded {
                    TaskDetails(item: item)
                        .padding(.leading, 30).padding(.trailing, 8).padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
        .padding(.leading, CGFloat(item.depth) * 20)
        .onHover { hovering = $0 }
        .contextMenu { contextMenu }
        .animation(.snappy(duration: 0.4), value: expanded)
        .animation(.snappy(duration: 0.4), value: confirmingDelete)
        .animation(.snappy(duration: 0.4), value: editing)
        .onChange(of: editing) { _, now in onEditing(now) }
        .animation(.snappy(duration: 0.3), value: hovering)
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Open") { model.openInReminders(item) }
        Button("Edit") { editing = true }
        Button("Details") { expanded.toggle() }
        // Reminders only goes one level deep, so a sub-task can't have sub-tasks of its own.
        if item.parentID == nil {
            Divider()
            Button("Add Sub-task…") { withAnimation(.snappy(duration: 0.2)) { addingSubtask = true } }
            if item.childCount > 0 {
                Menu("Sort Sub-tasks") {
                    SortChoices(current: model.subtaskSortOrders[item.id], inherited: listOrder, inheritedTitle: "Same as the List") {
                        model.setSubtaskOrder($0, for: item)
                    }
                }
            }
        }
        Divider()
        Menu("Date") {
            Button("Today") { model.setDay(item, to: Date()) }
            Button("Tomorrow") { model.setDay(item, to: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()) }
            Button("Weekend") { model.setDay(item, to: model.weekendDay) }
            Button("Next Week") { model.setDay(item, to: model.nextWeekDay) }
            if item.due != nil {
                Divider()
                Button("Remove Date") { model.setDue(item, to: nil, hasTime: false) }
            }
        }
        Menu("Priority") {
            ForEach([("None", 0), ("Low", 9), ("Medium", 5), ("High", 1)], id: \.1) { name, value in
                Button { model.setPriority(item, to: value) } label: {
                    if item.priority == value { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        }
        Button(item.isFlagged ? "Remove Flag" : "Flag") { model.setFlag(item, to: !item.isFlagged) }
        Menu("List") {
            ForEach(model.lists.filter { !$0.isSmart }) { list in
                Button { model.move(item, toListID: list.id) } label: {
                    if list.id == item.listID { Label(list.title, systemImage: "checkmark") } else { Text(list.title) }
                }
            }
        }
        Divider()
        Button("Move Up") { model.moveReminder(item, by: -1) }
            .disabled(model.neighbor(of: item, offset: -1) == nil)
        Button("Move Down") { model.moveReminder(item, by: 1) }
            .disabled(model.neighbor(of: item, offset: 1) == nil)
        Divider()
        Button("Delete…", role: .destructive) { confirmingDelete = true }
    }

    /// Asked inline, in the row, because a pop-up dialog would close the menu panel.
    private var deleteConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Delete “\(item.title)”?", systemImage: "trash")
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Text(item.isRepeating
                 ? "This also removes all its repeats from Reminders. It can't be undone."
                 : "It will be removed from Reminders. This can't be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { confirmingDelete = false }
                Spacer()
                Button("Delete") {
                    confirmingDelete = false
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

    private var header: some View {
        HStack(spacing: 8) {
            CompletionRing(color: item.listColor, size: item.depth > 0 ? 14 : 16, action: done)
            VStack(alignment: .leading, spacing: 0) {
                Text(rowTitle(item, markColor: item.listColor))
                    .lineLimit(hovering || expanded ? nil : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                caption
            }

            Spacer(minLength: 0)
            if hasDetails || hovering || expanded { infoButton }
            if item.isFlagged {
                Image(systemName: "flag.fill").font(.caption).foregroundStyle(.orange)
                    .accessibilityLabel("Flagged")
            }
            if item.childCount > 0 { subtaskToggle }
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: start)
    }

    @ViewBuilder private var caption: some View {
        let due = dueText(item)
        if due != nil || !item.tags.isEmpty {
            HStack(spacing: 6) {
                if let due { Text(due).foregroundStyle(isOverdue(item) ? Color.red : .secondary) }
                ForEach(item.tags, id: \.self) { Text("#" + $0).foregroundStyle(Color.purple) }
            }
            .font(.caption)
        }
    }

    /// Folds the sub-tasks away or brings them back.
    private var subtaskToggle: some View {
        let folded = model.collapsedParentIDs.contains(item.id)
        return Button { withAnimation(.snappy(duration: 0.4)) { model.toggleSubtasks(of: item) } } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(folded ? -90 : 0))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(folded ? "Show \(item.childCount) sub-tasks" : "Hide \(item.childCount) sub-tasks")
        .accessibilityLabel(folded ? "Show \(item.childCount) sub-tasks" : "Hide \(item.childCount) sub-tasks")
    }

    /// Shows or hides the notes and details.
    private var infoButton: some View {
        Button { expanded.toggle() } label: {
            Image(systemName: expanded ? "info.circle.fill" : "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "Hide details" : "Show details")
        .accessibilityLabel(expanded ? "Hide details" : "Show details")
        .transition(.opacity)
    }
}

/// Everything known about a reminder: notes with clickable links, URL and key facts.
struct TaskDetails: View {
    let item: ReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notes = item.notes {
                Text(linkified(notes))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let url = item.url {
                Link(destination: url) {
                    Label(url.absoluteString, systemImage: "link").lineLimit(2).font(.callout)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                fact("List", item.listTitle)
                if let due = item.due {
                    fact("Due", item.dueHasTime
                         ? due.formatted(date: .abbreviated, time: .shortened)
                         : due.formatted(date: .abbreviated, time: .omitted))
                }
                if item.priority > 0 {
                    fact("Priority", item.priority <= 4 ? "High" : item.priority == 5 ? "Medium" : "Low")
                }
                if item.isFlagged { fact("Flag", "Flagged") }
                if let repeats = item.recurrence { fact("Repeats", repeats.label) }
                if let created = item.created {
                    fact("Created", created.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).foregroundStyle(.tertiary).frame(width: 52, alignment: .leading)
            Text(value).foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
