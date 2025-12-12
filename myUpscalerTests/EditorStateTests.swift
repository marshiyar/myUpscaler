//
//  EditorStateTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Testing
import Foundation
import SwiftUI
import CoreImage
@testable import myUpscaler

@MainActor
struct EditorStateTests {
    
    // MARK: - Helpers
    
    func createTestImage() -> NSImage {
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }
    
    // MARK: - Initialization and Sync Tests
    
    @Test("EditorState should initialize with default values")
    func testInitialization() {
        let state = EditorState()
        
        #expect(state.filePath.isEmpty)
        #expect(state.thumbnailImage == nil)
        #expect(state.timelineFrames.isEmpty)
        #expect(state.contrast == 1.03) // Default
    }
    
    @Test("EditorState should sync from Settings on init")
    func testSyncFromSettingsInit() {
        let settings = UpscaleSettings()
        settings.eqContrast = "1.5"
        settings.denoiseStrength = "5.0"
        
        let state = EditorState(settings: settings)
        
        #expect(state.contrast == 1.5)
        #expect(state.denoiseStrength == 5.0)
    }
    
    @Test("EditorState should sync when Settings change")
    func testSyncFromSettingsUpdate() async throws {
        let settings = UpscaleSettings()
        let state = EditorState(settings: settings)
        
        // Initial value
        #expect(state.contrast == 1.03)
        
        // Change settings
        settings.eqContrast = "1.8"
        
        // Wait for throttle (50ms in code)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        #expect(state.contrast == 1.8)
    }
    
    // MARK: - Filter Logic Tests
    
    @Test("processImage should return an image")
    func testProcessImage() {
        let inputImage = createTestImage()
        let context = CIContext() // Use CPU context for tests
        
        let params = EditorState.FilterParameters(
            contrast: 1.2,
            brightness: 0.1,
            saturation: 1.1,
            denoiseStrength: 2.0,
            deringActive: true,
            deringStrength: 0.5,
            sharpenMethod: "cas",
            sharpenStrength: 0.5,
            usmRadius: 0,
            usmAmount: 0,
            usmThreshold: 0
        )
        
        let output = EditorState.processImage(inputImage, params: params, context: context)
        
        #expect(output != nil)
        #expect(output?.size.width == 100)
        #expect(output?.size.height == 100)
    }
    
    @Test("processImage should handle Unsharp Mask")
    func testProcessImageUnsharp() {
        let inputImage = createTestImage()
        let context = CIContext()
        
        let params = EditorState.FilterParameters(
            contrast: 1.0,
            brightness: 0.0,
            saturation: 1.0,
            denoiseStrength: 0.0,
            deringActive: false,
            deringStrength: 0.0,
            sharpenMethod: "unsharp",
            sharpenStrength: 0.0, // Ignored for unsharp
            usmRadius: 2.0,
            usmAmount: 0.5,
            usmThreshold: 0.01
        )
        
        let output = EditorState.processImage(inputImage, params: params, context: context)
        
        #expect(output != nil)
    }
    
    // MARK: - State Management Tests
    
    @Test("reset() should clear state")
    func testReset() {
        let state = EditorState()
        state.thumbnailImage = createTestImage()
        state.selectedFrameIndex = 5
        
        state.reset()
        
        #expect(state.thumbnailImage == nil)
        #expect(state.selectedFrameIndex == 0)
        #expect(state.timelineFrames.isEmpty)
    }
    
    @Test("setProcessingFullUpscale should update flag")
    func testFullUpscaleFlag() {
        let state = EditorState()
        
        // Cannot easily test private property isProcessingFullUpscale directly,
        // but we can verify it doesn't crash or error
        state.setProcessingFullUpscale(true)
        state.setProcessingFullUpscale(false)
    }
}

