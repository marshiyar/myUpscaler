import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct RestorationFiltersPanel: View {
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: UI.rowSpacing) {
            HStack {
                Label("Restoration Filters", systemImage: "wand.and.stars")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)

            GroupBox {
                VStack(spacing: UI.rowSpacing) {
                    ParameterRow(title: "Denoise Strength",
                                 binding: $settings.primary.denoiseStrength.text,
                                 range: settings.denoiseStrengthRange,
                                 step: settings.denoiseStrengthStep,
                                 defaultValue: settings.denoiseStrengthDefault,
                                 formatter: Formatters.oneFraction,
                                 sliderAccessibility: "Denoise strength slider",
                                 gradient: .denoise)
                    { _ in settings.objectWillChange.send() }

                    Divider()

                    // Deringing toggle + strength
                    Toggle(isOn: $settings.primary.useDering) {
                        Text("Deringing")
                            .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)  // Add vertical padding

                    if settings.primary.useDering {
                        ParameterRow(title: "Strength",
                                     binding: $settings.primary.deringStrength.text,
                                     range: 0...10,
                                     step: 0.005,
                                     defaultValue: 0.5,
                                     formatter: Formatters.twoFraction,
                                     sliderAccessibility: "Deringing strength slider",
                                     gradient: .dering)
                        { _ in settings.objectWillChange.send() }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .padding(.top, 8)
                            .animation(.easeInOut(duration: 0.2), value: settings.primary.useDering)
                    }

                    Divider()

                    // Sharpen
                    Picker("Method", selection: $settings.primary.sharpenMethod) {
                        Text("CAS").tag("cas")
                        Text("Unsharp Mask").tag("unsharp")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 160)

                    RestorationSharpenControls(stage: $settings.primary, settings: settings, presentation: .sliders)

                }
                .padding(.top, 16)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .cardStyle()
        }
    }
}

struct RestorationPanel: View {
    @Environment(\.workspaceInspector) private var inInspector
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !inInspector { HStack {
                Label("Restoration Filters (Extra)", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2) }

            GroupBox {
                VStack(spacing: 8) {
                    // Deblock Mode
                    HStack {
                        Text("Deblock")
                            .font(.caption)
                            .disabled(settings.upscaling.scaler == "coreml")
                        Spacer()
                        Picker("", selection: $settings.additionalDeblockMode) {
                            Text("Off").tag("off")
                            ForEach(settings.deblockModes, id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 110)
                        .accessibilityLabel("Primary deblock mode")
                        .disabled(settings.upscaling.scaler == "coreml")

                    }

                    if settings.primary.useDeblock {
                        DeblockThresholdControls(text: $settings.primary.deblockThresh.text)
                            .disabled(settings.upscaling.scaler == "coreml")
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Deband
                    HStack {
                        Text("Deband")
                            .font(.caption)
                        Spacer()
                        if settings.upscaling.scaler == "coreml" {
                            Text("Gradient-aware smoothing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("", selection: Binding(get: {
                                settings.additionalDebandMethod == "f3kdb" ? "deband" : settings.additionalDebandMethod
                            }, set: { method in
                                if method != "deband" || settings.primary.debandMethod != "f3kdb" {
                                    settings.additionalDebandMethod = method
                                } else {
                                    settings.primary.useDeband = true
                                }
                            })) {
                                Text("Off").tag("off")
                                Text("Deband").tag("deband")
                                Text("Gradfun").tag("gradfun")
                                Text("Neo F3kdb (CPU)").tag("neo_f3kdb")
                                    .disabled(!UpscaleSettings.neoF3kdbAvailable)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 200)
                        .accessibilityLabel("Primary deband method")
                        .disabled(settings.upscaling.scaler == "coreml")
                        }
                    }

                    if ["f3kdb", "neo_f3kdb"].contains(settings.primary.debandMethod) && settings.upscaling.scaler != "coreml" {
                        RestorationF3KDBControls(stage: $settings.additionalF3KDBStage, compact: false)
                            .help("Neo F3kdb: integer range 0–255, thresholds 0–511. Native CPU export only; preview omits this stage. Legacy presets keep the earlier FFmpeg mapping.")
                            .padding(.leading, 8)
                            .disabled(settings.upscaling.scaler == "coreml")
                    } else {
                        HStack {
                            Text("Strength")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("0.015", text: $settings.additionalDebandAmount)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 55)
                        }
                        .padding(.leading, 8)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Grain Strength
                    HStack {
                        Text("Grain")
                            .font(.caption)
                            .disabled(settings.upscaling.scaler == "coreml")
                        Spacer()
                        TextField("1.0", text: $settings.additionalGrainAmount)
                            .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                            .accessibilityLabel("Primary grain strength")
                            .disabled(settings.upscaling.scaler == "coreml")
                    }

                    Divider()
                        .padding(.vertical, 2)
                }
                .padding(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}
