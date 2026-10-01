import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct DragDropView: View {
    @StateObject private var state: EditorState
    @Binding var externalInputPath: String
    let settings: UpscaleSettings?
    let chooseInput: (() -> Void)?
    let canImport: () -> Bool
    var isProcessingFullUpscale: Bool = false
    var onFrameDoubleTap: ((NSImage?) -> Void)? = nil
    var onEditorStateAvailable: ((EditorState) -> Void)? = nil  // Callback to provide EditorState to parent

    init(externalInputPath: Binding<String>, settings: UpscaleSettings? = nil, chooseInput: (() -> Void)? = nil, canImport: @escaping () -> Bool = { true }, isProcessingFullUpscale: Bool = false, onFrameDoubleTap: ((NSImage?) -> Void)? = nil, onEditorStateAvailable: ((EditorState) -> Void)? = nil) {
        self._externalInputPath = externalInputPath
        self.settings = settings
        self.chooseInput = chooseInput
        self.canImport = canImport
        self.isProcessingFullUpscale = isProcessingFullUpscale
        self.onFrameDoubleTap = onFrameDoubleTap
        self.onEditorStateAvailable = onEditorStateAvailable
        _state = StateObject(wrappedValue: EditorState(settings: settings))
    }

    var body: some View {
        Group {
            if externalInputPath.isEmpty {
                ImportVideoView(isHovered: state.isHovered, chooseInput: chooseInput)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(URL(fileURLWithPath: externalInputPath).lastPathComponent, systemImage: "film")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Approximate preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let chooseInput {
                            Button("Change video", action: chooseInput)
                                .disabled(isProcessingFullUpscale)
                        }
                    }

                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            if let image = state.thumbnailImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .onTapGesture(count: 2) { onFrameDoubleTap?(image) }
                                    .accessibilityLabel("Adjusted video preview")
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "film").font(.title)
                                    Text("Video selected").font(.headline)
                                    Text("The preview will appear here when available.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                            }
                        }
                        .frame(minWidth: 160, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.appTertiaryBackground, in: RoundedRectangle(cornerRadius: 8))
                        .layoutPriority(1)

                    }
                    .disabled(isProcessingFullUpscale)
                    if !state.timelineFrames.isEmpty {
                        Divider()
                        TimelineView(state: state)
                            .frame(height: 82)
                            .disabled(isProcessingFullUpscale)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: $state.isHovered) { providers in
            guard canImport(), !isProcessingFullUpscale, let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        guard self.canImport() else { return }
                        self.externalInputPath = url.path
                    }
                } else if let url = item as? URL {
                    DispatchQueue.main.async {
                        guard self.canImport() else { return }
                        self.externalInputPath = url.path
                    }
                }
            }
            return true
        }
        .onChange(of: externalInputPath) { _, newPath in

            if state.filePath != newPath {
                state.filePath = newPath
            }
        }
        .onChange(of: state.filePath) { _, newPath in

            if externalInputPath != newPath {
                externalInputPath = newPath
            }
        }
        .onChange(of: isProcessingFullUpscale) { _, isProcessing in
            state.setProcessingFullUpscale(isProcessing)
        }
        .onAppear {
            if state.filePath != externalInputPath { state.filePath = externalInputPath }
            state.setProcessingFullUpscale(isProcessingFullUpscale)
            onEditorStateAvailable?(state)
        }
    }
}
