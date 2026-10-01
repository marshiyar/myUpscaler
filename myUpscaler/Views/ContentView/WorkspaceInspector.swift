import SwiftUI

/// The preview owns media state; this inspector edits the runner's existing settings.
struct WorkspaceInspector: View {
    @ObservedObject var runner: UpscaleRunner
    @ObservedObject var settings: UpscaleSettings
    @ObservedObject var presetStore: PresetStore
    let chooseOutputFolder: () -> Void
    enum Page: String, CaseIterable, Identifiable {
        case upscale = "Upscale", restore = "Restore", processor = "Processor", output = "Output"
        var id: Self { self }
    }
    @State private var page: Page = .upscale
    @State private var showEncoding = false
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
            Form {
                switch page {
                case .upscale:
                    Section { AIEnginePanel(settings: settings) }
                    Section { QualityScalePanel(settings: settings) }
                case .restore:
                    primaryFilters
                    colorFilters
                    Section { RestorationSecondSetPanel(settings: settings, initiallyExpanded: finishingInitiallyExpanded) }
                case .processor:
                    Section { RestorationPanel(settings: settings) }
                    Section {
                        Toggle("Remove near-duplicate frames", isOn: enabled($settings.modes.noDecimate))
                            .disabled(settings.upscaling.scaler == "coreml")
                            .help("FFmpeg Decimate removes near-duplicate frames before output frame-rate conversion.")
                    }
                    Section {
                        Button {
                            settings.resetToDefaults()
                        } label: {
                            Label("Reset processing settings", systemImage: "arrow.counterclockwise")
                        }
                        .help("Reset all processing settings to their defaults")
                    }
                case .output:
                    Section { OutputPanel(outputMode: $runner.outputMode, customOutputFolder: $runner.customOutputFolder,
                                          predictedName: runner.inputPath.isEmpty ? "Choose a video first" : runner.predictedOutputName,
                                          chooseFolder: chooseOutputFolder) }
                    Section {
                        HardwareEncodingPanel(settings: settings)
                        DisclosureGroup("CPU HEVC parameters", isExpanded: $showEncoding) {
                            X265ParametersPanel(settings: settings)
                        }
                        .disabled(!settings.codec.useHEVC || settings.hardware.encoder == "videotoolbox" || settings.upscaling.scaler == "coreml")
                    }
                    Section { SavedPresetsPanel(presetStore: presetStore, settings: settings, isProcessing: runner.isRunning) }
                }
            }
            .formStyle(.grouped)
            .disabled(runner.isRunning)
            .environment(\.workspaceInspector, true)
        }
        .background(Color.appBackground)
    }

    private var primaryFilters: some View {
        Section("Primary restoration") {
            Toggle("Denoise", isOn: $settings.primary.useDenoise)
            if settings.primary.useDenoise {
                Picker("Denoiser", selection: $settings.primary.denoiser) {
                    ForEach(settings.denoisers, id: \.self) { Text($0).tag($0) }
                }.disabled(settings.upscaling.scaler == "coreml")
                ParameterRow(title: "Strength", binding: $settings.primary.denoiseStrength.text,
                             range: settings.denoiseStrengthRange, step: settings.denoiseStrengthStep,
                             defaultValue: settings.denoiseStrengthDefault, formatter: Formatters.twoFraction,
                             sliderAccessibility: "Primary denoise strength", gradient: .denoise)
            }
            Toggle("Deringing", isOn: $settings.primary.useDering).disabled(settings.upscaling.scaler == "coreml")
            if settings.primary.useDering {
                ParameterRow(title: "Strength", binding: $settings.primary.deringStrength.text, range: 0...10, step: 0.005,
                             defaultValue: 0.5, formatter: Formatters.twoFraction,
                             sliderAccessibility: "Primary deringing strength", gradient: .dering)
                    .disabled(settings.upscaling.scaler == "coreml")
            }
            Toggle("Sharpen", isOn: $settings.primary.useSharpen)
            if settings.primary.useSharpen {
                Picker("Method", selection: $settings.primary.sharpenMethod) {
                    Text("CAS").tag("cas"); Text("Unsharp mask").tag("unsharp")
                }
                if settings.primary.sharpenMethod == "cas" {
                    ParameterRow(title: "Strength", binding: $settings.primary.sharpenStrength.text,
                                 range: settings.sharpenStrengthRange, step: settings.sharpenStrengthStep,
                                 defaultValue: settings.sharpenStrengthDefault, formatter: Formatters.twoFraction,
                                 sliderAccessibility: "Primary sharpen strength", gradient: .sharpen)
                } else {
                    ParameterRow(title: "Matrix", binding: $settings.primary.usmRadius.text, range: settings.usmRadiusRange,
                                 step: settings.usmRadiusStep, defaultValue: settings.usmRadiusDefault,
                                 formatter: Formatters.integer, sliderAccessibility: "Unsharp matrix size", gradient: .usmRadius)
                    ParameterRow(title: "Amount", binding: $settings.primary.usmAmount.text, range: settings.usmAmountRange,
                                 step: settings.usmAmountStep, defaultValue: settings.usmAmountDefault,
                                 formatter: Formatters.twoFraction, sliderAccessibility: "Unsharp amount", gradient: .usmAmount)
                }
            }
        }
    }

    private var colorFilters: some View {
        Section {
            Toggle("Color equalizer", isOn: enabled($settings.color.noEq))
            if settings.upscaling.scaler == "coreml" {
                Text("Preview only")
                    .font(.caption).foregroundStyle(.secondary)
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
