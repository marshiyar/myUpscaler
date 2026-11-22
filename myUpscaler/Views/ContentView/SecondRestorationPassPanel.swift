import SwiftUI

struct RestorationSecondSetPanel: View {
    @ObservedObject var settings: UpscaleSettings
    @State private var isExpanded: Bool = false

    init(settings: UpscaleSettings, initiallyExpanded: Bool = false) {
        self.settings = settings
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var aiUpscaling: Bool { settings.upscaling.scaler == "coreml" }

    var body: some View {
        VStack(alignment: .leading, spacing: UI.rowSpacing) {
            if aiUpscaling {
                InspectorNote("Not available with AI upscaling")
            }
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: UI.rowSpacing) {
                    InspectorRow(title: "Reduce noise") {
                        HStack(spacing: 8) {
                            Picker("Reduce noise", selection: $settings.secondary.denoiserChoice) {
                                Text("Off").tag("off")
                                ForEach(DisplayName.orderedDenoisers(settings.denoisers), id: \.self) {
                                    Text(DisplayName.denoiser($0)).tag($0)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                            if settings.secondary.useDenoise {
                                TextField("Strength", text: $settings.secondary.denoiseStrength.text)
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 50)
                                    .accessibilityLabel("Reduce noise strength")
                            }
                        }
                    }

                    ParameterRow(title: "Remove halos", binding: $settings.secondary.deringAmount, range: 0...10, step: 0.005,
                                 defaultValue: 0.5, formatter: Formatters.twoFraction,
                                 sliderAccessibility: "Remove halos", gradient: .dering)

                    InspectorSwitch(title: "Sharpen", isOn: $settings.secondary.useSharpen)
                    if settings.secondary.useSharpen {
                        InspectorRow(title: "Style") {
                            Picker("Style", selection: $settings.secondary.sharpenMethod) {
                                ForEach(settings.sharpenMethods, id: \.self) { Text(DisplayName.sharpenMethod($0)) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                        RestorationSharpenControls(stage: $settings.secondary, settings: settings,
                                                   presentation: .compact)
                    }

                    InspectorRow(title: "Remove banding") {
                        Picker("Remove banding", selection: $settings.secondary.debandChoice) {
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
                    if settings.secondary.useDeband {
                        if ["f3kdb", "neo_f3kdb"].contains(settings.secondary.debandMethod) {
                            RestorationF3KDBControls(stage: $settings.secondary)
                        } else {
                            InspectorField(title: "Strength", placeholder: "0.015",
                                           text: $settings.secondary.debandStrength.text, width: 55)
                        }
                    }

                    InspectorSwitch(title: "Grain", isOn: $settings.secondary.useGrain)
                    if settings.secondary.useGrain {
                        InspectorField(title: "Strength", placeholder: "1.0",
                                       text: $settings.secondary.grainStrength.text, width: 50)
                    }
                }
                .padding(.top, UI.rowSpacing)
            } label: {
                Text("Finishing")
                    .font(.headline)
            }
        }
        .disabled(aiUpscaling)
        .help("Runs after upscaling. Available with Standard.")
    }
}
