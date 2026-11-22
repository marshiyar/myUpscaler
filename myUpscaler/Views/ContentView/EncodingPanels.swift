import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

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

                    // The Lanczos engine always writes 8-bit H.264 with FLAC audio, so these choices only exist
                    // for the Core ML path, where AVFoundation honours them.
                    if settings.upscaling.scaler == "coreml" {
                        VStack(spacing: 6) {
                            HStack(spacing: 12) {
                                Toggle(isOn: $settings.codec.useHEVC) {
                                    Text("Use HEVC (H.265)")
                                        .font(.caption)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)

                                Toggle(isOn: $settings.effective10BitOutput) {
                                    Text("10-Bit Output")
                                        .font(.caption)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .disabled(!settings.codec.useHEVC || settings.modes.pciSafe)
                                .help("10-bit output requires HEVC")

                                Spacer()
                            }

                            Toggle("Force 8-bit processing", isOn: $settings.modes.pciSafe)
                                .font(.caption)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .help("Overrides 10-bit output while preserving your saved bit-depth preference.")
                        }

                        Divider()
                            .padding(.vertical, 2)
                    }

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
        }
        .frame(maxWidth: .infinity)
    }
}
