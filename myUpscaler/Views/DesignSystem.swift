import SwiftUI

extension Color {
    static let appBackground = Color(NSColor.windowBackgroundColor)
    static let appTertiaryBackground = Color(NSColor.textBackgroundColor)
}

/// One section of the inspector or of a settings page: a plain title over flat rows. Sections are separated by one
/// `Divider`, and nothing is boxed.
struct InspectorSection<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: UI.rowSpacing) {
            if let title { Text(title).font(.headline) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The label on the left, its control on the right. Every label in the inspector is `.body`.
struct InspectorRow<Control: View>: View {
    let title: String
    var enabled = true
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body)
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 22)
    }
}

/// A switch row: the label on the left, the switch on the right.
struct InspectorSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        InspectorRow(title: title, enabled: enabled) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!enabled)
        }
    }
}

/// A note under a control.
struct InspectorNote: View {
    let text: String
    var tint: Color = .secondary

    init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A short field with its label to the left.
struct InspectorField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var enabled = true
    var width: CGFloat = 60

    var body: some View {
        InspectorRow(title: title, enabled: enabled) {
            TextField(placeholder, text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .disabled(!enabled)
                .accessibilityLabel(title)
        }
    }
}

/// Names shown in menus for values the settings store under their own keys; the keys do not change.
enum DisplayName {
    /// The denoisers in the order the menus list them: fastest first.
    static let denoiserOrder = ["hqdn3d", "bm3d", "nlmeans", "atadenoise"]

    static func orderedDenoisers(_ values: [String]) -> [String] {
        values.sorted { (denoiserOrder.firstIndex(of: $0) ?? .max) < (denoiserOrder.firstIndex(of: $1) ?? .max) }
    }

    /// Fast, Balanced and Slow name the three denoisers by speed.
    static func denoiser(_ value: String) -> String {
        switch value {
        case "hqdn3d": return "Fast"
        case "bm3d": return "Balanced"
        case "nlmeans": return "Slow"
        case "atadenoise": return "Across frames"
        default: return value
        }
    }

    static func deblockMode(_ value: String) -> String {
        switch value {
        case "weak": return "Weak"
        case "strong": return "Strong"
        default: return value
        }
    }

    static func hardwareDecoding(_ value: String) -> String {
        switch value {
        case "videotoolbox": return "Mac"
        case "none": return "None"
        default: return value
        }
    }

    static func sharpenMethod(_ value: String) -> String {
        switch value {
        case "cas": return "Adaptive"
        case "unsharp": return "Classic"
        default: return value
        }
    }
}
