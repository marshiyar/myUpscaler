import SwiftUI

struct AboutView: View {

    private let websiteURL = URL(string: "https://github.com/marshiyar/myUpscaler")!
    @Environment(\.dismiss) private var dismiss
    private var version: String {
        let release = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(release) (\($0))" } ?? release
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image("AppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("myUpscaler")
                        .font(.title2.weight(.semibold))
                    Text("Version \(version)")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Upscale and restore video on Mac and Windows.")
            HStack {
                Link("GitHub repository", destination: websiteURL)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color.appBackground)
    }
}
// MARK: - Preview
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AboutView()
                .preferredColorScheme(.light)

            AboutView()
                .preferredColorScheme(.dark)
        }
    }
}
