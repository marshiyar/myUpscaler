import SwiftUI

// MARK: - UI Constants (Apple‑native sizing)

struct UI {
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

var cardBackground: Color {
    #if os(macOS)
    Color(NSColor.windowBackgroundColor)
    #else
    Color(UIColor.secondarySystemBackground)
    #endif
}


// MARK: - CardStyle Modifier (re‑usable visual style)
struct CardStyle: ViewModifier {
    @Environment(\.workspaceInspector) private var inInspector
    func body(content: Content) -> some View {
        content
            .background(inInspector ? Color.clear : Color.appTertiaryBackground, in: RoundedRectangle(cornerRadius: UI.cardCornerRadius))
    }
}
extension View {
    func cardStyle() -> some View { self.modifier(CardStyle()) }
}

// MARK: - NumberFormatters (static, reused)
enum Formatters {
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
enum SliderGradient {
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


}
