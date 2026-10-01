import SwiftUI
import Combine

/// Both passes edit their own stage; presentation and annotations are view concerns.
struct RestorationSharpenControls: View {
    enum Presentation { case sliders, compact }
    @Binding var stage: RestorationStage
    @ObservedObject var settings: UpscaleSettings
    var presentation: Presentation
    var effectiveStrength: String? = nil
    var effectiveAmount: String? = nil

    var body: some View {
        switch presentation {
        case .sliders:
            if stage.sharpenMethod == "cas" {
                ParameterRow(title: "CAS Strength",
                             binding: $stage.sharpenStrength.text,
                             range: settings.sharpenStrengthRange,
                             step: settings.sharpenStrengthStep,
                             defaultValue: settings.sharpenStrengthDefault,
                             formatter: Formatters.twoFraction,
                             sliderAccessibility: "CAS sharpen strength slider",
                             gradient: .sharpen)
                { _ in settings.objectWillChange.send() }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ParameterRow(title: "Radius",
                                 binding: $stage.usmRadius.text,
                                 range: settings.usmRadiusRange,
                                 step: settings.usmRadiusStep,
                                 defaultValue: settings.usmRadiusDefault,
                                 formatter: Formatters.integer,
                                 sliderAccessibility: "Unsharp mask radius slider",
                                 gradient: .usmRadius)
                    { _ in settings.objectWillChange.send() }

                    ParameterRow(title: "Amount",
                                 binding: $stage.usmAmount.text,
                                 range: settings.usmAmountRange,
                                 step: settings.usmAmountStep,
                                 defaultValue: settings.usmAmountDefault,
                                 formatter: Formatters.twoFraction,
                                 sliderAccessibility: "Unsharp mask amount slider",
                                 gradient: .usmAmount)
                    { _ in settings.objectWillChange.send() }

                    ParameterRow(title: "Threshold",
                                 binding: $stage.usmThreshold.text,
                                 range: settings.usmThresholdRange,
                                 step: settings.usmThresholdStep,
                                 defaultValue: settings.usmThresholdDefault,
                                 formatter: Formatters.threeFraction,
                                 sliderAccessibility: "Unsharp mask threshold slider",
                                 gradient: .usmThreshold)
                    { _ in settings.objectWillChange.send() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                .animation(.easeInOut(duration: 0.5), value: stage.useDering)
            }
        case .compact:
            if stage.sharpenMethod == "unsharp" {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Matrix")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("5", text: $stage.usmRadius.text)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 35)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Amount")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("1.0", text: $stage.usmAmount.text)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 35)
                    }
                    // Show effective values if attenuated
                    if let effectiveAmount {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("→")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("\(effectiveAmount)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.leading, 8)
            } else {
                HStack {
                    Text("CAS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0.25", text: $stage.sharpenStrength.text)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)

                    // Show effective value if attenuated
                    if let effectiveStrength {
                        Text("→\(effectiveStrength)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.leading, 8)
            }
        }
    }
}

struct RestorationF3KDBControls: View {
    @Binding var stage: RestorationStage
    var compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            field("Range", placeholder: "15", text: $stage.f3kdbRange.text)
            field("Y", placeholder: "64", text: $stage.f3kdbY.text)
            field("CbCr", placeholder: "64", text: $stage.f3kdbCbCr.text)
        }
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(compact ? .caption : .system(size: 10))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: compact ? 35 : 40)
        }
    }
}
