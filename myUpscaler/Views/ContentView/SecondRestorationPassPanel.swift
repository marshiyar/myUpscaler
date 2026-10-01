import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct RestorationSecondSetPanel: View {
    @ObservedObject var settings: UpscaleSettings
    @State private var isExpanded: Bool = false

    init(settings: UpscaleSettings, initiallyExpanded: Bool = false) {
        self.settings = settings
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.upscaling.scaler == "coreml" {
                Text("Unavailable for Core ML export")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GroupBox {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .padding(.vertical, 2)

                        // Denoise 2
                        HStack {
                            Text("Denoise").font(.caption)
                            Spacer()
                            Picker("", selection: $settings.secondary.denoiserChoice) {
                                Text("Off").tag("off")
                                ForEach(settings.denoisers, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 100)
                            if settings.secondary.useDenoise {
                                TextField("Str", text: $settings.secondary.denoiseStrength.text)
                                    .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)

                            } else {
                                Spacer()
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        ParameterRow(title: "Deringing", binding: $settings.secondary.deringAmount, range: 0...10, step: 0.005,
                                     defaultValue: 0.5, formatter: Formatters.twoFraction,
                                     sliderAccessibility: "Finishing deringing", gradient: .dering)

                        Divider()
                            .padding(.vertical, 2)

                        // Sharpen 2
                        VStack(alignment: .leading) {
                            Toggle(isOn: $settings.secondary.useSharpen) {
                                Text("Sharpen")
                                    .font(.caption)
                                    .foregroundColor(settings.secondary.useSharpen ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.secondary.useSharpen {
                                Picker("", selection: $settings.secondary.sharpenMethod) {
                                    ForEach(settings.sharpenMethods, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 90)
                            }
                        }

                        if settings.secondary.useSharpen {
                            RestorationSharpenControls(stage: $settings.secondary, settings: settings,
                                                       presentation: .compact)

                        }

                        Divider()
                            .padding(.vertical, 2)

                        Picker("Deband", selection: $settings.secondary.debandChoice) {
                            Text("Off").tag("off")
                            Text("Deband").tag("deband")
                            Text("Gradfun").tag("gradfun")
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)

                        if settings.secondary.useDeband {
                            if settings.secondary.debandMethod == "f3kdb" {
                                RestorationF3KDBControls(stage: $settings.secondary, compact: true)
                                    .padding(.leading, 8)
                            } else {
                                HStack {
                                    Text("Strength")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("0.015", text: $settings.secondary.debandStrength.text)
                                        .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                        .frame(width: 55)
                                }
                                .padding(.leading, 8)
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Grain 2
                        VStack(alignment: .leading) {
                            Toggle(isOn: $settings.secondary.useGrain) {
                                Text("Grain")
                                    .font(.caption)
                                    .foregroundColor(settings.secondary.useGrain ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.secondary.useGrain {
                                TextField("1.0", text: $settings.secondary.grainStrength.text)
                                    .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Finishing filters (FFmpeg)", systemImage: "wand.and.stars.inverse")
                        .font(.subheadline)
                }
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .cardStyle()
        }
        .disabled(settings.upscaling.scaler == "coreml")
        .help("The second restoration pass is available only for FFmpeg")
    }
}
