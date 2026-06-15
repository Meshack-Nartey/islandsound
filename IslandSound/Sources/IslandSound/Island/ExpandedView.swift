import SwiftUI

/// Hover state — album art, progress bar, transport controls, the current
/// lyric line, and the cross-app source switcher (FEATURE 2).
struct ExpandedView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.currentTrack?.title ?? "Nothing Playing")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(appState.currentTrack?.artist ?? "Open Apple Music or Spotify")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                sourceSwitcher
            }

            progressBar

            transportControls
        }
        .padding(14)
        .frame(width: IslandMetrics.expandedSize.width, height: IslandMetrics.expandedSize.height)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.cornerRadiusExpanded, style: .continuous)
                .fill(Color.black)
        )
        .moodGlow(appState.moodTheme, cornerRadius: IslandMetrics.cornerRadiusExpanded)
        .onTapGesture {
            appState.islandState = .fullScreen
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let url = appState.currentTrack?.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            )
    }

    private var progressBar: some View {
        let duration = max(appState.currentTrack?.duration ?? 0, 1)
        let fraction = min(max(appState.playbackPosition / duration, 0), 1)

        return VStack(spacing: 2) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(appState.moodTheme.primaryColor)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)

            HStack {
                Text(formatted(appState.playbackPosition))
                Spacer()
                Text(formatted(appState.currentTrack?.duration ?? 0))
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        ZStack {
            HStack(spacing: 20) {
                Button { appState.playbackEngine.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                Button {
                    appState.isPlaying ? appState.playbackEngine.pause() : appState.playbackEngine.play()
                } label: {
                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                }
                Button { appState.playbackEngine.next() } label: {
                    Image(systemName: "forward.fill")
                }
            }
            .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                Button {
                    Task { await appState.collabEngine.createRoom() }
                } label: {
                    Image(systemName: "person.2.wave.2")
                }
                .help("Start a collab room")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.primary)
    }

    /// Lets the user hand the currently-playing track off to another source
    /// (FEATURE 2 — Cross-App Listening Continuity).
    private var sourceSwitcher: some View {
        Menu {
            ForEach(MusicSource.allCases.filter { $0 != .unknown }) { source in
                Button {
                    Task { await appState.playbackEngine.handoff(to: source) }
                } label: {
                    if source == appState.sourceApp {
                        Label(source.displayName, systemImage: "checkmark")
                    } else {
                        Text(source.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
    }

    private func formatted(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    ExpandedView(appState: .shared)
        .padding()
        .background(Color.gray.opacity(0.2))
}
