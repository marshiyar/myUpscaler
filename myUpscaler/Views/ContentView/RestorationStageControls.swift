import SwiftUI
import Combine

/// Both passes edit their own stage; presentation and annotations are view concerns.
struct RestorationSharpenControls: View {
    enum Presentation { case sliders, compact }
    @Binding var stage: RestorationStage
    @ObservedObject var settings: UpscaleSettings
    var presentation: Presentation

    var body: some View {
        switch presentation {
        case .sliders:
            if stage.sharpenMethod == "cas" {
                ParameterRow(title: "Strength",
                             binding: $stage.sharpenStrength.text,
                             range: settings.sharpenStrengthRange,
                             step: settings.sharpenStrengthStep,
                             defaultValue: settings.sharpenStrengthDefault,
                             formatter: Formatters.twoFraction,
                             sliderAccessibility: "Sharpen strength",
                             gradient: .sharpen)
                { _ in settings.objectWillChange.send() }
            } else {
                VStack(alignment: .leading, spacing: UI.rowSpacing) {
                    ParameterRow(title: "Radius",
                                 binding: $stage.usmRadius.text,
                                 range: settings.usmRadiusRange,
                                 step: settings.usmRadiusStep,
                                 defaultValue: settings.usmRadiusDefault,
                                 formatter: Formatters.integer,
                                 sliderAccessibility: "Sharpen radius",
                                 gradient: .usmRadius)
                    { _ in settings.objectWillChange.send() }

                    ParameterRow(title: "Amount",
                                 binding: $stage.usmAmount.text,
                                 range: settings.usmAmountRange,
                                 step: settings.usmAmountStep,
                                 defaultValue: settings.usmAmountDefault,
                                 formatter: Formatters.twoFraction,
                                 sliderAccessibility: "Sharpen amount",
                                 gradient: .usmAmount)
                    { _ in settings.objectWillChange.send() }

                    ParameterRow(title: "Threshold",
                                 binding: $stage.usmThreshold.text,
                                 range: settings.usmThresholdRange,
                                 step: settings.usmThresholdStep,
                                 defaultValue: settings.usmThresholdDefault,
                                 formatter: Formatters.threeFraction,
                                 sliderAccessibility: "Sharpen threshold",
                                 gradient: .usmThreshold)
                    { _ in settings.objectWillChange.send() }
                }
            }
        case .compact:
            if stage.sharpenMethod == "unsharp" {
                InspectorField(title: "Radius", placeholder: "5", text: $stage.usmRadius.text, width: 50)
                InspectorField(title: "Amount", placeholder: "1.0", text: $stage.usmAmount.text, width: 50)
            } else {
                InspectorField(title: "Strength", placeholder: "0.25", text: $stage.sharpenStrength.text, width: 50)
            }
        }
    }
}

struct RestorationF3KDBControls: View {
    @Binding var stage: RestorationStage

    var body: some View {
        VStack(alignment: .leading, spacing: UI.rowSpacing) {
            InspectorField(title: "Radius", placeholder: "15", text: $stage.f3kdbRange.text, width: 50)
            InspectorField(title: "Brightness", placeholder: "64", text: $stage.f3kdbY.text, width: 50)
            InspectorField(title: "Color", placeholder: "64", text: $stage.f3kdbCbCr.text, width: 50)
        }
    }
}

/// Named deblock thresholds retain partial numeric drafts and legacy extra options.
struct DeblockThresholdControls: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: UI.rowSpacing) {
            InspectorRow(title: "Fine tuning") {
                Button("Reset") { text = "" }
            }
            HStack(spacing: 8) {
                ForEach(Array(["alpha", "beta", "gamma", "delta"].enumerated()), id: \.offset) { index, key in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(index + 1)").font(.callout).foregroundStyle(.secondary)
                        TextField(key == "alpha" ? "0.098" : "0.05", text: Binding(
                            get: { DeblockThresholds.value(key, in: text) },
                            set: { text = DeblockThresholds.replacing(key, with: $0, in: text) }),
                            prompt: Text(key == "alpha" ? "0.098" : "0.05"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Fine tuning \(index + 1)")
                    }
                }
            }
            .help("Detection thresholds from 0 to 1. Empty fields use the defaults.")
            if !DeblockThresholds.isValid(text) {
                InspectorNote("Use values from 0 to 1.", tint: .red)
            }
        }
    }
}
