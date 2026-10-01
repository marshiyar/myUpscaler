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
                .keyboardShortcut(manager.binding(for: command)?.native)
                .disabled(!dispatcher.canPerform(command))
        }
    }
}
