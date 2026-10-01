import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct QualityScalePanel: View {
    @ObservedObject var settings: UpscaleSettings
    @State private var localCRF: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Quality & Scale", systemImage: "chart.bar")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)

            GroupBox {
                VStack(spacing: 8) {
                    // CRF Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(settings.upscaling.scaler == "coreml" || settings.hardware.encoder == "videotoolbox" ? "Compression" : "CRF")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(localCRF ?? settings.codec.crf))")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.primary)
                            Text("(Lower is better)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        LuxuriousSlider(value: Binding(
                            get: { localCRF ?? settings.codec.crf },
                            set: { localCRF = $0 }
                        ), range: 0...51, step: 1, gradient: .crf, onEditingChanged: { editing in
                            if !editing {
                                if let finalValue = localCRF {
                                    settings.codec.crf = finalValue
                                    localCRF = nil
                                }
                            }
                        })
                        .frame(minWidth: 100)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    if settings.hardware.encoder == "videotoolbox" && settings.upscaling.scaler != "coreml" {
                        let quality = max(1, min(100, Int((100 - (localCRF ?? settings.codec.crf) * 99 / 51).rounded())))
                        Text("VideoToolbox quality: \(quality)/100. Hardware quality differs from CPU CRF.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if settings.upscaling.scaler == "coreml" {
                        Text("Controls the Core ML writer's target bitrate; this is not software CRF encoding.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Scale Factor and FPS
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scale")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("2.0", value: $settings.video.scaleFactor, format: .number)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.upscaling.scaler == "coreml" ? "FPS (source)" : "FPS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("60", text: $settings.video.fps.text)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .disabled(settings.upscaling.scaler == "coreml")
                        }
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Interpolation Mode
                    HStack {
                        Text("Interpolation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.interpolationChoice) {
                            if !["off", "mci", "blend"].contains(settings.interpolationChoice) {
                                Text("Saved mode unavailable").tag(settings.interpolationChoice).disabled(true)
                            }
                            Text("Off").tag("off")
                            Text("MCI").tag("mci")
                            Text("Blend").tag("blend")
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 140)
                        .disabled(settings.upscaling.scaler == "coreml")
                    }
                    if settings.upscaling.scaler == "coreml" {
                        Text("Core ML preserves source frame timing; interpolation and target FPS apply to FFmpeg only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}
