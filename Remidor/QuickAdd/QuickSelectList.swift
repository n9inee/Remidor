//
//  QuickSelectList.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

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
}

/// The rows under the quick-add box: "Add …" followed by matching open tasks.
struct QuickSelectList: View {
    let rows: [QuickRow]
    @Binding var selection: Int
    let onActivate: (QuickRow) -> Void
    let onComplete: (ReminderItem) -> Void

    private let rowHeight: CGFloat = 35
    private let maxHeight: CGFloat = 320

    @State private var expanded = Set<String>()
    @State private var contentHeight: CGFloat?

    /// What is drawn: list names and section headings between the tasks, and details under opened ones.
    private enum Entry: Identifiable {
        case list(ReminderList)
        case section(title: String, key: String)
        case row(index: Int, row: QuickRow)
        case details(ReminderItem, key: String)

        var id: String {
            switch self {
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
            result.append(.row(index: index, row: row))
            if expanded.contains(rowKey(item, list)) { result.append(.details(item, key: rowKey(item, list))) }
        }
        return result
    }

    /// Which row's details are open: a task shown twice opens each copy on its own.
    private func rowKey(_ item: ReminderItem, _ list: ReminderList) -> String { list.id + "-" + item.id }

    private func detailsOpen(_ row: QuickRow) -> Bool {
        if case .task(let item, let list) = row { return expanded.contains(rowKey(item, list)) }
        return false
    }

    private func toggleDetails(_ row: QuickRow) {
        guard case .task(let item, let list) = row else { return }
        let key = rowKey(item, list)
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
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
                        case .row(let index, let row):
                            QuickRowView(row: row, selected: index == selection, height: rowHeight, detailsOpen: detailsOpen(row),
                                         onComplete: onComplete, onToggleDetails: { toggleDetails(row) })
                                .id(row.id)
                                .onTapGesture {
                                    selection = index
                                    onActivate(row)
                                }
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

private struct QuickRowView: View {
    let row: QuickRow
    let selected: Bool
    let height: CGFloat
    var detailsOpen = false
    let onComplete: (ReminderItem) -> Void
    var onToggleDetails: () -> Void = {}

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
