import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

private enum CompactSliderGradient {
    case denoise
    case dering
    case sharpen
    case contrast
    case brightness
    case saturation
    case usmRadius
    case usmAmount
    case usmThreshold


}

private struct CompactSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let gradient: CompactSliderGradient
    var onEditingChanged: ((Bool) -> Void)? = nil
    @State private var isEditing = false

    var body: some View {
        Slider(value: Binding(get: { value }, set: { next in
            value = next
            // Keyboard and accessibility adjustments also commit, without a drag.
            if !isEditing { onEditingChanged?(false) }
        }), in: range, step: step, onEditingChanged: { editing in
            isEditing = editing
            onEditingChanged?(editing)
        })
        .controlSize(.small)
    }
}

struct VerticalColorEqualizerPanel: View {
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label("Color Equalizer", systemImage: "paintpalette.fill")
                .font(DesignSystem.Typography.caption1)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            if settings.upscaling.scaler == "coreml" || settings.color.noEq {
                Text(settings.color.noEq ? "Color EQ is off" : "Preview only for Core ML")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    VerticalParameterRow(
                        title: "Contrast",
                        binding: $settings.color.eqContrast.text,
                        range: 0.5...2.0,
                        step: 0.005,
                        defaultValue: 1.0,
                        formatter: Formatters.twoFraction,
                        gradient: .contrast
                    )

                    VerticalParameterRow(
                        title: "Brightness",
                        binding: $settings.color.eqBrightness.text,
                        range: -0.1...0.1,
                        step: 0.005,
                        defaultValue: 0.0,
                        formatter: Formatters.threeFraction,
                        gradient: .brightness
                    )

                    VerticalParameterRow(
                        title: "Saturation",
                        binding: $settings.color.eqSaturation.text,
                        range: 0...2,
                        step: 0.005,
                        defaultValue: 1.0,
                        formatter: Formatters.twoFraction,
                        gradient: .saturation
                    )
                }
                .padding(6)
            }
            .disabled(settings.color.noEq)
            .background(Color(nsColor: NSColor.windowBackgroundColor))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        }
        .frame(width: 140)
    }
}

private struct VerticalParameterRow: View {
    let title: String
    @Binding var binding: String
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    let formatter: NumberFormatter
    let gradient: CompactSliderGradient

    // Local state to track dragging without triggering global updates
    @State private var localValue: Double? = nil

    private var displayValue: Double {
        localValue ?? Double(binding) ?? defaultValue
    }

    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { displayValue },
            set: { localValue = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack {
                Text(title)
                    .font(DesignSystem.Typography.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatter.string(from: NSNumber(value: displayValue)) ?? "")
                    .font(DesignSystem.Typography.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 48, alignment: .trailing)
            }

            HStack(spacing: DesignSystem.Spacing.xs) {
                CompactSlider(value: sliderBinding, range: range, step: step, gradient: gradient, onEditingChanged: { editing in
                    if !editing {
                        // Commit changes only when dragging ends
                        if let finalValue = localValue {
                            binding = formatter.string(from: NSNumber(value: finalValue)) ?? "\(finalValue)"
                            localValue = nil
                        }
                    }
                })
                .accessibilityLabel(title)

                Button {
                    binding = formatter.string(from: NSNumber(value: defaultValue))!
                    localValue = nil
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(BorderlessButtonStyle())
                .controlSize(.mini)
                .frame(width: 20, height: 20)
                .foregroundColor(.accentColor)
                .accessibilityLabel("Reset \(title)")
                .help("Reset to default")
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}

struct VerticalRestorationFiltersPanel: View {
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label("Restoration Filters", systemImage: "wand.and.stars")
                .font(DesignSystem.Typography.caption1)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            if !settings.primary.useDenoise || !settings.primary.useSharpen {
                Text([!settings.primary.useDenoise ? "Denoise off" : nil,
                      !settings.primary.useSharpen ? "Sharpen off" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .top) {
                TransparentScrollView(showsIndicators: true) {
                    GroupBox {
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            // Denoise
                        VerticalParameterRow(
                            title: "Denoise",
                            binding: $settings.primary.denoiseStrength.text,
                            range: settings.denoiseStrengthRange,
                            step: settings.denoiseStrengthStep,
                            defaultValue: settings.denoiseStrengthDefault,
                            formatter: Formatters.oneFraction,
                            gradient: .denoise
                        )
                        .disabled(!settings.primary.useDenoise)

                        ModernDivider()
                            .padding(.vertical, DesignSystem.Spacing.xs)

                        // Deringing toggle
                        HStack {
                            Toggle(isOn: $settings.primary.useDering) {
                                Text("Dering")
                                    .font(DesignSystem.Typography.caption2)
                                    .fontWeight(.medium)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            Spacer()
                        }
                        .padding(.vertical, DesignSystem.Spacing.xs)

                        if settings.primary.useDering {
                            VerticalParameterRow(
                                title: "Strength",
                                binding: $settings.primary.deringStrength.text,
                                range: 0...10,
                                step: 0.005,
                                defaultValue: 0.5,
                                formatter: Formatters.twoFraction,
                                gradient: .dering
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.2), value: settings.primary.useDering)
                        }

                        ModernDivider()
                            .padding(.vertical, DesignSystem.Spacing.xs)

                        Picker(!settings.primary.useSharpen ? "Sharpen off" : "Method", selection: $settings.primary.sharpenMethod) {
                            Text("CAS").tag("cas")
                            Text("Unsharp").tag("unsharp")
                        }
                        .pickerStyle(.menu)
                        .disabled(!settings.primary.useSharpen)
                        .controlSize(.mini)
                        .font(DesignSystem.Typography.caption2)

                        if settings.primary.sharpenMethod == "cas" {
                            VerticalParameterRow(
                                title: "CAS Strength",
                                binding: $settings.primary.sharpenStrength.text,
                                range: 0...1,
                                step: 0.005,
                                defaultValue: 0.25,
                                formatter: Formatters.twoFraction,
                                gradient: .sharpen
                            )
                            .disabled(!settings.primary.useSharpen)
                        } else {
                            VerticalParameterRow(
                                title: "Radius",
                                binding: $settings.primary.usmRadius.text,
                                range: 3...23,
                                step: 1,
                                defaultValue: 5,
                                formatter: Formatters.integer,
                                gradient: .usmRadius
                            )
                            .disabled(!settings.primary.useSharpen)

                            VerticalParameterRow(
                                title: "Amount",
                                binding: $settings.primary.usmAmount.text,
                                range: -2...5,
                                step: 0.01,
                                defaultValue: 1.0,
                                formatter: Formatters.twoFraction,
                                gradient: .usmAmount
                            )
                            .disabled(!settings.primary.useSharpen)

                            VerticalParameterRow(
                                title: "Threshold",
                                binding: $settings.primary.usmThreshold.text,
                                range: 0...1,
                                step: 0.001,
                                defaultValue: 0.03,
                                formatter: Formatters.threeFraction,
                                gradient: .usmThreshold
                            )
                            .disabled(!settings.primary.useSharpen)
                        }
                    }
                    .padding(6)
                    }
                    .background(Color(nsColor: NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                    .padding(.trailing, 10)
                }

            }
        }
        .frame(width: 140)
    }
}
