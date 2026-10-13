import SwiftUI

struct AboutView: View {

    private let websiteURL = URL(string: "https://github.com/marshiyar/myUpscaler")!
    @Environment(\.dismiss) private var dismiss
    private var version: String {
        let release = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(release) (\($0))" } ?? release
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {

            Image("AppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                .shadow(
                    color: DesignSystem.Shadow.medium.color,
                    radius: DesignSystem.Shadow.medium.radius,
                    x: DesignSystem.Shadow.medium.x,
                    y: DesignSystem.Shadow.medium.y
                )

            Text("MyUpscaler")
                .font(DesignSystem.Typography.title1)
                .foregroundColor(.accentColor)

            Text("Version \(version)")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(.secondary)

            ModernDivider()
                .padding(.vertical, DesignSystem.Spacing.xs)

            Text("To be filled by Arshiya himself")
                .font(DesignSystem.Typography.body)
                .foregroundColor(.primary)

            Spacer(minLength: DesignSystem.Spacing.xl)

            // ── External link (styled as a button) ───────────────
            Link(destination: websiteURL) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "globe")
                        .font(DesignSystem.Typography.headline)
                    Text("Visit GitHub Repository")
                        .font(DesignSystem.Typography.subheadlineMedium)
                }
                .padding(.vertical, DesignSystem.Spacing.sm)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(Color.accentColor.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    }
            }

            Button(action: {
                dismiss()
            }) {
                HStack {
                    Spacer()
                    Text("Close")
                        .font(DesignSystem.Typography.subheadlineMedium)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .foregroundColor(.primary)

        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.xl)
        .frame(minWidth: 400, idealWidth: 450, minHeight: 450, idealHeight: 500)
        .background(Color.appBackground)
    }
}
// MARK: - Preview
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AboutView()
                .preferredColorScheme(.light)

            AboutView()
                .preferredColorScheme(.dark)
        }
    }
}
