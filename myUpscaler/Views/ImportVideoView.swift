import SwiftUI

/// The empty workspace has one clear action; effects appear after import.
struct ImportVideoView: View {
    let isHovered: Bool
    let chooseInput: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Import a video")
                    .font(.title2.weight(.semibold))
            }

            if let chooseInput {
                Button(action: chooseInput) {
                    Label("Browse", systemImage: "folder")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.accentColor.opacity(isHovered ? 0.5 : 0.02))
        .accessibilityElement(children: .contain)
        
    }
}
