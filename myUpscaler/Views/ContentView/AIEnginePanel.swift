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
                        Picker("", selection: Binding(
                            get: { settings.scalers.contains(settings.upscaling.scaler) ? settings.upscaling.scaler : "" },
                            set: { settings.upscaling.scaler = $0 }
                        )) {
                            if !settings.scalers.contains(settings.upscaling.scaler) {
                                Text("Choose a mode").tag("").disabled(true)
                            }
                            ForEach(settings.scalers, id: \.self) { scaler in
                                Text(UpscalingModeSupport.label(for: scaler)).tag(scaler)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 140)
                    }

                    if settings.upscaling.scaler == "coreml" && !settings.coremlModels.isEmpty {
                        Divider()
                            .padding(.vertical, 2)

                        HStack {
                            Text("CoreML Model")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.upscaling.coremlModelId) {
                                if !settings.coremlModels.contains(where: { $0.id == settings.upscaling.coremlModelId }) {
                                    Text("Choose a model").tag(settings.upscaling.coremlModelId).disabled(true)
                                }
                                ForEach(settings.coremlModels) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(minWidth: 160)
                        }
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
