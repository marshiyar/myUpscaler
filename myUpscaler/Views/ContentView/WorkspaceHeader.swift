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
            VStack(alignment: .leading, spacing: 3) {
                Text("Video workspace").font(.title2.weight(.semibold))
                Text("Preview your adjustments, choose output settings, then export.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct InputSection: View {
    @Binding var inputPath: String
    let chooseInput: () -> Void
    let settings: UpscaleSettings
    var isProcessingFullUpscale: Bool = false
    var onFrameDoubleTap: ((NSImage?) -> Void)? = nil
    var onRestorationFiltersDrag: (() -> Void)? = nil
    var onColorEqualizerDrag: (() -> Void)? = nil
    var onEditorStateAvailable: ((EditorState) -> Void)? = nil

    var body: some View {
        MatteCardGroup(spacing: 8) {
            dragDropView()
                .frame(minHeight: 280)
                .layoutPriority(1)
        }
    }

    private func dragDropView() -> some View {
        DragDropView(externalInputPath: $inputPath, settings: settings, chooseInput: chooseInput, isProcessingFullUpscale: isProcessingFullUpscale, onFrameDoubleTap: onFrameDoubleTap, onRestorationFiltersDrag: onRestorationFiltersDrag, onColorEqualizerDrag: onColorEqualizerDrag, onEditorStateAvailable: onEditorStateAvailable)
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
