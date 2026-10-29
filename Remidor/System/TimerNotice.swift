//
//  TimerNotice.swift
//  Remidor
//
//  Created by n9ine on 29.10.2026.
//

import Foundation
import OSLog
import UserNotifications

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Remidor", category: "notifications")

/// The notification shown when a focus timer runs out, for when the sound is off or nobody is looking at the menu bar.
/// macOS asks for permission the first time a timer is started; if it is refused, the sound and the menu bar
/// checkmark still tell.
enum TimerNotice {
    /// Asks once, when a timer is first started. Asking again later does nothing if the answer is already given.
    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, error in
            if let error { log.error("Notification permission failed: \(error.localizedDescription)") }
        }
    }

    static func post(for item: ReminderItem) {
        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        content.body = item.title
        let request = UNNotificationRequest(identifier: "timer-finished", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { log.error("Notification failed: \(error.localizedDescription)") }
        }
    }
}
