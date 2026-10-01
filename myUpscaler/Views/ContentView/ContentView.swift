import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - Main ContentView (orchestrates everything)
struct ContentView: View {
    @StateObject private var runner: UpscaleRunner
    @ObservedObject private var settings: UpscaleSettings
    @StateObject private var presetStore = PresetStore()
    @StateObject private var dispatcher = CommandDispatcher()

    @State private var showSettings = false
    @State private var showAbout = false
    @State private var enlargedFrameImage: NSImage? = nil
    @State private var showPiPPreview: Bool = false
    @State private var editorState: EditorState? = nil
    @State private var showInspector = false

    init(runner: UpscaleRunner = UpscaleRunner(), inspectorInitiallyVisible: Bool = false) {
        _showInspector = State(initialValue: inspectorInitiallyVisible)
        _runner = StateObject(wrappedValue: runner)
        _settings = ObservedObject(wrappedValue: runner.settings)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        InputSection(inputPath: Binding(get: { runner.inputPath }, set: { path in
                            if !runner.isRunning { runner.inputPath = path }
                        }), chooseInput: { dispatcher.perform(.chooseInput) },
                            canImport: { !runner.isRunning }, settings: settings,
                            isProcessingFullUpscale: runner.isRunning,
                            onFrameDoubleTap: { enlargedFrameImage = $0 },
                            onEditorStateAvailable: { editorState = $0 })
                            .frame(height: max(360, geometry.size.height - 140))
                        LogPanel(runner: runner)
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showInspector {
                    Divider()
                    inspector
                        .frame(width: geometry.size.width >= 1080 ? 440 : 320)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { dispatcher.perform(.chooseInput) } label: { Label("Import", systemImage: "folder.badge.plus") }
                        .disabled(runner.isRunning)
                        .help("Choose a video or batch folder")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        dispatcher.perform(.toggleInspector)
                    } label: { Label("Adjustments", systemImage: "sidebar.right") }
                    .help("Show or hide the docked adjustments panel")
                    .accessibilityLabel(showInspector ? "Hide adjustments panel" : "Show adjustments panel")
                    Button { dispatcher.perform(.openSettings) } label: { Label("Settings", systemImage: "gearshape") }

                    Button { dispatcher.perform(.openAbout) } label: { Label("About", systemImage: "info.circle") }

                }
            }
        }
        .frame(minWidth: 720, minHeight: UI.windowMinHeight)
        .background(Color.appBackground)
        .navigationTitle("myUpscaler")
        .focusedSceneValue(\.commandDispatcher, dispatcher)
        .onAppear { configureCommands() }
        .onDisappear { dispatcher.configure([:]) }
        .onChange(of: runner.isCancelling) { _, _ in dispatcher.refreshAvailability() }
        .onChange(of: runner.isRunning) { _, _ in dispatcher.refreshAvailability() }
        .onChange(of: runner.inputPath) { _, _ in dispatcher.refreshAvailability() }
        .onChange(of: settings.upscalingUnavailableReason) { _, _ in dispatcher.refreshAvailability() }
        .onChange(of: showSettings) { _, _ in dispatcher.refreshAvailability() }
        .onChange(of: showAbout) { _, _ in dispatcher.refreshAvailability() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !runner.inputPath.isEmpty || runner.isRunning {
                HStack(spacing: 20) {
                    ProgressDetails(runner: runner).frame(maxWidth: .infinity, alignment: .leading)
                    ActionButtons(runner: runner, settings: settings,
                                  run: { dispatcher.perform(.runUpscaler) },
                                  cancel: { dispatcher.perform(.cancel) }).frame(width: runner.isRunning ? 270 : 150)
                }
                .padding(16)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
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
            // Reset the enlarged frame when a new video is imported
            enlargedFrameImage = nil
        }
    }
    private var inspector: some View {
        WorkspaceInspector(runner: runner, settings: settings, presetStore: presetStore,
                           chooseOutputFolder: { dispatcher.perform(.chooseOutput) })
    }

    private func configureCommands() {
        let workspaceAvailable = { !showSettings && !showAbout && NSApplication.shared.modalWindow == nil }
        dispatcher.configure([
            .runUpscaler: .init(isEnabled: { workspaceAvailable() && !runner.isRunning && !runner.inputPath.isEmpty && settings.upscalingUnavailableReason == nil }, perform: runner.run),
            .cancel: .init(isEnabled: { runner.isRunning && !runner.isCancelling }, perform: runner.cancel),
            .openSettings: .init(isEnabled: { workspaceAvailable() }, perform: { showSettings = true }),
            .openAbout: .init(isEnabled: { workspaceAvailable() }, perform: { showAbout = true }),
            .chooseInput: .init(isEnabled: { workspaceAvailable() && !runner.isRunning }, perform: chooseInput),
            .chooseOutput: .init(isEnabled: { workspaceAvailable() && !runner.isRunning }, perform: chooseOutputFolder),
            .toggleInspector: .init(isEnabled: workspaceAvailable, perform: { showInspector.toggle() })
        ])
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
        guard !runner.isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK, let url = panel.url, !runner.isRunning {
            runner.customOutputFolder = url.path
            runner.securityScopedOutputURL = url
        }
    }
}
