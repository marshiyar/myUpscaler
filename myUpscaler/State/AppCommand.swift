import SwiftUI
import AppKit
import Combine

/// Stable raw values are the IDs already stored in customKeyboardShortcuts.
nonisolated enum AppCommand: String, CaseIterable, Identifiable, Codable, Sendable {
    case runUpscaler, cancel, openSettings, openAbout, chooseInput, chooseOutput, toggleInspector
    var id: String { rawValue }
    var name: String {
        switch self {
        case .runUpscaler: "Export video"
        case .cancel: "Cancel processing"
        case .openSettings: "Settings"
        case .openAbout: "About myUpscaler"
        case .chooseInput: "Import video or folder"
        case .chooseOutput: "Choose output folder"
        case .toggleInspector: "Show or hide adjustments"
        }
    }
    var purpose: String {
        switch self {
        case .runUpscaler: "Start exporting the imported video with the current settings."
        case .cancel: "Stop the current processing job."
        case .openSettings: "Open application preferences and shortcut settings."
        case .openAbout: "Show application information and credits."
        case .chooseInput: "Select a video or a folder to process."
        case .chooseOutput: "Select the destination for exported videos."
        case .toggleInspector: "Open or close the docked adjustment panel."
        }
    }
    var defaultBinding: ShortcutBinding {
        let key: String
        switch self {
        case .runUpscaler: key = "r"
        case .cancel: key = "."
        case .openSettings: key = ","
        case .openAbout, .toggleInspector: key = "i"
        case .chooseInput, .chooseOutput: key = "o"
        }
        let modifiers: EventModifiers = self == .toggleInspector ? [.command, .option] :
            self == .openAbout || self == .chooseOutput ? [.command, .shift] : .command
        return try! ShortcutBinding(key: key, modifiers: modifiers)
    }
}

nonisolated struct ShortcutInfo: Codable, Equatable, Sendable {
    let key: String
    let modifiers: [String]
}

/// One table defines persistence, native event conversion and visible glyph order.
nonisolated enum ShortcutModifiers {
    static let entries: [(name: String, value: EventModifiers, native: NSEvent.ModifierFlags, glyph: String)] = [
        ("command", .command, .command, "⌘"), ("shift", .shift, .shift, "⇧"),
        ("option", .option, .option, "⌥"), ("control", .control, .control, "⌃")
    ]
    static let supported = entries.reduce(EventModifiers()) { $0.union($1.value) }
    static func encode(_ value: EventModifiers) -> [String] { entries.filter { value.contains($0.value) }.map(\.name) }
    static func decode(_ names: [String]) -> EventModifiers {
        entries.filter { names.contains($0.name) }.reduce(EventModifiers()) { $0.union($1.value) }
    }
    static func fromEvent(_ flags: NSEvent.ModifierFlags) -> EventModifiers {
        entries.filter { flags.contains($0.native) }.reduce(EventModifiers()) { $0.union($1.value) }
    }
    static func display(_ value: EventModifiers) -> String { entries.filter { value.contains($0.value) }.map(\.glyph).joined() }
}

nonisolated enum ShortcutError: Error, LocalizedError, Equatable {
    case invalidKey, unsupportedModifier, reserved, conflict(AppCommand), staleConflict
    var errorDescription: String? {
        switch self {
        case .invalidKey: "Choose one character or a supported special key."
        case .unsupportedModifier: "Only Command, Shift, Option and Control are supported."
        case .reserved: "That combination is reserved by macOS or dialog controls."
        case .staleConflict: "Shortcuts changed while resolving this conflict. Record the combination again."
        case .conflict(let command): "Already assigned to \(command.name). Resolve the conflict or choose a different combination."
        }
    }
}

nonisolated struct ShortcutBinding: Equatable, Sendable {
    // Native KeyEquivalent characters also migrate the old recorder's word names.
    static let specialKeys: [(name: String, character: String, glyph: String, code: UInt16)] = [
        ("return", "\r", "↩", 36), ("tab", "\t", "⇥", 48), ("space", " ", "Space", 49),
        ("delete", "\u{7f}", "⌫", 51), ("escape", "\u{1b}", "⎋", 53),
        ("left", "\u{f702}", "←", 123), ("right", "\u{f703}", "→", 124),
        ("down", "\u{f701}", "↓", 125), ("up", "\u{f700}", "↑", 126)
    ]
    let key: String
    let modifiers: EventModifiers
    init(key input: String, modifiers: EventModifiers) throws {
        let lower = input.lowercased()
        let key = Self.specialKeys.first { $0.name == lower }?.character ?? lower
        guard key.count == 1 else { throw ShortcutError.invalidKey }
        guard modifiers.subtracting(ShortcutModifiers.supported).isEmpty else { throw ShortcutError.unsupportedModifier }
        guard key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) || Self.specialKeys.contains(where: { $0.character == key }) else { throw ShortcutError.invalidKey }
        self.key = key
        self.modifiers = modifiers
    }
    init(info: ShortcutInfo) throws {
        guard info.modifiers.allSatisfy({ name in ShortcutModifiers.entries.contains { $0.name == name } }) else { throw ShortcutError.unsupportedModifier }
        try self.init(key: info.key, modifiers: ShortcutModifiers.decode(info.modifiers))
    }
    var info: ShortcutInfo { ShortcutInfo(key: key, modifiers: ShortcutModifiers.encode(modifiers)) }
    var native: KeyboardShortcut { KeyboardShortcut(KeyEquivalent(key.first!), modifiers: modifiers) }
    var display: String {
        ShortcutModifiers.display(modifiers) + (Self.specialKeys.first { $0.character == key }?.glyph ?? key.uppercased())
    }
    var isReserved: Bool {
        if modifiers.isEmpty && ["\r", "\u{1b}"].contains(key) { return true }
        if modifiers == .command && ["q", "h", "m", "w", "\t", " "].contains(key) { return true }
        return key == "\u{1b}" && modifiers == [.command, .option]
    }
    static func capture(_ event: NSEvent) -> ShortcutBinding? {
        guard !event.isARepeat else { return nil }
        let key = specialKeys.first { $0.code == event.keyCode }?.character ?? event.charactersIgnoringModifiers ?? ""
        return try? ShortcutBinding(key: key, modifiers: ShortcutModifiers.fromEvent(event.modifierFlags))
    }
}

/// Per-window implementations stay outside persisted shortcut data.
@MainActor final class CommandDispatcher: ObservableObject {
    struct Action { let isEnabled: () -> Bool; let perform: () -> Void }
    @Published private(set) var revision = 0
    private var actions: [AppCommand: Action] = [:]
    func configure(_ actions: [AppCommand: Action]) { self.actions = actions; refreshAvailability() }
    func refreshAvailability() { revision &+= 1 }
    func canPerform(_ command: AppCommand) -> Bool { actions[command]?.isEnabled() ?? false }
    func perform(_ command: AppCommand) {
        guard let action = actions[command], action.isEnabled() else { return }
        action.perform()
    }
}
