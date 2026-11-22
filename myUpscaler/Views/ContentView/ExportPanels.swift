import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct OutputPanel: View {
    @Environment(\.workspaceInspector) private var inInspector
    @Binding var outputMode: UpscaleRunner.OutputMode
    @Binding var customOutputFolder: String
    let predictedName: String
    let chooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !inInspector { HStack {
                Label("Output", systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2) }

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
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 120)
                        .fixedSize()
                    }

                    if outputMode == .custom {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .font(.caption2)
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
                        }
                    }

                    Divider()
                        .padding(.vertical, 2)
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.accentColor)
                            .font(.caption2)
                        Text("Output:")
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
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActionButtons: View {
    @ObservedObject var runner: UpscaleRunner
    @ObservedObject var settings: UpscaleSettings

    let run: () -> Void
    let cancel: () -> Void

    var body: some View {
        Button {
            guard !runner.isCancelling else { return }
            if runner.isRunning {
                cancel()
            } else if !runner.inputPath.isEmpty && settings.upscalingUnavailableReason == nil {
                run()
            }
        } label: {
            Label(runner.isCancelling ? "Stopping…" : runner.isRunning ? "Cancel" : "Export video",
                  systemImage: runner.isRunning ? "stop.fill" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .frame(width: 150, height: UI.buttonHeight)
        .disabled(runner.isCancelling || (!runner.isRunning &&
                  (runner.inputPath.isEmpty || settings.upscalingUnavailableReason != nil)))
    }
}

struct ProgressDetails: View {
    @ObservedObject var runner: UpscaleRunner
    @ObservedObject private var settings: UpscaleSettings

    init(runner: UpscaleRunner) {
        self.runner = runner
        _settings = ObservedObject(wrappedValue: runner.settings)
    }

    private var status: String {
        if runner.isCancelling { return "Stopping…" }
        switch runner.phase {
        case .preparing: return "Preparing video…"
        case .processing: return runner.batchTotal > 0 ? "Folder export: \(runner.batchCompleted)/\(runner.batchTotal) completed" : "Processing frames"
        case .finalizing: return "Finalizing export…"
        case .idle:
            if runner.completedOutputPath != nil { return "Export complete" }
            if runner.batchTotal > 0 { return "Folder export stopped: \(runner.batchCompleted)/\(runner.batchTotal) completed" }
            if runner.inputPath.isEmpty { return "Import a video to begin" }
            return settings.upscalingUnavailableReason == nil ? "Ready to export" : "Choose an available upscaling mode"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if runner.completedOutputPath != nil && !runner.isRunning {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text(status).font(.subheadline.weight(.medium))
                Spacer()
                if runner.isRunning && runner.phase == .processing && runner.progressKnown {
                    Text(runner.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                }
            }
            if runner.isRunning {
                if runner.phase != .processing || !runner.progressKnown {
                    ProgressView().progressViewStyle(.linear).accessibilityLabel(status)
                } else {
                    ProgressView(value: max(0, min(1, runner.progress))).accessibilityLabel("Export progress")
                }
                if runner.batchTotal == 0 {
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
    }
}

struct LogPanel: View {
    @ObservedObject var runner: UpscaleRunner
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let outputPath = runner.completedOutputPath, !runner.isRunning {
                HStack(spacing: 8) {
                    Spacer()
                    Button("Open") { openVideoFile(at: outputPath) }.buttonStyle(.borderedProminent)
                    Button("Show in Finder") { revealVideoFile(at: outputPath) }.buttonStyle(.bordered)
                }
            }
            DisclosureGroup(isExpanded: $showDetails) {
                ScrollViewReader { reader in
                    ScrollView {
                        Text(runner.log.isEmpty ? "Export details will appear here." : runner.log)
                            .textSelection(.enabled)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                            .id("BOTTOM")
                    }
                    .onChange(of: runner.log) { _, _ in reader.scrollTo("BOTTOM", anchor: .bottom) }
                }
                .frame(height: 170)
                .background(Color.appTertiaryBackground)
                .padding(.top, 8)
            } label: {
                Label("Processing details", systemImage: "text.alignleft")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Note: sandbox requirement securityScopedOutputURL
    private func openVideoFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        let scopedURL = runner.securityScopedOutputURL
        let needsStopAccess = scopedURL?.startAccessingSecurityScopedResource() ?? false
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

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
