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

/// The things a system-wide shortcut can do.
enum HotKeyAction: UInt32, CaseIterable, Identifiable {
    case quickBar = 1, remindersApp

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .quickBar: "Open quick bar"
        case .remindersApp: "Open Reminders app"
        }
    }

    var defaultsKey: String {
        switch self {
        case .quickBar: DefaultsKey.quickAddShortcut
        case .remindersApp: DefaultsKey.remindersShortcut
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .quickBar: Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), key: "Space")
        case .remindersApp: Shortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(optionKey | shiftKey), key: "O")
        }
    }
}

nonisolated private func hotKeyEventHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr, let action = HotKeyAction(rawValue: id.id) else { return status }
    Task { @MainActor in HotKeyManager.shared.handlers[action]?() }
    return noErr
}

/// Registers the system-wide hotkeys. Carbon hotkeys work without Accessibility permission.
@MainActor @Observable
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// The actions whose shortcut macOS refused because something else already owns it.
    private(set) var conflicts: Set<HotKeyAction> = []

    private(set) var shortcuts: [HotKeyAction: Shortcut] = [:]
    @ObservationIgnored fileprivate var handlers: [HotKeyAction: () -> Void] = [:]
    @ObservationIgnored private var refs: [HotKeyAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handlerInstalled = false

    private init() {
        for action in HotKeyAction.allCases {
            if let data = UserDefaults.standard.data(forKey: action.defaultsKey) {
                shortcuts[action] = try? JSONDecoder().decode(Shortcut.self, from: data)   // empty data means "cleared"
            } else {
                shortcuts[action] = action.defaultShortcut
            }
        }
    }

    func shortcut(for action: HotKeyAction) -> Shortcut? { shortcuts[action] }

    func set(_ shortcut: Shortcut?, for action: HotKeyAction) {
        shortcuts[action] = shortcut
        UserDefaults.standard.set(shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: action.defaultsKey)
        register(action)
    }

    func start(_ handlers: [HotKeyAction: () -> Void]) {
        self.handlers = handlers
        HotKeyAction.allCases.forEach(register)
    }

    private func register(_ action: HotKeyAction) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        conflicts.remove(action)
        guard handlers[action] != nil, let shortcut = shortcuts[action] else { return }

        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            guard InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil) == noErr else {
                conflicts.insert(action)
                return
            }
            handlerInstalled = true
        }
        // The same combination can't serve two actions.
        if shortcuts.contains(where: { $0.key != action && $0.value == shortcut && refs[$0.key] != nil }) {
            conflicts.insert(action)
            return
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x524D4452), id: action.rawValue)   // 'RMDR'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[action] = ref } else { conflicts.insert(action) }
    }
}
