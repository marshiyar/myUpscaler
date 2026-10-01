import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - Main ContentView (orchestrates everything)
struct ContentView: View {
    @StateObject private var runner: UpscaleRunner
    @ObservedObject private var settings: UpscaleSettings
    @StateObject private var presetStore = PresetStore()

    @State private var showSettings = false
    @State private var showAbout = false
    @State private var enlargedFrameImage: NSImage? = nil
    @State private var showEnlargedRestorationFilters: Bool = false
    @State private var showEnlargedColorEqualizer: Bool = false
    @State private var showPiPPreview: Bool = false
    @State private var editorState: EditorState? = nil
    @State private var showEncoding = false
    @State private var showRestoration = false
    @State private var showConfigurationBeforeImport = false
    @State private var showPresets = false

    init(runner: UpscaleRunner = UpscaleRunner()) {
        _runner = StateObject(wrappedValue: runner)
        _settings = ObservedObject(wrappedValue: runner.settings)
    }

    var body: some View {
        // ---------- SCROLLABLE CONTENT ----------
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: UI.sectionSpacing) {
                    HeaderView()

                    InputSection(inputPath: Binding(get: { runner.inputPath }, set: { path in
                                    if !runner.isRunning { runner.inputPath = path }
                                }),
                                chooseInput: chooseInput,
                                canImport: { !runner.isRunning },
                                settings: runner.settings,
                                isProcessingFullUpscale: runner.isRunning,
                                onFrameDoubleTap: { image in
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        enlargedFrameImage = image
                                    }
                                },
                                onRestorationFiltersDrag: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        showEnlargedRestorationFilters = true
                                    }
                                },
                                onColorEqualizerDrag: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        showEnlargedColorEqualizer = true
                                    }
                                },
                                onEditorStateAvailable: { state in
                                    editorState = state
                                })

                    if runner.inputPath.isEmpty {
                        DisclosureGroup("Configure before importing", isExpanded: $showConfigurationBeforeImport) {
                            adaptiveColumnsLayout(geometry: geometry)
                                .padding(.top, 12)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 4)
                    } else {
                        adaptiveColumnsLayout(geometry: geometry)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, responsiveHorizontalPadding(for: geometry.size.width))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: UI.windowMinWidth, minHeight: UI.windowMinHeight)
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !runner.inputPath.isEmpty || runner.isRunning {
              VStack(spacing: 8) {
                Divider()
                HStack(spacing: 24) {
                    ProgressDetails(runner: runner)
                        .frame(maxWidth: .infinity)
                    ActionButtons(runner: runner, settings: settings)
                        .frame(width: 280)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
              .background(Color.appBackground)
            }
        }
        // ---------- TOOLBAR ----------
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .dynamicKeyboardShortcut(actionId: "openSettings") {
                    showSettings = true
                }

                Button(action: { showAbout = true }) {
                    Label("About", systemImage: "info.circle")
                }
                .dynamicKeyboardShortcut(actionId: "openAbout") {
                    showAbout = true
                }
            }
        }
        // ---------- SHEETS ----------
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: runner.settings)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        // MARK: -  ---------- ENLARGED FRAME OVERLAY (covers entire app) ----------
        .overlay(
                Group {
                    // Enlarged Frame Image
                    if let img = enlargedFrameImage {
                        ZStack {
                            // Semi-transparent background covering entire window
                            Color.black.opacity(0.85)
                                .ignoresSafeArea(.all)
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        enlargedFrameImage = nil
                                    }
                                }

                            // Enlarged image centered
                            VStack {
                                Spacer()

                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(40)
                                    .onTapGesture(count: 2) {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            enlargedFrameImage = nil
                                        }
                                    }

                                Spacer()
                                // Hint text
                                HStack {
                                    Text("Double-click to close")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.4))
                                    Text("Press ESC")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.bottom, 20)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .zIndex(10000)  // Very high z-index to ensure it's on top
                        .focusable()
                        .onKeyPress(.escape) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                enlargedFrameImage = nil
                            }
                            return .handled
                        }
                    }
                }
        )
        .onChange(of: runner.inputPath) { _, _ in
            // Reset enlarged frame, restoration filters, and color equalizer when new video is imported
            enlargedFrameImage = nil
            showEnlargedRestorationFilters = false
            showEnlargedColorEqualizer = false
        }
    }
    // MARK: – Responsive Layout Helpers
    /// Calculates responsive horizontal padding based on window width
    private func responsiveHorizontalPadding(for width: CGFloat) -> CGFloat {
        if width < 800 {
            return 12
        } else if width < 1200 {
            return 16
        } else {
            return 24
        }
    }

    @ViewBuilder
     func adaptiveColumnsLayout(geometry: GeometryProxy) -> some View {
        let availableWidth = geometry.size.width - (2 * responsiveHorizontalPadding(for: geometry.size.width))
        let useStackedLayout = availableWidth < 780

        if useStackedLayout {
            // Stacked layout for narrow windows (half screen, etc.)
            VStack(spacing: 14) {
                leftColumnContent
                rightColumnContent
            }
        } else {
            // Side-by-side layout for wider windows
            HStack(alignment: .top, spacing: UI.columnSpacing) {
                leftColumnContent
                    .frame(
                        minWidth: UI.leftColumnMinWidth,
                        idealWidth: UI.leftColumnIdealWidth,
                        maxWidth: UI.leftColumnMaxWidth
                    )

                rightColumnContent
                    .frame(
                        minWidth: UI.rightColumnMinWidth,
                        idealWidth: UI.rightColumnIdealWidth,
                        maxWidth: UI.rightColumnMaxWidth
                    )
            }
        }
    }

    /// Core decisions stay together; encoding and restoration detail remain optional.
    var leftColumnContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            MatteCardGroup(spacing: 16) {
                AIEnginePanel(settings: settings)
                Divider()
                QualityScalePanel(settings: settings)
                DisclosureGroup("Encoding details", isExpanded: $showEncoding) {
                    HardwareEncodingPanel(settings: settings)
                    X265ParametersPanel(settings: settings)
                        .disabled(!settings.useHEVC || settings.encoder == "videotoolbox" || settings.scaler == "coreml")
                        .help("x265 parameters apply only to CPU HEVC encoding")
                }
                .font(.subheadline)
            }
            MatteCardGroup(spacing: 8) {
                DisclosureGroup("Additional restoration", isExpanded: $showRestoration) {
                    RestorationPanel(settings: settings)
                    RestorationSecondSetPanel(settings: settings)
                }
                .font(.subheadline)
            }
        }
        .disabled(runner.isRunning)
    }

    var rightColumnContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            MatteCardGroup(spacing: 8) {
                OutputPanel(outputMode: $runner.outputMode,
                            customOutputFolder: $runner.customOutputFolder,
                            predictedName: runner.inputPath.isEmpty ? "Choose a video first" : runner.predictedOutputName,
                            chooseFolder: chooseOutputFolder)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .disabled(runner.isRunning)

            LogPanel(runner: runner)

            MatteCardGroup(spacing: 8) {
                DisclosureGroup("Saved presets", isExpanded: $showPresets) {
                    SavedPresetsPanel(presetStore: presetStore,
                                      settings: settings,
                                      isProcessing: runner.isRunning)
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: -  File‑picker helpers (UI only, MARKED @MainActor)
    @MainActor
    private func chooseInput() {
        guard !runner.isRunning else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a video or batch folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url, !runner.isRunning {
            runner.inputPath = url.path
        }
    }

    @MainActor
    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK, let url = panel.url {
            runner.customOutputFolder = url.path
            runner.securityScopedOutputURL = url
        }
    }
}
