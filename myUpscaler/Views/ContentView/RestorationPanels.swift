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
            .cardStyle()
        }
    }
}

struct RestorationPanel: View {
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Restoration Filters (Extra)", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)

            GroupBox {
                VStack(spacing: 8) {
                    // Deblock Mode
                    HStack {
                        Text("Deblock Mode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.primary.deblockMode) {
                            ForEach(settings.deblockModes, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 80)
                        TextField("Thresh", text: $settings.primary.deblockThresh.text)
                            .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Deband
                    HStack {
                        Text("Deband")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.primary.debandMethod) {
                            ForEach(settings.debandMethods, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 80)
                    }

                    if settings.primary.debandMethod == "f3kdb" {
                        RestorationF3KDBControls(stage: $settings.primary, compact: false)
                            .padding(.leading, 8)
                    } else {
                        HStack {
                            Text("Strength")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("0.015", text: $settings.primary.debandStrength.text)
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
                        Text("Grain Strength")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("1.0", text: $settings.primary.grainStrength.text)
                            .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                    }

                    Divider()
                        .padding(.vertical, 2)
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}
