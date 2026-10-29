//
//  QuickAddControls.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// The date, priority, flag and list buttons under the quick-add box, plus tag chips and the date picker.
struct QuickAddControls: View {
    @Bindable var draft: QuickAddDraft
    @Binding var showCalendar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            buttons
            if !draft.pickedTags.isEmpty {
                tagChips.transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showCalendar {
                calendar.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button { showCalendar.toggle() } label: {
                Chip(icon: "calendar", label: dateLabel, active: draft.due != nil)
            }
            .buttonStyle(.plain)

            Menu {
                Button("Never") { draft.setRecurrence(nil) }
                Divider()
                Button("Daily") { draft.setRecurrence(Recurrence(frequency: .daily)) }
                Button("Weekdays") { draft.setRecurrence(.weekdaysOnly) }
                Button("Weekly") { draft.setRecurrence(Recurrence(frequency: .weekly)) }
                Button("Monthly") { draft.setRecurrence(Recurrence(frequency: .monthly)) }
                Button("Yearly") { draft.setRecurrence(Recurrence(frequency: .yearly)) }
            } label: {
                Chip(icon: "repeat", label: draft.recurrence?.shortLabel ?? "", active: draft.recurrence != nil)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .help("Repeat. You can also type \"every sunday\" or \"every 2 weeks\".")

            Menu {
                Button("None") { draft.setPriority(nil) }
                Button("Low  !") { draft.setPriority(9) }
                Button("Medium  !!") { draft.setPriority(5) }
                Button("High  !!!") { draft.setPriority(1) }
            } label: {
                Chip(icon: draft.priority == nil ? "exclamationmark.2" : nil, label: priorityLabel, active: draft.priority != nil)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .help("Priority")

            Button { draft.toggleFlag() } label: {
                Chip(icon: draft.flagged ? "flag.fill" : "flag", label: "", active: draft.flagged, tint: .orange)
            }
            .buttonStyle(.plain)
            .help(draft.flagged ? "Remove the flag" : "Flag this reminder")
            .accessibilityLabel(draft.flagged ? "Remove the flag" : "Flag this reminder")

            if draft.lockedListID == nil {
            Menu {
                ForEach(draft.realLists) { list in
                    Button(list.title) { draft.setList(list.id) }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(draft.list?.color ?? .gray).frame(width: 7, height: 7)
                    Text(draft.list?.title ?? "List").lineLimit(1)
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            }

            Spacer(minLength: 0)
        }
    }

    private var tagChips: some View {
        HStack(spacing: 4) {
            ForEach(draft.pickedTags, id: \.self) { tag in
                Button { draft.pickedTags.removeAll { $0 == tag } } label: {
                    HStack(spacing: 3) {
                        Text("#" + tag)
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption)
                    .foregroundStyle(Color.purple)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.purple.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                quickDate("Today", daysFromNow: 0)
                quickDate("Tomorrow", daysFromNow: 1)
                quickDate("Weekend", day: draft.weekendDay)
                quickDate("Next week", day: draft.nextWeekDay)
                Spacer()
                Button("Clear") { draft.clearDate() }.controlSize(.small)
            }
            Toggle("Time", isOn: Binding(get: { draft.hasTime }, set: { draft.setTime($0) }))
                .toggleStyle(.switch).controlSize(.small)
            DatePicker("", selection: Binding(get: { draft.due ?? Date() }, set: { draft.setDate($0) }),
                       displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date])
                .datePickerStyle(.graphical).labelsHidden()
        }
    }

    private func quickDate(_ title: String, daysFromNow days: Int) -> some View {
        quickDate(title, day: Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    private func quickDate(_ title: String, day: Date) -> some View {
        Button(title) { draft.setDate(Calendar.current.startOfDay(for: day), hasTime: false) }
            .controlSize(.small)
    }

    private var dateLabel: String {
        guard let due = draft.due else { return "Date" }
        return describeDue(due, hasTime: draft.hasTime, includeWeekday: false)
    }

    private var priorityLabel: String {
        switch draft.priority {
        case 1: "!!!"
        case 5: "!!"
        case 9: "!"
        default: ""
        }
    }
}

/// A small rounded label such as "Tomorrow, 8:00 PM". Without a label it is just an icon.
private struct Chip: View {
    let icon: String?
    let label: String
    let active: Bool
    var tint: Color = .accentColor
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).symbolEffect(.bounce, options: .speed(0.5), value: active) }
            if !label.isEmpty { Text(label).lineLimit(1).contentTransition(.interpolate) }
        }
        .font(.caption)
        .foregroundStyle(active ? tint : .secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(active ? tint.opacity(hovering ? 0.25 : 0.15) : Color.primary.opacity(hovering ? 0.16 : 0.08)))
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.4), value: active)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
