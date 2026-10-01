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
    // Preserve unknown schemas and malformed entries without executing their IDs.
    private var retainedRecords: [String: Any] = [:]
    private var unreadablePayload: Data?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcuts = Dictionary(uniqueKeysWithValues: AppCommand.allCases.map { ($0, $0.defaultBinding) })
        guard let data = defaults.data(forKey: storageKey) else { return }
        guard let records = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            unreadablePayload = data
            loadWarnings = ["Stored shortcuts could not be read; defaults are active."]
            return
        }
        for (id, rawRecord) in records.sorted(by: { $0.key < $1.key }) {
            guard let command = AppCommand(rawValue: id) else { retainedRecords[id] = rawRecord; continue }
            do {
                let recordData = try JSONSerialization.data(withJSONObject: rawRecord, options: [.fragmentsAllowed])
                let record = try JSONDecoder().decode(ShortcutInfo.self, from: recordData)
                let binding = try ShortcutBinding(info: record)
                guard !binding.isReserved else { throw ShortcutError.reserved }
                overrides[command] = binding
            } catch {
                retainedRecords[id] = rawRecord
                loadWarnings.append("\(command.name): \(error.localizedDescription)")
            }
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

    func resetToDefaults() throws { try commit([:], resetKnownRecords: true) }

    private func resolved() -> [AppCommand: ShortcutBinding] {
        Dictionary(uniqueKeysWithValues: availableActions.map { ($0, overrides[$0] ?? $0.defaultBinding) })
    }

    private func commit(_ next: [AppCommand: ShortcutBinding], resetKnownRecords: Bool = false) throws {
        var retained = retainedRecords
        if resetKnownRecords {
            retained = retained.filter { AppCommand(rawValue: $0.key) == nil }
        }
        for command in next.keys { retained.removeValue(forKey: command.rawValue) }
        var records = retained
        for (command, binding) in next {
            let recordData = try JSONEncoder().encode(binding.info)
            records[command.rawValue] = try JSONSerialization.jsonObject(with: recordData)
        }
        // Finish every fallible conversion before changing storage or published state.
        let encoded = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
        if let unreadablePayload {
            let recoveryKey = storageKey + ".unreadableBackups"
            var backups = defaults.array(forKey: recoveryKey) as? [Data] ?? []
            if !backups.contains(unreadablePayload) { backups.append(unreadablePayload) }
            defaults.set(backups, forKey: recoveryKey)
        }
        defaults.set(encoded, forKey: storageKey)
        unreadablePayload = nil
        retainedRecords = retained
        overrides = next
        shortcuts = resolved()
        loadWarnings = retained.keys.sorted().compactMap { id in
            guard let command = AppCommand(rawValue: id) else { return nil }
            return "\(command.name): invalid stored record preserved; defaults are active."
        }
    }
}
