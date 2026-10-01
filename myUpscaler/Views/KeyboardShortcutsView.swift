import SwiftUI
import AppKit

struct KeyboardShortcutsView: View {
    @ObservedObject var manager = KeyboardShortcutsManager.shared
    private struct Edit { let command: AppCommand; var binding: ShortcutBinding }
    @State private var edit: Edit?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Edit a command, press its new combination, then Save. Escape cancels recording. Use Swap to exchange two bindings.")
                    .foregroundStyle(.secondary)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                ForEach(manager.loadWarnings, id: \.self) { Text($0).foregroundStyle(.orange) }
            }
            Section("Commands") {
                ForEach(manager.availableActions) { command in
                    HStack {
                        Text(command.name)
                        Spacer()
                        ShortcutBadge(binding: edit?.command == command ? edit!.binding : manager.binding(for: command))
                        if edit?.command == command {
                            Button("Save") { saveEdit() }
                            Button("Cancel") { edit = nil; errorMessage = nil }
                        } else {
                            Button("Edit") {
                                edit = Edit(command: command, binding: manager.binding(for: command))
                                errorMessage = nil
                            }
                            Menu("Swap") {
                                ForEach(manager.availableActions.filter { $0 != command }) { other in
                                    Button(other.name) {
                                        update { try manager.swapBindings(command, other) }
                                    }
                                }
                            }
                            .fixedSize()
                        }
                    }
                }
            }
            Section {
                Button("Reset shortcuts to defaults", systemImage: "arrow.counterclockwise") {
                    edit = nil
                    update { try manager.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .background {
            if edit != nil {
                ShortcutRecorder(onCapture: { binding in edit?.binding = binding; errorMessage = nil },
                                 onCancel: { edit = nil; errorMessage = nil })
                    .frame(width: 0, height: 0)
            }
        }
        .onDisappear { edit = nil }
    }

    private func saveEdit() {
        guard let edit else { return }
        update { try manager.setShortcut(for: edit.command, binding: edit.binding) }
        if errorMessage == nil { self.edit = nil }
    }
    private func update(_ operation: () throws -> Void) {
        do { try operation(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct ShortcutBadge: View {
    let binding: ShortcutBinding
    var body: some View {
        Text(binding.display)
            .font(.body.monospaced())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(binding.display)
    }
}

/// Only the active edit owns a recorder; app shortcut routing remains native.
struct ShortcutRecorder: NSViewRepresentable {
    let onCapture: (ShortcutBinding) -> Void
    let onCancel: () -> Void
    func makeNSView(context: Context) -> ShortcutRecorderView { ShortcutRecorderView() }
    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.takeFocus()
    }
    static func dismantleNSView(_ view: ShortcutRecorderView, coordinator: ()) { view.restoreFocus() }
}

final class ShortcutRecorderView: NSView {
    var onCapture: ((ShortcutBinding) -> Void)?
    var onCancel: (() -> Void)?
    private weak var previousResponder: NSResponder?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); takeFocus() }
    func takeFocus() {
        guard let window, window.firstResponder !== self else { return }
        if previousResponder == nil { previousResponder = window.firstResponder }
        window.makeFirstResponder(self)
    }
    func restoreFocus() {
        if window?.firstResponder === self { window?.makeFirstResponder(previousResponder) }
        previousResponder = nil
        onCapture = nil
        onCancel = nil
    }
    override func keyDown(with event: NSEvent) { record(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        record(event)
        return true
    }
    private func record(_ event: NSEvent) {
        guard window?.firstResponder === self, !event.isARepeat else { return }
        if event.keyCode == 53 && ShortcutModifiers.fromEvent(event.modifierFlags).isEmpty {
            onCancel?()
        } else if let binding = ShortcutBinding.capture(event) {
            onCapture?(binding)
        }
    }
}
