import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct TimelineView: View {
    @ObservedObject var state: EditorState
    @Namespace private var ns
    @State private var hoverIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 4) {
                    ForEach(state.timelineFrames.indices, id: \.self) { i in
                        thumbnail(i)
                            .id(i)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onChange(of: state.selectedFrameIndex) { _, idx in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
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
                .frame(width: 70, height: 45)
                .cornerRadius(3)

            RoundedRectangle(cornerRadius: 3)
                .stroke(selected ? Color.accentColor : Color.gray.opacity(0.3),
                        lineWidth: selected ? 3 : 1)
                .matchedGeometryEffect(id: "sel", in: ns, isSource: selected)
                .frame(width: 70, height: 45)
                .shadow(color: selected ? Color.accentColor.opacity(0.6) : .clear,
                        radius: selected ? 6 : 0)

            Text("\(index + 1)")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(selected ?
                            Color.accentColor.opacity(0.9) :
                            Color.primary.opacity(0.7))
                .cornerRadius(2)
                .padding(4)
        }
        .scaleEffect(selected ? 1.07 : (hoverIndex == index ? 1.02 : 1))
        .onHover { hoverIndex = $0 ? index : nil }
        .onTapGesture { state.selectFrame(index) }
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
