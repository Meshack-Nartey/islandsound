import Foundation
import Combine

/// Visual state of the island window.
enum IslandState: Equatable {
    /// Default — tiny pill showing track name scrolling, mood glow border only.
    case collapsed
    /// On hover — shows album art, progress bar, controls, current lyric line.
    case expanded
    /// On click — full overlay with karaoke view, collab participants, voice status.
    case fullScreen
}

/// Single source of truth for the entire app. All six engines
/// (`PlaybackEngine`, `MoodEngine`, `LyricsEngine`, `CollabEngine`,
/// `VoiceEngine`, and the `IslandWindowController`) read and write to this
/// shared object so the SwiftUI views stay in sync without any direct
/// engine-to-engine coupling.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Playback (written by PlaybackEngine)
    @Published var currentTrack: Track?
    @Published var playbackPosition: Double = 0 // seconds
    @Published var isPlaying: Bool = false
    @Published var sourceApp: MusicSource = .unknown

    // MARK: - Mood (written by MoodEngine)
    @Published var moodTheme: MoodTheme = .neutral

    // MARK: - Lyrics (written by LyricsEngine)
    @Published var activeLyricLine: LyricLine?
    @Published var lyricsAvailable: Bool = false

    // MARK: - Collab (written by CollabEngine)
    @Published var collabSession: CollabSession?

    // MARK: - Voice (written by VoiceEngine)
    @Published var isListeningForCommand: Bool = false
    @Published var lastVoiceTranscript: String = ""
    @Published var shazamResult: String?

    // MARK: - Island window state (written by IslandWindowController / views)
    @Published var islandState: IslandState = .collapsed

    // MARK: - Engines
    let playbackEngine: PlaybackEngine
    let moodEngine: MoodEngine
    let lyricsEngine: LyricsEngine
    let collabEngine: CollabEngine
    let voiceEngine: VoiceEngine

    private var cancellables = Set<AnyCancellable>()

    init() {
        let playbackEngine = PlaybackEngine()
        let moodEngine = MoodEngine()
        let lyricsEngine = LyricsEngine()
        let collabEngine = CollabEngine()
        let voiceEngine = VoiceEngine()

        self.playbackEngine = playbackEngine
        self.moodEngine = moodEngine
        self.lyricsEngine = lyricsEngine
        self.collabEngine = collabEngine
        self.voiceEngine = voiceEngine

        wireEngines()
    }

    /// Starts all engines. Called once from `IslandSoundApp` on launch.
    func start() {
        playbackEngine.start(appState: self)
        moodEngine.start(appState: self)
        lyricsEngine.start(appState: self)
        collabEngine.start(appState: self)
        voiceEngine.start(appState: self)
        // CollabEngine's WebSocket connects lazily when the user creates/joins a room.
    }

    /// Wires engine output back into the shared published state. Each engine
    /// remains independent (single responsibility) but funnels updates
    /// through here so views never need to know which engine owns what.
    private func wireEngines() {
        playbackEngine.onTrackChanged = { [weak self] track, position, isPlaying, source in
            guard let self else { return }
            let trackChanged = self.currentTrack?.id != track?.id
            self.currentTrack = track
            self.playbackPosition = position
            self.isPlaying = isPlaying
            self.sourceApp = source

            self.moodEngine.setPlaying(isPlaying)

            if trackChanged {
                self.activeLyricLine = nil
                if let track {
                    Task { await self.lyricsEngine.loadLyrics(for: track) }
                } else {
                    self.lyricsAvailable = false
                    self.lyricsEngine.clear()
                }
            }
        }

        playbackEngine.onPositionTick = { [weak self] position in
            guard let self else { return }
            self.playbackPosition = position
            self.lyricsEngine.tick(position: position)
        }

        moodEngine.onThemeChanged = { [weak self] theme in
            self?.moodTheme = theme
        }

        lyricsEngine.onActiveLineChanged = { [weak self] line, available in
            self?.activeLyricLine = line
            self?.lyricsAvailable = available
        }

        collabEngine.onSessionChanged = { [weak self] session in
            self?.collabSession = session
        }
        collabEngine.onRemoteSync = { [weak self] sync in
            guard let self else { return }
            self.playbackEngine.applyRemoteSync(sync)
        }

        voiceEngine.onListeningChanged = { [weak self] isListening in
            self?.isListeningForCommand = isListening
        }
        voiceEngine.onTranscript = { [weak self] transcript in
            self?.lastVoiceTranscript = transcript
        }
        voiceEngine.onShazamResult = { [weak self] result in
            self?.shazamResult = result
        }
        voiceEngine.onCommand = { [weak self] command in
            self?.handleVoiceCommand(command)
        }
    }

    private func handleVoiceCommand(_ command: VoiceCommand) {
        switch command {
        case .skip: playbackEngine.next()
        case .previous: playbackEngine.previous()
        case .pause: playbackEngine.pause()
        case .play: playbackEngine.play()
        case .replay: playbackEngine.seek(by: -10)
        case .whoSingsThis: voiceEngine.identifyCurrentAudio()
        case .showLyrics: islandState = .fullScreen
        case .startRoom:
            Task { await collabEngine.createRoom() }
        case .volumeUp: SystemVolume.adjust(by: 0.10)
        case .volumeDown: SystemVolume.adjust(by: -0.10)
        }
    }
}
