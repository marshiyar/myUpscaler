import Foundation
import SwiftUI

@main struct PersistenceTests {
    @MainActor static func main() throws {
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
        precondition(manager.binding(for: .runUpscaler).key == "x")
        precondition(manager.binding(for: .cancel) == AppCommand.cancel.defaultBinding)
        precondition(manager.loadWarnings.count == 1)
        try manager.setShortcut(for: .openAbout, binding: manager.binding(for: .openAbout))
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
        try repaired.swapBindings(.runUpscaler, .chooseInput)
        precondition(KeyboardShortcutsManager(defaults: defaults).shortcuts == repaired.shortcuts)
        let beforeFailure = defaults.data(forKey: key)
        let beforeBindings = repaired.shortcuts
        do {
            try repaired.setShortcut(for: .openAbout, binding: repaired.binding(for: .chooseInput))
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
        print("PASS entrywise migration, malformed/scalar preservation, unknown raw schemas, intentional defaults, repair/reset, swap roundtrip, failed-save invariants, unreadable backups")
    }
}
