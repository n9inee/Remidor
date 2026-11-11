//
//  ScrollActivity.swift
//  Remidor
//
//  Created by n9ine on 11.11.2026.
//

import AppKit

/// Knows when the scroll wheel or trackpad was last used, so that rows sliding under a resting pointer
/// aren't taken for the pointer resting on them.
@MainActor
final class ScrollActivity {
    static let shared = ScrollActivity()

    private var last = Date.distantPast
    private var monitor: Any?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.last = Date() }
            return event
        }
    }

    /// Whether nothing has been scrolled for at least `seconds`.
    func isIdle(for seconds: TimeInterval) -> Bool {
        Date().timeIntervalSince(last) >= seconds
    }
}
