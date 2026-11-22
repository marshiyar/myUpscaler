import SwiftUI
import AppKit

@main
struct myUpscalerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var shouldRunTests: Bool {
        CommandLine.arguments.contains("--test-all")
    }

    var body: some Scene {
        WindowGroup {

            ContentView()
                .frame(minWidth: 720, minHeight: 664)
                .navigationTitle("myUpscaler")
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands { UpscalerCommands() }
    }

    func openTestDashboard() {

    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        up60p_shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setenv("MTL_SHADER_VALIDATION", "0", 1)
        setenv("MTL_DEBUG_LAYER", "0", 1)
        setenv("AIR_Diagnostics", "0", 1)
        setenv("MTL_COMPILER_LOG_LEVEL", "0", 1)

        switch LaunchOptions.current.appearance {
        case .light?: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark?: NSApp.appearance = NSAppearance(named: .darkAqua)
        case nil: break
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.fixBlankWindows()
            self.applyLaunchWindowSize()
        }
    }

    private func applyLaunchWindowSize() {
        guard let size = LaunchOptions.current.windowSize,
              let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.frame.width >= 150 }) else { return }
        window.setContentSize(size)
        window.center()
    }

    private func fixBlankWindows() {
        let windows = NSApplication.shared.windows

        for window in windows where window.frame.width < 150 || window.frame.height < 150 {
            window.close()
        }

        if NSApplication.shared.windows.isEmpty {
            NotificationCenter.default.post(name: NSNotification.Name("CreateNewWindow"), object: nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
