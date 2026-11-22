import AppKit

/// Start-up options that open the app in a given state without clicking: the video to load, the adjustments
/// page, the appearance and the window's content size. Unknown flags and malformed values are ignored.
struct LaunchOptions: Equatable {
    enum Appearance: String { case light, dark }

    var inputPath: String?
    var page: WorkspaceInspector.Page?
    var appearance: Appearance?
    var windowSize: CGSize?

    static let current = LaunchOptions(arguments: CommandLine.arguments)

    /// `--open <path>`, `--page <upscale|restore|cleanup|output>`, `--appearance <light|dark>`, `--window-size <width>x<height>`.
    init(arguments: [String]) {
        let tokens = Array(arguments.dropFirst())
        for (offset, flag) in tokens.enumerated() where offset + 1 < tokens.count {
            let value = tokens[offset + 1]
            switch flag {
            case "--open":
                if !value.isEmpty { inputPath = value }
            case "--page":
                page = WorkspaceInspector.Page.allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }
            case "--appearance":
                appearance = Appearance(rawValue: value.lowercased())
            case "--window-size":
                windowSize = Self.size(value)
            default:
                break
            }
        }
    }

    private static func size(_ text: String) -> CGSize? {
        let parts = text.lowercased().split(separator: "x").map { Double($0) }
        guard parts.count == 2, let width = parts[0], let height = parts[1],
              (320...8000).contains(width), (320...8000).contains(height) else { return nil }
        return CGSize(width: width, height: height)
    }
}
