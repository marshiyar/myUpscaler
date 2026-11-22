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
