import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct RestorationSecondSetPanel: View {
    @ObservedObject var settings: UpscaleSettings
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Restoration (Second Set)", systemImage: "wand.and.stars.inverse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.bottom, 4)
            GroupBox {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .padding(.vertical, 2)

                        // Denoise 2
                        HStack {
                            Toggle(isOn: $settings.useDenoise2) {
                                Text("Denoise")
                                    .font(.caption)
                                    .foregroundColor(settings.useDenoise2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.useDenoise2 {
                                Spacer()
                                Picker("", selection: $settings.denoiser2) {
                                    ForEach(settings.denoisers, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 70)
                                TextField("Str", text: $settings.denoiseStrength2)
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
                            Toggle(isOn: $settings.useDering2) {
                                Text("Deringing")
                                    .font(.caption)
                                    .foregroundColor(settings.useDering2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.useDering2 {
                                Spacer()
                                Toggle(isOn: $settings.deringActive2) {
                                    Text("On")
                                        .font(.system(size: 10))
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)

                                if settings.deringActive2 {
                                    TextField("0.5", text: $settings.deringStrength2)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 45)
                                }
                            } else {
                                Spacer()
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Sharpen 2
                        HStack {
                            Toggle(isOn: $settings.useSharpen2) {
                                Text("Sharpen")
                                    .font(.caption)
                                    .foregroundColor(settings.useSharpen2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.useSharpen2 {
                                Spacer()
                                Picker("", selection: $settings.sharpenMethod2) {
                                    ForEach(settings.sharpenMethods, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 90)
                            } else {
                                Spacer()
                            }
                        }

                        if settings.useSharpen2 {
                            if settings.sharpenMethod2 == "unsharp" {
                                HStack(spacing: 6) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("R")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("5", text: $settings.usmRadius2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("A")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("1.0", text: $settings.usmAmount2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("T")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("0.03", text: $settings.usmThreshold2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 40)
                                    }

                                    // Show effective values if attenuated
                                    if settings.isSharpenStacked {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("→")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                            Text("\(settings.effectiveUsmAmount2)")
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
                                    TextField("0.25", text: $settings.sharpenStrength2)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 50)

                                    // Show effective value if attenuated
                                    if settings.isSharpenStacked {
                                        Text("→\(settings.effectiveSharpenStrength2)")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.leading, 8)
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Deband 2
                        HStack {
                            Toggle(isOn: $settings.useDeband2) {
                                Text("Deband")
                                    .font(.caption)
                                    .foregroundColor(settings.useDeband2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.useDeband2 {
                                Spacer()
                                Picker("", selection: $settings.debandMethod2) {
                                    ForEach(settings.debandMethods, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 70)
                            } else {
                                Spacer()
                            }
                        }

                        if settings.useDeband2 {
                            if settings.debandMethod2 == "f3kdb" {
                                HStack(spacing: 6) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Range")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("15", text: $settings.f3kdbRange2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Y")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("64", text: $settings.f3kdbY2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("CbCr")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("64", text: $settings.f3kdbCbCr2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                }
                                .padding(.leading, 8)
                            } else {
                                HStack {
                                    Text("Strength")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("0.015", text: $settings.debandStrength2)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 55)
                                }
                                .padding(.leading, 8)
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Grain 2
                        HStack {
                            Toggle(isOn: $settings.useGrain2) {
                                Text("Grain")
                                    .font(.caption)
                                    .foregroundColor(settings.useGrain2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if settings.useGrain2 {
                                Spacer()
                                TextField("1.0", text: $settings.grainStrength2)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                            } else {
                                Spacer()
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Text("Second restoration pass")
                        .font(.subheadline)
                    // Filter stacking indicator
                    if settings.hasFilterStacking {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 10))
                            Text("Smart Attenuation")
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
        .disabled(settings.scaler == "coreml")
        .help("The second restoration pass is available only for FFmpeg")
    }
}
