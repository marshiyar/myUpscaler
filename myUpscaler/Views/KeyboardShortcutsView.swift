import SwiftUI
import AppKit

struct KeyboardShortcutsView: View {
    @ObservedObject var manager = KeyboardShortcutsManager.shared
    private struct Edit { let command: AppCommand; var binding: ShortcutBinding? }
    @State private var edit: Edit?
    @State private var conflict: ShortcutConflict?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Commands") {
                ForEach(manager.availableActions) { command in
                    HStack {
                        Text(command.name)
                        Spacer()
                        ShortcutBadge(binding: edit?.command == command ? edit!.binding : manager.binding(for: command))
                        if edit?.command == command {
                            Button("Save") { saveEdit() }.disabled(edit?.binding == nil)
                            Button("Cancel") { edit = nil; errorMessage = nil }
                        } else {
                            Button("Edit") {
                                edit = Edit(command: command, binding: manager.binding(for: command))
                                errorMessage = nil
                            }
                        }
                    }
                }
            }
            Section {
                Button("Reset to defaults", systemImage: "arrow.counterclockwise") {
                    edit = nil
                    update { try manager.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)

        .sheet(item: $conflict) { requested in
            ShortcutConflictResolver(conflict: requested, errorMessage: errorMessage) { resolution in
                update { try manager.resolve(requested, using: resolution) }
                if errorMessage == nil { conflict = nil; edit = nil }
            }
        }
        .onDisappear { edit = nil }
    }

    private func record(_ binding: ShortcutBinding) {
        guard let edit else { return }
        update {
            let requested = try manager.conflict(for: edit.command, binding: binding)
            self.edit?.binding = binding
            conflict = requested
        }
    }

    private func saveEdit() {
        guard let edit, let binding = edit.binding else { return }
        update {
            if let requested = try manager.conflict(for: edit.command, binding: binding) {
                conflict = requested
            } else {
                try manager.setShortcut(for: edit.command, binding: binding)
                self.edit = nil
            }
        }
    }
    private func update(_ operation: () throws -> Void) {
        do { try operation(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct ShortcutBadge: View {
    let binding: ShortcutBinding?
    var body: some View {
        Text(binding?.display ?? "Unassigned")
            .font(.body.monospaced())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(binding?.display ?? "No keyboard shortcut")
    }
}

/// One resolver serves every command; it appears only for a recorded conflict.
struct ShortcutConflictResolver: View {
    let conflict: ShortcutConflict
    var errorMessage: String? = nil
    let resolve: (ShortcutConflictResolution) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(conflict.requested.display) is assigned to \(conflict.other.name).")
                .font(.headline)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            bindingRow(conflict.command, binding: conflict.previous)
            bindingRow(conflict.other, binding: conflict.otherPrevious)
            HStack {
                Button("Cancel") { resolve(.cancel) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Clear both", role: .destructive) { resolve(.clearBoth) }
                    .help("Remove both keyboard shortcuts; the menu commands remain available")
                Button("Swap") { resolve(.swap) }
                    .help("Exchange the two current keyboard bindings")
            }
        }.padding(24).frame(width: 480)
    }
    private func bindingRow(_ command: AppCommand, binding: ShortcutBinding?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(command.name).fontWeight(.medium)
                Text(command.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ShortcutBadge(binding: binding)
        }
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
