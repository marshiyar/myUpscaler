
import SwiftUI

// MARK: - Custom Slider
struct LuxuriousSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let gradient: SliderGradient
    var onEditingChanged: ((Bool) -> Void)? = nil
    
    var body: some View {
        GeometryReader { geometry in
            let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbPosition = progress * geometry.size.width
            let trackHeight: CGFloat = 8
            let thumbSize: CGFloat = 18
            
            ZStack(alignment: .leading) {
                // Background track (larger)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: trackHeight)
                
                // Filled track withgradient (larger)
                RoundedRectangle(cornerRadius: 4)
                    .fill(gradient.gradient)
                    .frame(width: max(0, min(geometry.size.width, thumbPosition)))
                    .frame(height: trackHeight)
                
                // Thumb/indicator (visible, easier to grab)
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(gradient.gradient, lineWidth: 2)
                    )
                    .offset(x: max(thumbSize/2, min(geometry.size.width - thumbSize/2, thumbPosition - thumbSize/2)))
            }
            // TODO: REVIEW CODE
            .frame(height: trackHeight)
            .padding(.vertical, 8) // Extra padding for easier grabbing
            .drawingGroup() // Offload rendering to GPU to prevent Main Thread hangs
            .contentShape(Rectangle()) // Make entire area interactive
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragValue in
                        if let onEditingChanged = onEditingChanged { onEditingChanged(true) }
                        let percentage = max(0, min(1, dragValue.location.x / geometry.size.width))
                        let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(percentage)
                        let steppedValue = round(newValue / step) * step
                        value = max(range.lowerBound, min(range.upperBound, steppedValue))
                    }
                    .onEnded { _ in
                        if let onEditingChanged = onEditingChanged { onEditingChanged(false) }
                    }
            )
            .onTapGesture { location in
                let percentage = max(0, min(1, location.x / geometry.size.width))
                let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(percentage)
                let steppedValue = round(newValue / step) * step
                value = max(range.lowerBound, min(range.upperBound, steppedValue))
                if let onEditingChanged = onEditingChanged {
                    onEditingChanged(true)
                    onEditingChanged(false)
                }
            }
        }
        .frame(height: 32) // Increased from 20 to 32 for better accessibility
    }
}


// MARK: - ParameterRow (compact, native)
private struct ParameterRow: View {
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
    
    private var isZero: Bool {
        displayValue == 0
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
                .foregroundColor(isZero ? .orange : .primary)
            
            // Reset button
            Button("R") {
                binding.wrappedValue = formatter.string(from: NSNumber(value: defaultValue))!
                localValue = nil
                onChange?(defaultValue)
            }
            .buttonStyle(UI.resetButtonStyle)
            .controlSize(.small)
            .frame(width: 28)
            .foregroundColor(.accentColor)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, isZero ? 4 : 0)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isZero ? Color.orange.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isZero ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 2)
                )
        )
    }
}


// MARK: - Matte Card Group Helper
private struct MatteCardGroup<Content: View>: View {
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
                .fill(Color.black.opacity(0.18)) // Matte blackish background
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1) // Subtle border for definition
        )
    }
}
