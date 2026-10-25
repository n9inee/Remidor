//
//  RemidorApp.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the global shortcut once the app is fully running.
        HotKeyManager.shared.start { QuickAddPanelController.shared.toggle(model: TaskModel.shared) }
        UpdateChecker.shared.start()
    }
}

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
