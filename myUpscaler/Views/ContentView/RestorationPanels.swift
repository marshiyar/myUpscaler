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
                                 binding: $settings.denoiseStrength,
                                 range: settings.denoiseStrengthRange,
                                 step: settings.denoiseStrengthStep,
                                 defaultValue: settings.denoiseStrengthDefault,
                                 formatter: Formatters.oneFraction,
                                 sliderAccessibility: "Denoise strength slider",
                                 gradient: .denoise)
                    { _ in settings.objectWillChange.send() }

                    Divider()

                    // Deringing toggle + strength
                    Toggle(isOn: $settings.deringActive) {
                        Text("Deringing")
                            .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)  // Add vertical padding

                    if settings.deringActive {
                        ParameterRow(title: "Strength",
                                     binding: $settings.deringStrength,
                                     range: 0...10,
                                     step: 0.005,
                                     defaultValue: 0.5,
                                     formatter: Formatters.twoFraction,
                                     sliderAccessibility: "Deringing strength slider",
                                     gradient: .dering)
                        { _ in settings.objectWillChange.send() }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .padding(.top, 8)
                            .animation(.easeInOut(duration: 0.2), value: settings.deringActive)
                    }

                    Divider()

                    // Sharpen
                    Picker("Method", selection: $settings.sharpenMethod) {
                        Text("CAS").tag("cas")
                        Text("Unsharp Mask").tag("unsharp")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 160)

                    if settings.sharpenMethod == "cas" {
                        ParameterRow(title: "CAS Strength",
                                     binding: $settings.sharpenStrength,
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
                                         binding: $settings.usmRadius,
                                         range: settings.usmRadiusRange,
                                         step: settings.usmRadiusStep,
                                         defaultValue: settings.usmRadiusDefault,
                                         formatter: Formatters.integer,
                                         sliderAccessibility: "Unsharp mask radius slider",
                                         gradient: .usmRadius)
                            { _ in settings.objectWillChange.send() }

                            ParameterRow(title: "Amount",
                                         binding: $settings.usmAmount,
                                         range: settings.usmAmountRange,
                                         step: settings.usmAmountStep,
                                         defaultValue: settings.usmAmountDefault,
                                         formatter: Formatters.twoFraction,
                                         sliderAccessibility: "Unsharp mask amount slider",
                                         gradient: .usmAmount)
                            { _ in settings.objectWillChange.send() }

                            ParameterRow(title: "Threshold",
                                         binding: $settings.usmThreshold,
                                         range: settings.usmThresholdRange,
                                         step: settings.usmThresholdStep,
                                         defaultValue: settings.usmThresholdDefault,
                                         formatter: Formatters.threeFraction,
                                         sliderAccessibility: "Unsharp mask threshold slider",
                                         gradient: .usmThreshold)
                            { _ in settings.objectWillChange.send() }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        .animation(.easeInOut(duration: 0.5), value: settings.deringActive)  // Animate changes
                    }
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
                        Picker("", selection: $settings.deblockMode) {
                            ForEach(settings.deblockModes, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 80)
                        TextField("Thresh", text: $settings.deblockThresh)
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
                        Picker("", selection: $settings.debandMethod) {
                            ForEach(settings.debandMethods, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 80)
                    }

                    if settings.debandMethod == "f3kdb" {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Range")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    TextField("15", text: $settings.f3kdbRange)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 40)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Y")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    TextField("64", text: $settings.f3kdbY)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 40)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("CbCr")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    TextField("64", text: $settings.f3kdbCbCr)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 40)
                                }
                            }
                        }
                        .padding(.leading, 8)
                    } else {
                        HStack {
                            Text("Strength")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("0.015", text: $settings.debandStrength)
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
                        TextField("1.0", text: $settings.grainStrength)
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
