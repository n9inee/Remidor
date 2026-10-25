//
//  PanelAligner.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import AppKit
import SwiftUI

/// Keeps the dropdown's right edge under the right edge of the menu bar item.
///
/// The menu bar item changes width when its label does, for example from the icon to a task title, and
/// it grows and shrinks towards the left, so only its right edge stays put. SwiftUI lines the panel up
/// with the item's left edge, which makes the panel jump when the label shrinks back. Pinning the right
/// edge means it never moves.
struct PanelAligner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AlignerView() }
    func updateNSView(_ view: NSView, context: Context) { (view as? AlignerView)?.align() }

    private final class AlignerView: NSView {
        private var observers: [NSObjectProtocol] = []
        private var isAligning = false

        /// How far the panel reaches past the item's right edge, mirroring the default look.
        private let overhang: CGFloat = 8

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard window != nil else { return }

            // Whenever the panel or a menu bar item is moved, resized or shown, check where the panel should be.
            let names: [Notification.Name] = [
                NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                NSWindow.didBecomeKeyNotification, NSWindow.didChangeScreenNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let self, let moved = note.object as? NSWindow,
                          moved === self.window || Self.isStatusItemWindow(moved) else { return }
                    self.align()
                }
            }
            DispatchQueue.main.async { [weak self] in self?.align() }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        func align() {
            guard !isAligning, let panel = window, panel.isVisible, let item = Self.statusItemWindow() else { return }

            let screen = item.screen ?? panel.screen
            var x = item.frame.maxX + overhang - panel.frame.width
            if let visible = screen?.visibleFrame {
                x = min(max(x, visible.minX + 4), visible.maxX - panel.frame.width - 4)   // never off screen
            }
            guard abs(x - panel.frame.minX) > 0.5 else { return }

            isAligning = true
            panel.setFrameOrigin(NSPoint(x: x, y: panel.frame.minY))
            isAligning = false
        }

        private static func isStatusItemWindow(_ window: NSWindow) -> Bool {
            window.className.contains("StatusBar")
        }

        /// This app's menu bar item, whose window has the item's position and size.
        private static func statusItemWindow() -> NSWindow? {
            NSApp.windows.first { isStatusItemWindow($0) && $0.isVisible }
        }
    }
}
