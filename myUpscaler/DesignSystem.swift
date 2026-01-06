import SwiftUI

struct DesignSystem {
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
        static let xxxl: CGFloat = 48
    }
    struct Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title1 = Font.system(size: 28, weight: .bold, design: .default)
        static let title2 = Font.system(size: 22, weight: .bold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 17, weight: .semibold, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let subheadlineMedium = Font.system(size: 15, weight: .medium, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let footnoteMedium = Font.system(size: 13, weight: .medium, design: .default)
        static let caption1 = Font.system(size: 12, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
        static let monospaced = Font.system(size: 11, weight: .regular, design: .monospaced)
    }
    
    struct CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xlarge: CGFloat = 16
    }
    
    struct Shadow {
        static let small = ShadowStyle(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        static let medium = ShadowStyle(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        static let large = ShadowStyle(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
        
        struct ShadowStyle {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }
}

extension Color {
    static let appBackground = Color(NSColor.windowBackgroundColor)
    static let appSecondaryBackground = Color(NSColor.controlBackgroundColor)
    static let appTertiaryBackground = Color(NSColor.textBackgroundColor)
    static let appAccent = Color.accentColor
    static let appAccentSecondary = Color.accentColor.opacity(0.7)
}

struct ModernCardStyle: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    
    init(padding: CGFloat = DesignSystem.Spacing.md, cornerRadius: CGFloat = DesignSystem.CornerRadius.large) {
        self.padding = padding
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.appSecondaryBackground)
                    .shadow(
                        color: DesignSystem.Shadow.small.color,
                        radius: DesignSystem.Shadow.small.radius,
                        x: DesignSystem.Shadow.small.x,
                        y: DesignSystem.Shadow.small.y
                    )
            }
    }
}

extension View {
    func modernCard(padding: CGFloat = DesignSystem.Spacing.md, cornerRadius: CGFloat = DesignSystem.CornerRadius.large) -> some View {
        modifier(ModernCardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DesignSystem.Typography.headline)
            .foregroundColor(.primary)
            .textCase(nil)
    }
}

extension View {
    func sectionHeader() -> some View {
        modifier(SectionHeaderStyle())
    }
}

struct ModernLabelStyle: ViewModifier {
    let icon: String
    let size: CGFloat
    
    init(icon: String, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }
    
    func body(content: Content) -> some View {
        Label {
            content
        } icon: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.accentColor)
        }
    }
}

extension View {
    func modernLabel(icon: String, size: CGFloat = 16) -> some View {
        modifier(ModernLabelStyle(icon: icon, size: size))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.subheadlineMedium)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(Color.accentColor)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.subheadlineMedium)
            .foregroundColor(.accentColor)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(Color.accentColor.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle {
        PrimaryButtonStyle()
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle {
        SecondaryButtonStyle()
    }
}

struct ModernGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            configuration.label
                .font(DesignSystem.Typography.subheadlineMedium)
                .foregroundColor(.secondary)
            configuration.content
        }
        .padding(DesignSystem.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color.appTertiaryBackground)
        }
    }
}

extension GroupBoxStyle where Self == ModernGroupBoxStyle {
    static var modern: ModernGroupBoxStyle {
        ModernGroupBoxStyle()
    }
}

struct ModernDivider: View {
    var body: some View {
        Divider()
            .background(Color.secondary.opacity(0.2))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(DesignSystem.Typography.title3)
                .foregroundColor(.primary)
            
            Text(message)
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
struct LoadingView: View {
    var body: some View {
        ProgressView()
            .scaleEffect(1.2)
            .padding(DesignSystem.Spacing.lg)
    }
}

