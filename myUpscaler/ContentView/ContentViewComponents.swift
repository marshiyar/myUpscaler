
import SwiftUI

// MARK: - Custom Slider
struct LuxuriousSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let gradient: SliderGradient
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
                .font(.subheadline.weight(.medium))
                .frame(width: 70, alignment: .leading)
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
            .frame(minWidth: 120)
            .accessibilityLabel(sliderAccessibility)
            
            // Value display
            Text(formatter.string(from: NSNumber(value: displayValue)) ?? "")
                .font(.subheadline.weight(.medium))
                .frame(width: 40, alignment: .trailing)
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
            .frame(width: 28)
            .foregroundColor(.accentColor)
        }
        .padding(.vertical, 2)

    }
}


// MARK: - Matte Card Group Helper
struct MatteCardGroup<Content: View>: View {
    let content: Content
    let spacing: CGFloat
    
    init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appSecondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
