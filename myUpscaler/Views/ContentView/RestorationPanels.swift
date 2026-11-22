import SwiftUI

struct RestorationPanel: View {
    @ObservedObject var settings: UpscaleSettings

    private var aiUpscaling: Bool { settings.upscaling.scaler == "coreml" }

    var body: some View {
        InspectorSection {
            // Deblock Mode
            InspectorRow(title: "Remove blockiness", enabled: !aiUpscaling) {
                Picker("Remove blockiness", selection: $settings.additionalDeblockMode) {
                    Text("Off").tag("off")
                    ForEach(settings.deblockModes, id: \.self) { Text(DisplayName.deblockMode($0)).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(aiUpscaling)
            }

            if settings.primary.useDeblock {
                DeblockThresholdControls(text: $settings.primary.deblockThresh.text)
                    .disabled(aiUpscaling)
            }

            // Deband
            InspectorRow(title: "Remove banding", enabled: !aiUpscaling) {
                if aiUpscaling {
                    Text("Gradient-aware smoothing")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Remove banding", selection: Binding(get: {
                        settings.additionalDebandMethod == "f3kdb" ? "deband" : settings.additionalDebandMethod
                    }, set: { method in
                        if method != "deband" || settings.primary.debandMethod != "f3kdb" {
                            settings.additionalDebandMethod = method
                        } else {
                            settings.primary.useDeband = true
                        }
                    })) {
                        Text("Off").tag("off")
                        Text("Standard").tag("deband")
                        Text("Gradient").tag("gradfun")
                        Text("Advanced").tag("neo_f3kdb")
                            .disabled(!UpscaleSettings.neoF3kdbAvailable)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            if ["f3kdb", "neo_f3kdb"].contains(settings.primary.debandMethod) && !aiUpscaling {
                RestorationF3KDBControls(stage: $settings.additionalF3KDBStage)
                    .help("Whole numbers only.")
            } else {
                InspectorField(title: "Strength", placeholder: "0.015", text: $settings.additionalDebandAmount,
                               width: 55)
            }

            // Grain Strength
            InspectorField(title: "Grain", placeholder: "1.0", text: $settings.additionalGrainAmount,
                           enabled: !aiUpscaling, width: 50)
        }
    }
}
