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
                Text("Start with a video")
                    .font(.title2.weight(.semibold))
                Text("Drop a video here, or choose a video or batch folder.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let chooseInput {
                Button(action: chooseInput) {
                    Label("Browse files…", systemImage: "folder")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            HStack(spacing: 20) {
                Label("Import", systemImage: "1.circle")
                Label("Adjust & preview", systemImage: "2.circle")
                Label("Export", systemImage: "3.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.accentColor.opacity(isHovered ? 0.08 : 0.02))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(isHovered ? 0.7 : 0.14), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
        .accessibilityElement(children: .contain)
    }
}
