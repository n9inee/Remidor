//
//  Preferences.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import Foundation

/// UserDefaults keys for everything that is saved between launches.
enum DefaultsKey {
    static let defaultMinutes = "defaultMinutes"
    static let selectedLists = "selectedListIDs"
    static let sortOrder = "sortOrder"
    static let preferredList = "preferredListID"
    static let listOrder = "listOrder"
    static let collapsedLists = "collapsedListIDs"
    static let quickAddShortcut = "quickAddShortcut"
}
