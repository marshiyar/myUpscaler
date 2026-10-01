import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

private enum DragDropFormatters {
    static let twoFraction: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
    static let threeFraction: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 3
        return f
    }()
    static let oneFraction: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()
    static let integer: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 0
        return f
    }()
}

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
    var onDragToEnlarge: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label("Color Equalizer", systemImage: "paintpalette.fill")
                .font(DesignSystem.Typography.caption1)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            if settings.scaler == "coreml" || settings.noEq {
                Text(settings.noEq ? "Color EQ is off" : "Preview only for Core ML")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    VerticalParameterRow(
                        title: "Contrast",
                        binding: $settings.eqContrast,
                        range: 0.5...2.0,
                        step: 0.005,
                        defaultValue: 1.0,
                        formatter: DragDropFormatters.twoFraction,
                        gradient: .contrast
                    )

                    VerticalParameterRow(
                        title: "Brightness",
                        binding: $settings.eqBrightness,
                        range: -0.1...0.1,
                        step: 0.005,
                        defaultValue: 0.0,
                        formatter: DragDropFormatters.threeFraction,
                        gradient: .brightness
                    )

                    VerticalParameterRow(
                        title: "Saturation",
                        binding: $settings.eqSaturation,
                        range: 0...2,
                        step: 0.005,
                        defaultValue: 1.0,
                        formatter: DragDropFormatters.twoFraction,
                        gradient: .saturation
                    )
                }
                .padding(6)
            }
            .disabled(settings.noEq)
            .background(Color(nsColor: NSColor.windowBackgroundColor))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        }
        .frame(width: 140)
        .offset(x: dragOffset)
        .scaleEffect(1.0 + min(abs(dragOffset) / 500.0, 0.3))  // Scale up as dragged, max 30% larger
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow dragging to the right (positive x)
                    if value.translation.width > 0 {
                        isDragging = true
                        // Rubber band effect: resistance increases as you drag further
                        // Use a non-linear resistance curve for better feel
                        let rawDrag = abs(value.translation.width)
                        let resistance: CGFloat = max(0.1, 1.0 - (rawDrag / 200.0))  // Decreasing resistance
                        dragOffset = value.translation.width * resistance

                        // Trigger enlargement if dragged far enough (threshold: 80 pixels)
                        if value.translation.width > 80 && onDragToEnlarge != nil {
                            onDragToEnlarge?()
                            // Reset after triggering
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = 0
                                isDragging = false
                            }
                        }
                    }
                }
                .onEnded { value in
                    // Spring back animation with bounce
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        dragOffset = 0
                        isDragging = false
                    }
                }
        )
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
    var onDragToEnlarge: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label("Restoration Filters", systemImage: "wand.and.stars")
                .font(DesignSystem.Typography.caption1)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            if settings.noDenoise || settings.noSharpen {
                Text([settings.noDenoise ? "Denoise off" : nil,
                      settings.noSharpen ? "Sharpen off" : nil].compactMap { $0 }.joined(separator: " · "))
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
                            binding: $settings.denoiseStrength,
                            range: settings.denoiseStrengthRange,
                            step: settings.denoiseStrengthStep,
                            defaultValue: settings.denoiseStrengthDefault,
                            formatter: DragDropFormatters.oneFraction,
                            gradient: .denoise
                        )
                        .disabled(settings.noDenoise)

                        ModernDivider()
                            .padding(.vertical, DesignSystem.Spacing.xs)

                        // Deringing toggle
                        HStack {
                            Toggle(isOn: $settings.deringActive) {
                                Text("Dering")
                                    .font(DesignSystem.Typography.caption2)
                                    .fontWeight(.medium)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            Spacer()
                        }
                        .padding(.vertical, DesignSystem.Spacing.xs)

                        if settings.deringActive {
                            VerticalParameterRow(
                                title: "Strength",
                                binding: $settings.deringStrength,
                                range: 0...10,
                                step: 0.005,
                                defaultValue: 0.5,
                                formatter: DragDropFormatters.twoFraction,
                                gradient: .dering
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.2), value: settings.deringActive)
                        }

                        ModernDivider()
                            .padding(.vertical, DesignSystem.Spacing.xs)

                        Picker(settings.noSharpen ? "Sharpen off" : "Method", selection: $settings.sharpenMethod) {
                            Text("CAS").tag("cas")
                            Text("Unsharp").tag("unsharp")
                        }
                        .pickerStyle(.menu)
                        .disabled(settings.noSharpen)
                        .controlSize(.mini)
                        .font(DesignSystem.Typography.caption2)

                        if settings.sharpenMethod == "cas" {
                            VerticalParameterRow(
                                title: "CAS Strength",
                                binding: $settings.sharpenStrength,
                                range: 0...1,
                                step: 0.005,
                                defaultValue: 0.25,
                                formatter: DragDropFormatters.twoFraction,
                                gradient: .sharpen
                            )
                            .disabled(settings.noSharpen)
                        } else {
                            VerticalParameterRow(
                                title: "Radius",
                                binding: $settings.usmRadius,
                                range: 3...23,
                                step: 1,
                                defaultValue: 5,
                                formatter: DragDropFormatters.integer,
                                gradient: .usmRadius
                            )
                            .disabled(settings.noSharpen)

                            VerticalParameterRow(
                                title: "Amount",
                                binding: $settings.usmAmount,
                                range: -2...5,
                                step: 0.01,
                                defaultValue: 1.0,
                                formatter: DragDropFormatters.twoFraction,
                                gradient: .usmAmount
                            )
                            .disabled(settings.noSharpen)

                            VerticalParameterRow(
                                title: "Threshold",
                                binding: $settings.usmThreshold,
                                range: 0...1,
                                step: 0.001,
                                defaultValue: 0.03,
                                formatter: DragDropFormatters.threeFraction,
                                gradient: .usmThreshold
                            )
                            .disabled(settings.noSharpen)
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
        .offset(x: dragOffset)
        .scaleEffect(1.0 + min(abs(dragOffset) / 500.0, 0.3))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.width < 0 {
                        isDragging = true
                        // Rubber band effect: resistance increases as you drag further
                        // Use a non-linear resistance curve for better feel
                        let rawDrag = abs(value.translation.width)
                        let resistance: CGFloat = max(0.1, 1.0 - (rawDrag / 200.0))  // Decreasing resistance
                        dragOffset = value.translation.width * resistance

                        // Trigger enlargement if dragged far enough (threshold: -80 pixels)
                        if value.translation.width < -80 && onDragToEnlarge != nil {
                            onDragToEnlarge?()
                            // Reset after triggering
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = 0
                                isDragging = false
                            }
                        }
                    }
                }
                .onEnded { value in
                    // Spring back animation with bounce
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        dragOffset = 0
                        isDragging = false
                    }
                }
        )
    }
}
