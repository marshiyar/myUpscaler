import AppKit
import SwiftUI

@main struct ShortcutTests {
    @MainActor static func main() throws {
        func expectError(_ expected: ShortcutError, _ action: () throws -> Void) {
            do { try action(); preconditionFailure("Expected \(expected)") }
            catch { precondition(error as? ShortcutError == expected, "Unexpected error: \(error)") }
        }
        for mask in 0..<16 {
            let modifiers = ShortcutModifiers.entries.enumerated().reduce(EventModifiers()) { value, entry in
                mask & (1 << entry.offset) != 0 ? value.union(entry.element.value) : value
            }
            let names = ShortcutModifiers.encode(modifiers)
            precondition(ShortcutModifiers.decode(names + names + ["future"]) == modifiers)
            precondition(names == ShortcutModifiers.entries.filter { modifiers.contains($0.value) }.map(\.name))
        }
        for input in ["", "hello", "ab", "\n"] {
            expectError(.invalidKey) { _ = try ShortcutBinding(key: input, modifiers: .command) }
        }
        for special in ShortcutBinding.specialKeys {
            let binding = try ShortcutBinding(key: special.name, modifiers: [.command, .shift])
            precondition(binding.key == special.character && !binding.display.isEmpty)
            let roundTrip = try ShortcutBinding(info: binding.info)
            precondition(roundTrip == binding)
            _ = binding.native
        }
        let unicode = try ShortcutBinding(key: "É", modifiers: .command)
        precondition(unicode.key == "é")
        let suite = "myUpscaler-shortcuts-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = KeyboardShortcutsManager(defaults: defaults)
        precondition(manager.shortcuts.count == AppCommand.allCases.count)
        precondition(manager.binding(for: .toggleInspector)! == AppCommand.toggleInspector.defaultBinding)
        do { try manager.setShortcut(for: .runUpscaler, binding: AppCommand.toggleInspector.defaultBinding); preconditionFailure("Inspector conflict must fail") }
        catch ShortcutError.conflict(.toggleInspector) {}
        expectError(.conflict(.chooseInput)) { try manager.setShortcut(for: .runUpscaler, binding: manager.binding(for: .chooseInput)!) }
        expectError(.reserved) { try manager.setShortcut(for: .runUpscaler, binding: ShortcutBinding(key: "q", modifiers: .command)) }
        try manager.setShortcut(for: .runUpscaler, binding: ShortcutBinding(key: "x", modifiers: [.command, .option]))
        let restored = KeyboardShortcutsManager(defaults: defaults)
        precondition(restored.binding(for: .runUpscaler)! == manager.binding(for: .runUpscaler)!)
        let beforeConflict = defaults.data(forKey: "customKeyboardShortcuts")
        let beforeBindings = manager.shortcuts
        expectError(.conflict(.chooseInput)) { try manager.setShortcut(for: .runUpscaler, binding: manager.binding(for: .chooseInput)!) }
        precondition(manager.shortcuts == beforeBindings && defaults.data(forKey: "customKeyboardShortcuts") == beforeConflict)
        precondition(ShortcutError.conflict(.chooseInput).localizedDescription.contains(AppCommand.chooseInput.name))
        let unchanged = KeyboardShortcutsManager(defaults: defaults)
        precondition(unchanged.binding(for: .runUpscaler)!.key == "x" && unchanged.binding(for: .chooseInput)!.key == "o")
        var legacy: [String: ShortcutInfo] = [
            "runUpscaler": ShortcutInfo(key: "r", modifiers: ["command", "command"]),
            "chooseInput": ShortcutInfo(key: "oops", modifiers: ["command"]),
            "chooseOutput": ShortcutInfo(key: "u", modifiers: ["unknown"]),
            "futureAction": ShortcutInfo(key: "future-key", modifiers: ["future-modifier"])
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "customKeyboardShortcuts")
        let migrated = KeyboardShortcutsManager(defaults: defaults)
        precondition(migrated.binding(for: .chooseInput)!.key == "o")
        precondition(migrated.loadWarnings.count == 2)
        try migrated.setShortcut(for: .openAbout, binding: migrated.binding(for: .openAbout)!)
        let stored = try JSONDecoder().decode([String: ShortcutInfo].self, from: defaults.data(forKey: "customKeyboardShortcuts")!)
        precondition(stored["futureAction"] == legacy["futureAction"], "Unknown newer command must survive")
        precondition(stored["runUpscaler"] != nil, "Same-as-default customization must remain intentional")
        legacy["chooseInput"] = ShortcutInfo(key: "r", modifiers: ["command"])
        defaults.set(try JSONEncoder().encode(legacy), forKey: "customKeyboardShortcuts")
        let conflicting = KeyboardShortcutsManager(defaults: defaults)
        precondition(conflicting.binding(for: .runUpscaler)!.key == "r" && conflicting.binding(for: .chooseInput)!.key == "o")
        try migrated.resetToDefaults()
        precondition(migrated.shortcuts == Dictionary(uniqueKeysWithValues: AppCommand.allCases.map { ($0, $0.defaultBinding) }))
        let resetStored = try JSONDecoder().decode([String: ShortcutInfo].self, from: defaults.data(forKey: "customKeyboardShortcuts")!)
        precondition(resetStored.count == 1 && resetStored["futureAction"] != nil)
        defaults.set(Data("broken".utf8), forKey: "customKeyboardShortcuts")
        precondition(!KeyboardShortcutsManager(defaults: defaults).loadWarnings.isEmpty)

        // Preserve the historical NumberFormatter behavior, including locale parsing and rounding.
        let formats = [(Formatters.integer, 0), (Formatters.oneFraction, 1),
                       (Formatters.twoFraction, 2), (Formatters.threeFraction, 3)]
        for (format, precision) in formats {
            for locale in ["en_US", "de_DE", "fr_FR"] {
                let actual = format.copy() as! NumberFormatter
                actual.locale = Locale(identifier: locale)
                let historical = NumberFormatter()
                historical.minimumFractionDigits = precision
                historical.maximumFractionDigits = precision
                historical.locale = actual.locale
                for value in [-1.25, -0.125, 0, 1.234567, 2.5] {
                    let number = NSNumber(value: value)
                    precondition(actual.string(from: number) == historical.string(from: number))
                    precondition(number.doubleValue == value, "Display formatting must not mutate stored precision")
                }
                for input in ["", "-", "1", "1.", "1,", "-1,25", "1.25"] {
                    precondition(actual.number(from: input) == historical.number(from: input))
                }
            }
        }

        let dispatcher = CommandDispatcher()
        var enabled = false; var executions = 0
        dispatcher.configure([.runUpscaler: .init(isEnabled: { enabled }, perform: { executions += 1 })])
        dispatcher.perform(.runUpscaler); precondition(executions == 0)
        enabled = true; dispatcher.perform(.runUpscaler); precondition(executions == 1)
        dispatcher.perform(.cancel); precondition(executions == 1)
        dispatcher.configure([:]); dispatcher.perform(.runUpscaler); precondition(executions == 1)

        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        let previous = NSTextView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(previous); window.makeFirstResponder(previous)
        let recorder = ShortcutRecorderView(frame: .zero)
        var captured: ShortcutBinding?; var cancelled = false
        recorder.onCapture = { captured = $0 }; recorder.onCancel = { cancelled = true }
        window.contentView!.addSubview(recorder); recorder.takeFocus()
        func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = [], repeated: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: repeated, keyCode: code)!
        }
        precondition(recorder.performKeyEquivalent(with: key("X", code: 7, flags: [.command, .shift])))
        precondition(captured?.key == "x" && captured?.modifiers == [.command, .shift])
        recorder.keyDown(with: key("y", code: 16, repeated: true)); precondition(captured?.key == "x")
        recorder.onCapture = { _ in executions += 10 }
        recorder.keyDown(with: key("z", code: 6)); precondition(executions == 11, "Latest callback must be used")
        recorder.keyDown(with: key("\u{1b}", code: 53)); precondition(cancelled)
        recorder.restoreFocus(); precondition(window.firstResponder === previous)
        print("PASS modifier codec, validated keys/specials, injected persistence/migration/conflicts/failed-save/reset, dispatcher guards and native recorder/focus")
    }
}
