import SwiftUI
import AppKit

struct KeyboardShortcutsView: View {
    @ObservedObject var manager = KeyboardShortcutsManager.shared
    @State private var editingActionId: String? = nil
    @State private var capturedKey: String? = nil
    @State private var capturedModifiers: EventModifiers = []
    
    var body: some View {
        Form {
            Section {
                Text("set a custom keyboard shortcut.")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(.secondary)
            } header: {
                Label("Instructions", systemImage: "info.circle.fill")
                    .sectionHeader()
            }
            
            Section {
                ForEach(manager.availableActions) { action in
                    HStack {
                        Text(action.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Spacer()
                        
                        if editingActionId == action.id {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                if capturedModifiers.contains(.command) {
                                    Text("⌘")
                                        .font(DesignSystem.Typography.caption1)
                                        .foregroundColor(.secondary)
                                }
                                if capturedModifiers.contains(.shift) {
                                    Text("⇧")
                                        .font(DesignSystem.Typography.caption1)
                                        .foregroundColor(.secondary)
                                }
                                if capturedModifiers.contains(.option) {
                                    Text("⌥")
                                        .font(DesignSystem.Typography.caption1)
                                        .foregroundColor(.secondary)
                                }
                                if capturedModifiers.contains(.control) {
                                    Text("⌃")
                                        .font(DesignSystem.Typography.caption1)
                                        .foregroundColor(.secondary)
                                }
                                if let key = capturedKey {
                                    Text(key.uppercased())
                                        .font(DesignSystem.Typography.caption1)
                                        .fontWeight(.medium)
                                } else {
                                    Text("Press keys...")
                                        .font(DesignSystem.Typography.caption1)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background {
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                    .fill(Color.accentColor.opacity(0.1))
                            }
                        } else {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                let modifiers = manager.getModifiers(for: action.id)
                                if modifiers.contains(.command) {
                                    Text("⌘")
                                        .font(DesignSystem.Typography.caption1)
                                        .foregroundColor(.secondary)
                                }
                                if modifiers.contains(.shift) {
                                    Text("⇧")
                                        .font(DesignSystem.Typography.caption1)
                                        .foregroundColor(.secondary)
                                }
                                if modifiers.contains(.option) {
                                    Text("⌥")
                                        .font(DesignSystem.Typography.caption1)
                                        .foregroundColor(.secondary)
                                }
                                if modifiers.contains(.control) {
                                    Text("⌃")
                                        .font(DesignSystem.Typography.caption1)
                                        .foregroundColor(.secondary)
                                }
                                if let shortcut = manager.shortcuts[action.id] {
                                    Text(shortcut.key.uppercased())
                                        .font(DesignSystem.Typography.caption1)
                                        .fontWeight(.medium)
                                } else {
                                    Text(action.defaultKey.uppercased())
                                        .font(DesignSystem.Typography.caption1)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background {
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                    .fill(Color.appSecondaryBackground)
                            }
                        }
                        
                        Button(action: {
                            if editingActionId == action.id {
                                // Save the shortcut
                                if let key = capturedKey, !key.isEmpty {
                                    manager.setShortcut(for: action.id, key: key.lowercased(), modifiers: capturedModifiers)
                                }
                                editingActionId = nil
                                capturedKey = nil
                                capturedModifiers = []
                            } else {
                                // Start editing
                                editingActionId = action.id
                                if let shortcut = manager.shortcuts[action.id] {
                                    capturedKey = shortcut.key
                                    capturedModifiers = manager.getModifiers(for: action.id)
                                } else {
                                    capturedKey = action.defaultKey
                                    capturedModifiers = action.defaultModifiers
                                }
                            }
                        }) {
                            Text(editingActionId == action.id ? "Done" : "Edit")
                                .font(DesignSystem.Typography.caption1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if editingActionId != action.id {
                            editingActionId = action.id
                            if let shortcut = manager.shortcuts[action.id] {
                                capturedKey = shortcut.key
                                capturedModifiers = manager.getModifiers(for: action.id)
                            } else {
                                capturedKey = action.defaultKey
                                capturedModifiers = action.defaultModifiers
                            }
                        }
                    }
                    .background(
                        KeyCaptureView(
                            isActive: editingActionId == action.id,
                            onKeyCaptured: { key, modifiers in
                                capturedKey = key
                                capturedModifiers = modifiers
                            }
                        )
                    )
                }
            } header: {
                Label("Actions", systemImage: "keyboard.fill")
                    .sectionHeader()
            }
            
            Section {
                Button(action: {
                    manager.resetToDefaults()
                }) {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(DesignSystem.Typography.subheadline)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onKeyCaptured: (String, EventModifiers) -> Void
    
    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyCaptured = onKeyCaptured
        return view
    }
    
    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isActive = isActive
    }
}

class KeyCaptureNSView: NSView {
    var isActive: Bool = false {
        didSet {
            if isActive {
                window?.makeFirstResponder(self)
            }
        }
    }
    var onKeyCaptured: ((String, EventModifiers) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        return isActive
    }
    
    override func keyDown(with event: NSEvent) {
        guard isActive else {
            super.keyDown(with: event)
            return
        }
        
        var key = event.charactersIgnoringModifiers ?? ""
        
        // Handle special keys
        if key.isEmpty {
            switch event.keyCode {
            case 36: key = "return"
            case 48: key = "tab"
            case 49: key = "space"
            case 51: key = "delete"
            case 53: key = "escape"
            case 123: key = "left"
            case 124: key = "right"
            case 125: key = "down"
            case 126: key = "up"
            default:
                // Try to get character from key code
                if let char = event.characters?.first {
                    key = String(char)
                }
            }
        }
        
        var modifiers: EventModifiers = []
        
        if event.modifierFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if event.modifierFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if event.modifierFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if event.modifierFlags.contains(.control) {
            modifiers.insert(.control)
        }
        
        if !key.isEmpty {
            onKeyCaptured?(key, modifiers)
        }
    }
}

