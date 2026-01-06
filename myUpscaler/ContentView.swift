import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - Main ContentView (orchestrates everything)
struct ContentView: View {
    @StateObject private var runner: UpscaleRunner
    @StateObject private var shortcutsManager = KeyboardShortcutsManager.shared
    @StateObject private var presetStore = PresetStore()
    
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var enlargedFrameImage: NSImage? = nil
    @State private var showEnlargedRestorationFilters: Bool = false
    @State private var showEnlargedColorEqualizer: Bool = false
    @State private var showPiPPreview: Bool = false
    @State private var editorState: EditorState? = nil

    init(runner: UpscaleRunner = UpscaleRunner()) {
        _runner = StateObject(wrappedValue: runner)
    }
    
    var body: some View {
        // ---------- SCROLLABLE CONTENT ----------
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: UI.sectionSpacing) {
                    HeaderView()
                        .zIndex(2)
                    
                    InputSection(inputPath: $runner.inputPath,
                                chooseInput: chooseInput,
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
                    
                    // Responsive two-column layout
                    adaptiveColumnsLayout(geometry: geometry)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, responsiveHorizontalPadding(for: geometry.size.width))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: UI.windowMinWidth, minHeight: UI.windowMinHeight)
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
    private func adaptiveColumnsLayout(geometry: GeometryProxy) -> some View {
        let availableWidth = geometry.size.width - (2 * responsiveHorizontalPadding(for: geometry.size.width))
        let useStackedLayout = availableWidth < 680
        
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
    
    /// Left column content - Configuration & AI panels
    private var leftColumnContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Group 1: Configuration & Encoding
            MatteCardGroup(spacing: 8) {
                QualityScalePanel(settings: runner.settings)
                HardwareEncodingPanel(settings: runner.settings)
                X265ParametersPanel(settings: runner.settings)
            }
            
            // Group 2: AI & Restoration
            MatteCardGroup(spacing: 8) {
                AIEnginePanel(settings: runner.settings)
                RestorationPanel(settings: runner.settings)
                RestorationSecondSetPanel(settings: runner.settings)
            }
        }
    }
    
    /// Right column content - Output, Progress & Presets
    private var rightColumnContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Group 3: Output & Controls
            MatteCardGroup(spacing: 8) {
                OutputPanel(outputMode: $runner.outputMode,
                           customOutputFolder: $runner.customOutputFolder,
                           predictedName: runner.predictedOutputName,
                           chooseFolder: chooseOutputFolder)
         
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(runner.inputPath.isEmpty)
                
                ActionButtons(runner: runner)
            }
            
            // Group 4: Progress & Status
            MatteCardGroup(spacing: 8) {
                ProgressDetails(runner: runner)
                LogPanel(runner: runner)
            }
            
            // Group 5: Presets
            MatteCardGroup(spacing: 8) {
                SavedPresetsPanel(presetStore: presetStore,
                                  settings: runner.settings,
                                  isProcessing: runner.isRunning)
            }
        }
    }
    
    // MARK: -  File‑picker helpers (UI only, MARKED @MainActor)
    @MainActor
    private func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
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
