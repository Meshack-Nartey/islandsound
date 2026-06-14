import SwiftUI

/// Default island state — a tiny pill showing the scrolling track name with
/// a mood-coloured glow border. No controls, no album art: this is the
/// "0% CPU at idle" resting state (see Section 11.3 performance rules).
struct CollapsedView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            playbackDot

            if let track = appState.currentTrack {
                MarqueeText(text: "\(track.title) — \(track.artist)", font: .system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            } else {
                Text("IslandSound")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if appState.isListeningForCommand {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: IslandMetrics.collapsedSize.width, height: IslandMetrics.collapsedSize.height)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.cornerRadiusCollapsed, style: .continuous)
                .fill(Color.black)
        )
        .moodGlow(appState.moodTheme, cornerRadius: IslandMetrics.cornerRadiusCollapsed)
    }

    @ViewBuilder
    private var playbackDot: some View {
        Circle()
            .fill(appState.isPlaying ? appState.moodTheme.primaryColor : Color.gray)
            .frame(width: 6, height: 6)
    }
}

#Preview {
    CollapsedView(appState: .shared)
        .padding()
        .background(Color.gray.opacity(0.2))
}
