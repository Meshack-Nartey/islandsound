import SwiftUI

/// Horizontally scrolling text used by `CollapsedView` for long track names.
/// Only animates when the text overflows the available width — short titles
/// render statically with zero animation overhead.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12, weight: .medium)
    var color: Color = .primary
    /// Points per second the text scrolls.
    var speed: Double = 24

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let overflow = textWidth > proxy.size.width

            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
                    .background(WidthReader(width: $textWidth))
                    .offset(x: overflow ? offset : max(0, (proxy.size.width - textWidth) / 2))
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipped()
            .onAppear { containerWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, newValue in containerWidth = newValue }
            .onChange(of: textWidth) { _, _ in restartIfNeeded(overflow: overflow) }
            .onChange(of: text) { _, _ in offset = 0 }
            .task(id: "\(text)-\(textWidth)-\(containerWidth)") {
                guard overflow else { return }
                await runMarquee()
            }
        }
        .frame(height: 16)
    }

    private func restartIfNeeded(overflow: Bool) {
        if !overflow {
            offset = 0
        }
    }

    @MainActor
    private func runMarquee() async {
        // Pause at start, scroll to fully reveal the end, pause, then snap back.
        let distance = textWidth - containerWidth + 24
        guard distance > 0 else { return }

        offset = 0
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        withAnimation(.linear(duration: distance / speed)) {
            offset = -distance
        }

        try? await Task.sleep(for: .seconds(distance / speed + 1))
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: 0.4)) {
            offset = 0
        }
    }
}

/// Measures the natural width of its parent via a zero-size background.
private struct WidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newValue in width = newValue }
        }
    }
}
