import SwiftUI

struct HardwareEncodingPanel: View {
    @ObservedObject var settings: UpscaleSettings

    private var aiUpscaling: Bool { settings.upscaling.scaler == "coreml" }

    var body: some View {
        InspectorSection(title: "Performance") {
            InspectorRow(title: "Hardware decoding", enabled: !aiUpscaling) {
                Picker("Hardware decoding", selection: $settings.hardware.hwAccel) {
                    ForEach(settings.hwAccels, id: \.self) { Text(DisplayName.hardwareDecoding($0)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(aiUpscaling)
            }

            // The Lanczos engine always writes 8-bit H.264 with FLAC audio, so these choices only exist
            // for the Core ML path, where AVFoundation honours them.
            if aiUpscaling {
                InspectorSwitch(title: "Smaller file", isOn: $settings.codec.useHEVC)
                InspectorSwitch(title: "More color depth", isOn: $settings.effective10BitOutput,
                                enabled: settings.codec.useHEVC && !settings.modes.pciSafe)
                    .help("10-bit output requires HEVC")
                InspectorSwitch(title: "Standard color depth", isOn: $settings.modes.pciSafe)
                    .help("Overrides 10-bit output while preserving your saved bit-depth preference.")
            }

            InspectorField(title: "CPU threads", placeholder: "0 (auto)", text: $settings.hardware.threads.text,
                           enabled: !aiUpscaling)
        }
    }
}
