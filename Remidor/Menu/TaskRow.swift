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
    /// The row the arrow keys are on.
    var highlighted = false
    /// False while a drag has only just ended, so letting go isn't taken for a click.
    var allowsClicks: () -> Bool = { true }
    @State private var hovering = false
    /// A long title opens up in full once the pointer has rested on it for a moment, not as it passes over.
    @State private var showsFull = false
    @State private var confirmingDelete = false
    @State private var editing = false
    @State private var editFocus = EditFocus.title
    @State private var addingSubtask = false

    /// The order of the list this reminder is in, which its sub-tasks follow unless told otherwise.
    private var listOrder: SortOrder {
        model.lists.first { $0.id == item.listID }.map(model.sortOrder(for:)) ?? model.sortOrder
    }

    private func beginEditing(_ focus: EditFocus) {
        guard allowsClicks() else { return }
        editFocus = focus
        editing = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editing {
                TaskEditor(item: item, model: model, focus: editFocus) { editing = false }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if confirmingDelete {
                DeleteConfirmation(item: item, model: model) { confirmingDelete = false }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                header
                if addingSubtask {
                    TaskComposer(model: model, listID: item.listID, parent: item, placeholder: "New sub-task") {
                        withAnimation(.snappy(duration: 0.2)) { addingSubtask = false }
                    }
                    .padding(.leading, 20).padding(.trailing, 6)
                }
                Reveal(shown: showsFull) {
                    TaskDetails(item: item, model: model, onEditNotes: { beginEditing(.notes) })
                        .padding(.leading, 30).padding(.trailing, 8).padding(.bottom, 8)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 7).fill(highlighted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(hovering ? 0.08 : 0)))
        .padding(.leading, CGFloat(item.depth) * 20)
        // Reports the pointer as it moves, not only when it enters. Entering while the row is still
        // opening or closing can go unnoticed, which used to leave the row stuck shut.
        .onContinuousHover { phase in
            switch phase {
            case .active: if !hovering { hovering = true }
            case .ended: hovering = false
            }
        }
        .contextMenu { contextMenu }
        .animation(Motion.reveal, value: confirmingDelete)
        .animation(Motion.reveal, value: editing)
        .onChange(of: editing) { _, now in onEditing(now) }
        .animation(.snappy(duration: 0.3), value: hovering)
        .animation(.snappy(duration: 0.3), value: highlighted)
        .animation(Motion.reveal, value: showsFull)
        .task(id: hovering) {
            guard hovering else {
                showsFull = false
                return
            }
            // The details open once the pointer has rested a while, and never while the list is being scrolled.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                if Task.isCancelled { return }
                if ScrollActivity.shared.isIdle(for: 0.4) {
                    showsFull = true
                    return
                }
            }
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Open") { model.openInReminders(item) }
        Button("Edit") { beginEditing(.title) }
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
        ReminderAttributeMenus(item: item, model: model)
        Divider()
        Button("Move Up") { model.moveReminder(item, by: -1) }
            .disabled(model.neighbor(of: item, offset: -1) == nil)
        Button("Move Down") { model.moveReminder(item, by: 1) }
            .disabled(model.neighbor(of: item, offset: 1) == nil)
        Divider()
        Button("Delete…", role: .destructive) { confirmingDelete = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            CompletionRing(color: item.listColor, size: item.depth > 0 ? 14 : 16, label: "Mark “\(item.title)” as done", action: done)
            VStack(alignment: .leading, spacing: 0) {
                Text(rowTitle(item, markColor: item.listColor))
                    .lineLimit(showsFull ? nil : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                caption
                // The notes are shown in full once the details open.
                Reveal(shown: !showsFull) { NotesPreview(lines: NotesFormatting.previewLines(item.notes)) }
            }

            Spacer(minLength: 0)
            if item.childCount > 0 { subtaskToggle }
            if item.isFlagged {
                Image(systemName: "flag.fill").font(.caption).foregroundStyle(.orange)
                    .accessibilityLabel("Flagged")
            }
            if hovering || highlighted { startButton }
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .contentShape(Rectangle())
        // A click edits once the details are open, and otherwise goes on to the timer.
        .onTapGesture { if showsFull { beginEditing(.title) } else { start() } }
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
            HStack(spacing: 3) {
                // A folded parent says how much it hides.
                if folded {
                    Text("\(item.childCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(folded ? -90 : 0))
                    .frame(width: 22, height: 22)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(folded ? "Show \(item.childCount) sub-tasks" : "Hide \(item.childCount) sub-tasks")
        .accessibilityLabel(folded ? "Show \(item.childCount) sub-tasks" : "Hide \(item.childCount) sub-tasks")
    }

    /// Goes on to choosing how long to work on the reminder.
    private var startButton: some View {
        Button(action: start) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Start a timer")
        .accessibilityLabel("Start a timer for “\(item.title)”")
        .transition(.opacity)
    }
}

/// Everything known about a reminder: notes with clickable links, URL and key facts.
struct TaskDetails: View {
    let item: ReminderItem
    let model: TaskModel
    /// When set, a click on the notes calls this instead of editing them right here.
    var onEditNotes: (() -> Void)?
    @State private var editingNotes = false
    @State private var draftNotes = ""

    /// Reminders keeps notes as plain text, with line breaks but no formatting, so that is what is edited here.
    /// Web addresses in them still turn into links when they are shown.
    private var notesView: some View {
        Group {
            if editingNotes {
                VStack(alignment: .trailing, spacing: 4) {
                    NotesEditor(text: $draftNotes, onCancel: cancelNotes, onEnd: endNotes)
                        .frame(height: 90)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    HStack(spacing: 6) {
                        Text("⌘↩ saves").font(.caption2).foregroundStyle(.tertiary)
                        Button("Cancel", action: cancelNotes).controlSize(.small)
                        Button("Save", action: saveNotes)
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                // Leaving the box, or the panel closing, keeps what was typed instead of losing it.
                .onDisappear(perform: endNotes)
            } else if let notes = item.notes {
                Text(linkified(NotesFormatting.detail(notes)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: startNotes)
                    .help("Click to edit the notes")
            } else {
                Button(action: startNotes) {
                    Label("Add notes", systemImage: "note.text").font(.callout).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func startNotes() {
        if let onEditNotes { onEditNotes(); return }
        draftNotes = item.notes ?? ""
        editingNotes = true
    }

    private func saveNotes() {
        editingNotes = false
        model.setNotes(item, to: draftNotes)
    }

    private func cancelNotes() { editingNotes = false }

    private func endNotes() {
        if editingNotes { saveNotes() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            notesView
            if let url = item.url {
                Link(destination: url) {
                    Label(url.absoluteString, systemImage: "link").lineLimit(2).font(.callout)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let due = item.due {
                    fact("Due", item.dueHasTime
                         ? due.formatted(date: .abbreviated, time: .shortened)
                         : due.formatted(date: .abbreviated, time: .omitted))
                }
                if let repeats = item.recurrence { fact("Repeats", repeats.label) }
                if let created = item.created {
                    fact("Created", created.formatted(date: .abbreviated, time: .omitted))
                }
            }
            Button { model.openInReminders(item) } label: {
                Label("Open in Reminders", systemImage: "arrow.up.forward.app").font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
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
