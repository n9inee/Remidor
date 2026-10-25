//
//  ShortcutRecorder.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import Carbon.HIToolbox
import SwiftUI

/// Click, then press the key combination you want. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    @Bindable var hotKey: HotKeyManager
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button { recording ? stop() : start() } label: {
                Text(recording ? "Press shortcut…" : (hotKey.shortcut?.display ?? "Record shortcut"))
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 110)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(recording ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(recording ? Color.accentColor : .clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            if hotKey.shortcut != nil, !recording {
                Button { hotKey.shortcut = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
        }
        .animation(.snappy(duration: 0.3), value: recording)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            return stop()
        case kVK_Delete, kVK_ForwardDelete:
            hotKey.shortcut = nil
            return stop()
        default:
            break
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        // A global shortcut without ⌃, ⌥ or ⌘ would hijack normal typing.
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { return }

        hotKey.shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: Self.label(for: event))
        stop()
    }

    private static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        default: (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
