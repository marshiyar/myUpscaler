import Foundation
import Combine
import SwiftUI

nonisolated struct ShortcutConflict: Identifiable, Equatable, Sendable {
    let id = UUID()
    let command: AppCommand
    let other: AppCommand
    let requested: ShortcutBinding
    let previous: ShortcutBinding?
    let otherPrevious: ShortcutBinding?
    fileprivate let bindings: [AppCommand: ShortcutBinding]
}

nonisolated enum ShortcutConflictResolution: Sendable { case swap, clearBoth, cancel }

@MainActor final class KeyboardShortcutsManager: ObservableObject {
    static let shared = KeyboardShortcutsManager()
    let availableActions = AppCommand.allCases
    @Published private(set) var shortcuts: [AppCommand: ShortcutBinding]
    private(set) var loadWarnings: [String] = []
    private let defaults: UserDefaults
    private let storageKey = "customKeyboardShortcuts"
    private var disabled: Set<AppCommand> = []
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
                if let object = rawRecord as? [String: Any], object.count == 1, object["disabled"] != nil {
                    struct DisabledRecord: Decodable { let disabled: Bool }
                    let record = try JSONDecoder().decode(DisabledRecord.self, from: recordData)
                    guard record.disabled else { throw ShortcutError.invalidKey }
                    disabled.insert(command)
                    continue
                }
                let record = try JSONDecoder().decode(ShortcutInfo.self, from: recordData)
                let binding = try ShortcutBinding(info: record)
                guard !binding.isReserved else { throw ShortcutError.reserved }
                overrides[command] = binding
            } catch {
                retainedRecords[id] = rawRecord
                loadWarnings.append("\(command.name): \(error.localizedDescription)")
            }
        }
        // Validate the whole migrated mapping, so valid remappings survive loading.
        for _ in AppCommand.allCases {
            let candidate = resolved()
            let conflicting = AppCommand.allCases.filter { command in
                guard let binding = candidate[command] else { return false }
                return AppCommand.allCases.contains { $0 != command && candidate[$0] == binding }
            }
            guard !conflicting.isEmpty else { break }
            for command in conflicting where overrides[command] != nil {
                overrides.removeValue(forKey: command)
                retainedRecords[command.rawValue] = records[command.rawValue]
                loadWarnings.append("\(command.name): conflicting stored binding; restored its default.")
            }
        }
        shortcuts = resolved()
    }

    /// Absence is an intentional unbound command, never a fallback to its default.
    func binding(for command: AppCommand) -> ShortcutBinding? { shortcuts[command] }

    func conflict(for command: AppCommand, binding: ShortcutBinding) throws -> ShortcutConflict? {
        guard !binding.isReserved else { throw ShortcutError.reserved }
        guard let other = availableActions.first(where: { $0 != command && shortcuts[$0] == binding }) else { return nil }
        return ShortcutConflict(command: command, other: other, requested: binding,
                                previous: shortcuts[command], otherPrevious: shortcuts[other], bindings: shortcuts)
    }

    func setShortcut(for command: AppCommand, binding: ShortcutBinding) throws {
        if let conflict = try conflict(for: command, binding: binding) { throw ShortcutError.conflict(conflict.other) }
        var next = overrides
        var nextDisabled = disabled
        next[command] = binding // Preserve intentional custom bindings equal to defaults.
        nextDisabled.remove(command)
        try commit(next, disabled: nextDisabled)
    }

    func resolve(_ conflict: ShortcutConflict, using resolution: ShortcutConflictResolution) throws {
        if case .cancel = resolution { return }
        guard shortcuts == conflict.bindings,
              shortcuts[conflict.command] == conflict.previous,
              shortcuts[conflict.other] == conflict.otherPrevious,
              conflict.otherPrevious == conflict.requested else { throw ShortcutError.staleConflict }
        var next = overrides
        var nextDisabled = disabled
        switch resolution {
        case .swap:
            next[conflict.command] = conflict.requested
            nextDisabled.remove(conflict.command)
            if let previous = conflict.previous {
                next[conflict.other] = previous
                nextDisabled.remove(conflict.other)
            } else {
                next.removeValue(forKey: conflict.other)
                nextDisabled.insert(conflict.other)
            }
        case .clearBoth:
            for command in [conflict.command, conflict.other] {
                next.removeValue(forKey: command)
                nextDisabled.insert(command)
            }
        case .cancel: return
        }
        try commit(next, disabled: nextDisabled)
    }

    func resetToDefaults() throws { try commit([:], disabled: [], resetKnownRecords: true) }

    private func resolved(overrides: [AppCommand: ShortcutBinding]? = nil, disabled: Set<AppCommand>? = nil) -> [AppCommand: ShortcutBinding] {
        let overrides = overrides ?? self.overrides
        let disabled = disabled ?? self.disabled
        return Dictionary(uniqueKeysWithValues: availableActions.compactMap { command in
            disabled.contains(command) ? nil : (command, overrides[command] ?? command.defaultBinding)
        })
    }

    private func commit(_ next: [AppCommand: ShortcutBinding], disabled nextDisabled: Set<AppCommand>, resetKnownRecords: Bool = false) throws {
        var retained = retainedRecords
        if resetKnownRecords {
            retained = retained.filter { AppCommand(rawValue: $0.key) == nil }
        }
        for command in Set(next.keys).union(nextDisabled) { retained.removeValue(forKey: command.rawValue) }
        var records = retained
        for (command, binding) in next {
            let recordData = try JSONEncoder().encode(binding.info)
            records[command.rawValue] = try JSONSerialization.jsonObject(with: recordData)
        }
        for command in nextDisabled { records[command.rawValue] = ["disabled": true] }
        let nextBindings = resolved(overrides: next, disabled: nextDisabled)
        let boundCommands = availableActions.filter { nextBindings[$0] != nil }
        for command in boundCommands {
            if let other = boundCommands.first(where: { $0 != command && nextBindings[$0] == nextBindings[command] }) {
                throw ShortcutError.conflict(other)
            }
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
        disabled = nextDisabled
        if shortcuts != nextBindings { shortcuts = nextBindings }
        loadWarnings = retained.keys.sorted().compactMap { id in
            guard let command = AppCommand(rawValue: id) else { return nil }
            return "\(command.name): invalid stored record preserved; defaults are active."
        }
    }
}
