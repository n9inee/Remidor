//
//  SettingsView.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var model: TaskModel
    @State private var hotKey = HotKeyManager.shared
    @State private var launchAtLogin = LaunchAtLogin.shared
    @State private var updates = UpdateChecker.shared
    @State private var leftColumnHeight: CGFloat = 0
    @State private var creatingList = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 14) {
                GroupBox("General") {
                    VStack(alignment: .leading, spacing: 10) {
                        launchAtLoginRow
                        Divider()
                        updatesRow
                    }
                }
                GroupBox("Sorting") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Sort tasks by", selection: $model.sortOrder) {
                            ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
                        }
                        Text("Manual keeps the order you made in Reminders. A single list can have its own order, using the arrows next to it.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Use for every list") { model.applySortOrderToAllLists() }
                                .controlSize(.small)
                                .disabled(model.listSortOrders.isEmpty)
                                .help("Gives every list this order again, so none keeps one of its own.")
                            if model.listsWithOwnOrder > 0 {
                                Text(model.listsWithOwnOrder == 1 ? "1 list has its own" : "\(model.listsWithOwnOrder) lists have their own")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                GroupBox("Timer") {
                    VStack(spacing: 8) {
                        Text("Default duration").frame(maxWidth: .infinity, alignment: .leading)
                        DurationPicker(totalMinutes: $model.defaultMinutes)
                    }
                    .padding(6)
                }
                GroupBox("Shortcuts") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(HotKeyAction.allCases) { action in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(action.title)
                                ShortcutRecorder(hotKey: hotKey, action: action)
                                if hotKey.conflicts.contains(action) {
                                    Label("macOS or another app already uses this shortcut. Pick a different one.",
                                          systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }
            .frame(width: 270)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { leftColumnHeight = $0 }

            // The lists column is exactly as tall as the left column and scrolls if the lists don't fit.
            GroupBox("Lists shown in the menu bar") { listsPane }
                .frame(width: 280, height: leftColumnHeight > 0 ? leftColumnHeight : nil)
        }
        .padding(16)
        .task { await model.refresh() }
        .onAppear { launchAtLogin.refresh() }
        // The setting can also be changed in System Settings, so look again when coming back to the app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private var updatesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Check for updates", isOn: $updates.isEnabled)
            HStack(spacing: 8) {
                Button("Check now") { Task { await updates.checkNow() } }
                    .controlSize(.small)
                    .disabled(updates.status == .checking)
                updateStatus
            }
            Text("Remidor \(UpdateChecker.currentVersion). Looks at GitHub about once a day and never installs anything by itself.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
    }

    @ViewBuilder private var updateStatus: some View {
        switch updates.status {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .available(let update):
            Button("\(update.version) is available") { NSWorkspace.shared.open(update.url) }
                .buttonStyle(.link).font(.caption)
        case .failed:
            Label("Couldn't check", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
    }

    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Open Remidor at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            if launchAtLogin.needsApproval {
                Text("macOS needs your approval before Remidor can start at login.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Login Items Settings…", action: launchAtLogin.openLoginItemsSettings)
                    .controlSize(.small)
            }
            if let message = launchAtLogin.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
    }

    private var listsPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drag to reorder. This order is used everywhere.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6)
            if model.lists.isEmpty {
                Text(model.accessDenied
                     ? "Reminders access denied. Enable it in System Settings → Privacy & Security."
                     : "No lists found.")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            List {
                ForEach(model.lists) { list in
                    ListRow(model: model, list: list)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: model.moveLists)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(.snappy(duration: 0.4), value: model.lists.map(\.id))
            newListFooter
        }
        .animation(.snappy(duration: 0.4), value: creatingList)
    }

    /// A button for making a new list, which turns into a name box with colours to choose from.
    private var newListFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if creatingList {
                NewListForm(model: model) { creatingList = false }
            } else {
                Button { creatingList = true } label: { Label("New List…", systemImage: "plus") }
                    .controlSize(.small)
                    .disabled(model.accessDenied)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 8)
    }
}

/// A draggable list with a visibility checkbox and, for regular lists, a star to make it the default.
private struct ListRow: View {
    let model: TaskModel
    let list: ReminderList

    @State private var renaming = false
    @State private var confirmingDelete = false

    var body: some View {
        if renaming {
            NameField(initial: list.title, placeholder: "List name", onSubmit: { name in
                model.renameList(list, to: name)
                renaming = false
            }, onCancel: { renaming = false })
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(.tertiary)
            Toggle(isOn: Binding(get: { model.isSelected(list) }, set: { model.setList(list, selected: $0) })) {
                Label {
                    Text(list.title)
                } icon: {
                    Image(systemName: list.symbol).foregroundStyle(list.color)
                }
            }
            Spacer(minLength: 0)
            if !SmartList.sortsByTime(list) { sortMenu }
            if !list.isSmart { defaultButton }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if !list.isSmart {
                Button("Rename…") { renaming = true }
                Divider()
                Button("Delete List…", role: .destructive) { confirmingDelete = true }
            }
        }
        .confirmationDialog("Delete “\(list.title)”?", isPresented: $confirmingDelete) {
            Button("Delete List and Its Reminders", role: .destructive) { model.deleteList(list) }
        } message: {
            Text("This also deletes every reminder in it, in the Reminders app too. It can't be undone.")
        }
    }

    /// Lets this list use its own sort order instead of the common one.
    private var sortMenu: some View {
        let own = model.listSortOrders[list.id]
        return Menu {
            SortChoices(current: own, inherited: model.sortOrder, inheritedTitle: "Same as the Rest") { model.setSortOrder($0, for: list) }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption)
                .foregroundStyle(own == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
        .help(own.map { "Sorted by \($0.label.lowercased()). Click to change." } ?? "Sorted like the other lists. Click to give this list its own order.")
    }

    private var defaultButton: some View {
        let isDefault = model.defaultListID == list.id
        return Button {
            // Choosing the current default again goes back to automatic (Inbox, else the system default).
            model.preferredListID = model.preferredListID == list.id ? nil : list.id
        } label: {
            Image(systemName: isDefault ? "star.fill" : "star")
                .foregroundStyle(isDefault ? Color.yellow : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(isDefault ? "Default list for new reminders" : "Use as default list for new reminders")
        .animation(.snappy(duration: 0.3), value: isDefault)
    }
}
