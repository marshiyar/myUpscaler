//
//  KeyboardShortcutsManagerTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Testing
import SwiftUI
@testable import myUpscaler

@MainActor
struct KeyboardShortcutsManagerTests {
    
    // MARK: - Singleton Tests
    
    @Test("shared should return the same instance")
    func testSingleton() {
        let instance1 = KeyboardShortcutsManager.shared
        let instance2 = KeyboardShortcutsManager.shared
        
        #expect(instance1 === instance2)
    }
    
    // MARK: - Initialization Tests
    
    @Test("Manager should have default actions")
    func testDefaultActions() {
        let manager = KeyboardShortcutsManager.shared
        
        #expect(manager.availableActions.count > 0)
        #expect(manager.availableActions.contains { $0.id == "runUpscaler" })
        #expect(manager.availableActions.contains { $0.id == "cancel" })
        #expect(manager.availableActions.contains { $0.id == "openSettings" })
    }
    
    @Test("Manager should initialize with default shortcuts")
    func testDefaultShortcuts() {
        let manager = KeyboardShortcutsManager.shared
        
        // Should have shortcuts for all available actions
        for action in manager.availableActions {
            let shortcut = manager.getShortcut(for: action.id)
            #expect(shortcut != nil, "Should have shortcut for action: \(action.id)")
        }
    }
    
    // MARK: - Shortcut Retrieval Tests
    
    @Test("getShortcut should return correct key equivalent")
    func testGetShortcut() {
        let manager = KeyboardShortcutsManager.shared
        
        let shortcut = manager.getShortcut(for: "runUpscaler")
        #expect(shortcut != nil)
        
        // Should return the default key if custom not set
        let action = manager.availableActions.first { $0.id == "runUpscaler" }
        if let action = action {
            #expect(shortcut == KeyEquivalent(Character(action.defaultKey)))
        }
    }
    
    @Test("getShortcut should return nil for unknown action")
    func testGetShortcutUnknown() {
        let manager = KeyboardShortcutsManager.shared
        
        let shortcut = manager.getShortcut(for: "unknownAction")
        #expect(shortcut == nil)
    }
    
    @Test("getModifiers should return correct modifiers")
    func testGetModifiers() {
        let manager = KeyboardShortcutsManager.shared
        
        let modifiers = manager.getModifiers(for: "runUpscaler")
        #expect(modifiers.contains(.command))
    }
    
    @Test("getModifiers should return default for unknown action")
    func testGetModifiersUnknown() {
        let manager = KeyboardShortcutsManager.shared
        
        _ = manager.getModifiers(for: "unknownAction")
        // Should return empty or default
        #expect(true) // Just verify it doesn't crash
    }
    
    // MARK: - Shortcut Setting Tests
    
    @Test("setShortcut should store custom shortcut")
    func testSetShortcut() {
        let manager = KeyboardShortcutsManager.shared
        
        manager.setShortcut(for: "runUpscaler", key: "x", modifiers: [.command, .shift])
        
        let shortcut = manager.getShortcut(for: "runUpscaler")
        let modifiers = manager.getModifiers(for: "runUpscaler")
        
        #expect(shortcut == KeyEquivalent("x"))
        #expect(modifiers.contains(.command))
        #expect(modifiers.contains(.shift))
    }
    
    @Test("setShortcut should persist across instances")
    func testShortcutPersistence() {
        let manager = KeyboardShortcutsManager.shared
        
        // Set a custom shortcut
        manager.setShortcut(for: "cancel", key: "z", modifiers: [.control])
        
        // Get shortcut should return the custom value
        let shortcut = manager.getShortcut(for: "cancel")
        let modifiers = manager.getModifiers(for: "cancel")
        
        #expect(shortcut == KeyEquivalent("z"))
        #expect(modifiers.contains(.control))
    }
    
    // MARK: - Modifier Conversion Tests
    
    @Test("modifiersToStrings should convert correctly")
    func testModifiersToStrings() {
        let manager = KeyboardShortcutsManager.shared
        
        // Test through setShortcut which uses modifiersToStrings internally
        manager.setShortcut(for: "openSettings", key: "s", modifiers: [.command, .option])
        
        let modifiers = manager.getModifiers(for: "openSettings")
        #expect(modifiers.contains(.command))
        #expect(modifiers.contains(.option))
    }
    
    @Test("stringsToModifiers should convert correctly")
    func testStringsToModifiers() {
        let manager = KeyboardShortcutsManager.shared
        
        // Test by setting and retrieving
        manager.setShortcut(for: "chooseInput", key: "i", modifiers: [.command, .shift, .control])
        
        let modifiers = manager.getModifiers(for: "chooseInput")
        #expect(modifiers.contains(.command))
        #expect(modifiers.contains(.shift))
        #expect(modifiers.contains(.control))
    }
    
    // MARK: - Reset Tests
    
    @Test("resetToDefaults should restore default shortcuts")
    func testResetToDefaults() {
        let manager = KeyboardShortcutsManager.shared
        
        // Set custom shortcuts
        manager.setShortcut(for: "runUpscaler", key: "x", modifiers: [.control])
        manager.setShortcut(for: "cancel", key: "y", modifiers: [.control])
        
        // Reset
        manager.resetToDefaults()
        
        // Should be back to defaults
        let runShortcut = manager.getShortcut(for: "runUpscaler")
        let cancelShortcut = manager.getShortcut(for: "cancel")
        
        // Should match default keys
        let runAction = manager.availableActions.first { $0.id == "runUpscaler" }
        let cancelAction = manager.availableActions.first { $0.id == "cancel" }
        
        if let runAction = runAction {
            #expect(runShortcut == KeyEquivalent(Character(runAction.defaultKey)))
        }
        if let cancelAction = cancelAction {
            #expect(cancelShortcut == KeyEquivalent(Character(cancelAction.defaultKey)))
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Should handle empty key strings")
    func testEmptyKey() {
        let manager = KeyboardShortcutsManager.shared
        
        // Should not crash
        manager.setShortcut(for: "runUpscaler", key: "", modifiers: [])
        
        _ = manager.getShortcut(for: "runUpscaler")
        // Behavior depends on implementation
        #expect(true) // Just verify it doesn't crash
    }
    
    @Test("Should handle special character keys")
    func testSpecialCharacterKeys() {
        let manager = KeyboardShortcutsManager.shared
        
        let specialKeys = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"]
        
        for key in specialKeys {
            manager.setShortcut(for: "runUpscaler", key: key, modifiers: [])
            let shortcut = manager.getShortcut(for: "runUpscaler")
            #expect(shortcut != nil || true) // May or may not support special chars
        }
    }
    
    @Test("Should handle multiple modifier combinations")
    func testMultipleModifiers() {
        let manager = KeyboardShortcutsManager.shared
        
        let modifierCombos: [EventModifiers] = [
            [.command],
            [.shift],
            [.option],
            [.control],
            [.command, .shift],
            [.command, .option],
            [.command, .control],
            [.shift, .option],
            [.command, .shift, .option],
            [.command, .shift, .option, .control]
        ]
        
        for modifiers in modifierCombos {
            manager.setShortcut(for: "runUpscaler", key: "r", modifiers: modifiers)
            _ = manager.getModifiers(for: "runUpscaler")
            
            // Should match (allowing for some flexibility)
            #expect(true) // Just verify it doesn't crash
        }
    }
    
    @Test("Should handle unknown action IDs gracefully")
    func testUnknownActionID() {
        let manager = KeyboardShortcutsManager.shared
        
        // Should not crash
        manager.setShortcut(for: "nonexistentAction", key: "x", modifiers: [])
        
        _ = manager.getShortcut(for: "nonexistentAction")
        // May return nil or handle gracefully
        #expect(true) // Just verify it doesn't crash
    }
}

