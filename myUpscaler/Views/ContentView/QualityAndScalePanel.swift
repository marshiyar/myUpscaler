import SwiftUI

struct QualityScalePanel: View {
    @ObservedObject var settings: UpscaleSettings
    @State private var localCRF: Double? = nil

    var body: some View {
        InspectorSection(title: "Size and quality") {
            HStack(alignment: .center, spacing: 8) {
                Text("Quality")
                    .font(.body)
                    .frame(width: 92, alignment: .leading)
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
                .frame(minWidth: 90)
                .accessibilityLabel("Quality")
                Text("\(Int(localCRF ?? settings.codec.crf))")
                    .font(.body.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
                Color.clear.frame(width: 24, height: 1)
            }
            .padding(.vertical, 2)
            InspectorNote("Lower number, better quality")

            InspectorRow(title: "Size") {
                TextField("2.0", value: $settings.video.scaleFactor, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .accessibilityLabel("Size")
            }

            InspectorRow(title: settings.upscaling.scaler == "coreml" ? "Frame rate (source)" : "Frame rate",
                         enabled: settings.upscaling.scaler != "coreml") {
                TextField("60", text: $settings.video.fps.text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .disabled(settings.upscaling.scaler == "coreml")
                    .accessibilityLabel("Frame rate")
            }

            InspectorRow(title: "Smooth motion", enabled: settings.upscaling.scaler != "coreml") {
                Picker("Smooth motion", selection: $settings.interpolationChoice) {
                    if !["off", "mci", "blend"].contains(settings.interpolationChoice) {
                        Text("Saved choice unavailable").tag(settings.interpolationChoice).disabled(true)
                    }
                    Text("Off").tag("off")
                    Text("Follow motion").tag("mci")
                    Text("Blend frames").tag("blend")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(settings.upscaling.scaler == "coreml")
            }
        }
    }
}
