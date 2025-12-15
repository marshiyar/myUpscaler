import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// ------------------------------------------------------------
// MARK: - UI Constants (Apple‑native sizing)
// ------------------------------------------------------------
private struct UI {
    // Card‑style
    static let cardCornerRadius: CGFloat = 12         // softer than the default
    static let cardShadowRadius: CGFloat = 3
    static let cardInnerPadding: CGFloat = 12        // padding *inside* every card
    
    // Layout - responsive spacing
    static let sectionSpacing: CGFloat = 20       // space between the big sections
    static let rowSpacing: CGFloat = 8             // space inside a card
    static let labelWidth: CGFloat = 50             // width of the left‑hand label
    static let columnSpacing: CGFloat = 16         // space between left/right columns
    
    // Responsive column widths
    static let leftColumnMinWidth: CGFloat = 320
    static let leftColumnIdealWidth: CGFloat = 380
    static let leftColumnMaxWidth: CGFloat = 480
    
    static let rightColumnMinWidth: CGFloat = 300
    static let rightColumnIdealWidth: CGFloat = 360
    static let rightColumnMaxWidth: CGFloat = 450
    
    // Window constraints
    static let windowMinWidth: CGFloat = 700
    static let windowIdealWidth: CGFloat = 900
    static let windowMinHeight: CGFloat = 600
    
    // Controls
    static let buttonHeight: CGFloat = 32           // system regular height
    static let resetButtonWidth: CGFloat = 38
    static let resetButtonStyle = BorderlessButtonStyle()
}

// ------------------------------------------------------------
// MARK: - Card background colour (platform safe)
// ------------------------------------------------------------
private var cardBackground: Color {
    #if os(macOS)
    Color(NSColor.windowBackgroundColor)
    #else
    Color(UIColor.secondarySystemBackground)
    #endif
}

// ------------------------------------------------------------
// MARK: - CardStyle Modifier (re‑usable visual style)
// ------------------------------------------------------------
private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(cardBackground)
            .cornerRadius(UI.cardCornerRadius)
            .shadow(color: Color.black.opacity(0.08),
                    radius: UI.cardShadowRadius,
                    x: 0, y: 0.5)
            .padding(.horizontal, 8)                // keep the card away from the window edge
    }
}
private extension View {
    func cardStyle() -> some View { self.modifier(CardStyle()) }
}

// ------------------------------------------------------------
// MARK: - NumberFormatters (static, reused)
// ------------------------------------------------------------
private enum Formatters {
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

// ------------------------------------------------------------
// MARK: - Slider Gradient Colors
// ------------------------------------------------------------
private enum SliderGradient {
    case crf          // Quality - deep blue to purple (professional)
    case denoise      // Denoise - cool cyan to blue (clean, smooth)
    case dering       // Deringing - teal to green (healing, correction)
    case sharpen      // Sharpen - bright yellow to white (sharp, crisp)
    case contrast     // Contrast - purple to pink (vibrant, dynamic)
    case brightness   // Brightness - yellow to white (light, bright)
    case saturation   // Saturation - rainbow colors (colorful, rich)
    case scale        // Scale - blue to purple (growth, expansion)
    case usmRadius    // Unsharp radius - orange to yellow (focused)
    case usmAmount    // Unsharp amount - red to orange (intense)
    case usmThreshold  // Unsharp threshold - pink to purple (precise)
    
    var gradient: LinearGradient {
        switch self {
        case .crf:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.2, green: 0.4, blue: 0.9),   // Deep blue
                    Color(red: 0.5, green: 0.3, blue: 0.9),  // Purple
                    Color(red: 0.7, green: 0.2, blue: 0.8)  // Deep purple
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .denoise:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.0, green: 0.7, blue: 0.9),  // Cyan
                    Color(red: 0.2, green: 0.5, blue: 0.9),   // Sky blue
                    Color(red: 0.3, green: 0.4, blue: 0.95)   // Deep blue
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .dering:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.0, green: 0.8, blue: 0.7),   // Teal
                    Color(red: 0.2, green: 0.7, blue: 0.6),  // Aqua
                    Color(red: 0.3, green: 0.8, blue: 0.5)    // Green
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .sharpen:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.9, blue: 0.3),  // Bright yellow
                    Color(red: 1.0, green: 0.95, blue: 0.6),  // Light yellow
                    Color(red: 1.0, green: 1.0, blue: 0.9)     // Near white
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .contrast:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.6, green: 0.2, blue: 0.8),  // Purple
                    Color(red: 0.8, green: 0.3, blue: 0.7),  // Magenta
                    Color(red: 1.0, green: 0.4, blue: 0.6)   // Pink
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .brightness:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.8, blue: 0.2),  // Golden yellow
                    Color(red: 1.0, green: 0.9, blue: 0.5),  // Light yellow
                    Color(red: 1.0, green: 1.0, blue: 0.9)  // Cream white
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .saturation:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.0, blue: 0.5),   // Hot pink
                    Color(red: 1.0, green: 0.5, blue: 0.0),   // Orange
                    Color(red: 0.8, green: 1.0, blue: 0.0)   // Lime green
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .scale:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.3, green: 0.5, blue: 0.9),   // Blue
                    Color(red: 0.5, green: 0.4, blue: 0.9),  // Indigo
                    Color(red: 0.7, green: 0.3, blue: 0.8)   // Purple
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .usmRadius:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.5, blue: 0.0),  // Orange
                    Color(red: 1.0, green: 0.7, blue: 0.2),  // Light orange
                    Color(red: 1.0, green: 0.9, blue: 0.4)  // Yellow-orange
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .usmAmount:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.9, green: 0.2, blue: 0.2),  // Red
                    Color(red: 1.0, green: 0.4, blue: 0.2), // Red-orange
                    Color(red: 1.0, green: 0.6, blue: 0.3)  // Orange
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .usmThreshold:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.4, blue: 0.7),   // Pink
                    Color(red: 0.9, green: 0.3, blue: 0.8),   // Magenta
                    Color(red: 0.7, green: 0.2, blue: 0.9)   // Purple
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

// ------------------------------------------------------------
// MARK: - Luxurious Custom Slider
// ------------------------------------------------------------
private struct LuxuriousSlider: View {
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
                
                // Filled track with custom gradient (larger)
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

// ------------------------------------------------------------
// MARK: - ParameterRow (compact, native)
// ------------------------------------------------------------
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
            
            // Luxurious custom slider
            LuxuriousSlider(value: sliderBinding, range: range, step: step, gradient: gradient, onEditingChanged: { editing in
                if !editing {
                    // Commit changes only when dragging ends
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

// ------------------------------------------------------------
// MARK: - Sub‑views (each block is its own struct)
// ------------------------------------------------------------

/// Header – stays at the top of the scroll view
private struct HeaderView: View {
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.accentColor)
                
                Text("MyUpscaler")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

/// Input section (drag‑drop + browse button)
private struct InputSection: View {
    @Binding var inputPath: String
    let chooseInput: () -> Void
    let settings: UpscaleSettings
    var isProcessingFullUpscale: Bool = false
    var onFrameDoubleTap: ((NSImage?) -> Void)? = nil
    var onRestorationFiltersDrag: (() -> Void)? = nil
    var onColorEqualizerDrag: (() -> Void)? = nil
    var onEditorStateAvailable: ((EditorState) -> Void)? = nil
    
    var body: some View {
        MatteCardGroup(spacing: 8) {
            dragDropView()
                .frame(minHeight: 280)
                .layoutPriority(1)
        }
    }
    
    private func dragDropView() -> some View {
        DragDropView(externalInputPath: $inputPath, settings: settings, chooseInput: chooseInput, isProcessingFullUpscale: isProcessingFullUpscale, onFrameDoubleTap: onFrameDoubleTap, onRestorationFiltersDrag: onRestorationFiltersDrag, onColorEqualizerDrag: onColorEqualizerDrag, onEditorStateAvailable: onEditorStateAvailable)
            .cornerRadius(10) // Match the card corner radius
            .overlay(
                // Show overlay when processing to indicate preview is frozen
                Group {
                    if isProcessingFullUpscale {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Processing... Preview frozen")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            )
                    }
                }
            )
    }
    
}


/// Color‑Equalizer card
// MARK: - COMMENTED OUT: Bigger Color Equalizer Panel (keeping the small VerticalColorEqualizerPanel in DragDropView.swift)
/*
private struct ColorEqualizerPanel: View {
    @ObservedObject var settings: UpscaleSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Color Equalizer", systemImage: "paintpalette")
                    .font(.headline)
                Spacer()
            }
            GroupBox {
                VStack(spacing: UI.rowSpacing) {
                    ParameterRow(title: "Contrast",
                                 binding: $settings.eqContrast,
                                 range: 0.5...2.0,
                                 step: 0.005,
                                 defaultValue: 1.03,
                                 formatter: Formatters.twoFraction,
                                 sliderAccessibility: "Contrast slider")
                    { _ in settings.objectWillChange.send() }
                    
                    ParameterRow(title: "Brightness",
                                 binding: $settings.eqBrightness,
                                 range: -0.1...0.1,
                                 step: 0.005,
                                 defaultValue: 0.005,
                                 formatter: Formatters.threeFraction,
                                 sliderAccessibility: "Brightness slider")
                    { _ in settings.objectWillChange.send() }
                    
                    ParameterRow(title: "Saturation",
                                 binding: $settings.eqSaturation,
                                 range: 0...2,
                                 step: 0.005,
                                 defaultValue: 1.06,
                                 formatter: Formatters.twoFraction,
                                 sliderAccessibility: "Saturation slider")
                    { _ in settings.objectWillChange.send() }
                }
                .padding(UI.cardInnerPadding)
            }
            .cardStyle()
        }
    }
}
*/

/// Enlarged Color Equalizer Panel (full-screen style)
private struct EnlargedColorEqualizerPanel: View {
    @ObservedObject var settings: UpscaleSettings
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.85)
                .ignoresSafeArea(.all)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            
            // Enlarged panel
            VStack {
                Spacer()
                
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Label("Color Equalizer", systemImage: "paintpalette")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 10)
                    
                    // Content with better spacing
                    GroupBox {
                        VStack(spacing: 20) {
                            ParameterRow(title: "Contrast",
                                         binding: $settings.eqContrast,
                                         range: settings.eqContrastRange,
                                         step: settings.eqContrastStep,
                                         defaultValue: settings.eqContrastDefault,
                                         formatter: Formatters.twoFraction,
                                         sliderAccessibility: "Contrast slider",
                                         gradient: .contrast)
                            { _ in settings.objectWillChange.send() }
                            
                            Divider()
                            
                            ParameterRow(title: "Brightness",
                                         binding: $settings.eqBrightness,
                                         range: settings.eqBrightnessRange,
                                         step: settings.eqBrightnessStep,
                                         defaultValue: settings.eqBrightnessDefault,
                                         formatter: Formatters.threeFraction,
                                         sliderAccessibility: "Brightness slider",
                                         gradient: .brightness)
                            { _ in settings.objectWillChange.send() }
                            
                            Divider()
                            
                            ParameterRow(title: "Saturation",
                                         binding: $settings.eqSaturation,
                                         range: settings.eqSaturationRange,
                                         step: settings.eqSaturationStep,
                                         defaultValue: settings.eqSaturationDefault,
                                         formatter: Formatters.twoFraction,
                                         sliderAccessibility: "Saturation slider",
                                         gradient: .saturation)
                            { _ in settings.objectWillChange.send() }
                        }
                        .padding(24)
                    }
                    .frame(width: 600)
                    .background(cardBackground)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 15)
                }
                .padding(40)
                
                Spacer()
                
                // Hint text
                HStack {
                    Text("Double-click background to close")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                    Text("Press ESC")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom, 30)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .zIndex(10000)
        .focusable()
        .onKeyPress(.escape) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isPresented = false
            }
            return .handled
        }
    }
}

/// Enlarged Restoration Filters Panel (full-screen style)
private struct EnlargedRestorationFiltersPanel: View {
    @ObservedObject var settings: UpscaleSettings
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.85)
                .ignoresSafeArea(.all)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            
            // Enlarged panel
            VStack {
                Spacer()
                
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Label("Restoration Filters", systemImage: "wand.and.stars")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 10)
                    
                    // Content with better spacing
                    GroupBox {
                        VStack(spacing: 20) {
                            // Denoise
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
                                    .font(.title3)
                            }
                            .toggleStyle(.switch)
                            .padding(.vertical, 8)
                            
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
                            HStack {
                                Text("Sharpen Method")
                                    .font(.title3)
                                Spacer()
                                Picker("Method", selection: $settings.sharpenMethod) {
                                    Text("CAS").tag("cas")
                                    Text("Unsharp Mask").tag("unsharp")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                            }
                            
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
                                VStack(alignment: .leading, spacing: 16) {
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
                                }
                            }
                        }
                        .padding(24)
                    }
                    .frame(width: 600)
                    .background(cardBackground)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 15)
                }
                .padding(40)
                
                Spacer()
                
                // Hint text
                HStack {
                    Text("Double-click background to close")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                    Text("Press ESC")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom, 30)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .zIndex(10000)
        .focusable()
        .onKeyPress(.escape) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isPresented = false
            }
            return .handled
        }
    }
}

/// Restoration‑Filters card (denoise, deringing, sharpen)
private struct RestorationFiltersPanel: View {
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
                    // Denoise
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
                            .padding(.top, 8)  // Space above the dropdown content
                            .animation(.easeInOut(duration: 0.2), value: settings.deringActive)
                    }
                    
                    Divider()
                    
                    // Sharpen
                    Picker("Method", selection: $settings.sharpenMethod) {
                        Text("CAS").tag("cas")
                        Text("Unsharp Mask").tag("unsharp")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    
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

/// Quality & Scale panel (compact)
private struct QualityScalePanel: View {
    @ObservedObject var settings: UpscaleSettings
    @State private var localCRF: Double? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Quality & Scale", systemImage: "chart.bar")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    // CRF Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("CRF")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(localCRF ?? settings.crf))")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.primary)
                            Text("(Lower is better)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        LuxuriousSlider(value: Binding(
                            get: { localCRF ?? settings.crf },
                            set: { localCRF = $0 }
                        ), range: 0...51, step: 1, gradient: .crf, onEditingChanged: { editing in
                            if !editing {
                                if let finalValue = localCRF {
                                    settings.crf = finalValue
                                    localCRF = nil
                                }
                            }
                        })
                        .frame(minWidth: 100)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Scale Factor and FPS
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scale")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("2.0", value: $settings.scaleFactor, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FPS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("60", text: $settings.fps)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Interpolation Mode
                    HStack {
                        Text("Interpolation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.interpolation) {
                            ForEach(settings.interpolations, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

/// AI Engine panel (compact)
private struct AIEnginePanel: View {
    @ObservedObject var settings: UpscaleSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("AI Engine", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    // Scaler
                    HStack {
                        Text("Scaler")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.scaler) {
                            ForEach(settings.scalers, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                    
                    if settings.scaler == "coreml" {
                        Divider()
                            .padding(.vertical, 2)
                        
                        HStack {
                            Text("CoreML Model")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.coremlModelId) {
                                ForEach(settings.coremlModels) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 140)
                        }
                    }
                    
                    if settings.scaler == "ai" {
                        Divider()
                            .padding(.vertical, 2)
                        
                        // AI Backend
                        HStack {
                            Text("AI Backend")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.aiBackend) {
                                ForEach(settings.aiBackends, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 100)
                        }
                        
                        // DNN Backend
                        HStack {
                            Text("DNN Backend")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.dnnBackend) {
                                ForEach(settings.dnnBackends, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 100)
                        }
                        
                        // Model Type
                        HStack {
                            Text("Model Type")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.aiModelType) {
                                ForEach(settings.aiModelTypes, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 100)
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        // Model Path
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Model Path")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                TextField("", text: $settings.aiModelPath)
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse") {
                                    let panel = NSOpenPanel()
                                    panel.allowsMultipleSelection = false
                                    if panel.runModal() == .OK, let url = panel.url {
                                        settings.aiModelPath = url.path
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Restoration (First Set) panel (compact)
/// Contains elements missing from the VerticalRestorationFiltersPanel: Deblock, Unsharp Mask Threshold, Deband advanced params, Grain Strength, LUT
private struct RestorationPanel: View {
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
                    
                    // LUT Path
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LUT Path (.cube)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("", text: $settings.lutPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse") {
                                let panel = NSOpenPanel()
                                if let cubeType = UTType(filenameExtension: "cube") {
                                    panel.allowedContentTypes = [cubeType]
                                }
                                if panel.runModal() == .OK, let url = panel.url {
                                    settings.lutPath = url.path
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Restoration (Second Set) panel (compact) - shown on main page
private struct RestorationSecondSetPanel: View {
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
                                        .font(.system(size: 9))
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
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("5", text: $settings.usmRadius2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("A")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("1.0", text: $settings.usmAmount2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("T")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("0.03", text: $settings.usmThreshold2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 40)
                                    }
                                    
                                    // Show effective values if attenuated
                                    if settings.isSharpenStacked {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("→")
                                                .font(.system(size: 9))
                                                .foregroundColor(.orange)
                                            Text("\(settings.effectiveUsmAmount2)")
                                                .font(.system(size: 9))
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
                                            .font(.system(size: 9))
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
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("15", text: $settings.f3kdbRange2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Y")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("64", text: $settings.f3kdbY2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("CbCr")
                                            .font(.system(size: 9))
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
            .groupBoxStyle(ModernGroupBoxStyle()) // Use modern style for consistent look
            .cardStyle() // Apply card style to the whole container
        }
    }
}

/// x265 Parameters panel (compact)
private struct X265ParametersPanel: View {
    @ObservedObject var settings: UpscaleSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("x265 Parameters", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        // AQ Mode
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AQ Mode")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            TextField("3", text: $settings.x265AqMode)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                        }
                        
                        // Psy-RD
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Psy-RD")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            TextField("2.0", text: $settings.x265PsyRd)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                        }
                        
                        // Deblock
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Deblock")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                TextField("-2", text: $settings.x265Deblock1)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 35)
                                Text(",")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("-2", text: $settings.x265Deblock2)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 35)
                            }
                        }
                        
                        Spacer()
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Hardware & Encoding panel (compact)
private struct HardwareEncodingPanel: View {
    @ObservedObject var settings: UpscaleSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Hardware & Encoding", systemImage: "gearshape.2")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    // HW Acceleration
                    HStack {
                        Text("HW Acceleration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.hwAccel) {
                            ForEach(settings.hwAccels, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Encoder
                    HStack {
                        Text("Encoder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.encoder) {
                            ForEach(settings.encoders, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Toggles
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            Toggle(isOn: $settings.useHEVC) {
                                Text("Use HEVC (H.265)")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            Toggle(isOn: $settings.use10Bit) {
                                Text("10‑Bit Output")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            // MOV Faststart Toggle
                            Toggle(isOn: Binding(
                                get: { settings.movflags.contains("+faststart") },
                                set: { isEnabled in
                                    if isEnabled {
                                        if !settings.movflags.contains("+faststart") {
                                            if settings.movflags.isEmpty {
                                                settings.movflags = "+faststart"
                                            } else {
                                                settings.movflags += " +faststart"
                                            }
                                        }
                                    } else {
                                        settings.movflags = settings.movflags.replacingOccurrences(of: "+faststart", with: "").trimmingCharacters(in: .whitespaces)
                                    }
                                }
                            )) {
                                Text("Faststart")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .help("Moves metadata to the beginning of the file for faster web playback")
                            
                            Spacer()
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        HStack {
                           Text("Audio Bitrate")
                               .font(.caption)
                               .foregroundColor(.secondary)
                           Spacer()
                           TextField("192k", text: $settings.audioBitrate)
                               .textFieldStyle(.roundedBorder)
                               .frame(width: 60)
                       }

                        #if arch(arm64)
                        Text("Apple Silicon default: VideoToolbox decode for speed without quality loss. Switch HW Acceleration to None if a file fails.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        #else
                        Text("If hardware decode causes issues on this Mac, set HW Acceleration to None.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        #endif
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Preset
                    HStack {
                        Text("Preset")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.preset) {
                            ForEach(settings.presets, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Threads
                    HStack {
                        Text("Threads")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("0 (auto)", text: $settings.threads)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Output panel (compact, destination picker + preview name)
private struct OutputPanel: View {
    @Binding var outputMode: UpscaleRunner.OutputMode
    @Binding var customOutputFolder: String
    let predictedName: String
    let chooseFolder: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Output", systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    // Destination picker
                    HStack {
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $outputMode) {
                            Text("Same folder").tag(UpscaleRunner.OutputMode.same)
                            Text("Custom folder").tag(UpscaleRunner.OutputMode.custom)
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 120)
                        .fixedSize()  // Prevents size changes
                        .transition(.opacity)  // Smooth transition
                        .animation(.easeInOut(duration: 0.15), value: outputMode)
                    }
                    
                    // Custom folder UI (only visible when needed)
                    if outputMode == .custom {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                            Text(customOutputFolder)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                            Spacer()
                            
                            Button("Choose", action: chooseFolder)
                                .controlSize(.mini)
                                .dynamicKeyboardShortcut(actionId: "chooseOutput", action: chooseFolder)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .background(cardBackground)  // Add background to ensure visibility
                        .cornerRadius(6)  // Match your card style
                        .zIndex(1)  // Ensure header stays on top
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Predicted output name
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 10))
                        Text("Will output:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(predictedName)
                            .font(.system(size: 9))
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Run / Cancel buttons
private struct ActionButtons: View {
    @ObservedObject var runner: UpscaleRunner
    
    var body: some View {
        HStack(spacing: 12) {
            // Run
            Button(action: runner.run) {
                HStack {
                    if runner.isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(runner.isRunning ? "Processing…" : "Run Upscaler")
                }
                .frame(maxWidth: .infinity)
            }
            
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .frame(height: UI.buttonHeight)
            .disabled(runner.isRunning || runner.inputPath.isEmpty)
            .dynamicKeyboardShortcut(actionId: "runUpscaler") {
                if !runner.isRunning && !runner.inputPath.isEmpty { runner.run() }
            }
            
            // Cancel
            Button(action: runner.cancel) {
                Label("Cancel", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(height: UI.buttonHeight)
            .disabled(!runner.isRunning)
            .dynamicKeyboardShortcut(actionId: "cancel") {
                if runner.isRunning { runner.cancel() }
            }
        }
    }
}

/// Progress bar + FPS / time / ETA line
private struct ProgressDetails: View {
    @ObservedObject var runner: UpscaleRunner
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: runner.progress)
                .tint(.accentColor)
                .frame(height: 4)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)// slim native bar
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 14) {
                Label(runner.fpsString, systemImage: "gauge")
                Label(runner.timeString, systemImage: "clock")
                Label(runner.etaString, systemImage: "hourglass")
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.accentColor.opacity(0.07))
        .cornerRadius(6)
    }
}

/// Log view – scrolls automatically to the bottom
private struct LogPanel: View {
    @ObservedObject var runner: UpscaleRunner
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Processing Log", systemImage: "text.bubble")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    ScrollViewReader { reader in
                        ScrollView {
                            Text(runner.log.isEmpty ? "Waiting to start processing…" : runner.log)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(6)                      // tight inner padding
                                .id("BOTTOM")
                        }
                        .padding(.vertical, 30)  // Add this
                        .onChange(of: runner.log) { _, _ in
                            withAnimation { reader.scrollTo("BOTTOM", anchor: .bottom) }
                            
                            // Check for completion when log updates
                            if !runner.isRunning {
                                runner.checkForCompletedOutput()
                            }
                        }
                        .onChange(of: runner.isRunning) { _, isRunning in
                            // When processing stops, check for output file
                            if !isRunning {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    runner.checkForCompletedOutput()
                                }
                            }
                        }
                    }
                    .frame(height: 170)  // Reduced to make room for button
                    
                    // Button to open completed video (uses completedOutputPath which is set correctly)
                    if !runner.isRunning, let outputPath = runner.completedOutputPath {
                        if FileManager.default.fileExists(atPath: outputPath),
                           let attributes = try? FileManager.default.attributesOfItem(atPath: outputPath),
                           let fileSize = attributes[.size] as? Int64,
                           fileSize > 0 {
                            Divider()
                                .padding(.vertical, 4)
                            
                            HStack(spacing: 8) {
                                Button(action: {
                                    openVideoFile(at: outputPath)
                                }) {
                                    HStack {
                                        Image(systemName: "play.circle.fill")
                                        Text("Open")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                Button(action: {
                                    revealVideoFile(at: outputPath)
                                }) {
                                    HStack {
                                        Image(systemName: "folder")
                                        Text("Reveal in Finder")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
        .onChange(of: runner.inputPath) { _, _ in
            // Reset completed output path when new video is imported
            runner.completedOutputPath = nil
        }
    }
    
    private func openVideoFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        
        // Under App Sandbox, we may need security-scoped access to open the file.
        // Start accessing the security-scoped resource if available
        var needsStopAccess = false
        if let scopedURL = runner.securityScopedOutputURL {
            needsStopAccess = scopedURL.startAccessingSecurityScopedResource()
        }
        
        // Try to open with NSWorkspace
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        
        // Capture the scoped URL for the completion handler
        let scopedURL = runner.securityScopedOutputURL
        
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            // Stop accessing the security-scoped resource after attempt
            if needsStopAccess, let url = scopedURL {
                url.stopAccessingSecurityScopedResource()
            }
            
            if let error = error {
                // If opening fails, fall back to revealing in Finder
                DispatchQueue.main.async {
                    print("Failed to open video: \(error.localizedDescription)")
                    // Show alert and reveal in Finder
                    let alert = NSAlert()
                    alert.messageText = "Cannot Open Video"
                    alert.informativeText = "The app doesn't have permission to open this file. The file will be revealed in Finder instead.\n\nYou can open it manually from there."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }
    
    private func revealVideoFile(at path: String) {
        // Revealing in Finder works reliably under sandbox
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

/// Saved presets management panel
private struct SavedPresetsPanel: View {
    @ObservedObject var presetStore: PresetStore
    @ObservedObject var settings: UpscaleSettings
    let isProcessing: Bool
    
    @State private var newPresetName: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Saved Presets", systemImage: "bookmark.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Preset name", text: $newPresetName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                            .disabled(isProcessing)
                        
                        Button(action: savePreset) {
                            Label("Save current", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isProcessing || trimmed(newPresetName).isEmpty)
                    }
                    
                    Text("Presets capture all current upscale settings for quick reuse.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    if presetStore.presets.isEmpty {
                        Text("No presets yet. Save one to reuse your favorite configuration.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(presetStore.presets) { preset in
                                PresetRow(
                                    preset: preset,
                                    isProcessing: isProcessing,
                                    onApply: { presetStore.apply(preset, to: settings) },
                                    onOverwrite: { presetStore.update(preset, settings: settings) },
                                    onRename: { newName in presetStore.update(preset, newName: newName) },
                                    onDuplicate: { presetStore.duplicate(preset) },
                                    onDelete: { presetStore.delete(preset) }
                                )
                            }
                        }
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
    }
    
    private func savePreset() {
        let cleaned = trimmed(newPresetName)
        guard !cleaned.isEmpty else { return }
        presetStore.add(name: cleaned, settings: settings)
        newPresetName = ""
    }
    
    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Single preset row with actions
private struct PresetRow: View {
    let preset: Preset
    let isProcessing: Bool
    let onApply: () -> Void
    let onOverwrite: () -> Void
    let onRename: (String) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    @State private var isRenaming = false
    @State private var nameDraft = ""
    @State private var confirmDelete = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isRenaming {
                    TextField("Preset name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitRename)
                } else {
                    Text(preset.name)
                        .font(.subheadline.weight(.medium))
                }
                
                Spacer()
                
                Button(action: toggleRename) {
                    Image(systemName: isRenaming ? "checkmark.circle.fill" : "pencil")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }
            
            HStack(spacing: 8) {
                Button(action: onApply) {
                    Label("Apply", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isProcessing)
                
                Button(action: onOverwrite) {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isProcessing)
                
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(role: .destructive, action: { confirmDelete = true }) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.04))
        .cornerRadius(8)
        .onAppear { nameDraft = preset.name }
        .confirmationDialog("Delete preset?", isPresented: $confirmDelete) {
            Button("Delete \"\(preset.name)\"", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        }
    }
    
    private func toggleRename() {
        if isRenaming {
            commitRename()
        } else {
            nameDraft = preset.name
            isRenaming = true
        }
    }
    
    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isRenaming = false
            return
        }
        onRename(trimmed)
        isRenaming = false
    }
}

// ------------------------------------------------------------
// MARK: - Picture-in-Picture Preview
// ------------------------------------------------------------
private struct PictureInPicturePreview: View {
    let thumbnailImage: NSImage?
    let timelineFrames: [NSImage]
    let selectedFrameIndex: Int
    let onSelectFrame: (Int) -> Void
    @Binding var isVisible: Bool
    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    @State private var isMinimized: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "pip")
                    .foregroundColor(.secondary)
                Text("Preview")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                
                // Minimize button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isMinimized.toggle()
                    }
                }) {
                    Image(systemName: isMinimized ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                // Close button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isVisible = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        accumulatedOffset.width += value.translation.width
                        accumulatedOffset.height += value.translation.height
                        dragOffset = .zero
                    }
            )
            
            if !isMinimized {
                // Preview image
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 280, maxHeight: 160)
                        .cornerRadius(6)
                        .padding(8)
                }
                
                // Mini timeline
                if !timelineFrames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(0..<min(timelineFrames.count, 20), id: \.self) { index in
                                Image(nsImage: timelineFrames[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 30, height: 20)
                                    .clipped()
                                    .cornerRadius(2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(selectedFrameIndex == index ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        onSelectFrame(index)
                                    }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(height: 28)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(width: isMinimized ? 150 : 300)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .offset(x: accumulatedOffset.width + dragOffset.width,
                y: accumulatedOffset.height + dragOffset.height)
        .padding(14)
    }
}

// ------------------------------------------------------------
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

// MARK: - Main ContentView (orchestrates everything)
// ------------------------------------------------------------
struct ContentView: View {
    @StateObject private var runner: UpscaleRunner
    @StateObject private var shortcutsManager = KeyboardShortcutsManager.shared
    @StateObject private var presetStore = PresetStore()
    
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var enlargedFrameImage: NSImage? = nil
    @State private var showEnlargedRestorationFilters: Bool = false
    @State private var showEnlargedColorEqualizer: Bool = false
    @State private var showPiPPreview: Bool = false
    @State private var editorState: EditorState? = nil

    init(runner: UpscaleRunner = UpscaleRunner()) {
        _runner = StateObject(wrappedValue: runner)
    }
    
    var body: some View {
        // ---------- SCROLLABLE CONTENT ----------
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: UI.sectionSpacing) {
                    HeaderView()
                        .zIndex(2)
                    
                    InputSection(inputPath: $runner.inputPath,
                                chooseInput: chooseInput,
                                settings: runner.settings,
                                isProcessingFullUpscale: runner.isRunning,
                                onFrameDoubleTap: { image in
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        enlargedFrameImage = image
                                    }
                                },
                                onRestorationFiltersDrag: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        showEnlargedRestorationFilters = true
                                    }
                                },
                                onColorEqualizerDrag: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        showEnlargedColorEqualizer = true
                                    }
                                },
                                onEditorStateAvailable: { state in
                                    editorState = state
                                })
                    
                    // Responsive two-column layout
                    adaptiveColumnsLayout(geometry: geometry)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, responsiveHorizontalPadding(for: geometry.size.width))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: UI.windowMinWidth, minHeight: UI.windowMinHeight)
        // ---------- TOOLBAR ----------
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .dynamicKeyboardShortcut(actionId: "openSettings") {
                    showSettings = true
                }
                
                Button(action: { showAbout = true }) {
                    Label("About", systemImage: "info.circle")
                }
                .dynamicKeyboardShortcut(actionId: "openAbout") {
                    showAbout = true
                }
            }
        }
        // ---------- SHEETS ----------
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: runner.settings)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        // ---------- ENLARGED FRAME OVERLAY (covers entire app) ----------
        .overlay(
                Group {
                    // Enlarged Color Equalizer Panel
                    if showEnlargedColorEqualizer {
                        EnlargedColorEqualizerPanel(settings: runner.settings, isPresented: $showEnlargedColorEqualizer)
                    }
                    
                    // Enlarged Restoration Filters Panel
                    if showEnlargedRestorationFilters {
                        EnlargedRestorationFiltersPanel(settings: runner.settings, isPresented: $showEnlargedRestorationFilters)
                    }
                    
                    // Enlarged Frame Image
                    if let img = enlargedFrameImage {
                        ZStack {
                            // Semi-transparent background covering entire window
                            Color.black.opacity(0.85)
                                .ignoresSafeArea(.all)
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        enlargedFrameImage = nil
                                    }
                                }
                            
                            // Enlarged image centered
                            VStack {
                                Spacer()
                                
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(40)
                                    .onTapGesture(count: 2) {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            enlargedFrameImage = nil
                                        }
                                    }
                                
                                Spacer()
                                
                                // Hint text
                                HStack {
                                    Text("Double-click to close")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.4))
                                    Text("Press ESC")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.bottom, 20)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .zIndex(10000)  // Very high z-index to ensure it's on top
                        .focusable()
                        .onKeyPress(.escape) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                enlargedFrameImage = nil
                            }
                            return .handled
                        }
                    }
                }
        )
        .onChange(of: runner.inputPath) { _, _ in
            // Reset enlarged frame, restoration filters, and color equalizer when new video is imported
            enlargedFrameImage = nil
            showEnlargedRestorationFilters = false
            showEnlargedColorEqualizer = false
        }
        // Picture-in-Picture Floating Preview
        .overlay(
            Group {
                if showPiPPreview, let state = editorState {
                    PictureInPicturePreview(
                        thumbnailImage: state.thumbnailImage,
                        timelineFrames: state.timelineFrames,
                        selectedFrameIndex: state.selectedFrameIndex,
                        onSelectFrame: { index in
                            state.selectFrame(index)
                        },
                        isVisible: $showPiPPreview
                    )
                }
            }
            , alignment: .bottomTrailing
        )
    }
    
    // ------------------------------------------------------------------------
    // MARK: – Responsive Layout Helpers
    // ------------------------------------------------------------------------
    
    /// Calculates responsive horizontal padding based on window width
    private func responsiveHorizontalPadding(for width: CGFloat) -> CGFloat {
        if width < 800 {
            return 12
        } else if width < 1200 {
            return 16
        } else {
            return 24
        }
    }
    
    /// Adaptive columns layout that responds to window size
    @ViewBuilder
    private func adaptiveColumnsLayout(geometry: GeometryProxy) -> some View {
        let availableWidth = geometry.size.width - (2 * responsiveHorizontalPadding(for: geometry.size.width))
        let useStackedLayout = availableWidth < 680
        
        if useStackedLayout {
            // Stacked layout for narrow windows (half screen, etc.)
            VStack(spacing: 14) {
                leftColumnContent
                rightColumnContent
            }
        } else {
            // Side-by-side layout for wider windows
            HStack(alignment: .top, spacing: UI.columnSpacing) {
                leftColumnContent
                    .frame(
                        minWidth: UI.leftColumnMinWidth,
                        idealWidth: UI.leftColumnIdealWidth,
                        maxWidth: UI.leftColumnMaxWidth
                    )
                
                rightColumnContent
                    .frame(
                        minWidth: UI.rightColumnMinWidth,
                        idealWidth: UI.rightColumnIdealWidth,
                        maxWidth: UI.rightColumnMaxWidth
                    )
            }
        }
    }
    
    /// Left column content - Configuration & AI panels
    private var leftColumnContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Group 1: Configuration & Encoding
            MatteCardGroup(spacing: 8) {
                QualityScalePanel(settings: runner.settings)
                HardwareEncodingPanel(settings: runner.settings)
                X265ParametersPanel(settings: runner.settings)
            }
            
            // Group 2: AI & Restoration
            MatteCardGroup(spacing: 8) {
                AIEnginePanel(settings: runner.settings)
                RestorationPanel(settings: runner.settings)
                RestorationSecondSetPanel(settings: runner.settings)
            }
        }
    }
    
    /// Right column content - Output, Progress & Presets
    private var rightColumnContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Group 3: Output & Controls
            MatteCardGroup(spacing: 8) {
                OutputPanel(outputMode: $runner.outputMode,
                           customOutputFolder: $runner.customOutputFolder,
                           predictedName: runner.predictedOutputName,
                           chooseFolder: chooseOutputFolder)
                
                // PiP Toggle Button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showPiPPreview.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: showPiPPreview ? "pip.exit" : "pip.enter")
                        Text(showPiPPreview ? "Hide PiP" : "Show PiP Preview")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(runner.inputPath.isEmpty)
                
                ActionButtons(runner: runner)
            }
            
            // Group 4: Progress & Status
            MatteCardGroup(spacing: 8) {
                ProgressDetails(runner: runner)
                LogPanel(runner: runner)
            }
            
            // Group 5: Presets
            MatteCardGroup(spacing: 8) {
                SavedPresetsPanel(presetStore: presetStore,
                                  settings: runner.settings,
                                  isProcessing: runner.isRunning)
            }
        }
    }
    
    // ------------------------------------------------------------------------
    // MARK: – File‑picker helpers (UI only, MARKED @MainActor)
    // ------------------------------------------------------------------------
    @MainActor
    private func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            runner.inputPath = url.path
        }
    }
    
    @MainActor
    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK, let url = panel.url {
            runner.customOutputFolder = url.path
            runner.securityScopedOutputURL = url
        }
    }
}

#if DEBUG
#Preview {
    ContentView(runner: .makePreview())
}
#endif
