import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct AIEnginePanel: View {
    @Environment(\.workspaceInspector) private var inInspector
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !inInspector { HStack {
                Label("Upscaling", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2) }

            GroupBox {
                VStack(spacing: 8) {
                    // Scaler
                    HStack {
                        Text("Scaler")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("Scaler", selection: $settings.upscalingChoice) {
                            if let selected = settings.upscalingChoice, !settings.availableUpscalingChoices.contains(selected) {
                                Text("\(selected.displayName) (unavailable)").tag(Optional(selected)).disabled(true)
                            } else if settings.upscalingChoice == nil {
                                Text("Choose a scaler").tag(Optional<UpscalingChoice>.none).disabled(true)
                            }
                            ForEach(settings.availableUpscalingChoices) { choice in
                                Text(choice.displayName).tag(Optional(choice))
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Scaler")
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 160)
                    }


                    if settings.upscaling.scaler == "coreml" {
                        Text("Core ML supports primary denoise, sharpen, and deband. Deblock, dering, grain, and the second restoration pass apply to FFmpeg only. Preview is approximate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        let model = CoreMLModelRegistry.model(for: settings.upscaling.coremlModelId)
                        Text(model.nativeScale == settings.video.scaleFactor
                             ? "Model and output use \(model.nativeScale.formatted())× scaling."
                             : "Model predicts at \(model.nativeScale.formatted())×; output is resized once to \(settings.video.scaleFactor.formatted())×.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let reason = settings.upscalingUnavailableReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}
