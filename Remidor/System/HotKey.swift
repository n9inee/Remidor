//
//  HotKey.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import Carbon.HIToolbox
import Foundation
import Observation

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon modifier flags
    var key: String         // label of the key, for display

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }
}

nonisolated private func hotKeyEventHandler(_: EventHandlerCallRef?, _: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    Task { @MainActor in HotKeyManager.shared.onPress?() }
    return noErr
}

/// Registers one system-wide hotkey. Carbon hotkeys work without Accessibility permission.
@MainActor @Observable
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPress: (() -> Void)?
    /// True when macOS refused the shortcut because something else already owns it.
    var conflict = false

    var shortcut: Shortcut? {
        didSet {
            let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()   // empty data means "cleared"
            UserDefaults.standard.set(data, forKey: DefaultsKey.quickAddShortcut)
            register()
        }
    }

    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerInstalled = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.quickAddShortcut) {
            shortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        } else {
            shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey), key: "N")
        }
    }

    func start(onPress: @escaping () -> Void) {
        self.onPress = onPress
        register()
    }

    private func register() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        conflict = false
        guard onPress != nil, let shortcut else { return }

        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x524D4452), id: 1)   // 'RMDR'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        conflict = status != noErr
    }
}
