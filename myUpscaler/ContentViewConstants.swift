import SwiftUI

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