import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct AIEnginePanel: View {
    @Environment(\.workspaceInspector) private var inInspector
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !inInspector {
                HStack {
                Label("Upscaling", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2) }

            GroupBox {
                VStack(spacing: 8) {
                    // Scaler
                    HStack {
                        Text("Upscaling")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("Upscaling", selection: $settings.upscalingChoice) {
                            if let selected = settings.upscalingChoice, !settings.availableUpscalingChoices.contains(selected) {
                                Text("\(selected.menuName) (unavailable)").tag(Optional(selected)).disabled(true)
                            } else if settings.upscalingChoice == nil {
                                Text("Choose a scaler").tag(Optional<UpscalingChoice>.none).disabled(true)
                            }
                            ForEach(settings.availableUpscalingChoices) { choice in
                                Text(choice.menuName).tag(Optional(choice))
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Upscaling")
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 160)
                    }

                    if let reason = settings.upscalingUnavailableReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                }
                .padding(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .frame(maxWidth: .infinity)
    }
}

extension UpscalingChoice {
    /// The name in the Upscaling menu. `displayName` stays the model's own name, which the processing log uses.
    var menuName: String {
        switch self {
        case .lanczos: return "Standard"
        case .model(let id):
            return CoreMLModelRegistry.model(for: id).displayName
                .replacingOccurrences(of: #"^Real-ESRGAN x(\d+)"#, with: "AI $1x", options: .regularExpression)
        }
    }
}
