import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct HeaderView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "video.badge.waveform")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("myUpscaler")
                .font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct InputSection: View {
    @Binding var inputPath: String
    let chooseInput: () -> Void
    var canImport: () -> Bool = { true }
    let settings: UpscaleSettings
    var isProcessingFullUpscale: Bool = false
    var onFrameDoubleTap: ((NSImage?) -> Void)? = nil
    var onEditorStateAvailable: ((EditorState) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            dragDropView()
                .layoutPriority(1)
        }
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }

    private func dragDropView() -> some View {
        DragDropView(externalInputPath: $inputPath, settings: settings, chooseInput: chooseInput, canImport: canImport, isProcessingFullUpscale: isProcessingFullUpscale, onFrameDoubleTap: onFrameDoubleTap, onEditorStateAvailable: onEditorStateAvailable)
            .cornerRadius(10)
            .overlay(
                // Show overlay when processing to indicate preview is frozen
                Group {
                    if isProcessingFullUpscale {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Processing... Preview frozen")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            )
                    }
                }
            )
    }

}
