import SwiftUI
import UniformTypeIdentifiers

private struct ZeroValueIndicator: ViewModifier {
    let isZero: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isZero ? Color.orange.opacity(0.8) : Color.clear, lineWidth: 2)
            )
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isZero ? Color.orange.opacity(0.1) : Color.clear)
            )
    }
}

private extension View {
    func zeroValueIndicator(isZero: Bool) -> some View {
        self.modifier(ZeroValueIndicator(isZero: isZero))
    }
}


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
        TabView {
            aiAndFiltersTab
            shortcutsTab
        }
        .frame(minWidth: UI.minWidth, idealWidth: UI.idealWidth, minHeight: UI.minHeight, idealHeight: UI.idealHeight)
        .background(Color.appBackground)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    settings.resetToDefaults()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .help("Reset all settings to default values")
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
    
    private var aiAndFiltersTab: some View {
        Form {
                Section {
                    Toggle(isOn: $settings.noDeblock)  { Label("Disable Deblock",  systemImage: "xmark.circle") }
                    Toggle(isOn: $settings.noDenoise) { Label("Disable Denoise", systemImage: "xmark.circle") }
                    Toggle(isOn: $settings.noDecimate){ Label("Disable Decimate",systemImage: "xmark.circle") }
                    Toggle(isOn: $settings.noInterpolate){ Label("Disable Interpolate",systemImage: "xmark.circle") }
                    Toggle(isOn: $settings.noSharpen) { Label("Disable Sharpen", systemImage: "xmark.circle") }
                    Toggle(isOn: $settings.noDeband)  { Label("Disable Deband",  systemImage: "xmark.circle") }
                    Toggle(isOn: $settings.noEq)      { Label("Disable EQ",      systemImage: "xmark.circle") }
                    Toggle(isOn: $settings.noGrain)   { Label("Disable Grain",   systemImage: "xmark.circle") }
                    Toggle(isOn: $settings.pciSafe)   { Label("PCI Safe Mode",   systemImage: "shield") }
                } header: {
                    Label("Advanced Toggles", systemImage: "slider.horizontal.below.rectangle")
                        .font(DesignSystem.Typography.headline)
                }
        }
        .formStyle(.grouped)
        .tabItem { Label("Toggles", systemImage: "switch.2") }
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
