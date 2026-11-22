import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: UpscaleSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        KeyboardShortcutsView()
        .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 600)
        .background(Color.appBackground)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
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
