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
            #if DEBUG
            if shouldRunTests {
                TestDashboardView()
                    .frame(minWidth: 800, minHeight: 600)
                    .task {
                        let vm = TestDashboardViewModel()
                        await vm.runFuzzer()
                        await vm.runPerformance()
                    }
            } else {
                ContentView()
                    .frame(minWidth: 800, minHeight: 600)
            }
            #else
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
            #endif
        }
        .defaultSize(width: 950, height: 800)
        .windowResizability(.contentSize)
        .commands {
            #if DEBUG
            CommandMenu("Debug") {
                Button("Open Test Dashboard") {
                    openTestDashboard()
                }
            }
            #endif
        }
    }
    
    func openTestDashboard() {
        #if DEBUG
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.center()
        window.title = "Test Dashboard"
        window.contentView = NSHostingView(rootView: TestDashboardView())
        window.makeKeyAndOrderFront(nil)
        #endif
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if getenv("UP60P_FFMPEG") == nil {
            setenv("UP60P_FFMPEG", "/opt/homebrew/bin/ffmpeg", 1)
        }
        #endif

        setenv("MTL_SHADER_VALIDATION", "0", 1)
        setenv("MTL_DEBUG_LAYER", "0", 1)
        setenv("AIR_Diagnostics", "0", 1)
        setenv("MTL_COMPILER_LOG_LEVEL", "0", 1)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.fixBlankWindows()
        }
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
