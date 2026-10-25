//
//  DurationPicker.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// Hour and minute boxes with chevrons above and below, typing support and quick presets.
/// The binding holds the total in minutes; minutes carry over into hours.
struct DurationPicker: View {
    @Binding var totalMinutes: Int
    var presets = [15, 30, 45, 60]

    private static let allowed = 1...999
    private static let minuteStep = 15

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                box(value: Binding(get: { totalMinutes / 60 }, set: { set($0 * 60 + totalMinutes % 60) }),
                    unit: "h", step: 60)
                box(value: Binding(get: { totalMinutes % 60 }, set: { set(totalMinutes / 60 * 60 + $0) }),
                    unit: "m", step: Self.minuteStep)
            }
            HStack(spacing: 4) {
                ForEach(presets, id: \.self, content: presetButton)
            }
        }
    }

    private func presetButton(_ minutes: Int) -> some View {
        let selected = totalMinutes == minutes
        return Button { set(minutes) } label: {
            Text(minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m")
                .font(.caption)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func box(value: Binding<Int>, unit: String, step: Int) -> some View {
        VStack(spacing: 0) {
            chevron("chevron.up") { nudge(1, by: step) }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .frame(width: 26)
                Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 9, alignment: .leading)
            }
            .frame(width: 64, height: 32)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
            chevron("chevron.down") { nudge(-1, by: step) }
        }
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Hour chevrons add or remove a full hour. Minute chevrons jump to the next quarter-hour, so a
    /// typed 20 goes to 30 going up and to 15 going down.
    private func nudge(_ direction: Int, by step: Int) {
        guard step < 60 else { return set(totalMinutes + direction * step) }
        let minutes = totalMinutes
        set(direction > 0 ? (minutes / step + 1) * step : ((minutes + step - 1) / step - 1) * step)
    }

    private func set(_ minutes: Int) {
        totalMinutes = min(max(minutes, Self.allowed.lowerBound), Self.allowed.upperBound)
    }
}
