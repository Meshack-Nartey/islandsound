import SwiftUI

/// Full overlay shown on click — collaborative listening rooms and live
/// voice-control status (FEATURES 3 & 5).
struct FullScreenView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var collabEngine: CollabEngine
    @ObservedObject var voiceEngine: VoiceEngine

    @State private var joinCode: String = ""

    private static let reactionEmojis = ["🔥", "❤️", "🎉", "👍"]

    init(appState: AppState) {
        self.appState = appState
        self.collabEngine = appState.collabEngine
        self.voiceEngine = appState.voiceEngine
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            collabContent
                .frame(maxHeight: .infinity)

            voiceStatusBar
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

    // MARK: - Collab room

    @ViewBuilder
    private var collabContent: some View {
        if let session = appState.collabSession {
            activeRoomView(session)
        } else {
            startRoomView
        }
    }

    /// Shown when the user isn't in a room yet — explains what a collab room
    /// does and offers prominent "Start Room" / "Join" actions (FEATURE 3).
    private var startRoomView: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 30))
                .foregroundStyle(appState.moodTheme.primaryColor)

            VStack(spacing: 4) {
                Text("Listen Together")
                    .font(.system(size: 15, weight: .semibold))
                Text("Start a room to sync this track with friends in real time, or join one with a code.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Button {
                Task { await collabEngine.createRoom() }
            } label: {
                Label("Start Room", systemImage: "play.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(appState.moodTheme.primaryColor)
            .background(appState.moodTheme.primaryColor.opacity(0.16))
            .clipShape(Capsule())
            .padding(.horizontal, 70)

            HStack(spacing: 8) {
                TextField("Enter room code", text: $joinCode)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.06)))

                Button("Join") {
                    let code = joinCode
                    joinCode = ""
                    Task { await collabEngine.joinRoom(code: code) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isJoinDisabled ? .secondary : .primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(isJoinDisabled ? 0.04 : 0.1)))
                .disabled(isJoinDisabled)
            }
            .padding(.horizontal, 48)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var isJoinDisabled: Bool {
        joinCode.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Shown once the user has created or joined a room — the room code,
    /// roster, reactions, and a "Leave Room" action.
    private func activeRoomView(_ session: CollabSession) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image(systemName: session.role == .host ? "crown.fill" : "person.2.fill")
                .font(.system(size: 26))
                .foregroundStyle(appState.moodTheme.primaryColor)

            VStack(spacing: 4) {
                Text(session.code)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .tracking(6)
                Text(session.role == .host ? "You're hosting — share this code" : "Listening along with the host")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !session.participants.isEmpty {
                HStack(spacing: 8) {
                    ForEach(session.participants) { participant in
                        Text(participant.avatar)
                            .font(.system(size: 20))
                            .help(participant.name)
                    }
                }
            }

            HStack(spacing: 16) {
                ForEach(Self.reactionEmojis, id: \.self) { emoji in
                    Button {
                        collabEngine.sendReaction(emoji)
                    } label: {
                        Text(emoji).font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let reaction = session.recentReactions.last {
                Text("\(reaction.from) reacted \(reaction.emoji)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .id(reaction.from + reaction.emoji + "\(session.recentReactions.count)")
            }

            Spacer(minLength: 0)

            Button("Leave Room") {
                Task { await collabEngine.leaveRoom() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .frame(maxWidth: .infinity)
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
}

#Preview {
    FullScreenView(appState: .shared)
        .padding()
        .background(Color.gray.opacity(0.2))
}
