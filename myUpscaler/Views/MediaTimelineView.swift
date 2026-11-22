import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct TimelineView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(state.timelineFrames.indices, id: \.self) { i in
                        thumbnail(i)
                            .id(i)
                    }
                }
                .padding(8)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onChange(of: state.selectedFrameIndex) { _, idx in
                proxy.scrollTo(idx, anchor: .center)
            }
        }
        .modifier(KeyboardNavigationModifier(selectedIndex: $state.selectedFrameIndex,
                                             maxIndex: state.timelineFrames.count - 1,
                                             select: state.selectFrame))
    }

    private func thumbnail(_ index: Int) -> some View {
        let selected = (index == state.selectedFrameIndex)
        return ZStack(alignment: .topLeading) {
            Image(nsImage: state.timelineFrames[index])
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 104, height: 64)
                .clipped()

            // The selected frame is outlined in the accent colour.
            if selected {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 104, height: 64)
            }

            Text("\(index + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .background(selected ? Color.accentColor : Color.black)
        }
        .onTapGesture { state.selectFrame(index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frame \(index + 1), \(state.formatTime(state.timelineFrameTimes[index]))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { state.selectFrame(index) }
        .help(state.formatTime(state.timelineFrameTimes[index]))

        .focusable(false)
    }
}

struct KeyboardNavigationModifier: ViewModifier {
    @Binding var selectedIndex: Int
    let maxIndex: Int
    let select: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .modifier(KeyPressHandler(selectedIndex: $selectedIndex,
                                      maxIndex: maxIndex,
                                      select: select))
    }
}

struct KeyPressHandler: ViewModifier {
    @Binding var selectedIndex: Int
    let maxIndex: Int
    let select: (Int) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.upArrow) {
                    if selectedIndex > 0 { select(selectedIndex - 1) }
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if selectedIndex < maxIndex { select(selectedIndex + 1) }
                    return .handled
                }
        } else {
            content
        }
    }
}
