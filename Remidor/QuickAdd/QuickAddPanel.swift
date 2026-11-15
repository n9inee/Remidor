//
//  QuickAddPanel.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import AppKit
import SwiftUI

/// The borderless window of the quick-add box. It can take keyboard focus without activating the app.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Esc. The controller closes it, so its click monitor goes too.
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Reports its fitting size whenever the SwiftUI content changes, so the panel can follow it.
private final class FittingHostingView<Content: View>: NSHostingView<Content> {
    var onFitChange: (@MainActor (NSSize) -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // Resizing the window in the middle of layout upsets AppKit, so wait for the next runloop turn.
        Task { @MainActor [weak self] in
            guard let self else { return }
            onFitChange?(fittingSize)
        }
    }
}

/// The top edge of the quick-add box: a clear strip that moves the window when dragged, and says so
/// with the open-hand cursor. AppKit won't drag the window from the hosting view behind it, so the
/// strip starts the drag itself.
private final class DragStrip: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    /// The panel doesn't activate, so the first click has to be enough to start dragging.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Starts the drag and returns; the window finishes it on its own.
        window?.performDrag(with: event)
    }
}

/// The strip along the top of the box that drags it out of the way.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragStrip() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The Spotlight-style add-and-pick box that the global shortcut opens.
@MainActor
final class QuickAddPanelController {
    static let shared = QuickAddPanelController()

    private var panel: FloatingPanel?
    private weak var model: TaskModel?
    private var clickMonitor: Any?

    func toggle(model: TaskModel) {
        if panel?.isVisible == true { close() } else { show(model: model) }
    }

    func show(model: TaskModel) {
        close()
        model.scheduleRefresh()

        self.model = model
        let host = FittingHostingView(rootView: QuickAddPanelContent(model: model, draft: model.draftForPanel()) { [weak self] in self?.close() })
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize

        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak self] in self?.close() }
        host.onFitChange = { @MainActor [weak self, weak panel, weak host] fit in
            guard let self, let panel, let host else { return }
            follow(fit, with: panel, host: host)
        }

        // Upper part of the screen the mouse is on, like Spotlight.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let target = NSRect(x: (area.midX - size.width / 2).rounded(),
                            y: (area.maxY - area.height * 0.22 - size.height).rounded(),
                            width: size.width, height: size.height)

        // Fade and settle in.
        panel.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }

        // A click anywhere outside Remidor dismisses the box.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        guard let panel else { return }
        self.panel = nil
        model?.panelClosedAt = Date()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    /// Keeps the window as tall as its content, with the top edge where it is. The content opens and closes
    /// through animated heights, so this follows it frame by frame, and no delay is needed on the way down.
    /// A box that was dragged away from the top of the screen stays inside it.
    private func follow(_ fit: NSSize, with panel: NSPanel, host: NSView) {
        guard fit.height > 0, abs(fit.height - panel.frame.height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - fit.height
        frame.size.height = fit.height
        panel.setFrame(insideScreen(frame, for: panel), display: true)
    }

    /// The frame moved back inside the usable part of the panel's screen. A window taller than the screen
    /// keeps its top edge, since that is where the box and its input field are.
    private func insideScreen(_ frame: NSRect, for panel: NSPanel) -> NSRect {
        guard let area = (panel.screen ?? NSScreen.main)?.visibleFrame else { return frame }
        var result = frame
        result.origin.x = min(max(result.minX, area.minX), max(area.maxX - result.width, area.minX))
        if result.height >= area.height {
            result.origin.y = area.maxY - result.height
        } else {
            result.origin.y = min(max(result.minY, area.minY), area.maxY - result.height)
        }
        return result
    }
}

/// Add or pick a task; picking one continues with choosing how long to work on it.
private struct QuickAddPanelContent: View {
    let model: TaskModel
    let draft: QuickAddDraft
    let dismiss: () -> Void

    @State private var chosen: ReminderItem?
    @State private var minutes = 30

    var body: some View {
        Group {
            if let item = chosen {
                TimerSetupView(item: item, minutes: $minutes, secondaryTitle: "Back", onSecondary: { chosen = nil }) {
                    model.start(item, minutes: minutes)
                    dismiss()
                }
                .transition(.opacity)
            } else {
                QuickAddView(model: model, autofocus: true, draft: draft, onAdded: dismiss) { item in
                    minutes = model.defaultMinutes
                    chosen = item
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.44), value: chosen)
        .padding(12)
        .frame(width: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .overlay(alignment: .top) {
            // The top edge drags the box out of the way.
            WindowDragArea()
                .frame(maxWidth: .infinity)
                .frame(height: 12)
        }
        // The window can be taller than the content for a moment; keep the content pinned to the top.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
