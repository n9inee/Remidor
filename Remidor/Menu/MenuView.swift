//
//  MenuView.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// The panel that opens from the menu bar icon.
struct MenuView: View {
    let model: TaskModel
    @Environment(\.openWindow) private var openWindow
    @State private var minutes = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
                .transition(.opacity)
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
        .animation(.snappy(duration: 0.5), value: model.phase)
        .animation(.snappy(duration: 0.5), value: model.undoBannerItem?.id)
        .onAppear { model.scheduleRefresh() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            VStack(alignment: .leading, spacing: 10) {
                if model.hasAccess {
                    QuickAddView(model: model)
                    Divider()
                }
                TaskList(model: model) { item in
                    minutes = model.defaultMinutes
                    model.select(item)
                }
                if let completed = model.undoBannerItem {
                    UndoBanner(item: completed) { model.undoComplete(completed) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        case .choosing(let item):
            TimerSetupView(item: item, minutes: $minutes, secondaryTitle: "Cancel", onSecondary: model.cancel) {
                model.start(item, minutes: minutes)
            }
        case .running(let item, _):
            RunningTimerView(model: model, item: item)
        case .finished(let item):
            FinishedTimerView(
                item: item, minutes: $minutes,
                onExtend: { model.start(item, minutes: minutes) },
                onDone: { model.markDone(item) },
                onDismiss: model.cancel
            )
            .onAppear { minutes = model.defaultMinutes }
        }
    }

    private var footer: some View {
        HStack {
            FooterButton(title: "Settings", icon: "gearshape") {
                openWindow(id: "settings")
                NSApp.activate()
            }
            Spacer()
            if !model.recentlyCompleted.isEmpty {
                Menu {
                    ForEach(model.recentlyCompleted) { item in
                        Button { model.undoComplete(item) } label: {
                            Label("Undo “\(item.title)”", systemImage: "arrow.uturn.backward")
                        }
                    }
                } label: {
                    Label("Recent", systemImage: "clock.arrow.circlepath").font(.callout)
                }
                .menuStyle(.button).buttonStyle(FooterButtonStyle()).menuIndicator(.hidden)
                .transition(.opacity)
                Spacer()
            }
            FooterButton(title: "Quit", icon: "power") { NSApplication.shared.terminate(nil) }
        }
    }
}

private struct UndoBanner: View {
    let item: ReminderItem
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Completed “\(item.title)”").lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward").font(.callout.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
    }
}

private struct FooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(title, systemImage: icon).font(.callout) }
            .buttonStyle(FooterButtonStyle())
    }
}

private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0)))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
    }
}
