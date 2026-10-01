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
                            TextField("3", text: $settings.x265AqMode)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                        }

                        // Psy-RD
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Psy-RD")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("2.0", text: $settings.x265PsyRd)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                        }

                        // Deblock
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Deblock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                TextField("-2", text: $settings.x265Deblock1)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 35)
                                Text(",")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("-2", text: $settings.x265Deblock2)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 35)
                            }
                        }

                        Spacer()
                    }
                }
                .padding(8)
            }
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
                        Picker("", selection: $settings.hwAccel) {
                            ForEach(settings.hwAccels, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 140)
                        .disabled(settings.scaler == "coreml")
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Encoder
                    HStack {
                        Text("Encoder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.encoder) {
                            ForEach(settings.encoders, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 140)
                        .disabled(settings.scaler == "coreml")
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Toggles
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            Toggle(isOn: $settings.useHEVC) {
                                Text("Use HEVC (H.265)")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            Toggle(isOn: $settings.use10Bit) {
                                Text("10‑Bit Output")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            .disabled(settings.scaler == "coreml" || !settings.useHEVC)
                            .help("10-bit output requires HEVC and the FFmpeg processing path")
                            // MOV Faststart Toggle
                            Toggle(isOn: Binding(
                                get: { settings.movflags.contains("+faststart") },
                                set: { isEnabled in
                                    if isEnabled {
                                        if !settings.movflags.contains("+faststart") {
                                            if settings.movflags.isEmpty {
                                                settings.movflags = "+faststart"
                                            } else {
                                                settings.movflags += " +faststart"
                                            }
                                        }
                                    } else {
                                        settings.movflags = settings.movflags.replacingOccurrences(of: "+faststart", with: "").trimmingCharacters(in: .whitespaces)
                                    }
                                }
                            )) {
                                Text("Faststart")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .disabled(settings.scaler == "coreml")
                            .help("Moves metadata to the beginning of the file for faster web playback")

                            Spacer()
                        }

                        Divider()
                            .padding(.vertical, 2)

                        HStack {
                           Text("Audio Bitrate")
                               .font(.caption)
                               .foregroundColor(.secondary)
                           Spacer()
                           TextField("192k", text: $settings.audioBitrate)
                               .textFieldStyle(.roundedBorder)
                               .frame(width: 60)
                               .disabled(settings.scaler == "coreml")
                       }

                        Text(settings.scaler == "coreml"
                             ? "Core ML uses its own reader and writer. Decode, encoder, 10-bit, audio bitrate, and Faststart controls apply to FFmpeg only."
                             : "Decode acceleration and output encoding are independent. 10-bit output requires HEVC; PCI Safe Mode forces 8-bit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text("CPU encoding speed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.preset) {
                            ForEach(settings.presets, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 140)
                        .disabled(settings.scaler == "coreml" || settings.encoder == "videotoolbox")
                        .help("CPU x264/x265 speed and compression tradeoff. Does not control AI inference or VideoToolbox encoding.")
                    }

                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text("Threads")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("0 (auto)", text: $settings.threads)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .disabled(settings.scaler == "coreml")
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}
