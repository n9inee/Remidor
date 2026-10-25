//
//  TimerViews.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// The task title with its list underneath.
struct TaskTitleBlock: View {
    let item: ReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(taggedTitle(item.title)).font(.headline).lineLimit(3)
            HStack(spacing: 5) {
                Circle().fill(item.listColor).frame(width: 7, height: 7)
                Text(item.listTitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "How long do you want to work on this?", shared by the menu and the hotkey panel.
struct TimerSetupView: View {
    let item: ReminderItem
    @Binding var minutes: Int
    let secondaryTitle: String
    let onSecondary: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TaskTitleBlock(item: item)
            Text("How long do you want to work on this?").foregroundStyle(.secondary)
            DurationPicker(totalMinutes: $minutes).frame(maxWidth: .infinity)
            HStack {
                Button(secondaryTitle, action: onSecondary)
                Spacer()
                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .tint(item.listColor)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The countdown ring.
struct RunningTimerView: View {
    let model: TaskModel
    let item: ReminderItem

    var body: some View {
        let progress = model.runTotal > 0 ? model.remaining / model.runTotal : 0
        VStack(spacing: 12) {
            TaskTitleBlock(item: item)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(item.listColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Text(formatRemaining(model.remaining))
                    .font(.system(size: 26, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.9), value: Int(model.remaining))
            }
            .frame(width: 118, height: 118)
            HStack {
                Button("Stop", action: model.cancel)
                Spacer()
                Button("Mark done") { model.markDone(item) }
                    .buttonStyle(.borderedProminent)
                    .tint(item.listColor)
            }
        }
    }
}

/// Shown when the time is up: extend, mark done, or close without doing either.
struct FinishedTimerView: View {
    let item: ReminderItem
    @Binding var minutes: Int
    let onExtend: () -> Void
    let onDone: () -> Void
    let onDismiss: () -> Void

    @State private var bounce = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .speed(0.5), value: bounce)
            TaskTitleBlock(item: item)
            Text("Time's up. Extend by:")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            DurationPicker(totalMinutes: $minutes)
            HStack {
                Button("Extend", action: onExtend)
                Spacer()
                Button("Mark done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("Close without extending or marking done")
        }
        .onAppear { bounce.toggle() }
    }
}
