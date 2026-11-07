//
//  QuickSelectList.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// A row under the quick-add box: the "Add …" row or a reminder to pick.
enum QuickRow: Identifiable {
    case add(String)
    /// A task, with the list it is shown under. The same task can appear under Today and under its own list.
    case task(ReminderItem, in: ReminderList)

    var id: String {
        switch self {
        case .add: "add"
        case .task(let item, let list): "task-" + list.id + "-" + item.id
        }
    }

    /// Identifies one shown copy of a task, for opening its details or editing it.
    static func key(of item: ReminderItem, in list: ReminderList) -> String { list.id + "-" + item.id }

    var item: ReminderItem? {
        if case .task(let item, _) = self { return item }
        return nil
    }
}

/// The rows under the quick-add box: "Add …" followed by matching open tasks.
struct QuickSelectList: View {
    let model: TaskModel
    let rows: [QuickRow]
    @Binding var selection: Int
    /// Which rows have their details open, and which are being edited. The box needs them for its shortcuts.
    @Binding var expanded: Set<String>
    @Binding var editing: Set<String>
    let onActivate: (QuickRow) -> Void
    let onComplete: (ReminderItem) -> Void
    /// Gives the typing field the keyboard back when an edit box or the delete card closes.
    var onRefocus: () -> Void = {}

    private let rowHeight: CGFloat = 35
    private let maxHeight: CGFloat = 320

    @State private var deleting: String?
    @State private var contentHeight: CGFloat?

    /// What is drawn: list names and section headings between the tasks, and details under opened ones.
    private enum Entry: Identifiable {
        case list(ReminderList)
        case section(title: String, key: String)
        case row(index: Int, row: QuickRow)
        case details(ReminderItem, key: String)
        /// "Overdue" over what is late in a smart list, with its Reschedule button.
        case overdue(ReminderList)
        case editor(ReminderItem, key: String)
        case confirmDelete(ReminderItem, key: String)

        var id: String {
            switch self {
            case .overdue(let list): "overdue-" + list.id
            case .editor(_, let key): "editor-" + key
            case .confirmDelete(_, let key): "delete-" + key
            case .list(let list): "list-" + list.id
            case .section(_, let key): "section-" + key
            case .row(_, let row): row.id
            case .details(_, let key): "details-" + key
            }
        }
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        var lastList: String?
        var lastSection: String?
        var overdueShown = Set<String>()
        for (index, row) in rows.enumerated() {
            guard case .task(let item, let list) = row else {
                result.append(.row(index: index, row: row))
                continue
            }
            if list.id != lastList {
                result.append(.list(list))
                lastList = list.id
                lastSection = nil
            }
            // Sections belong to regular lists. Sub-tasks sit under their parent, whatever their own section says.
            if !list.isSmart, item.depth == 0, let id = item.sectionID, let title = item.sectionTitle, id != lastSection {
                result.append(.section(title: title, key: list.id + "|" + id))
                lastSection = id
            }
            if list.isSmart, item.depth == 0, isOverdue(item), overdueShown.insert(list.id).inserted {
                result.append(.overdue(list))
            }
            let key = rowKey(item, list)
            if editing.contains(key) {
                result.append(.editor(item, key: key))
            } else if deleting == key {
                result.append(.confirmDelete(item, key: key))
            } else {
                result.append(.row(index: index, row: row))
                if expanded.contains(key) { result.append(.details(item, key: key)) }
            }
        }
        return result
    }

    /// Which row's details are open: a task shown twice opens each copy on its own.
    private func rowKey(_ item: ReminderItem, _ list: ReminderList) -> String { QuickRow.key(of: item, in: list) }

    private func detailsOpen(_ row: QuickRow) -> Bool {
        if case .task(let item, let list) = row { return expanded.contains(rowKey(item, list)) }
        return false
    }

    private func toggleDetails(_ row: QuickRow) {
        guard case .task(let item, let list) = row else { return }
        let key = rowKey(item, list)
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    /// The reminders shown under one smart list. Its Reschedule button moves the late ones among them.
    private func shownItems(in list: ReminderList) -> [ReminderItem] {
        rows.compactMap { row in
            if case .task(let item, let rowList) = row, rowList.id == list.id { return item }
            return nil
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .list(let list):
                            HStack(spacing: 5) {
                                if list.isSmart {
                                    Image(systemName: list.symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(list.color)
                                } else {
                                    Circle().fill(list.color).frame(width: 7, height: 7)
                                }
                                Text(list.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                            .accessibilityAddTraits(.isHeader)
                        case .section(let title, _):
                            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                                .padding(.horizontal, 8).padding(.top, 4)
                                .accessibilityAddTraits(.isHeader)
                        case .overdue(let list):
                            HStack(spacing: 6) {
                                Text("Overdue").font(.caption.weight(.semibold)).foregroundStyle(.red)
                                Spacer(minLength: 0)
                                Menu {
                                    ForEach(model.rescheduleChoices, id: \.title) { choice in
                                        Button(choice.title) { model.rescheduleOverdue(in: shownItems(in: list), toDay: choice.day) }
                                    }
                                } label: {
                                    Text("Reschedule").font(.caption.weight(.medium))
                                }
                                .menuStyle(.button).buttonStyle(HoverButtonStyle(horizontal: 6, vertical: 2, radius: 5)).menuIndicator(.hidden)
                                .fixedSize()
                                .help("Move everything that is overdue to another day")
                            }
                            .padding(.horizontal, 8).padding(.top, 4)
                        case .row(let index, let row):
                            QuickRowView(row: row, selected: index == selection, height: rowHeight, detailsOpen: detailsOpen(row),
                                         folded: row.item.map { model.collapsedParentIDs.contains($0.id) } ?? false,
                                         onComplete: onComplete, onToggleDetails: { toggleDetails(row) },
                                         onToggleFold: { if let item = row.item { model.toggleSubtasks(of: item) } })
                                .id(row.id)
                                .onTapGesture {
                                    selection = index
                                    onActivate(row)
                                }
                                .contextMenu { menu(for: row) }
                        case .editor(let item, let key):
                            TaskEditor(item: item, model: model) {
                                editing.remove(key)
                                onRefocus()
                            }
                            .padding(.vertical, 2)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        case .confirmDelete(let item, _):
                            DeleteConfirmation(item: item, model: model) {
                                deleting = nil
                                onRefocus()
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        case .details(let item, _):
                            TaskDetails(item: item)
                                .padding(.leading, 34).padding(.trailing, 8).padding(.bottom, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .animation(.snappy(duration: 0.4), value: entries.map(\.id))
            }
            // A ScrollView has no intrinsic height here, so it is sized to its content, up to a limit.
            .frame(height: min(contentHeight ?? CGFloat(rows.count) * (rowHeight + 1), maxHeight))
            .onChange(of: selection) { _, new in
                guard rows.indices.contains(new) else { return }
                withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(rows[new].id) }
            }
        }
    }
}

extension QuickSelectList {
    /// The right-click menu of a task: what the dropdown's menu has for a single reminder.
    @ViewBuilder fileprivate func menu(for row: QuickRow) -> some View {
        if case .task(let item, let list) = row {
            let key = rowKey(item, list)
            Button("Open") { model.openInReminders(item) }
            Button("Edit") { editing.insert(key) }
            Button(expanded.contains(key) ? "Hide Details" : "Details") { toggleDetails(row) }
            Divider()
            ReminderAttributeMenus(item: item, model: model)
            Divider()
            Button("Delete…", role: .destructive) { deleting = key }
        }
    }
}

/// One row of the pick list, with its completion ring and details.
private struct QuickRowView: View {
    let row: QuickRow
    let selected: Bool
    let height: CGFloat
    var detailsOpen = false
    var folded = false
    let onComplete: (ReminderItem) -> Void
    var onToggleDetails: () -> Void = {}
    var onToggleFold: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        // The highlighted row uses the accent colour with white text, like a native menu.
        let primary: Color = selected ? .white : .primary
        let secondary: Color = selected ? .white.opacity(0.8) : .secondary

        HStack(spacing: 6) {
            switch row {
            case .add(let title):
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(selected ? .white : Color.accentColor)
                    .frame(width: 12)
                Text("Add “\(title)”").lineLimit(1).foregroundStyle(primary)
                Spacer(minLength: 0)
                Text("↩").foregroundStyle(secondary)
            case .task(let item, _):
                Color.clear.frame(width: CGFloat(item.depth) * 16, height: 1)
                CompletionRing(color: selected ? .white : item.listColor, checkColor: selected ? .accentColor : .white,
                               size: 12, hitSize: 20) { onComplete(item) }
                Text(rowTitle(item, markColor: selected ? .white : item.listColor))
                    .lineLimit(1).truncationMode(.tail).foregroundStyle(primary)
                Spacer(minLength: 0)
                if item.isFlagged {
                    Image(systemName: "flag.fill").font(.caption).foregroundStyle(selected ? .white : .orange)
                }
                if let due = dueText(item) {
                    Text(due)
                        .font(.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : (isOverdue(item) ? .red : secondary))
                }
                if item.childCount > 0 {
                    Button(action: onToggleFold) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(secondary)
                            .rotationEffect(.degrees(folded ? -90 : 0))
                            .frame(width: 20, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(folded ? "Show \(item.childCount) sub-tasks" : "Hide \(item.childCount) sub-tasks")
                    .accessibilityLabel(folded ? "Show \(item.childCount) sub-tasks" : "Hide \(item.childCount) sub-tasks")
                }
                if hovering || selected || detailsOpen || item.notes != nil || item.url != nil || !item.tags.isEmpty {
                    Button(action: onToggleDetails) {
                        Image(systemName: detailsOpen ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(detailsOpen ? "Hide details" : "Show details")
                    .accessibilityLabel(detailsOpen ? "Hide details" : "Show details")
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: selected)
    }
}
