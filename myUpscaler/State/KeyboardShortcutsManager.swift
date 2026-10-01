import Foundation
import Combine
import SwiftUI

@MainActor final class KeyboardShortcutsManager: ObservableObject {
    static let shared = KeyboardShortcutsManager()
    let availableActions = AppCommand.allCases
    @Published private(set) var shortcuts: [AppCommand: ShortcutBinding]
    private(set) var loadWarnings: [String] = []
    private let defaults: UserDefaults
    private let storageKey = "customKeyboardShortcuts"
    private var overrides: [AppCommand: ShortcutBinding] = [:]
    // Keep records from newer versions without exposing or executing their IDs.
    private var unknownRecords: [String: ShortcutInfo] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcuts = Dictionary(uniqueKeysWithValues: AppCommand.allCases.map { ($0, $0.defaultBinding) })
        guard let data = defaults.data(forKey: storageKey) else { return }
        guard let records = try? JSONDecoder().decode([String: ShortcutInfo].self, from: data) else {
            loadWarnings = ["Stored shortcuts could not be read; defaults are active."]
            return
        }
        for (id, record) in records.sorted(by: { $0.key < $1.key }) {
            guard let command = AppCommand(rawValue: id) else { unknownRecords[id] = record; continue }
            do {
                let binding = try ShortcutBinding(info: record)
                guard !binding.isReserved else { throw ShortcutError.reserved }
                overrides[command] = binding
            } catch { loadWarnings.append("\(command.name): \(error.localizedDescription)") }
        }
        // Validate the whole migrated mapping, so valid swaps survive loading.
        for _ in AppCommand.allCases {
            let candidate = resolved()
            let conflicting = AppCommand.allCases.filter { command in
                AppCommand.allCases.contains { $0 != command && candidate[$0] == candidate[command] }
            }
            guard !conflicting.isEmpty else { break }
            for command in conflicting where overrides[command] != nil {
                overrides.removeValue(forKey: command)
                loadWarnings.append("\(command.name): conflicting stored binding; restored its default.")
            }
        }
        shortcuts = resolved()
    }

    func binding(for command: AppCommand) -> ShortcutBinding { shortcuts[command] ?? command.defaultBinding }

    func setShortcut(for command: AppCommand, binding: ShortcutBinding) throws {
        guard !binding.isReserved else { throw ShortcutError.reserved }
        if let other = availableActions.first(where: { $0 != command && self.binding(for: $0) == binding }) {
            throw ShortcutError.conflict(other)
        }
        var next = overrides
        next[command] = binding // Preserve intentional custom bindings equal to defaults.
        try commit(next)
    }

    func swapBindings(_ first: AppCommand, _ second: AppCommand) throws {
        guard first != second else { return }
        var next = overrides
        next[first] = binding(for: second)
        next[second] = binding(for: first)
        try commit(next)
    }

    func resetToDefaults() throws { try commit([:]) }

    private func resolved() -> [AppCommand: ShortcutBinding] {
        Dictionary(uniqueKeysWithValues: availableActions.map { ($0, overrides[$0] ?? $0.defaultBinding) })
    }

    private func commit(_ next: [AppCommand: ShortcutBinding]) throws {
        var records = unknownRecords
        for (command, binding) in next { records[command.rawValue] = binding.info }
        let encoded = try JSONEncoder().encode(records)
        defaults.set(encoded, forKey: storageKey)
        overrides = next
        shortcuts = resolved()
        loadWarnings = []
    }
}
