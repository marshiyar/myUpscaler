
import SwiftUI

// MARK: - Custom Slider
struct LuxuriousSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let gradient: SliderGradient
    var onEditingChanged: ((Bool) -> Void)? = nil
    @State private var isEditing = false

    /// The value rounded to the step from the range's start. The slider itself is continuous: a stepped slider
    /// draws tick marks as a second line under the track.
    private func snapped(_ next: Double) -> Double {
        guard step > 0 else { return next }
        let rounded = ((next - range.lowerBound) / step).rounded() * step + range.lowerBound
        return min(max(rounded, range.lowerBound), range.upperBound)
    }

    var body: some View {
        Slider(value: Binding(get: { value }, set: { next in
            value = snapped(next)
            // Keyboard and accessibility adjustments also commit, without a drag.
            if !isEditing { onEditingChanged?(false) }
        }), in: range, onEditingChanged: { editing in
            isEditing = editing
            onEditingChanged?(editing)
        })
        .controlSize(.regular)
    }
}


// MARK: - ParameterRow (compact, native)
struct ParameterRow: View {
    let title: String
    let binding: Binding<String>
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    let formatter: NumberFormatter
    let sliderAccessibility: String
    let gradient: SliderGradient
    var onChange: ((Double) -> Void)? = nil

    // Local state to track dragging without triggering global updates
    @State private var localValue: Double? = nil

    private var displayValue: Double {
        localValue ?? Double(binding.wrappedValue) ?? defaultValue
    }

    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { displayValue },
            set: { localValue = $0 }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.body)
                .frame(width: 92, alignment: .leading)
                .lineLimit(1)

            LuxuriousSlider(value: sliderBinding, range: range, step: step, gradient: gradient, onEditingChanged: { editing in
                if !editing {
                    // changes happen only when dragging ends
                    if let finalValue = localValue {
                        binding.wrappedValue = formatter.string(from: NSNumber(value: finalValue)) ?? "\(finalValue)"
                        onChange?(finalValue)
                        localValue = nil
                    }
                }
            })
            .frame(minWidth: 90)
            .accessibilityLabel(sliderAccessibility)

            // Value display
            Text(formatter.string(from: NSNumber(value: displayValue)) ?? "")
                .font(.body.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
                .foregroundColor(.primary)

            // Reset button
            Button {
                binding.wrappedValue = formatter.string(from: NSNumber(value: defaultValue))!
                localValue = nil
                onChange?(defaultValue)
            }
            label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel("Reset \(title)")
            .help("Reset \(title) to default")
            .buttonStyle(UI.resetButtonStyle)
            .controlSize(.small)
            .frame(width: 24)
            .foregroundColor(.accentColor)
        }
        .padding(.vertical, 2)

    }
}
