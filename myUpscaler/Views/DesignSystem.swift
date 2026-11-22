import SwiftUI

extension Color {
    static let appBackground = Color(NSColor.windowBackgroundColor)
    static let appTertiaryBackground = Color(NSColor.textBackgroundColor)
}

/// A group of rows without a box of its own: the label above its content.
struct ModernGroupBoxStyle: GroupBoxStyle {
    @Environment(\.workspaceInspector) private var inInspector
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            configuration.content
        }
        .padding(inInspector ? 0 : 16)
    }
}

private struct WorkspaceInspectorKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var workspaceInspector: Bool {
        get { self[WorkspaceInspectorKey.self] }
        set { self[WorkspaceInspectorKey.self] = newValue }
    }
}

/// Names shown in menus for values the settings store under their own keys; the keys do not change.
enum DisplayName {
    static func denoiser(_ value: String) -> String {
        value == "atadenoise" ? "Across frames" : value
    }

    static func sharpenMethod(_ value: String) -> String {
        switch value {
        case "cas": return "Adaptive"
        case "unsharp": return "Classic"
        default: return value
        }
    }
}
