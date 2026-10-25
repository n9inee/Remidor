//
//  LaunchAtLogin.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import Observation
import ServiceManagement

/// Starts Remidor when you log in. macOS keeps the setting itself (it also shows up under
/// System Settings → General → Login Items), so this only reads it and asks for changes.
@MainActor @Observable
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    private(set) var status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    /// On, or waiting for you to allow it in System Settings.
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    /// Re-reads the setting, for example after it was changed in System Settings.
    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "macOS couldn't change this setting: \(error.localizedDescription)"
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
