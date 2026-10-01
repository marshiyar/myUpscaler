import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: UpscaleSettings
    @Environment(\.dismiss) private var dismiss

    private struct UI {
        static let cornerRadius: CGFloat = 12
        static let spacing: CGFloat      = 16
        static let accentColor = Color.accentColor
        static let minWidth: CGFloat = 500
        static let minHeight: CGFloat = 500
        static let idealWidth: CGFloat = 600
        static let idealHeight: CGFloat = 600
    }

    var body: some View {
        KeyboardShortcutsView()
        .frame(minWidth: UI.minWidth, idealWidth: UI.idealWidth, minHeight: UI.minHeight, idealHeight: UI.idealHeight)
        .background(Color.appBackground)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }


}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsView(settings: UpscaleSettings.mock())
                .preferredColorScheme(.light)

            SettingsView(settings: UpscaleSettings.mock())
                .preferredColorScheme(.dark)
        }
    }
}
