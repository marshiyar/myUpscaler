import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct OutputPanel: View {
    @Binding var outputMode: UpscaleRunner.OutputMode
    @Binding var customOutputFolder: String
    let predictedName: String
    let chooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Output", systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $outputMode) {
                            Text("Same folder").tag(UpscaleRunner.OutputMode.same)
                            Text("Custom folder").tag(UpscaleRunner.OutputMode.custom)
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 120)
                        .fixedSize()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: outputMode)
                    }

                    if outputMode == .custom {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                            Text(customOutputFolder.isEmpty ? "Choose an output folder" : customOutputFolder)
                                .help(customOutputFolder)
                                .textSelection(.enabled)
                                .truncationMode(.middle)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                            Spacer()

                            Button("Choose", action: chooseFolder)
                                .controlSize(.mini)
                                .dynamicKeyboardShortcut(actionId: "chooseOutput", action: chooseFolder)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .background(cardBackground)  // background to see easier
                        .cornerRadius(6)
                        .zIndex(1)
                    }

                    Divider()
                        .padding(.vertical, 2)
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 10))
                        Text("Output file:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(predictedName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActionButtons: View {
    @ObservedObject var runner: UpscaleRunner
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        HStack(spacing: 12) {
            Button(action: runner.run) {
                HStack {
                    if runner.isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(runner.isRunning ? "Processing…" : "Run Upscaler")
                }
                .frame(maxWidth: .infinity)
            }

            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .frame(height: UI.buttonHeight)
            .disabled(runner.isRunning || runner.inputPath.isEmpty || settings.upscalingUnavailableReason != nil)
            .dynamicKeyboardShortcut(actionId: "runUpscaler") {
                if !runner.isRunning && !runner.inputPath.isEmpty && settings.upscalingUnavailableReason == nil { runner.run() }
            }

            Button(action: runner.cancel) {
                Label("Cancel", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(height: UI.buttonHeight)
            .disabled(!runner.isRunning)
            .dynamicKeyboardShortcut(actionId: "cancel") {
                if runner.isRunning { runner.cancel() }
            }
        }
    }
}

struct ProgressDetails: View {
    @ObservedObject var runner: UpscaleRunner

    private var status: String {
        if runner.isCancelling { return "Stopping…" }
        switch runner.phase {
        case .preparing: return "Preparing video…"
        case .processing: return "Processing frames"
        case .finalizing: return "Finalizing export…"
        case .idle: return runner.completedOutputPath == nil ? "Ready to export" : "Export complete"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(status).font(.caption.weight(.semibold))
                Spacer()
                if runner.progressKnown {
                    Text(runner.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                }
            }
            if runner.isRunning && (runner.phase != .processing || !runner.progressKnown) {
                ProgressView().progressViewStyle(.linear)
                    .accessibilityLabel(status)
            } else {
                ProgressView(value: max(0, min(1, runner.progress)))
                    .accessibilityLabel("Export progress")
            }
            HStack(spacing: 14) {
                Text("Processing: \(runner.fpsString) fps")
                Text("Media time: \(runner.timeString)")
                Text("Remaining: \(runner.etaString)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

struct LogPanel: View {
    @ObservedObject var runner: UpscaleRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Processing Log", systemImage: "text.bubble")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)

            GroupBox {
                VStack(spacing: 8) {
                    ScrollViewReader { reader in
                        ScrollView {
                            Text(runner.log.isEmpty ? "Processing details appear here when you export." : runner.log)
                                .textSelection(.enabled)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(6)                      // tight inner padding
                                .id("BOTTOM")
                        }
                        .onChange(of: runner.log) { _, _ in
                            reader.scrollTo("BOTTOM", anchor: .bottom)
                        }
                    }
                    .frame(height: 170)

                    if !runner.isRunning, let outputPath = runner.completedOutputPath {
                            Divider()
                                .padding(.vertical, 4)

                            HStack(spacing: 8) {
                                Button(action: {
                                    openVideoFile(at: outputPath)
                                }) {
                                    HStack {
                                        Image(systemName: "play.circle.fill")
                                        Text("Open")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button(action: {
                                    revealVideoFile(at: outputPath)
                                }) {
                                    HStack {
                                        Image(systemName: "folder")
                                        Text("Reveal in Finder")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
        .onChange(of: runner.inputPath) { _, _ in
            runner.completedOutputPath = nil
        }
    }

    // Note: sandbox requirement securityScopedOutputURL
    private func openVideoFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        var needsStopAccess = false
        if let scopedURL = runner.securityScopedOutputURL {
            needsStopAccess = scopedURL.startAccessingSecurityScopedResource()
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let scopedURL = runner.securityScopedOutputURL

        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if needsStopAccess, let url = scopedURL {
                url.stopAccessingSecurityScopedResource()
            }

            if let error = error {
                DispatchQueue.main.async {
                    print("Failed to open video: \(error.localizedDescription)")
                    let alert = NSAlert()
                    alert.informativeText = "No path permission, revealed in Finder instead."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()

                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    private func revealVideoFile(at path: String) {
        // Revealing in Finder works reliably under sandbox
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
