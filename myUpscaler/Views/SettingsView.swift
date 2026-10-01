import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: UpscaleSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

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
        TabView(selection: $selectedTab) {
            aiAndFiltersTab.tag(0)
            shortcutsTab.tag(1)
        }
        .frame(minWidth: UI.minWidth, idealWidth: UI.idealWidth, minHeight: UI.minHeight, idealHeight: UI.idealHeight)
        .background(Color.appBackground)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if selectedTab == 0 {
                    Button {
                        settings.resetToDefaults()
                    } label: {
                        Label("Reset processing settings", systemImage: "arrow.counterclockwise")
                    }
                    .help("Reset all processing settings to their defaults")
                }
            }

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

    private func enabled(_ disabled: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { !disabled.wrappedValue }, set: { disabled.wrappedValue = !$0 })
    }

    private var aiAndFiltersTab: some View {
        Form {
            Section {
                RestorationPanel(settings: settings)
                    .environment(\.workspaceInspector, true)
            }
            Section {
                Toggle("Remove near-duplicate frames", isOn: enabled($settings.modes.noDecimate))
                    .disabled(settings.upscaling.scaler == "coreml")
                    .help("FFmpeg Decimate removes near-duplicate frames before output frame-rate conversion.")
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("Processing", systemImage: "switch.2") }
    }

    private var shortcutsTab: some View {
        KeyboardShortcutsView()
            .tabItem { Label("Shortcuts", systemImage: "keyboard") }
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
