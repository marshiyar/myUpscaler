import AppKit

@main struct LaunchOptionsTests {
    @MainActor static func main() {
        let none = LaunchOptions(arguments: ["myUpscaler"])
        precondition(none == LaunchOptions(arguments: []) && none.inputPath == nil && none.page == nil
            && none.appearance == nil && none.windowSize == nil, "No arguments leave every option unset")

        let all = LaunchOptions(arguments: ["myUpscaler", "--open", "/tmp/clip.mp4", "--page", "Cleanup",
                                            "--appearance", "LIGHT", "--window-size", "1280x800"])
        precondition(all.inputPath == "/tmp/clip.mp4", "--open sets the input path")
        precondition(all.page == .processor, "--page matches the page title without case")
        precondition(all.appearance == .light, "--appearance matches without case")
        precondition(all.windowSize == CGSize(width: 1280, height: 800), "--window-size reads width x height")

        for page in WorkspaceInspector.Page.allCases {
            let parsed = LaunchOptions(arguments: ["myUpscaler", "--page", page.rawValue.lowercased()])
            precondition(parsed.page == page, "Every page is reachable by its lower-case title")
        }

        let bad = LaunchOptions(arguments: ["myUpscaler", "--page", "nowhere", "--appearance", "sepia",
                                            "--window-size", "10x10", "--open", "", "--unknown", "x"])
        precondition(bad == none, "Unknown pages, appearances, sizes and flags are ignored")
        precondition(LaunchOptions(arguments: ["myUpscaler", "--window-size", "1280"]).windowSize == nil, "A size needs both numbers")
        precondition(LaunchOptions(arguments: ["myUpscaler", "--open"]).inputPath == nil, "A flag without a value is ignored")
        print("PASS launch options: path, page, appearance and window size are read; malformed values are ignored")
    }
}
