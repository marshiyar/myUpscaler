import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct X265ParametersPanel: View {
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("x265 Parameters", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)

            GroupBox {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        // AQ Mode
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AQ Mode")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("3", text: $settings.codec.x265AqMode.text)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                        }

                        // Psy-RD
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Psy-RD")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("2.0", text: $settings.codec.x265PsyRd.text)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                        }

                        // Deblock
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Deblock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                TextField("-2", text: $settings.codec.x265Deblock1.text)
                                    .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                    .frame(width: 35)
                                Text(",")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("-2", text: $settings.codec.x265Deblock2.text)
                                    .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                    .frame(width: 35)
                            }
                        }

                        Spacer()
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

struct HardwareEncodingPanel: View {
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Hardware & Encoding", systemImage: "gearshape.2")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)

            GroupBox {
                VStack(spacing: 8) {
                    // HW Acceleration
                    HStack {
                        Text("Decode acceleration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.hardware.hwAccel) {
                            ForEach(settings.hwAccels, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 140)
                        .disabled(settings.upscaling.scaler == "coreml")
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Encoder
                    HStack {
                        Text("Encoder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.hardware.encoder) {
                            ForEach(settings.encoders, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 140)
                        .disabled(settings.upscaling.scaler == "coreml")
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Toggles
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            Toggle(isOn: $settings.codec.useHEVC) {
                                Text("Use HEVC (H.265)")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            Toggle(isOn: $settings.effective10BitOutput) {
                                Text("10‑Bit Output")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            .disabled(settings.upscaling.scaler == "coreml" || !settings.codec.useHEVC || settings.modes.pciSafe)
                            .help("10-bit output requires HEVC and the Core ML path; Lanczos exports are 8-bit H.264")
                            // MOV Faststart Toggle
                            Toggle(isOn: Binding(
                                get: { settings.output.movflags.contains("+faststart") },
                                set: { isEnabled in
                                    if isEnabled {
                                        if !settings.output.movflags.contains("+faststart") {
                                            if settings.output.movflags.isEmpty {
                                                settings.output.movflags = "+faststart"
                                            } else {
                                                settings.output.movflags += " +faststart"
                                            }
                                        }
                                    } else {
                                        settings.output.movflags = settings.output.movflags.replacingOccurrences(of: "+faststart", with: "").trimmingCharacters(in: .whitespaces)
                                    }
                                }
                            )) {
                                Text("Faststart")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .disabled(settings.upscaling.scaler == "coreml")
                            .help("Moves metadata to the beginning of the file for faster web playback")

                            Spacer()
                        }

                        Toggle("Force 8-bit processing", isOn: $settings.modes.pciSafe)
                            .font(.caption)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .disabled(settings.upscaling.scaler == "coreml")
                            .help("Overrides 10-bit output while preserving your saved bit-depth preference.")

                        Divider()
                            .padding(.vertical, 2)

                        HStack {
                           Text("Audio Bitrate")
                               .font(.caption)
                               .foregroundColor(.secondary)
                           Spacer()
                           TextField("192k", text: $settings.output.audioBitrate)
                               .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                               .frame(width: 60)
                               .disabled(settings.upscaling.scaler == "coreml")
                       }

                    }

                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text("CPU encoding speed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.codec.preset) {
                            ForEach(settings.presets, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 140)
                        .disabled(settings.upscaling.scaler == "coreml" || settings.hardware.encoder == "videotoolbox")
                        .help("CPU x264/x265 speed and compression tradeoff. Does not control AI inference or VideoToolbox encoding.")
                    }

                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text("Threads")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("0 (auto)", text: $settings.hardware.threads.text)
                            .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .disabled(settings.upscaling.scaler == "coreml")
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
