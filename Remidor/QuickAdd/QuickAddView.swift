//
//  QuickAddView.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// The "add a reminder" box. In the hotkey panel it also lists open tasks, so one can be picked to work on.
struct QuickAddView: View {
    let model: TaskModel
    var autofocus = false
    var onAdded: (() -> Void)?
    /// When set, open tasks are listed under the box and one can be chosen with ↑ ↓ and Return.
    var onPickTask: ((ReminderItem) -> Void)?
    /// For the dropdown, whose list is outside this view: move the highlight by one row (false when there is none),
    /// start the highlighted one (false when nothing is highlighted), and check it off.
    var onMoveRow: ((Int) -> Bool)?
    var onOpenRow: (() -> Bool)?
    var onCompleteRow: (() -> Void)?

    @State private var draft: QuickAddDraft
    @State private var showCalendar = false
    @State private var justAdded = false
    @State private var isAdding = false
    @State private var focusTrigger = 0
    @State private var selection = 0
    @State private var expanded = Set<String>()
    @State private var editing = Set<String>()
    /// The smart list picked with the chips under the box, if any.
    @State private var listFilter: String?

    init(model: TaskModel, autofocus: Bool = false, draft: QuickAddDraft? = nil, onAdded: (() -> Void)? = nil,
         onPickTask: ((ReminderItem) -> Void)? = nil, onMoveRow: ((Int) -> Bool)? = nil,
         onOpenRow: (() -> Bool)? = nil, onCompleteRow: (() -> Void)? = nil) {
        self.model = model
        self.autofocus = autofocus
        self.onAdded = onAdded
        self.onPickTask = onPickTask
        self.onMoveRow = onMoveRow
        self.onOpenRow = onOpenRow
        self.onCompleteRow = onCompleteRow
        _draft = State(initialValue: draft ?? QuickAddDraft(model: model))
    }

    var body: some View {
        let suggestions = draft.suggestions
        let rows = quickRows(suggestions: suggestions)

        VStack(alignment: .leading, spacing: 6) {
            inputField

            if !suggestions.isEmpty {
                SuggestionList(suggestions: suggestions) { suggestion in
                    draft.apply(suggestion)
                    focusTrigger += 1
                }
                .transition(RevealTransition())
            }

            DetailFields(draft: draft, onSubmit: submit)

            // Always shown, so the box keeps its size when the first character is typed.
            QuickAddControls(draft: draft, showCalendar: $showCalendar)

            if onPickTask != nil { listChips }

            if !rows.isEmpty {
                Divider().padding(.vertical, 2)
                QuickSelectList(model: model, rows: rows, selection: $selection, expanded: $expanded, editing: $editing,
                                onActivate: activate, onComplete: model.completeOnly, onRefocus: { focusTrigger += 1 })
                    .transition(RevealTransition())
            }

            // The dropdown shows its own banner under the list; the hotkey box shows it here.
            if onPickTask != nil {
                if let notice = model.undoNotice {
                    NoticeBanner(notice: notice, onUndo: model.undoNoticeAction)
                        .transition(RevealTransition())
                }
                if let completed = model.undoBannerItem {
                    UndoBanner(item: completed, canUndo: model.undoBannerCanUndo) { model.undoComplete(completed) }
                        .transition(RevealTransition())
                }
                if let message = model.errorMessage {
                    ErrorBanner(message: message, onDismiss: model.dismissError)
                        .transition(RevealTransition())
                }
            }
        }
        .background(undoShortcut)
        .background(rowShortcuts)
        .animation(Motion.reveal, value: model.undoBannerItem?.id)
        .animation(Motion.reveal, value: model.undoNotice)
        .animation(Motion.reveal, value: model.errorMessage)
        .onChange(of: draft.text) { selection = 0 }
        .onChange(of: rows.count) { selection = min(selection, max(rows.count - 1, 0)) }
        .onChange(of: model.lists.map(\.id)) { draft.reparse() }
        .onAppear {
            if autofocus { Task { @MainActor in focusTrigger += 1 } }
        }
        .animation(Motion.reveal, value: suggestions.map(\.id))
        .animation(Motion.reveal, value: draft.pickedTags)
        .animation(Motion.reveal, value: showCalendar)
        .animation(Motion.reveal, value: draft.hasText)
    }

    /// Today, Scheduled, Flagged and the other smart lists, to look at one list on its own. Picking the
    /// chosen one again shows everything.
    private var listChips: some View {
        HStack(spacing: 6) {
            ForEach(model.sections.map(\.list).filter(\.isSmart)) { list in
                let on = list.id == activeFilter
                Button { listFilter = on ? nil : list.id } label: {
                    Text(list.title)
                        .font(.caption)
                        .foregroundStyle(on ? list.color : .secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(on ? list.color.opacity(0.15) : Color.primary.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.12), value: listFilter)
    }

    /// The chosen smart list, unless it has been turned off in Settings since.
    private var activeFilter: String? {
        listFilter.flatMap { id in model.sections.contains { $0.list.id == id } ? id : nil }
    }

    /// The highlighted task and the list it is shown under.
    private func highlighted() -> (item: ReminderItem, list: ReminderList)? {
        let rows = quickRows(suggestions: draft.suggestions)
        guard rows.indices.contains(selection), case .task(let item, let list) = rows[selection] else { return nil }
        return (item, list)
    }

    /// ⌘F flags, ⌘I opens the details and ⌘E edits the highlighted task.
    private var rowShortcuts: some View {
        Group {
            Button("Flag") { if let task = highlighted() { model.setFlag(task.item, to: !task.item.isFlagged) } }
                .keyboardShortcut("f", modifiers: .command)
            Button("Details") {
                guard let task = highlighted() else { return }
                let key = QuickRow.key(of: task.item, in: task.list)
                if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
            }
            .keyboardShortcut("i", modifiers: .command)
            Button("Edit") { if let task = highlighted() { editing.insert(QuickRow.key(of: task.item, in: task.list)) } }
                .keyboardShortcut("e", modifiers: .command)
        }
        // Not in the dropdown, and not while a task is being edited.
        .disabled(onPickTask == nil || !editing.isEmpty)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// ⌘Z undoes the last completed task. While something is typed it is left alone, so it still
    /// undoes typing as usual.
    private var undoShortcut: some View {
        Button("Undo") { model.undoLast() }
            .keyboardShortcut("z", modifiers: .command)
            // Not while the banner shows a repeating task, which can't be undone: ⌘Z must not undo an older one.
            .disabled(draft.text.isEmpty == false
                      || (model.undoNotice == nil && (model.recentlyCompleted.isEmpty
                          || (model.undoBannerItem != nil && !model.undoBannerCanUndo))))
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var inputField: some View {
        HStack(spacing: 6) {
            Image(systemName: justAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                .foregroundStyle(justAdded ? .green : Color.accentColor)
                .symbolEffect(.bounce, options: .speed(0.5), value: justAdded)
                .contentTransition(.symbolEffect(.replace))
            HighlightedTextField(
                text: $draft.text,
                placeholder: "Add a new Reminder! e. g. Call mom at 8pm tmrw !!!",
                tokens: draft.parsed.tokens,
                color: draft.color(for:),
                focusTrigger: focusTrigger,
                onSubmit: submit,
                onShiftSubmit: completeHighlighted,
                onTab: absorbTyped,
                onMove: move
            )
            .frame(maxWidth: .infinity)
            if !draft.title.isEmpty {
                Button("Add", action: submit)
                    .controlSize(.small)
                    .disabled(draft.linkIsInvalid)
                    .transition(.opacity)
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
        .animation(.snappy(duration: 0.3), value: draft.title.isEmpty)
    }

    // MARK: Quick select

    /// "Add …" for the typed title, followed by the open tasks that match it (dates and other tokens are ignored).
    private func quickRows(suggestions: [QuickAddDraft.Suggestion]) -> [QuickRow] {
        guard onPickTask != nil, suggestions.isEmpty else { return [] }
        // Grouped like the dropdown: Today and the other smart lists, then each list with its sections.
        let query = draft.title.lowercased()
        let tasks = model.sections.filter { activeFilter == nil || $0.list.id == activeFilter }.flatMap { section in
            // A smart list puts what is late first. Folded sub-tasks stay hidden unless something is being searched for.
            section.entries(foldedParents: query.isEmpty ? model.collapsedParentIDs : [], foldedSections: [])
                .compactMap { entry -> ReminderItem? in
                    if case .item(let item) = entry { return item }
                    return nil
                }
                .filter { query.isEmpty || $0.title.lowercased().contains(query) }
                .map { QuickRow.task($0, in: section.list) }
        }
        return (draft.title.isEmpty ? [] : [.add(draft.title)]) + tasks
    }

    private func activate(_ row: QuickRow) {
        switch row {
        case .add: addCurrent()
        case .task(let item, _): onPickTask?(item)
        }
    }

    /// Shift + Return checks off the highlighted task.
    private func completeHighlighted() {
        if onPickTask == nil { onCompleteRow?(); return }
        let rows = quickRows(suggestions: draft.suggestions)
        guard rows.indices.contains(selection), case .task(let item, _) = rows[selection] else { return }
        model.completeOnly(item)
    }

    private func move(_ delta: Int) -> Bool {
        if onPickTask == nil { return onMoveRow?(delta) ?? false }
        let count = quickRows(suggestions: draft.suggestions).count
        guard count > 0 else { return false }
        selection = min(max(selection + delta, 0), count - 1)
        return true
    }

    // MARK: Actions

    /// Takes in everything still being typed: the open ~list / #tag suggestion first, then every
    /// recognized (coloured) token, which all move out of the text and onto the chips.
    /// Returns false if there was nothing to take in.
    private func absorbTyped() -> Bool {
        let absorbed = draft.absorbTyped()
        if absorbed { focusTrigger += 1 }
        return absorbed
    }

    /// Return takes in everything first, then acts on the highlighted row: adding the reminder, or
    /// starting the chosen task in the hotkey panel.
    private func submit() {
        let absorbed = absorbTyped()
        // Only metadata was typed, so there is no reminder to add yet and the highlighted row isn't meant.
        if absorbed && draft.title.isEmpty { return }
        // Nothing to add: in the dropdown, Return starts the highlighted reminder.
        if onPickTask == nil, draft.title.isEmpty, onOpenRow?() == true { return }

        let rows = quickRows(suggestions: draft.suggestions)
        if rows.indices.contains(selection) { activate(rows[selection]) } else { addCurrent() }
    }

    private func addCurrent() {
        // Return pressed twice in a row must not add the reminder twice.
        guard !isAdding, let request = draft.request else { return }
        isAdding = true
        Task {
            defer { isAdding = false }
            guard await model.addReminder(request) else { return }
            draft.reset()
            showCalendar = false
            justAdded = true
            if let onAdded {
                try? await Task.sleep(for: .seconds(0.5))
                onAdded()
            } else {
                try? await Task.sleep(for: .seconds(1.5))
            }
            justAdded = false
        }
    }
}

/// The lists or tags that match what is being typed, to pick with the mouse.
struct SuggestionList: View {
    let suggestions: [QuickAddDraft.Suggestion]
    let onSelect: (QuickAddDraft.Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button { onSelect(suggestion) } label: {
                    Text(suggestion.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
    }
}
