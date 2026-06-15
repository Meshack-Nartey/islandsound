import SwiftUI

/// Default island state — a tiny pill with the album artwork on the left and
/// an animated "music signal" waveform on the right, inside a mood-coloured
/// glow border. The track title/artist are intentionally hidden here -- they
/// only appear once the user hovers and the island expands. The waveform
/// only animates while something is playing (or while listening for "Hey
/// Island"), so this remains the "0% CPU at idle" resting state (see Section
/// 11.3 performance rules).
struct CollapsedView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            albumArt

            Spacer(minLength: 0)

            signalWave
        }
        .padding(.horizontal, 10)
        .frame(width: IslandMetrics.collapsedSize.width, height: IslandMetrics.collapsedSize.height)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.cornerRadiusCollapsed, style: .continuous)
                .fill(Color.black)
        )
        .moodGlow(appState.moodTheme, cornerRadius: IslandMetrics.cornerRadiusCollapsed)
    }

    /// Small artwork thumbnail anchoring the left edge of the pill, falling
    /// back to a generic note glyph when there's no track or no artwork.
    @ViewBuilder
    private var albumArt: some View {
        Group {
            if let url = appState.currentTrack?.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        albumArtPlaceholder
                    }
                }
            } else {
                albumArtPlaceholder
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var albumArtPlaceholder: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            )
    }

    /// Animated waveform on the right edge representing the live music
    /// signal -- it pulses with mood colour while something is playing (or
    /// while listening for "Hey Island"), and sits static/grey at idle.
    private var signalWave: some View {
        let active = appState.isPlaying || appState.isListeningForCommand
        return Image(systemName: "waveform")
            .font(.system(size: 10))
            .foregroundStyle(active ? appState.moodTheme.primaryColor : Color.secondary)
            .symbolEffect(.variableColor.iterative, isActive: active)
    }
}

#Preview {
    CollapsedView(appState: .shared)
        .padding()
        .background(Color.gray.opacity(0.2))
}
