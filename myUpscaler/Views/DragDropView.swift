import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct DragDropView: View {
    @StateObject private var state: EditorState
    @Binding var externalInputPath: String
    let settings: UpscaleSettings?
    let chooseInput: (() -> Void)?
    var isProcessingFullUpscale: Bool = false
    var onFrameDoubleTap: ((NSImage?) -> Void)? = nil
    var onRestorationFiltersDrag: (() -> Void)? = nil
    var onColorEqualizerDrag: (() -> Void)? = nil
    var onEditorStateAvailable: ((EditorState) -> Void)? = nil  // Callback to provide EditorState to parent

    init(externalInputPath: Binding<String>, settings: UpscaleSettings? = nil, chooseInput: (() -> Void)? = nil, isProcessingFullUpscale: Bool = false, onFrameDoubleTap: ((NSImage?) -> Void)? = nil, onRestorationFiltersDrag: (() -> Void)? = nil, onColorEqualizerDrag: (() -> Void)? = nil, onEditorStateAvailable: ((EditorState) -> Void)? = nil) {
        self._externalInputPath = externalInputPath
        self.settings = settings
        self.chooseInput = chooseInput
        self.isProcessingFullUpscale = isProcessingFullUpscale
        self.onFrameDoubleTap = onFrameDoubleTap
        self.onRestorationFiltersDrag = onRestorationFiltersDrag
        self.onColorEqualizerDrag = onColorEqualizerDrag
        self.onEditorStateAvailable = onEditorStateAvailable
        _state = StateObject(wrappedValue: EditorState(settings: settings))
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 600
            let sidePanelWidth: CGFloat = isCompact ? 120 : 140
            let timelineWidth: CGFloat = isCompact ? 70 : 90

            VStack(spacing: DesignSystem.Spacing.sm) {

                HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                    // Left side: Color Equalizer (centered vertically)
                    if let settings = settings {
                        VStack(alignment: .leading, spacing: 6) {
                            VerticalColorEqualizerPanel(settings: settings, onDragToEnlarge: onColorEqualizerDrag)

                            if let chooseInput = chooseInput {
                                Button(action: chooseInput) {
                                    Label("Browse Files", systemImage: "folder.fill")
                                        .font(DesignSystem.Typography.caption1)
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .frame(width: sidePanelWidth)
                                .dynamicKeyboardShortcut(actionId: "chooseInput", action: chooseInput)
                            }
                        }
                        .frame(width: sidePanelWidth)
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    ZStack {

                        if let img = state.thumbnailImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(10)
                                .shadow(radius: 3)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onTapGesture(count: 2) {
                                    onFrameDoubleTap?(img)
                                }
                        } else {
                            EmptyStateView(
                                icon: "video.fill",
                                title: "Drop a video",
                                message: "Drop a video or use Browse Files to begin."
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 200)
                    .layoutPriority(1)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.25))
                    )

                    if let settings = settings {
                        HStack(spacing: DesignSystem.Spacing.xs) {

                            VerticalRestorationFiltersPanel(settings: settings, onDragToEnlarge: onRestorationFiltersDrag)
                                .frame(width: sidePanelWidth)

                            // Timeline
                            TimelineView(state: state)
                                .frame(width: timelineWidth)
                                .frame(maxHeight: .infinity)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    } else {
                        // Timeline only (if no settings)
                        TimelineView(state: state)
                            .frame(width: timelineWidth)
                            .frame(maxHeight: .infinity)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .padding(DesignSystem.Spacing.sm)
        }
        .background(Color.appBackground.opacity(0.3))
        .onDrop(of: [UTType.fileURL], isTargeted: $state.isHovered) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        self.state.filePath = url.path
                    }
                } else if let url = item as? URL {
                    DispatchQueue.main.async {
                        self.state.filePath = url.path
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
            state.setProcessingFullUpscale(isProcessingFullUpscale)
            onEditorStateAvailable?(state)
        }
    }
}
