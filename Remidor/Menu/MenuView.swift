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
    @State private var creatingList = false
    /// The reminder the arrow keys are on, the search box and what is typed in it.
    @State private var highlight: String?
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

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
        .animation(.snappy(duration: 0.4), value: creatingList)
        .animation(.snappy(duration: 0.4), value: searching)
        .animation(.snappy(duration: 0.5), value: model.undoBannerItem?.id)
        .animation(.snappy(duration: 0.5), value: model.undoNotice)
        .animation(.snappy(duration: 0.5), value: model.errorMessage)
        .animation(.snappy(duration: 0.5), value: updates.availableUpdate)
        .onAppear {
            model.scheduleRefresh()
            highlight = nil
        }
    }

    // MARK: Keyboard and search

    private var activeQuery: String { searching ? query : "" }

    /// ↑ and ↓ move through the reminders as listed. False when there are none, so the key does what it always did.
    private func moveHighlight(_ delta: Int) -> Bool {
        let keys = model.rowKeys(matching: activeQuery)
        guard !keys.isEmpty else { return false }
        if let current = highlight.flatMap(keys.firstIndex(of:)) {
            highlight = keys[min(max(current + delta, 0), keys.count - 1)]
        } else {
            highlight = delta > 0 ? keys.first : keys.last
        }
        return true
    }

    /// Starts the timer for the highlighted reminder. False when nothing is highlighted.
    private func openHighlighted() -> Bool {
        guard let item = highlight.flatMap(model.item(forRowKey:)) else { return false }
        minutes = model.defaultMinutes
        model.select(item)
        return true
    }

    /// Checks off the highlighted reminder and moves on to the next one, so Shift + Return can be pressed again.
    private func completeHighlighted() {
        guard let key = highlight, let item = model.item(forRowKey: key) else { return }
        let keys = model.rowKeys(matching: activeQuery)
        func other(_ key: String) -> Bool {
            guard let candidate = model.item(forRowKey: key) else { return false }
            return candidate.id != item.id && candidate.parentID != item.id
        }
        if let index = keys.firstIndex(of: key) {
            highlight = keys[(index + 1)...].first(where: other) ?? keys[..<index].last(where: other)
        }
        model.completeOnly(item)
    }

    private func toggleSearch() {
        searching.toggle()
        query = ""
        highlight = nil
        // The field only exists after this update, so ask for focus once it does.
        if searching { Task { @MainActor in searchFocused = true } }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Search reminders", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onChange(of: query) { highlight = model.rowKeys(matching: query).first }
                .onKeyPress(.upArrow) { moveHighlight(-1) ? .handled : .ignored }
                .onKeyPress(.downArrow) { moveHighlight(1) ? .handled : .ignored }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        completeHighlighted()
                        return .handled
                    }
                    return openHighlighted() ? .handled : .ignored
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
        .onAppear { Task { @MainActor in searchFocused = true } }
        .onExitCommand(perform: toggleSearch)
        .transition(RevealTransition())
    }

    /// ⌘F opens and closes the search.
    private var searchShortcut: some View {
        Button("Search", action: toggleSearch)
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            VStack(alignment: .leading, spacing: 10) {
                if model.hasAccess {
                    QuickAddView(model: model, autofocus: true, onMoveRow: moveHighlight, onOpenRow: openHighlighted,
                                 onCompleteRow: completeHighlighted)
                    Divider()
                    if searching { searchField }
                }
                TaskList(model: model, search: activeQuery, highlight: highlight) { item in
                    minutes = model.defaultMinutes
                    model.select(item)
                }
                if creatingList { NewListForm(model: model) { creatingList = false } }
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
                if let update = updates.availableUpdate {
                    UpdateBanner(update: update, onDismiss: updates.dismissBanner)
                        .transition(RevealTransition())
                }
            }
            .background(searchShortcut)
        case .choosing(let item):
            TimerSetupView(item: item, minutes: $minutes, secondaryTitle: "Cancel", onSecondary: model.cancel) {
                model.start(item, minutes: minutes)
            }
        case .running(let item, _):
            RunningTimerView(model: model, item: item)
        case .onBreak(let item, _):
            BreakTimerView(model: model, item: item)
        case .finished(let item):
            FinishedTimerView(
                item: item, minutes: $minutes,
                onExtend: { model.start(item, minutes: minutes) },
                onDone: { model.markDone(item) },
                onBreak: { model.startBreak(after: item) },
                onDismiss: model.cancel
            )
            .onAppear { minutes = model.defaultMinutes }
        }
    }

    private var footer: some View {
        // Adding, searching and creating lists only make sense on the main screen, not while setting up a timer.
        let browsing = model.phase == .idle && model.hasAccess
        return HStack(spacing: 2) {
            if browsing {
                FooterButton(title: "New List", icon: "plus", iconOnly: true) { withAnimation(.snappy(duration: 0.4)) { creatingList.toggle() } }
                FooterButton(title: "Search", icon: "magnifyingglass", iconOnly: true, action: toggleSearch)
            }
            if !model.recentlyCompleted.isEmpty {
                Menu {
                    ForEach(model.recentlyCompleted) { item in
                        Button { model.undoComplete(item) } label: {
                            Label("Undo “\(item.title)”", systemImage: "arrow.uturn.backward")
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath").font(.callout)
                }
                .menuStyle(.button).buttonStyle(HoverButtonStyle(horizontal: 8, vertical: 3)).menuIndicator(.hidden)
                .help("Recent")
                .accessibilityLabel("Recent")
                .transition(.opacity)
            }
            Spacer()
            FooterButton(title: "Open Reminders", icon: "checklist", iconOnly: true, action: model.openRemindersApp)
            FooterButton(title: "Settings", icon: "gearshape", iconOnly: true) {
                openWindow(id: "settings")
                NSApp.activate()
            }
            FooterButton(title: "Quit", icon: "power", iconOnly: true) { NSApplication.shared.terminate(nil) }
        }
    }
}

/// A button in the dropdown's footer, with an icon and a title.
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
        .buttonStyle(HoverButtonStyle(horizontal: 8, vertical: 3))
        .help(title)
    }
}

/// Shows only the icon when a footer button is icon-only.
private struct FooterLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly { configuration.icon } else { Label(configuration) }
    }
}
