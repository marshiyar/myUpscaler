import SwiftUI

// MARK: - UI Constants

struct UI {
    static let rowSpacing: CGFloat = 8             // space inside a group of rows
    static let windowMinHeight: CGFloat = 600
    static let buttonHeight: CGFloat = 32
    static let resetButtonStyle = BorderlessButtonStyle()
}

// MARK: - NumberFormatters (static, reused)
enum Formatters {
    private static func make(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter
    }
    static let twoFraction = make(fractionDigits: 2)
    static let threeFraction = make(fractionDigits: 3)
    static let oneFraction = make(fractionDigits: 1)
    static let integer = make(fractionDigits: 0)
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
