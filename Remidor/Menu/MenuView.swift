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
    @State private var updates = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
                .transition(.opacity)
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
        .background(PanelAligner())
        .animation(.snappy(duration: 0.5), value: model.phase)
        .animation(.snappy(duration: 0.5), value: model.undoBannerItem?.id)
        .animation(.snappy(duration: 0.5), value: model.errorMessage)
        .animation(.snappy(duration: 0.5), value: updates.availableUpdate)
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
                    UndoBanner(item: completed, canUndo: model.undoBannerCanUndo) { model.undoComplete(completed) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let message = model.errorMessage {
                    ErrorBanner(message: message, onDismiss: model.dismissError)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let update = updates.availableUpdate {
                    UpdateBanner(update: update, onDismiss: updates.dismissBanner)
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
            HStack(spacing: 2) {
                FooterButton(title: "Settings", icon: "gearshape", iconOnly: true) {
                    openWindow(id: "settings")
                    NSApp.activate()
                }
                FooterButton(title: "Open Reminders", icon: "checklist", iconOnly: true, action: model.openRemindersApp)
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

private struct FooterButton: View {
    let title: String
    let icon: String
    var iconOnly = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.callout)
                .labelStyle(FooterLabelStyle(iconOnly: iconOnly))
        }
        .buttonStyle(FooterButtonStyle())
        .help(title)
    }
}

private struct FooterLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly { configuration.icon } else { Label(configuration) }
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
