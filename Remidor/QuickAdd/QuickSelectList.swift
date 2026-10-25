//
//  QuickSelectList.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

enum QuickRow: Identifiable {
    case add(String)
    case task(ReminderItem)

    var id: String {
        switch self {
        case .add: "add"
        case .task(let item): "task-" + item.id
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        QuickRowView(row: row, selected: index == selection, height: rowHeight, onComplete: onComplete)
                            .id(row.id)
                            .onTapGesture {
                                selection = index
                                onActivate(row)
                            }
                    }
                }
                .animation(.snappy(duration: 0.4), value: rows.map(\.id))
            }
            // A ScrollView has no intrinsic height here, so size it for up to eight rows.
            .frame(height: min(CGFloat(rows.count) * (rowHeight + 1), 288))
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
    let onComplete: (ReminderItem) -> Void

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
            case .task(let item):
                Color.clear.frame(width: CGFloat(item.depth) * 16, height: 1)
                CompletionRing(color: selected ? .white : item.listColor, checkColor: selected ? .accentColor : .white,
                               size: 12, hitSize: 20) { onComplete(item) }
                Text(rowTitle(item, markColor: selected ? .white : item.listColor))
                    .lineLimit(1).truncationMode(.tail).foregroundStyle(primary)
                Spacer(minLength: 0)
                if let due = dueText(item) {
                    Text(due)
                        .font(.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : (isOverdue(item) ? .red : secondary))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.2), value: selected)
    }
}
