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
                VStack(spacing: 0) {
                    InputSection(inputPath: Binding(get: { runner.inputPath }, set: { path in
                        if !runner.isRunning { runner.inputPath = path }
                    }), chooseInput: { dispatcher.perform(.chooseInput) },
                        canImport: { !runner.isRunning }, settings: settings,
                        isProcessingFullUpscale: runner.isRunning,
                        onFrameDoubleTap: { enlargedFrameImage = $0 },
                        onEditorStateAvailable: { editorState = $0 })
                    Divider()
                    LogPanel(runner: runner)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showInspector {
                    Divider()
                    inspector
                        .frame(width: geometry.size.width >= 1080 ? 440 : 320)
                }
            }
            .toolbar {
                if #available(macOS 26, *) {
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 400, height: 24)
                            .contentShape(Rectangle())
                            .gesture(WindowDragGesture())
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 400, height: 24)
                            .contentShape(Rectangle())
                            .gesture(WindowDragGesture())
                    }
                }
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
        .onChange(of: enlargedFrameImage != nil) { _, _ in dispatcher.refreshAvailability() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !runner.inputPath.isEmpty || runner.isRunning {
                HStack(spacing: 20) {
                    ProgressDetails(runner: runner).frame(maxWidth: .infinity, alignment: .leading)
                    ActionButtons(runner: runner, settings: settings,
                                  run: { dispatcher.perform(.runUpscaler) },
                                  cancel: { dispatcher.perform(.cancel) }).frame(width: 150)
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
        // The enlarged preview covers the window.
        .overlay {
            if let img = enlargedFrameImage {
                ZStack {
                    Color.black
                        .onTapGesture(count: 2) { enlargedFrameImage = nil }
                    VStack(spacing: 8) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture(count: 2) { enlargedFrameImage = nil }
                        Text("Double-click or press Esc to close")
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.7))
                    }
                    .padding(16)
                }
                .ignoresSafeArea()
                .focusable()
                .onKeyPress(.escape) {
                    enlargedFrameImage = nil
                    return .handled
                }
            }
        }
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
        let workspaceAvailable = { !showSettings && !showAbout && enlargedFrameImage == nil && NSApplication.shared.modalWindow == nil }
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
        panel.allowedContentTypes = VideoInput.contentTypes
        panel.allowsOtherFileTypes = false

        if panel.runModal() == .OK, let url = panel.url, !runner.isRunning {
            guard VideoInput.acceptsSelection(url) else {
                runner.log.append("ERROR: \(VideoInput.message)\n")
                return
            }
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
