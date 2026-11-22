import SwiftUI

struct AIEnginePanel: View {
    @ObservedObject var settings: UpscaleSettings

    var body: some View {
        InspectorSection {
            InspectorRow(title: "Upscaling") {
                Picker("Upscaling", selection: $settings.upscalingChoice) {
                    if let selected = settings.upscalingChoice, !settings.availableUpscalingChoices.contains(selected) {
                        Text("\(selected.menuName) (unavailable)").tag(Optional(selected)).disabled(true)
                    } else if settings.upscalingChoice == nil {
                        Text("Choose upscaling").tag(Optional<UpscalingChoice>.none).disabled(true)
                    }
                    ForEach(settings.availableUpscalingChoices) { choice in
                        Text(choice.menuName).tag(Optional(choice))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            if let reason = settings.upscalingUnavailableReason {
                InspectorNote(reason, tint: .orange)
            }
        }
    }
}

extension UpscalingChoice {
    /// The name in the Upscaling menu. `displayName` stays the model's own name, which the processing log uses.
    var menuName: String {
        switch self {
        case .lanczos: return "Standard"
        case .model(let id):
            return CoreMLModelRegistry.model(for: id).displayName
                .replacingOccurrences(of: #"^Real-ESRGAN x(\d+)"#, with: "AI $1x", options: .regularExpression)
        }
    }
}
