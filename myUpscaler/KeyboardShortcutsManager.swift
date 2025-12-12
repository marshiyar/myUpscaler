import Foundation
import Combine
import AppKit
import SwiftUI

struct ShortcutInfo: Codable {
    let key: String
    let modifiers: [String]
}

class KeyboardShortcutsManager: ObservableObject {
    static let shared = KeyboardShortcutsManager()
    
    @Published var shortcuts: [String: ShortcutInfo] = [:]
    
    // Available actions that can have keyboard shortcuts
    let availableActions: [ActionInfo] = [
        ActionInfo(id: "runUpscaler", name: "Run Upscaler", defaultKey: "r", defaultModifiers: [.command]),
        ActionInfo(id: "cancel", name: "Cancel Processing", defaultKey: ".", defaultModifiers: [.command]),
        ActionInfo(id: "openSettings", name: "Open Settings", defaultKey: ",", defaultModifiers: [.command]),
        ActionInfo(id: "openAbout", name: "Open About", defaultKey: "i", defaultModifiers: [.command, .shift]),
        ActionInfo(id: "chooseInput", name: "Choose Input File", defaultKey: "o", defaultModifiers: [.command]),
        ActionInfo(id: "chooseOutput", name: "Choose Output Folder", defaultKey: "o", defaultModifiers: [.command, .shift]),
    ]
    
    struct ActionInfo: Identifiable {
        let id: String
        let name: String
        let defaultKey: String
        let defaultModifiers: EventModifiers
    }
    
    private let userDefaultsKey = "customKeyboardShortcuts"
    
    init() {
        loadShortcuts()
        initializeDefaults()
    }
    
    private func initializeDefaults() {
        for action in availableActions {
            if shortcuts[action.id] == nil {
                shortcuts[action.id] = ShortcutInfo(
                    key: action.defaultKey,
                    modifiers: modifiersToStrings(action.defaultModifiers)
                )
            }
        }
    }
    
    func getShortcut(for actionId: String) -> KeyEquivalent? {
        if let shortcut = shortcuts[actionId] {
            return KeyEquivalent(Character(shortcut.key))
        }
        if let action = availableActions.first(where: { $0.id == actionId }) {
            return KeyEquivalent(Character(action.defaultKey))
        }
        return nil
    }
    
    func getModifiers(for actionId: String) -> EventModifiers {
        if let shortcut = shortcuts[actionId] {
            return stringsToModifiers(shortcut.modifiers)
        }
        if let action = availableActions.first(where: { $0.id == actionId }) {
            return action.defaultModifiers
        }
        return []
    }
    
    func setShortcut(for actionId: String, key: String, modifiers: EventModifiers) {
        shortcuts[actionId] = ShortcutInfo(
            key: key,
            modifiers: modifiersToStrings(modifiers)
        )
        saveShortcuts()
    }
    
    private func saveShortcuts() {
        if let encoded = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadShortcuts() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: ShortcutInfo].self, from: data) else {
            return
        }
        shortcuts = decoded
    }
    
    private func modifiersToStrings(_ modifiers: EventModifiers) -> [String] {
        var strings: [String] = []
        if modifiers.contains(.command) { strings.append("command") }
        if modifiers.contains(.shift) { strings.append("shift") }
        if modifiers.contains(.option) { strings.append("option") }
        if modifiers.contains(.control) { strings.append("control") }
        return strings
    }
    
    private func stringsToModifiers(_ strings: [String]) -> EventModifiers {
        var modifiers: EventModifiers = []
        if strings.contains("command") { modifiers.insert(.command) }
        if strings.contains("shift") { modifiers.insert(.shift) }
        if strings.contains("option") { modifiers.insert(.option) }
        if strings.contains("control") { modifiers.insert(.control) }
        return modifiers
    }
    
    func resetToDefaults() {
        shortcuts.removeAll()
        initializeDefaults()
        saveShortcuts()
    }
}

