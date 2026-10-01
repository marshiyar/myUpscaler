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
                    Toggle("Deblock", isOn: enabled($settings.noDeblock)).disabled(settings.scaler == "coreml")
                    Toggle("Denoise", isOn: enabled($settings.noDenoise))
                    Toggle("Decimate", isOn: enabled($settings.noDecimate)).disabled(settings.scaler == "coreml")
                    Toggle("Frame interpolation", isOn: enabled($settings.noInterpolate)).disabled(settings.scaler == "coreml")
                    Toggle("Sharpen", isOn: enabled($settings.noSharpen))
                    Toggle("Deband", isOn: enabled($settings.noDeband))
                    Toggle("Color equalizer", isOn: enabled($settings.noEq)).disabled(settings.scaler == "coreml")
                    Toggle("Grain", isOn: enabled($settings.noGrain)).disabled(settings.scaler == "coreml")
                    Toggle(isOn: $settings.pciSafe) { Label("PCI Safe Mode", systemImage: "shield") }
                        .disabled(settings.scaler == "coreml")
                        .help("Forces 8-bit pixel output in FFmpeg")
                } header: {
                    Label("Enabled processing stages", systemImage: "slider.horizontal.below.rectangle")
                        .font(DesignSystem.Typography.headline)
                } footer: {
                    Text(settings.scaler == "coreml" ? "Core ML supports primary denoise, sharpen, and deband. Other stages apply to FFmpeg only." : "A stage is applied only when enabled. Its parameters are available in the video workspace.")
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
