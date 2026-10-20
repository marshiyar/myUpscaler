import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct TransparentScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let showsIndicators: Bool

    init(showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = showsIndicators
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let hostingView = NSHostingView(rootView: content)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        // Size the hosting view to fit its content
        hostingView.setFrameSize(hostingView.fittingSize)

        scrollView.documentView = hostingView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        nsView.hasVerticalScroller = showsIndicators
        nsView.drawsBackground = false
        nsView.backgroundColor = .clear
        nsView.borderType = .noBorder
        nsView.scrollerStyle = .overlay

        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.setFrameSize(hostingView.fittingSize)
        }
    }
}
