import SwiftUI
import AppKit


@main
//struct myUpscalerApp: App {
//    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
//    
//    var body: some Scene {
//        WindowGroup {
//            ContentView()
//                .frame(minWidth: 800, minHeight: 600)
//        }
//        .defaultSize(width: 950, height: 800)
//        .windowResizability(.contentSize)
//    }
//}
//
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let exeURL = Bundle.main.executableURL {
            let ffmpegURL = exeURL
                .deletingLastPathComponent()
                .appendingPathComponent("ffmpeg")
            if FileManager.default.isExecutableFile(atPath: ffmpegURL.path) {
                setenv("UP60P_FFMPEG", ffmpegURL.path, 1)
            }
        }
        
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
