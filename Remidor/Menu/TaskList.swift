//
//  TaskList.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// The scrolling list of reminders, one section per list.
struct TaskList: View {
    let model: TaskModel
    let onStart: (ReminderItem) -> Void

    var body: some View {
        if model.accessDenied {
            VStack(alignment: .leading, spacing: 8) {
                Label("Remidor needs access to your reminders.", systemImage: "lock.fill")
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } else if model.sections.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.id) { index, section in
                        if index > 0 { Divider().padding(.vertical, 6) }
                        let collapsed = model.collapsedListIDs.contains(section.id)
                        SectionHeader(section: section, collapsed: collapsed) {
                            withAnimation(.snappy(duration: 0.4)) { model.toggleCollapsed(section.list) }
                        }
                        if !collapsed {
                            ForEach(section.items) { item in
                                TaskRow(item: item, model: model, start: { onStart(item) }, done: { model.completeOnly(item) })
                                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                            removal: .opacity.combined(with: .scale(scale: 0.95))))
                            }
                        }
                    }
                }
                .animation(.snappy(duration: 0.5), value: layoutKey)
            }
            .frame(height: listHeight)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.hasAccess ? "sparkles" : "hourglass")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .speed(0.5), isActive: !model.hasAccess)
            Text(model.hasAccess ? "All clear" : "Loading…").font(.headline)
            if model.hasAccess {
                Text("No open reminders in the selected lists.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
    }

    /// Changes whenever a section or task appears, disappears or moves, to drive the list animation.
    private var layoutKey: [String] {
        model.sections.map { section in
            model.collapsedListIDs.contains(section.id) ? section.id : section.id + ":" + section.items.map(\.id).joined(separator: ",")
        }
    }

    /// A ScrollView has no intrinsic height inside the menu bar panel, so size it explicitly:
    /// about 42pt per task and 34pt per section header, capped at 320pt (it scrolls beyond that).
    private var listHeight: CGFloat {
        let tasks = model.sections.reduce(0) { $0 + (model.collapsedListIDs.contains($1.id) ? 0 : $1.items.count) }
        let estimate = CGFloat(tasks) * 42 + CGFloat(model.sections.count) * 34
        return min(max(estimate, 100), 320)
    }
}

/// A list's name and count. Clicking it folds the list shut or open.
private struct SectionHeader: View {
    let section: ReminderSection
    let collapsed: Bool
    let onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: section.list.isSmart ? "sparkles" : "list.bullet")
                    .foregroundStyle(section.list.color)
                Text(section.list.title).font(.subheadline.weight(.semibold))
                Text("\(section.items.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentTransition(.numericText())
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .opacity(hovering || collapsed ? 1 : 0.5)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.3), value: hovering)
        .animation(.snappy(duration: 0.4), value: collapsed)
        .help(collapsed ? "Show \(section.list.title)" : "Hide \(section.list.title)")
    }
}
