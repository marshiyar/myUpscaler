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

                        Text(settings.upscaling.scaler == "coreml" ? "These filters are unavailable for Core ML export." : "Optional filters after scaling and the primary sharpen/deband filters. Each switch works independently of the primary filters. Grain here replaces primary grain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("When the same filter is enabled in both sets, fixed multipliers reduce finishing strength. This does not analyze the image or guarantee better quality. Auto denoise is unchanged.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Denoise 2
                        HStack {
                            Toggle(isOn: $settings.secondary.useDenoise) {
                                Text("Denoise")
                                    .font(.caption)
                                    .foregroundColor(settings.secondary.useDenoise ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.secondary.useDenoise {
                                Spacer()
                                Picker("", selection: $settings.secondary.denoiser) {
                                    ForEach(settings.denoisers, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 70)
                                TextField("Str", text: $settings.secondary.denoiseStrength.text)
                                    .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)

                                // Show effective value if attenuated
                                if settings.isDenoiseStacked {
                                    Text("→\(settings.effectiveDenoiseStrength2)")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            } else {
                                Spacer()
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Deringing 2
                        HStack {
                            Toggle(isOn: $settings.secondary.useDering) {
                                Text("Deringing")
                                    .font(.caption)
                                    .foregroundColor(settings.secondary.useDering ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.secondary.useDering {
                                Spacer()
                                TextField("Strength", text: $settings.secondary.deringStrength.text)
                                    .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            } else {
                                Spacer()
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Sharpen 2
                        HStack {
                            Toggle(isOn: $settings.secondary.useSharpen) {
                                Text("Sharpen")
                                    .font(.caption)
                                    .foregroundColor(settings.secondary.useSharpen ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.secondary.useSharpen {
                                Spacer()
                                Picker("", selection: $settings.secondary.sharpenMethod) {
                                    ForEach(settings.sharpenMethods, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 90)
                            } else {
                                Spacer()
                            }
                        }

                        if settings.secondary.useSharpen {
                            RestorationSharpenControls(stage: $settings.secondary, settings: settings,
                                                       presentation: .compact,
                                                       effectiveStrength: settings.isSharpenStacked ? settings.effectiveSharpenStrength2 : nil,
                                                       effectiveAmount: settings.isSharpenStacked ? settings.effectiveUsmAmount2 : nil)

                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Deband 2
                        HStack {
                            Toggle(isOn: $settings.secondary.useDeband) {
                                Text("Deband")
                                    .font(.caption)
                                    .foregroundColor(settings.secondary.useDeband ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.secondary.useDeband {
                                Spacer()
                                Picker("", selection: $settings.secondary.debandMethod) {
                                    ForEach(settings.debandMethods, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 70)
                            } else {
                                Spacer()
                            }
                        }

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
                                    if settings.isDebandStacked {
                                        Text("→\(settings.effectiveDebandStrength2)")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .padding(.leading, 8)
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Grain 2
                        HStack {
                            Toggle(isOn: $settings.secondary.useGrain) {
                                Text("Grain")
                                    .font(.caption)
                                    .foregroundColor(settings.secondary.useGrain ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.secondary.useGrain {
                                Spacer()
                                TextField("1.0", text: $settings.secondary.grainStrength.text)
                                    .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                            } else {
                                Spacer()
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Finishing filters (FFmpeg)", systemImage: "wand.and.stars.inverse")
                        .font(.subheadline)
                    // Filter stacking indicator
                    if settings.hasFilterStacking {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 10))
                            Text("Fixed strength reduction")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange.opacity(0.15))
                        )
                    }
                }
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .cardStyle()
        }
        .disabled(settings.upscaling.scaler == "coreml")
        .help("The second restoration pass is available only for FFmpeg")
    }
}
