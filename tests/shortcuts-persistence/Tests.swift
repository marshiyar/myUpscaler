import Foundation
import SwiftUI
import Combine

@main struct PersistenceTests {
    // This must compile outside MainActor even when it is the module default:
    // persisted shortcut values and LocalizedError formatting contain no UI state.
    nonisolated static func verifyValueIsolation() throws {
        let binding = try ShortcutBinding(key: "x", modifiers: [.command, .option])
        let encoded = try JSONEncoder().encode(binding.info)
        let restored = try ShortcutBinding(info: JSONDecoder().decode(ShortcutInfo.self, from: encoded))
        precondition(restored == binding)
        precondition(ShortcutError.conflict(.runUpscaler).errorDescription?.contains(AppCommand.runUpscaler.name) == true)
    }
    @MainActor static func main() throws {
        try verifyValueIsolation()
        let suite = "shortcut-persistence-review-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "customKeyboardShortcuts"
        func store(_ json: String) { defaults.set(Data(json.utf8), forKey: key) }
        func records() throws -> NSDictionary {
            try JSONSerialization.jsonObject(with: defaults.data(forKey: key)!) as! NSDictionary
        }
        store(#"{"runUpscaler":{"key":"x","modifiers":["command","command"]},"cancel":{"key":42,"modifiers":["command"]},"futureAction":{"schema":2,"payload":[null,{"other":true}]},"futureScalar":null}"#)
        let original = try records()
        let manager = KeyboardShortcutsManager(defaults: defaults)
        precondition(manager.binding(for: .runUpscaler)!.key == "x")
        precondition(manager.binding(for: .cancel)! == AppCommand.cancel.defaultBinding)
        precondition(manager.loadWarnings.count == 1)
        try manager.setShortcut(for: .openAbout, binding: manager.binding(for: .openAbout)!)
        let saved = try records()
        for id in ["cancel", "futureAction", "futureScalar"] {
            precondition((saved[id] as! NSObject).isEqual(original[id]))
        }
        precondition(saved["openAbout"] != nil)
        let reloaded = KeyboardShortcutsManager(defaults: defaults)
        precondition(reloaded.shortcuts == manager.shortcuts && reloaded.loadWarnings.count == 1)
        try reloaded.setShortcut(for: .cancel, binding: AppCommand.cancel.defaultBinding)
        precondition(reloaded.loadWarnings.isEmpty)
        let repaired = KeyboardShortcutsManager(defaults: defaults)
        precondition(repaired.loadWarnings.isEmpty)
        try repaired.setShortcut(for: .runUpscaler, binding: ShortcutBinding(key: "y", modifiers: [.command, .option]))
        precondition(KeyboardShortcutsManager(defaults: defaults).shortcuts == repaired.shortcuts)
        let beforeFailure = defaults.data(forKey: key)
        let beforeBindings = repaired.shortcuts
        do {
            try repaired.setShortcut(for: .openAbout, binding: repaired.binding(for: .chooseInput)!)
            preconditionFailure("Conflict must fail")
        } catch ShortcutError.conflict(.chooseInput) {}
        precondition(defaults.data(forKey: key) == beforeFailure && repaired.shortcuts == beforeBindings)
        try repaired.resetToDefaults()
        let resetRecords = try records()
        precondition(resetRecords.count == 2)
        precondition(KeyboardShortcutsManager(defaults: defaults).shortcuts == Dictionary(uniqueKeysWithValues: AppCommand.allCases.map { ($0, $0.defaultBinding) }))
        // Invalid semantic entries and scalar known entries also survive unrelated saves.
        store(#"{"cancel":null,"chooseOutput":{"key":"oops","modifiers":["command"]},"runUpscaler":{"key":"x","modifiers":["command"]}}"#)
        let invalidOriginal = try records()
        let invalid = KeyboardShortcutsManager(defaults: defaults)
        try invalid.setShortcut(for: .openAbout, binding: AppCommand.openAbout.defaultBinding)
        let invalidSaved = try records()
        for id in ["cancel", "chooseOutput"] { precondition((invalidSaved[id] as! NSObject).isEqual(invalidOriginal[id])) }
        // Entire unreadable/root-incompatible payloads are recoverable after Save; distinct backups survive.
        for payload in [Data("broken".utf8), Data("[]".utf8)] {
            defaults.set(payload, forKey: key)
            let unreadable = KeyboardShortcutsManager(defaults: defaults)
            precondition(!unreadable.loadWarnings.isEmpty && defaults.data(forKey: key) == payload)
            try unreadable.setShortcut(for: .openAbout, binding: AppCommand.openAbout.defaultBinding)
            precondition((defaults.array(forKey: key + ".unreadableBackups") as! [Data]).contains(payload))
            precondition(KeyboardShortcutsManager(defaults: defaults).loadWarnings.isEmpty)
        }
        precondition((defaults.array(forKey: key + ".unreadableBackups") as! [Data]).count == 2)
        defaults.removeObject(forKey: key)
        let resolver = KeyboardShortcutsManager(defaults: defaults)
        var publications = 0
        let token = resolver.$shortcuts.dropFirst().sink { _ in publications += 1 }
        let input = resolver.binding(for: .chooseInput)!
        let export = resolver.binding(for: .runUpscaler)!
        let selfConflict = try resolver.conflict(for: .runUpscaler, binding: export)
        precondition(selfConflict == nil)
        let first = try resolver.conflict(for: .runUpscaler, binding: input)!
        precondition(first.command == .runUpscaler && first.other == .chooseInput)
        precondition(first.previous == export && first.otherPrevious == input)
        let unchangedBytes = defaults.data(forKey: key)
        try resolver.resolve(first, using: .cancel)
        precondition(publications == 0 && defaults.data(forKey: key) == unchangedBytes)
        try resolver.resolve(first, using: .swap)
        precondition(publications == 1 && resolver.binding(for: .runUpscaler) == input && resolver.binding(for: .chooseInput) == export)
        precondition(KeyboardShortcutsManager(defaults: defaults).shortcuts == resolver.shortcuts)
        // A displayed conflict is a snapshot; stale confirmation cannot overwrite newer choices.
        do { try resolver.resolve(first, using: .clearBoth); preconditionFailure("Stale conflict must fail") }
        catch ShortcutError.staleConflict {}
        precondition(publications == 1)
        let second = try resolver.conflict(for: .runUpscaler, binding: export)!
        try resolver.resolve(second, using: .clearBoth)
        precondition(publications == 2 && resolver.binding(for: .runUpscaler) == nil && resolver.binding(for: .chooseInput) == nil)
        let clearedBytes = defaults.data(forKey: key)!
        let clearedRecords = try records()
        for id in ["runUpscaler", "chooseInput"] { precondition((clearedRecords[id] as! NSDictionary)["disabled"] as? Bool == true) }
        let cleared = KeyboardShortcutsManager(defaults: defaults)
        precondition(cleared.shortcuts == resolver.shortcuts && cleared.loadWarnings.isEmpty)
        let disabledConflict = try cleared.conflict(for: .runUpscaler, binding: export)
        precondition(disabledConflict == nil, "Disabled defaults do not own their old keys")
        // Swapping from an unbound command transfers its empty binding to the previous owner.
        let settingsBinding = cleared.binding(for: .openSettings)!
        let unboundConflict = try cleared.conflict(for: .runUpscaler, binding: settingsBinding)!
        precondition(unboundConflict.previous == nil)
        try cleared.resolve(unboundConflict, using: .swap)
        precondition(cleared.binding(for: .runUpscaler) == settingsBinding && cleared.binding(for: .openSettings) == nil)
        precondition(KeyboardShortcutsManager(defaults: defaults).shortcuts == cleared.shortcuts)
        try cleared.setShortcut(for: .chooseInput, binding: input)
        precondition(cleared.binding(for: .chooseInput) == input)
        precondition(KeyboardShortcutsManager(defaults: defaults).binding(for: .chooseInput) == input)
        precondition(defaults.data(forKey: key) != clearedBytes)
        try cleared.resetToDefaults()
        precondition(cleared.shortcuts == Dictionary(uniqueKeysWithValues: AppCommand.allCases.map { ($0, $0.defaultBinding) }))
        // Semantically conflicting legacy records also remain recoverable after unrelated edits.
        store(#"{"runUpscaler":{"key":"r","modifiers":["command"]},"chooseInput":{"key":"r","modifiers":["command"]}}"#)
        let duplicateRecords = try records()
        let duplicate = KeyboardShortcutsManager(defaults: defaults)
        precondition(!duplicate.loadWarnings.isEmpty)
        try duplicate.setShortcut(for: .openAbout, binding: AppCommand.openAbout.defaultBinding)
        let duplicateSaved = try records()
        for id in ["runUpscaler", "chooseInput"] { precondition((duplicateSaved[id] as! NSObject).isEqual(duplicateRecords[id])) }
        // Entire historical permutations are validated together, rather than against intermediate defaults.
        var permutation: [String: Any] = [:]
        let commands = AppCommand.allCases
        for (index, command) in commands.enumerated() {
            let info = commands[(index + 1) % commands.count].defaultBinding.info
            permutation[command.rawValue] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(info))
        }
        defaults.set(try JSONSerialization.data(withJSONObject: permutation), forKey: key)
        let permuted = KeyboardShortcutsManager(defaults: defaults)
        precondition(permuted.loadWarnings.isEmpty && permuted.shortcuts.count == commands.count)
        for (index, command) in commands.enumerated() { precondition(permuted.binding(for: command) == commands[(index + 1) % commands.count].defaultBinding) }
        // Disabled + malformed + unknown schemas survive a conflict resolution in one atomic save.
        store(#"{"runUpscaler":{"disabled":true},"cancel":{"key":42,"modifiers":["command"]},"futureAction":{"version":3,"disabled":true},"chooseOutput":{"disabled":"yes"}}"#)
        let mixed = KeyboardShortcutsManager(defaults: defaults)
        let mixedOriginal = try records()
        let mixedConflict = try mixed.conflict(for: .runUpscaler, binding: AppCommand.chooseInput.defaultBinding)!
        try mixed.resolve(mixedConflict, using: .swap)
        let mixedSaved = try records()
        for id in ["cancel", "futureAction", "chooseOutput"] { precondition((mixedSaved[id] as! NSObject).isEqual(mixedOriginal[id])) }
        precondition(KeyboardShortcutsManager(defaults: defaults).shortcuts == mixed.shortcuts)
        withExtendedLifetime(token) {}
        print("PASS conflict swap/clear/cancel, disabled reload, stale snapshots, single publications, historical permutations; entrywise migration, malformed/scalar preservation, unknown raw schemas, intentional defaults, repair/reset, edit roundtrip, failed-save invariants, unreadable backups")
    }
}
