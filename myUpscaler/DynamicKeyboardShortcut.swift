import SwiftUI
import AppKit

struct DynamicKeyboardShortcut: ViewModifier {
    let actionId: String
    let action: () -> Void
    @ObservedObject var manager = KeyboardShortcutsManager.shared
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                setupKeyboardMonitor()
            }
            .onChange(of: Array(manager.shortcuts.keys)) {
                setupKeyboardMonitor()
            }
            .background(
                KeyboardShortcutHandler(
                    actionId: actionId,
                    action: action,
                    manager: manager
                )
            )
    }
    
    private func setupKeyboardMonitor() {
    }
}

struct KeyboardShortcutHandler: NSViewRepresentable {
    let actionId: String
    let action: () -> Void
    @ObservedObject var manager: KeyboardShortcutsManager
    
    func makeNSView(context: Context) -> KeyboardMonitorView {
        let view = KeyboardMonitorView()
        view.actionId = actionId
        view.action = action
        view.manager = manager
        return view
    }
    
    func updateNSView(_ nsView: KeyboardMonitorView, context: Context) {
        nsView.actionId = actionId
        nsView.action = action
        nsView.manager = manager
        nsView.updateMonitor()
    }
}

class KeyboardMonitorView: NSView {
    var actionId: String = ""
    var action: (() -> Void)?
    var manager: KeyboardShortcutsManager?
    var eventMonitor: Any?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
    }
    
    func updateMonitor() {
        // Remove old monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        guard let manager = manager,
              let shortcut = manager.shortcuts[actionId],
              let keyChar = shortcut.key.first else {
            // Use default
            if let action = manager?.availableActions.first(where: { $0.id == actionId }) {
                setupMonitor(key: action.defaultKey, modifiers: action.defaultModifiers)
            }
            return
        }
        
        let modifiers = manager.getModifiers(for: actionId)
        setupMonitor(key: String(keyChar), modifiers: modifiers)
    }
    
    private func setupMonitor(key: String, modifiers: EventModifiers) {
        guard let action = action else { return }
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Check if this matches our shortcut
            let eventKey = event.charactersIgnoringModifiers?.lowercased() ?? ""
            var eventModifiers: EventModifiers = []
            
            if event.modifierFlags.contains(.command) { eventModifiers.insert(.command) }
            if event.modifierFlags.contains(.shift) { eventModifiers.insert(.shift) }
            if event.modifierFlags.contains(.option) { eventModifiers.insert(.option) }
            if event.modifierFlags.contains(.control) { eventModifiers.insert(.control) }
            
            if eventKey == key.lowercased() && eventModifiers == modifiers {
                DispatchQueue.main.async {
                    action()
                }
                return nil // Consume the event
            }
            
            return event
        }
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

extension View {
    func dynamicKeyboardShortcut(actionId: String, action: @escaping () -> Void) -> some View {
        self.modifier(DynamicKeyboardShortcut(actionId: actionId, action: action))
    }
}

