import SwiftUI
import AppKit
import AVFoundation
import Combine
import CoreImage
import Metal
import MetalKit
import UniformTypeIdentifiers

// EditorState moved to EditorState.swift

// MARK: - TIMELINE VIEW
struct TimelineView: View {
    @ObservedObject var state: EditorState
    @Namespace private var ns
    @State private var hoverIndex: Int?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 4) {
                    ForEach(state.timelineFrames.indices, id: \.self) { i in
                        thumbnail(i)
                            .id(i)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onChange(of: state.selectedFrameIndex) { _, idx in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
        .modifier(KeyboardNavigationModifier(selectedIndex: $state.selectedFrameIndex,
                                             maxIndex: state.timelineFrames.count - 1,
                                             select: state.selectFrame))
    }
    
    private func thumbnail(_ index: Int) -> some View {
        let selected = (index == state.selectedFrameIndex)
        return ZStack(alignment: .topLeading) {
            
            Image(nsImage: state.timelineFrames[index])
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 70, height: 45)
                .cornerRadius(3)
            
            RoundedRectangle(cornerRadius: 3)
                .stroke(selected ? Color.accentColor : Color.gray.opacity(0.3),
                        lineWidth: selected ? 3 : 1)
                .matchedGeometryEffect(id: "sel", in: ns, isSource: selected)
                .frame(width: 70, height: 45)
                .shadow(color: selected ? Color.accentColor.opacity(0.6) : .clear,
                        radius: selected ? 6 : 0)
            
            Text("\(index + 1)")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(selected ?
                            Color.accentColor.opacity(0.9) :
                                Color.primary.opacity(0.7))
                .cornerRadius(2)
                .padding(4)
        }
        .scaleEffect(selected ? 1.07 : (hoverIndex == index ? 1.02 : 1))
        .onHover { hoverIndex = $0 ? index : nil }
        .onTapGesture { state.selectFrame(index) }
        .help(state.formatTime(state.timelineFrameTimes[index]))
        
        .focusable(false)
    }
}

//// MARK: - FILTER PANEL
//struct FilterPanel: View {
//    @ObservedObject var state: EditorState
//
//    var body: some View {
//        Form {
//            Section(header: Text("Color")) {
//                LabeledSlider("Contrast", value: $state.contrast, range: 0.5...2.0)
//                LabeledSlider("Brightness", value: $state.brightness, range: -0.3...0.3, format: "%.3f")
//                LabeledSlider("Saturation", value: $state.saturation, range: 0...2)
//            }
//
//            Section(header: Text("Noise")) {
//                LabeledSlider("Denoise", value: $state.denoiseStrength, range: 0...5)
//                Toggle("Ring-removal", isOn: $state.deringActive)
//                if state.deringActive {
//                    LabeledSlider("Ring strength", value: $state.deringStrength, range: 0...1)
//                }
//            }
//
//            Section(header: Text("Sharpen")) {
//                Picker("Method", selection: $state.sharpenMethod) {
//                    Text("CAS").tag("cas")
//                    Text("Unsharp").tag("unsharp")
//                }
//                .pickerStyle(.segmented)
//
//                LabeledSlider("Strength", value: $state.sharpenStrength, range: 0...1)
//
//                if state.sharpenMethod == "unsharp" {
//                    LabeledSlider("Radius", value: $state.usmRadius, range: 0...10)
//                    LabeledSlider("Amount", value: $state.usmAmount, range: 0...3)
//                }
//            }
//        }
//        .frame(maxHeight: 350)
//    }
//}

// MARK: - SUPPORT VIEWS
struct DropArea: View {
    @Binding var isHovered: Bool
    @Binding var filePath: String
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isHovered ? Color.accentColor : Color.secondary, lineWidth: 2)
            .overlay(Text("Drop video here"))
            .onDrop(of: [UTType.fileURL], isTargeted: $isHovered) { providers in
                return handleDrop(providers)
            }
    }
    
    // Helper to avoid closure capture issues with 'self'
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    self.filePath = url.path
                }
            } else if let url = item as? URL {
                DispatchQueue.main.async {
                    self.filePath = url.path
                }
            }
        }
        return true
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"
    
    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String = "%.2f") {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(title): \(String(format: format, value))")
                .font(.caption)
            Slider(value: $value, in: range)
        }
        .padding(.vertical, 4)
    }
}

struct KeyboardNavigationModifier: ViewModifier {
    @Binding var selectedIndex: Int
    let maxIndex: Int
    let select: (Int) -> Void
    
    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .modifier(KeyPressHandler(selectedIndex: $selectedIndex,
                                      maxIndex: maxIndex,
                                      select: select))
    }
}

struct KeyPressHandler: ViewModifier {
    @Binding var selectedIndex: Int
    let maxIndex: Int
    let select: (Int) -> Void
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.upArrow) {
                    if selectedIndex > 0 { select(selectedIndex - 1) }
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if selectedIndex < maxIndex { select(selectedIndex + 1) }
                    return .handled
                }
        } else {
            content
        }
    }
}

// MARK: - FORMATTERS
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

// MARK: - Slider Gradient Colors (for DragDropView)
private enum CompactSliderGradient {
    case denoise      // Denoise - cool cyan to blue (clean, smooth)
    case dering       // Deringing - teal to green (healing, correction)
    case sharpen      // Sharpen - bright yellow to white (sharp, crisp)
    case contrast     // Contrast - purple to pink (vibrant, dynamic)
    case brightness   // Brightness - yellow to white (light, bright)
    case saturation   // Saturation - rainbow colors (colorful, rich)
    case usmRadius    // Unsharp radius - orange to yellow (focused)
    case usmAmount    // Unsharp amount - red to orange (intense)
    case usmThreshold  // Unsharp threshold - pink to purple (precise)
    
    var gradient: LinearGradient {
        switch self {
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

// MARK: - COMPACT SLIDER
private struct CompactSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let gradient: CompactSliderGradient
    var onEditingChanged: ((Bool) -> Void)? = nil
    
    var body: some View {
        GeometryReader { geometry in
            let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbPosition = progress * geometry.size.width
            let trackHeight: CGFloat = 6
            let thumbSize: CGFloat = 14
            
            ZStack(alignment: .leading) {
                // Background track (larger)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: trackHeight)
                
                // Filled track with custom gradient (larger)
                RoundedRectangle(cornerRadius: 3)
                    .fill(gradient.gradient)
                    .frame(width: max(0, min(geometry.size.width, thumbPosition)))
                    .frame(height: trackHeight)
                
                // Thumb/indicator (visible, easier to grab)
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(gradient.gradient, lineWidth: 1.5)
                    )
                    .offset(x: max(thumbSize/2, min(geometry.size.width - thumbSize/2, thumbPosition - thumbSize/2)))
            }
            .frame(height: trackHeight)
            .padding(.vertical, 6) // Extra padding for easier grabbing
            .drawingGroup() // Offload rendering to GPU to prevent Main Thread hangs
            .contentShape(Rectangle())
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
        .frame(height: 24) // Increased from 16 to 24 for better accessibility
    }
}

// MARK: - VERTICAL COLOR EQUALIZER PANEL
private struct VerticalColorEqualizerPanel: View {
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
            
            GroupBox {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    VerticalParameterRow(
                        title: "Contrast",
                        binding: $settings.eqContrast,
                        range: 0.5...2.0,
                        step: 0.005,
                        defaultValue: 1.03,
                        formatter: DragDropFormatters.twoFraction,
                        gradient: .contrast
                    )
                    
                    VerticalParameterRow(
                        title: "Brightness",
                        binding: $settings.eqBrightness,
                        range: -0.1...0.1,
                        step: 0.005,
                        defaultValue: 0.005,
                        formatter: DragDropFormatters.threeFraction,
                        gradient: .brightness
                    )
                    
                    VerticalParameterRow(
                        title: "Saturation",
                        binding: $settings.eqSaturation,
                        range: 0...2,
                        step: 0.005,
                        defaultValue: 1.06,
                        formatter: DragDropFormatters.twoFraction,
                        gradient: .saturation
                    )
                }
                .padding(6)
            }
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

// MARK: - VERTICAL PARAMETER ROW
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
    
    private var isZero: Bool {
        displayValue == 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack {
                Text(title)
                    .font(DesignSystem.Typography.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    if isZero {
                        Circle()
                            .fill(Color.orange.opacity(0.6))
                            .frame(width: 4, height: 4)
                    }
                    Text(formatter.string(from: NSNumber(value: displayValue)) ?? "")
                        .font(DesignSystem.Typography.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(isZero ? .orange.opacity(0.8) : .primary)
                }
                .frame(width: 35, alignment: .trailing)
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
                .help("Reset to default")
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}

// MARK: - TRANSPARENT SCROLL VIEW WRAPPER
private struct TransparentScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let showsIndicators: Bool
    
    init(showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = showsIndicators
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        
        let hostingView = NSHostingView(rootView: content)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Size the hosting view to fit its content
        hostingView.setFrameSize(hostingView.fittingSize)
        
        scrollView.documentView = hostingView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        nsView.hasVerticalScroller = showsIndicators
        nsView.drawsBackground = false
        nsView.backgroundColor = .clear
        nsView.borderType = .noBorder
        nsView.scrollerStyle = .overlay
        
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.setFrameSize(hostingView.fittingSize)
        }
    }
}

// MARK: - SCROLL VIEW BACKGROUND MODIFIER
private struct TransparentScrollViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(TransparentScrollViewBackground())
    }
}

private struct TransparentScrollViewBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

extension View {
    func transparentScrollViewBackground() -> some View {
        self.modifier(TransparentScrollViewModifier())
    }
}

// MARK: - VERTICAL RESTORATION FILTERS PANEL
private struct VerticalRestorationFiltersPanel: View {
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
                        
                        // Sharpen method picker
                        Picker("Method", selection: $settings.sharpenMethod) {
                            Text("CAS").tag("cas")
                            Text("Unsharp").tag("unsharp")
                        }
                        .pickerStyle(.menu)
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
                            
                            VerticalParameterRow(
                                title: "Amount",
                                binding: $settings.usmAmount,
                                range: -2...5,
                                step: 0.01,
                                defaultValue: 1.0,
                                formatter: DragDropFormatters.twoFraction,
                                gradient: .usmAmount
                            )
                            
                            VerticalParameterRow(
                                title: "Threshold",
                                binding: $settings.usmThreshold,
                                range: 0...1,
                                step: 0.001,
                                defaultValue: 0.03,
                                formatter: DragDropFormatters.threeFraction,
                                gradient: .usmThreshold
                            )
                        }
                    }
                    .padding(6)
                    }
                    .background(Color(nsColor: NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                    .padding(.trailing, 10)
                }
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.95),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
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

// MARK: - MAIN VIEW
struct DragDropView: View {
    @StateObject private var state: EditorState
    @Binding var externalInputPath: String
    let settings: UpscaleSettings?
    let chooseInput: (() -> Void)?
    var isProcessingFullUpscale: Bool = false
    var onFrameDoubleTap: ((NSImage?) -> Void)? = nil
    var onRestorationFiltersDrag: (() -> Void)? = nil
    var onColorEqualizerDrag: (() -> Void)? = nil
    var onEditorStateAvailable: ((EditorState) -> Void)? = nil  // Callback to provide EditorState to parent
    
    init(externalInputPath: Binding<String>, settings: UpscaleSettings? = nil, chooseInput: (() -> Void)? = nil, isProcessingFullUpscale: Bool = false, onFrameDoubleTap: ((NSImage?) -> Void)? = nil, onRestorationFiltersDrag: (() -> Void)? = nil, onColorEqualizerDrag: (() -> Void)? = nil, onEditorStateAvailable: ((EditorState) -> Void)? = nil) {
        self._externalInputPath = externalInputPath
        self.settings = settings
        self.chooseInput = chooseInput
        self.isProcessingFullUpscale = isProcessingFullUpscale
        self.onFrameDoubleTap = onFrameDoubleTap
        self.onRestorationFiltersDrag = onRestorationFiltersDrag
        self.onColorEqualizerDrag = onColorEqualizerDrag
        self.onEditorStateAvailable = onEditorStateAvailable
        _state = StateObject(wrappedValue: EditorState(settings: settings))
    }
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 600
            let sidePanelWidth: CGFloat = isCompact ? 120 : 140
            let timelineWidth: CGFloat = isCompact ? 70 : 90
            
            VStack(spacing: DesignSystem.Spacing.sm) {
              
                HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                    // Left side: Color Equalizer (centered vertically)
                    if let settings = settings {
                        VStack(alignment: .leading, spacing: 6) {
                            VerticalColorEqualizerPanel(settings: settings, onDragToEnlarge: onColorEqualizerDrag)
                            
                            if let chooseInput = chooseInput {
                                Button(action: chooseInput) {
                                    Label("Browse Files", systemImage: "folder.fill")
                                        .font(DesignSystem.Typography.caption1)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .frame(width: sidePanelWidth)
                                .dynamicKeyboardShortcut(actionId: "chooseInput", action: chooseInput)
                            }
                        }
                        .frame(width: sidePanelWidth)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    ZStack {
                 
                        if let img = state.thumbnailImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(10)
                                .shadow(radius: 3)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onTapGesture(count: 2) {
                                    onFrameDoubleTap?(img)
                                }
                        } else {
                            EmptyStateView(
                                icon: "video.fill",
                                title: "Drop a video",
                                message: ""
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 200)
                    .layoutPriority(1) // Give center area priority for remaining space
//                    .clipped() // Ensure nothing overflows
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.25))
                    )
                    
                    if let settings = settings {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                         
                            VerticalRestorationFiltersPanel(settings: settings, onDragToEnlarge: onRestorationFiltersDrag)
                                .frame(width: sidePanelWidth)
                            
                            // Timeline
                            TimelineView(state: state)
                                .frame(width: timelineWidth)
                                .frame(maxHeight: .infinity)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    } else {
                        // Timeline only (if no settings)
                        TimelineView(state: state)
                            .frame(width: timelineWidth)
                            .frame(maxHeight: .infinity)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .padding(DesignSystem.Spacing.sm)
        }
        .background(Color.appBackground.opacity(0.3))
        .onDrop(of: [UTType.fileURL], isTargeted: $state.isHovered) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        self.state.filePath = url.path
                    }
                } else if let url = item as? URL {
                    DispatchQueue.main.async {
                        self.state.filePath = url.path
                    }
                }
            }
            return true
        }
        .onChange(of: externalInputPath) { _, newPath in
            
            if state.filePath != newPath {
                state.filePath = newPath
            }
        }
        .onChange(of: state.filePath) { _, newPath in
            
            if externalInputPath != newPath {
                externalInputPath = newPath
            }
        }
        .onChange(of: isProcessingFullUpscale) { _, isProcessing in
            state.setProcessingFullUpscale(isProcessing)
        }
        .onAppear {
            state.setProcessingFullUpscale(isProcessingFullUpscale)
            onEditorStateAvailable?(state)
        }
    }
}
