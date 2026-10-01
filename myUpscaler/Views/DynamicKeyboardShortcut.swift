import SwiftUI

private struct CommandDispatcherKey: FocusedValueKey { typealias Value = CommandDispatcher }
extension FocusedValues {
    var commandDispatcher: CommandDispatcher? {
        get { self[CommandDispatcherKey.self] }
        set { self[CommandDispatcherKey.self] = newValue }
    }
}

/// Native menus own shortcut routing, including active-window and disabled state.
struct UpscalerCommands: Commands {
    @FocusedValue(\.commandDispatcher) private var dispatcher
    @ObservedObject private var manager = KeyboardShortcutsManager.shared
    var body: some Commands {
        CommandMenu("Video") {
            if let dispatcher {
                CommandMenuItems(dispatcher: dispatcher, manager: manager)
            } else {
                ForEach(AppCommand.allCases) { command in Button(command.name) {}.disabled(true) }
            }
        }
    }
}

private struct CommandMenuItems: View {
    @ObservedObject var dispatcher: CommandDispatcher
    @ObservedObject var manager: KeyboardShortcutsManager
    var body: some View {
        ForEach(AppCommand.allCases) { command in
            Button(command.name) { dispatcher.perform(command) }
                .keyboardShortcut(manager.binding(for: command).native)
                .disabled(!dispatcher.canPerform(command))
        }
    }
}

// Transitional native binding used by existing button sites until the workspace
// switches to the focused command menu in the following UI commit.
private struct ExistingCommandShortcut: ViewModifier {
    @ObservedObject private var manager = KeyboardShortcutsManager.shared
    let command: AppCommand
    func body(content: Content) -> some View {
        content.keyboardShortcut(manager.binding(for: command).native)
    }
}
extension View {
    @ViewBuilder func dynamicKeyboardShortcut(actionId: String, action: @escaping () -> Void) -> some View {
        if let command = AppCommand(rawValue: actionId) {
            modifier(ExistingCommandShortcut(command: command))
        } else { self }
    }
}
