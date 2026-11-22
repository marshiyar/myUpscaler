import SwiftUI

/// The empty workspace has one action; effects appear after import.
struct ImportVideoView: View {
    let isHovered: Bool
    let chooseInput: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(isHovered ? "Drop to import" : "Import a video")
                .font(.title3)
            if let chooseInput {
                Button("Browse", action: chooseInput)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isHovered { Rectangle().stroke(Color.accentColor, lineWidth: 2) }
        }
        .accessibilityElement(children: .contain)
    }
}
