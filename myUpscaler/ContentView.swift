import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers


// MARK: - UI Constants (Apple‑native sizing)

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
    static let buttonHeight: CGFloat = 32
    static let resetButtonWidth: CGFloat = 38
    static let resetButtonStyle = BorderlessButtonStyle()
}


// MARK: - Card background colour (platform safe)

private var cardBackground: Color {
    #if os(macOS)
    Color(NSColor.windowBackgroundColor)
    #else
    Color(UIColor.secondarySystemBackground)
    #endif
}


// MARK: - CardStyle Modifier (re‑usable visual style)
private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(cardBackground)
            .cornerRadius(UI.cardCornerRadius)
            .shadow(color: Color.black.opacity(0.08),
                    radius: UI.cardShadowRadius,
                    x: 0, y: 0.5)
            .padding(.horizontal, 8)
    }
}
private extension View {
    func cardStyle() -> some View { self.modifier(CardStyle()) }
}

// MARK: - NumberFormatters (static, reused)
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


// MARK: - Slider Gradient Colors
private enum SliderGradient {
    case crf          // Quality
    case denoise      // Denoise
    case dering       // Deringing
    case sharpen      // Sharpen
    case contrast     // Contrast
    case brightness   // Brightness
    case saturation   // Saturation
    case scale        // Scale
    case usmRadius    // Unsharp radius
    case usmAmount    // Unsharp amount
    case usmThreshold  // Unsharp threshold
    
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

// MARK: - Custom Slider
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

// MARK: - Sub‑views (each block is its own struct)
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
        // MARK: -  ---------- ENLARGED FRAME OVERLAY (covers entire app) ----------
        .overlay(
                Group {
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
    }
    
    
    // MARK: – Responsive Layout Helpers
    
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
    
    // MARK: -  File‑picker helpers (UI only, MARKED @MainActor)
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
