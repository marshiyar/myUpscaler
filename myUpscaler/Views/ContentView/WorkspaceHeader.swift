import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct InputSection: View {
    @Binding var inputPath: String
    let chooseInput: () -> Void
    var canImport: () -> Bool = { true }
    let settings: UpscaleSettings
    var isProcessingFullUpscale: Bool = false
    var onFrameDoubleTap: ((NSImage?) -> Void)? = nil
    var onEditorStateAvailable: ((EditorState) -> Void)? = nil

    var body: some View {
        DragDropView(externalInputPath: $inputPath, settings: settings, chooseInput: chooseInput, canImport: canImport, isProcessingFullUpscale: isProcessingFullUpscale, onFrameDoubleTap: onFrameDoubleTap, onEditorStateAvailable: onEditorStateAvailable)
    }
}
