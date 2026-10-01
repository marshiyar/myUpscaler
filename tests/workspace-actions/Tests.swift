import AppKit
import SwiftUI

@main struct WorkspaceActionTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let runner = UpscaleRunner()
        runner.inputPath = "/tmp/workspace-action-fixture.mp4"
        runner.settings.upscaling.scaler = "lanczos"
        var runs = 0, cancellations = 0
        let dispatcher = CommandDispatcher()
        dispatcher.configure([
            .runUpscaler: .init(isEnabled: { !runner.isRunning }, perform: { runs += 1 }),
            .cancel: .init(isEnabled: { runner.isRunning && !runner.isCancelling },
                perform: { cancellations += 1; runner.cancel() })
        ])
        let content = ActionButtons(runner: runner, settings: runner.settings,
            run: { dispatcher.perform(.runUpscaler) }, cancel: { dispatcher.perform(.cancel) })
        // Host the actual production view without environment objects. This window
        // is never ordered or activated, preserving other apps' focus and UI state.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: content)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        precondition(host.bounds.width > 0 && host.bounds.height > 0)
        precondition(runner.settings.upscalingUnavailableReason == nil)
        // Explicitly invoke the injected production actions. Native accessibility
        // buttons and mouse presses are unavailable in this invisible host; these
        // assertions test dependency injection/dispatch, not native click delivery.
        content.run()
        precondition(runs == 1, "Injected export action must dispatch once")
        runner.isRunning = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        host.layoutSubtreeIfNeeded()
        content.run()
        precondition(runs == 1, "An active export must block repeated export commands")
        content.cancel()
        precondition(cancellations == 1 && runner.isCancelling,
            "Injected cancel action must enter guarded cancellation")
        content.cancel()
        precondition(cancellations == 1, "Repeat cancellation must remain guarded")
        print("PASS production ActionButtons layout without environment objects; explicit export/cancel callbacks and live dispatcher guards")
        print("UNVERIFIED native button presses: invisible SwiftUI host exposes no accessibility buttons and does not deliver synthetic mouse actions")
    }
}
