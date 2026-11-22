import SwiftUI

/// The preview owns media state; this inspector edits the runner's existing settings.
struct WorkspaceInspector: View {
    @ObservedObject var runner: UpscaleRunner
    @ObservedObject var settings: UpscaleSettings
    @ObservedObject var presetStore: PresetStore
    let chooseOutputFolder: () -> Void
    enum Page: String, CaseIterable, Identifiable {
        case upscale = "Upscale", restore = "Restore", processor = "Cleanup", output = "Output"
        var id: Self { self }
    }
    @State private var page: Page = .upscale
    @State private var showExtra = false
    private let finishingInitiallyExpanded: Bool

    init(runner: UpscaleRunner, settings: UpscaleSettings, presetStore: PresetStore,
         chooseOutputFolder: @escaping () -> Void, initialPage: Page = .upscale,
         extraInitiallyExpanded: Bool = false, finishingInitiallyExpanded: Bool = false) {
        self.runner = runner
        self.settings = settings
        self.presetStore = presetStore
        self.chooseOutputFolder = chooseOutputFolder
        _page = State(initialValue: initialPage)
        _showExtra = State(initialValue: extraInitiallyExpanded)
        self.finishingInitiallyExpanded = finishingInitiallyExpanded
    }

    private func enabled(_ disabled: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { !disabled.wrappedValue }, set: { disabled.wrappedValue = !$0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Adjustments", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch page {
                    case .upscale:
                        AIEnginePanel(settings: settings)
                        Divider()
                        QualityScalePanel(settings: settings)
                    case .restore:
                        primaryFilters
                        Divider()
                        colorFilters
                        Divider()
                        RestorationSecondSetPanel(settings: settings, initiallyExpanded: finishingInitiallyExpanded)
                    case .processor:
                        RestorationPanel(settings: settings)
                        Divider()
                        InspectorSection {
                            InspectorSwitch(title: "Remove near-duplicate frames", isOn: enabled($settings.modes.noDecimate),
                                            enabled: settings.upscaling.scaler != "coreml")
                                .help("Removes frames that repeat.")
                        }
                        Divider()
                        Button("Reset processing settings") {
                            settings.resetToDefaults()
                        }
                        .help("Reset all processing settings to their defaults")
                    case .output:
                        OutputPanel(outputMode: $runner.outputMode, customOutputFolder: $runner.customOutputFolder,
                                    predictedName: runner.inputPath.isEmpty ? "Choose a video first" : runner.predictedOutputName,
                                    chooseFolder: chooseOutputFolder)
                        Divider()
                        HardwareEncodingPanel(settings: settings)
                        Divider()
                        SavedPresetsPanel(presetStore: presetStore, settings: settings, isProcessing: runner.isRunning)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120)
            .disabled(runner.isRunning)
        }
    }

    private var primaryFilters: some View {
        InspectorSection(title: "Restore") {
            InspectorRow(title: "Reduce noise") {
                Picker("Reduce noise", selection: $settings.primary.denoiserChoice) {
                    Text("Off").tag("off")
                    ForEach(DisplayName.orderedDenoisers(settings.denoisers), id: \.self) {
                        Text(DisplayName.denoiser($0)).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            if settings.primary.useDenoise {
                ParameterRow(title: "Strength", binding: $settings.primary.denoiseStrength.text,
                             range: settings.denoiseStrengthRange, step: settings.denoiseStrengthStep,
                             defaultValue: settings.denoiseStrengthDefault, formatter: Formatters.twoFraction,
                             sliderAccessibility: "Reduce noise strength", gradient: .denoise)
            }
            ParameterRow(title: "Remove halos", binding: $settings.primary.deringAmount, range: 0...10, step: 0.005,
                         defaultValue: 0.5, formatter: Formatters.twoFraction,
                         sliderAccessibility: "Remove halos", gradient: .dering)
                .disabled(settings.upscaling.scaler == "coreml")
            InspectorSwitch(title: "Sharpen", isOn: $settings.primary.useSharpen)
            if settings.primary.useSharpen {
                InspectorRow(title: "Style") {
                    Picker("Style", selection: $settings.primary.sharpenMethod) {
                        Text("Adaptive").tag("cas"); Text("Classic").tag("unsharp")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if settings.primary.sharpenMethod == "cas" {
                    ParameterRow(title: "Strength", binding: $settings.primary.sharpenStrength.text,
                                 range: settings.sharpenStrengthRange, step: settings.sharpenStrengthStep,
                                 defaultValue: settings.sharpenStrengthDefault, formatter: Formatters.twoFraction,
                                 sliderAccessibility: "Sharpen strength", gradient: .sharpen)
                } else {
                    ParameterRow(title: "Radius", binding: $settings.primary.usmRadius.text, range: settings.usmRadiusRange,
                                 step: settings.usmRadiusStep, defaultValue: settings.usmRadiusDefault,
                                 formatter: Formatters.integer, sliderAccessibility: "Sharpen radius", gradient: .usmRadius)
                    ParameterRow(title: "Amount", binding: $settings.primary.usmAmount.text, range: settings.usmAmountRange,
                                 step: settings.usmAmountStep, defaultValue: settings.usmAmountDefault,
                                 formatter: Formatters.twoFraction, sliderAccessibility: "Sharpen amount", gradient: .usmAmount)
                }
            }
        }
    }

    private var colorFilters: some View {
        InspectorSection {
            InspectorSwitch(title: "Color", isOn: enabled($settings.color.noEq))
            if settings.upscaling.scaler == "coreml" {
                InspectorNote("Preview only")
            }
            if !settings.color.noEq {
                ParameterRow(title: "Contrast", binding: $settings.color.eqContrast.text, range: 0.5...2, step: 0.005,
                             defaultValue: 1, formatter: Formatters.twoFraction, sliderAccessibility: "Contrast", gradient: .contrast)
                ParameterRow(title: "Brightness", binding: $settings.color.eqBrightness.text, range: -0.1...0.1, step: 0.005,
                             defaultValue: 0, formatter: Formatters.threeFraction, sliderAccessibility: "Brightness", gradient: .brightness)
                ParameterRow(title: "Saturation", binding: $settings.color.eqSaturation.text, range: 0...2, step: 0.005,
                             defaultValue: 1, formatter: Formatters.twoFraction, sliderAccessibility: "Saturation", gradient: .saturation)
            }
        }
    }
}
