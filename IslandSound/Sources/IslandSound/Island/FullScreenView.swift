import SwiftUI

/// Full overlay shown on click — karaoke lyric view, collab participant row,
/// and live voice-control status (FEATURES 3, 4 & 5).
struct FullScreenView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var lyricsEngine: LyricsEngine
    @ObservedObject var collabEngine: CollabEngine
    @ObservedObject var voiceEngine: VoiceEngine

    @State private var joinCode: String = ""

    private static let reactionEmojis = ["🔥", "❤️", "🎉", "👍"]

    init(appState: AppState) {
        self.appState = appState
        self.lyricsEngine = appState.lyricsEngine
        self.collabEngine = appState.collabEngine
        self.voiceEngine = appState.voiceEngine
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            karaokeView

            Spacer(minLength: 0)

            voiceStatusBar

            collabBar
        }
        .padding(18)
        .frame(width: IslandMetrics.fullScreenSize.width, height: IslandMetrics.fullScreenSize.height)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black)
        )
        .moodGlow(appState.moodTheme, cornerRadius: 28)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.currentTrack?.title ?? "Nothing Playing")
                    .font(.system(size: 16, weight: .bold))
                Text(appState.currentTrack?.artist ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation { appState.islandState = .collapsed }
            } label: {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Karaoke lyrics

    @ViewBuilder
    private var karaokeView: some View {
        if !lyricsEngine.lines.isEmpty {
            syncedLyricsView
        } else if let plain = lyricsEngine.plainLyrics {
            ScrollView {
                Text(plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            }
        } else {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "text.quote")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text(lyricsEngine.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var syncedLyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(lyricsEngine.lines) { line in
                        Text(line.text.isEmpty ? "•" : line.text)
                            .font(.system(size: isActive(line) ? 20 : 15, weight: isActive(line) ? .bold : .regular))
                            .foregroundStyle(isActive(line) ? appState.moodTheme.primaryColor : .secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .id(line.id)
                            .animation(.easeInOut(duration: 0.3), value: appState.activeLyricLine?.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
            .onChange(of: appState.activeLyricLine?.id) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func isActive(_ line: LyricLine) -> Bool {
        line.id == appState.activeLyricLine?.id
    }

    // MARK: - Voice status

    @ViewBuilder
    private var voiceStatusBar: some View {
        if appState.isListeningForCommand || appState.shazamResult != nil {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(appState.moodTheme.primaryColor)
                    .symbolEffect(.pulse, isActive: appState.isListeningForCommand)

                if let shazam = appState.shazamResult {
                    Text(shazam)
                } else if !appState.lastVoiceTranscript.isEmpty {
                    Text(appState.lastVoiceTranscript)
                } else {
                    Text("Listening for \u{201C}Hey Island\u{201D}…")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .transition(.opacity)
        }
    }

    // MARK: - Collab bar

    @ViewBuilder
    private var collabBar: some View {
        if let session = appState.collabSession {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: session.role == .host ? "crown.fill" : "person.2.fill")
                        .foregroundStyle(appState.moodTheme.primaryColor)
                        .font(.system(size: 11))

                    Text(session.code)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))

                    ForEach(session.participants) { participant in
                        Text(participant.avatar)
                            .font(.system(size: 14))
                            .help(participant.name)
                    }

                    Spacer()

                    if let reaction = session.recentReactions.last {
                        Text(reaction.emoji)
                            .font(.system(size: 16))
                            .transition(.scale.combined(with: .opacity))
                            .id(reaction.from + reaction.emoji + "\(session.recentReactions.count)")
                    }

                    ForEach(Self.reactionEmojis, id: \.self) { emoji in
                        Button {
                            collabEngine.sendReaction(emoji)
                        } label: {
                            Text(emoji).font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Leave") {
                        Task { await collabEngine.leaveRoom() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        } else {
            HStack(spacing: 10) {
                Button {
                    Task { await collabEngine.createRoom() }
                } label: {
                    Label("Start Room", systemImage: "person.2.wave.2")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Spacer()

                TextField("Room code", text: $joinCode)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 80)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))

                Button("Join") {
                    let code = joinCode
                    joinCode = ""
                    Task { await collabEngine.joinRoom(code: code) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

#Preview {
    FullScreenView(appState: .shared)
        .padding()
        .background(Color.gray.opacity(0.2))
}
