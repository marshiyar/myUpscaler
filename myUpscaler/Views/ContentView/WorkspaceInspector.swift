import SwiftUI

/// The preview owns media state; this inspector edits the runner's existing settings.
struct WorkspaceInspector: View {
    @ObservedObject var runner: UpscaleRunner
    @ObservedObject var settings: UpscaleSettings
    @ObservedObject var presetStore: PresetStore
    let chooseOutputFolder: () -> Void
    enum Page: String, CaseIterable, Identifiable {
        case upscale = "Upscale", restore = "Restore", output = "Output"
        var id: Self { self }
    }
    @State private var page: Page = .upscale
    @State private var showEncoding = false
    @State private var showExtra = false

    init(runner: UpscaleRunner, settings: UpscaleSettings, presetStore: PresetStore,
         chooseOutputFolder: @escaping () -> Void, initialPage: Page = .upscale) {
        self.runner = runner
        self.settings = settings
        self.presetStore = presetStore
        self.chooseOutputFolder = chooseOutputFolder
        _page = State(initialValue: initialPage)
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
                    Section("Additional filters") {
                        DisclosureGroup("Deblock, deband and grain", isExpanded: $showExtra) {
                            Toggle("Deblock", isOn: enabled($settings.noDeblock)).disabled(settings.scaler == "coreml")
                            Toggle("Deband", isOn: enabled($settings.noDeband))
                            Toggle("Grain", isOn: enabled($settings.noGrain)).disabled(settings.scaler == "coreml")
                            RestorationPanel(settings: settings).disabled(settings.scaler == "coreml")
                            if settings.scaler == "coreml" {
                                Text("Core ML debanding uses its pipeline settings in Settings.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section { RestorationSecondSetPanel(settings: settings) }
                case .output:
                    Section { OutputPanel(outputMode: $runner.outputMode, customOutputFolder: $runner.customOutputFolder,
                                          predictedName: runner.inputPath.isEmpty ? "Choose a video first" : runner.predictedOutputName,
                                          chooseFolder: chooseOutputFolder) }
                    Section("Encoding") {
                        HardwareEncodingPanel(settings: settings)
                        DisclosureGroup("CPU HEVC parameters", isExpanded: $showEncoding) {
                            X265ParametersPanel(settings: settings)
                        }
                        .disabled(!settings.useHEVC || settings.encoder == "videotoolbox" || settings.scaler == "coreml")
                    }
                    Section("Presets") { SavedPresetsPanel(presetStore: presetStore, settings: settings, isProcessing: runner.isRunning) }
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
            Toggle("Denoise", isOn: enabled($settings.noDenoise))
            if !settings.noDenoise {
                Picker("Denoiser", selection: $settings.denoiser) {
                    ForEach(settings.denoisers, id: \.self) { Text($0).tag($0) }
                }.disabled(settings.scaler == "coreml")
                ParameterRow(title: "Strength", binding: $settings.denoiseStrength,
                             range: settings.denoiseStrengthRange, step: settings.denoiseStrengthStep,
                             defaultValue: settings.denoiseStrengthDefault, formatter: Formatters.twoFraction,
                             sliderAccessibility: "Primary denoise strength", gradient: .denoise)
            }
            Toggle("Deringing", isOn: $settings.deringActive).disabled(settings.scaler == "coreml")
            if settings.deringActive {
                ParameterRow(title: "Strength", binding: $settings.deringStrength, range: 0...10, step: 0.005,
                             defaultValue: 0.5, formatter: Formatters.twoFraction,
                             sliderAccessibility: "Primary deringing strength", gradient: .dering)
                    .disabled(settings.scaler == "coreml")
            }
            Toggle("Sharpen", isOn: enabled($settings.noSharpen))
            if !settings.noSharpen {
                Picker("Method", selection: $settings.sharpenMethod) {
                    Text("CAS").tag("cas"); Text("Unsharp mask").tag("unsharp")
                }
                if settings.sharpenMethod == "cas" {
                    ParameterRow(title: "Strength", binding: $settings.sharpenStrength,
                                 range: settings.sharpenStrengthRange, step: settings.sharpenStrengthStep,
                                 defaultValue: settings.sharpenStrengthDefault, formatter: Formatters.twoFraction,
                                 sliderAccessibility: "Primary sharpen strength", gradient: .sharpen)
                } else {
                    ParameterRow(title: "Matrix", binding: $settings.usmRadius, range: settings.usmRadiusRange,
                                 step: settings.usmRadiusStep, defaultValue: settings.usmRadiusDefault,
                                 formatter: Formatters.integer, sliderAccessibility: "Unsharp matrix size", gradient: .usmRadius)
                    ParameterRow(title: "Amount", binding: $settings.usmAmount, range: settings.usmAmountRange,
                                 step: settings.usmAmountStep, defaultValue: settings.usmAmountDefault,
                                 formatter: Formatters.twoFraction, sliderAccessibility: "Unsharp amount", gradient: .usmAmount)
                }
            }
        }
    }

    private var colorFilters: some View {
        Section("Color equalizer") {
            Toggle("Color equalizer", isOn: enabled($settings.noEq))
            if settings.scaler == "coreml" {
                Text("Preview only for Core ML; these colors are not applied to its export.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !settings.noEq {
                ParameterRow(title: "Contrast", binding: $settings.eqContrast, range: 0.5...2, step: 0.005,
                             defaultValue: 1, formatter: Formatters.twoFraction, sliderAccessibility: "Contrast", gradient: .contrast)
                ParameterRow(title: "Brightness", binding: $settings.eqBrightness, range: -0.1...0.1, step: 0.005,
                             defaultValue: 0, formatter: Formatters.threeFraction, sliderAccessibility: "Brightness", gradient: .brightness)
                ParameterRow(title: "Saturation", binding: $settings.eqSaturation, range: 0...2, step: 0.005,
                             defaultValue: 1, formatter: Formatters.twoFraction, sliderAccessibility: "Saturation", gradient: .saturation)
            }
        }
    }
}

