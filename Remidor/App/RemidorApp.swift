//
//  RemidorApp.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// Registers the global shortcuts and starts the update check once the app has launched.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the global shortcut once the app is fully running.
        HotKeyManager.shared.start([
            .quickBar: { QuickAddPanelController.shared.toggle(model: TaskModel.shared) },
            .remindersApp: { TaskModel.shared.openRemindersApp() },
        ])
        UpdateChecker.shared.start()
    }
}

/// The menu bar item with its dropdown, and the Settings window.
@main
struct RemidorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = TaskModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Remidor Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
