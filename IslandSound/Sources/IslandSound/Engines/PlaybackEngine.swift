import Foundation
import AppKit

/// Unifies playback state from every supported source into `AppState`
/// (FEATURE 2 — Cross-App Listening Continuity).
///
/// - Apple Music & Spotify: tracked via `DistributedNotificationCenter`
///   (Section 5.3) + on-demand `AppleScriptBridge` queries for the fields the
///   notifications don't reliably carry (position, duration).
/// - Boomplay & YouTube Music: tracked via `BrowserBridgeServer`, a local
///   WebSocket server the companion browser extension posts to
///   (Section 5.4).
///
/// A 100ms `DispatchSourceTimer` interpolates playback position between
/// native-source queries so `LyricsEngine`'s karaoke ticker stays smooth
/// without polling AppleScript on every tick (Section 11.3).
@MainActor
final class PlaybackEngine: ObservableObject {
    /// User-facing status for the last handoff attempt, surfaced in the UI
    /// per Section 5.5's "Track not available on [App]" requirement.
    @Published var handoffStatusMessage: String?

    /// Fired whenever the active track, position, play state, or source changes.
    var onTrackChanged: ((Track?, Double, Bool, MusicSource) -> Void)?
    /// Fired ~10x/sec with the interpolated playback position.
    var onPositionTick: ((Double) -> Void)?

    private(set) var currentTrack: Track?
    private(set) var sourceApp: MusicSource = .unknown
    private(set) var isPlaying = false

    private var positionAnchor: Double = 0
    private var anchorDate = Date()

    private var tickTimer: DispatchSourceTimer?
    private var resyncTimer: DispatchSourceTimer?
    private var dncTokens: [NSObjectProtocol] = []
    private let browserBridge = BrowserBridgeServer()

    // Bundle identifiers used to avoid AppleScript-launching apps that aren't running.
    private static let appleMusicBundleID = "com.apple.Music"
    private static let spotifyBundleID = "com.spotify.client"

    func start(appState: AppState) {
        observeDistributedNotifications()

        browserBridge.onMessage = { [weak self] message in
            Task { @MainActor in self?.handleBrowserBridgeMessage(message) }
        }
        browserBridge.start()

        startTickTimer()
        startResyncTimer()

        Task { await refreshFromActivePlayer() }
    }

    deinit {
        tickTimer?.cancel()
        resyncTimer?.cancel()
        let dnc = DistributedNotificationCenter.default()
        for token in dncTokens { dnc.removeObserver(token) }
        browserBridge.stop()
    }

    // MARK: - Transport Controls (Section 8.2 voice command targets)

    func next() {
        Task {
            switch sourceApp {
            case .appleMusic: await AppleScriptBridge.appleNext()
            case .spotify: await AppleScriptBridge.spotifyNext()
            default: return
            }
            await refreshFromActivePlayer()
        }
    }

    func previous() {
        Task {
            switch sourceApp {
            case .appleMusic: await AppleScriptBridge.applePrevious()
            case .spotify: await AppleScriptBridge.spotifyPrevious()
            default: return
            }
            await refreshFromActivePlayer()
        }
    }

    func pause() {
        Task {
            switch sourceApp {
            case .appleMusic: await AppleScriptBridge.applePause()
            case .spotify: await AppleScriptBridge.spotifyPause()
            default: return
            }
            updateState(track: currentTrack, position: positionAnchor, isPlaying: false, source: sourceApp)
        }
    }

    func play() {
        Task {
            switch sourceApp {
            case .appleMusic: await AppleScriptBridge.applePlay()
            case .spotify: await AppleScriptBridge.spotifyPlay()
            default: return
            }
            updateState(track: currentTrack, position: positionAnchor, isPlaying: true, source: sourceApp)
        }
    }

    /// Seeks by a relative offset (e.g. -10 for "Hey Island, replay").
    func seek(by delta: Double) {
        let target = max(0, currentPosition() + delta)
        seek(to: target)
    }

    func seek(to position: Double) {
        Task {
            switch sourceApp {
            case .appleMusic: await AppleScriptBridge.appleSeek(to: position)
            case .spotify: await AppleScriptBridge.spotifySeek(to: position)
            default: return
            }
            positionAnchor = position
            anchorDate = Date()
            onPositionTick?(position)
        }
    }

    /// Current interpolated playback position.
    func currentPosition() -> Double {
        guard isPlaying else { return positionAnchor }
        return positionAnchor + Date().timeIntervalSince(anchorDate)
    }

    // MARK: - Collab drift correction (FEATURE 3)

    /// Applies a `SYNC` message from the collab host: corrects play/pause
    /// state and silently seeks if local drift exceeds the 500ms threshold.
    func applyRemoteSync(_ sync: SyncMessage) {
        let networkLatencyMs = Double(Date().milliseconds - sync.timestamp) / 2
        let expectedPosition = sync.position + (networkLatencyMs / 1000.0)
        let drift = abs(currentPosition() - expectedPosition)

        if drift > 0.5 {
            seek(to: expectedPosition)
        }

        if sync.isPlaying != isPlaying {
            sync.isPlaying ? play() : pause()
        }
    }

    // MARK: - DistributedNotificationCenter (Section 5.3)

    private func observeDistributedNotifications() {
        let dnc = DistributedNotificationCenter.default()

        let appleToken = dnc.addObserver(
            forName: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleAppleMusicNotification(note) }
        }

        let spotifyToken = dnc.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleSpotifyNotification(note) }
        }

        dncTokens = [appleToken, spotifyToken]
    }

    private func handleAppleMusicNotification(_ note: Notification) {
        if (note.userInfo?["Player State"] as? String) == "Stopped" {
            if sourceApp == .appleMusic {
                updateState(track: nil, position: 0, isPlaying: false, source: .appleMusic)
            }
            return
        }
        Task { await refreshAppleMusicState() }
    }

    private func handleSpotifyNotification(_ note: Notification) {
        if (note.userInfo?["Player State"] as? String) == "Stopped" {
            if sourceApp == .spotify {
                updateState(track: nil, position: 0, isPlaying: false, source: .spotify)
            }
            return
        }
        Task { await refreshSpotifyState() }
    }

    // MARK: - Polling / Refresh

    private func startResyncTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in await self?.resyncPosition() }
        }
        timer.resume()
        resyncTimer = timer
    }

    /// Corrects accumulated drift in the interpolated position every 5
    /// seconds, without doing a full `NowPlayingInfo` round-trip.
    private func resyncPosition() async {
        guard isPlaying else { return }
        let position: Double?
        switch sourceApp {
        case .appleMusic where isAppRunning(Self.appleMusicBundleID):
            position = await AppleScriptBridge.applePlayerPosition()
        case .spotify where isAppRunning(Self.spotifyBundleID):
            position = await AppleScriptBridge.spotifyPlayerPosition()
        default:
            position = nil
        }
        if let position {
            positionAnchor = position
            anchorDate = Date()
        }
    }

    /// Checks both native sources on launch and picks whichever is actively
    /// playing (Apple Music takes priority if both are, which is an edge
    /// case unlikely in practice).
    private func refreshFromActivePlayer() async {
        if isAppRunning(Self.appleMusicBundleID) {
            await refreshAppleMusicState()
            if isPlaying { return }
        }
        if isAppRunning(Self.spotifyBundleID) {
            await refreshSpotifyState()
        }
    }

    private func refreshAppleMusicState() async {
        guard isAppRunning(Self.appleMusicBundleID),
              let info = await AppleScriptBridge.appleNowPlaying() else {
            if sourceApp == .appleMusic {
                updateState(track: nil, position: 0, isPlaying: false, source: .appleMusic)
            }
            return
        }
        let id = "apple:\(Track.makeCacheKey(title: info.title, artist: info.artist))"
        var artworkURL = (currentTrack?.id == id) ? currentTrack?.artworkURL : nil
        if artworkURL == nil,
           let data = await AppleScriptBridge.appleArtworkData(),
           NSImage(data: data) != nil {
            artworkURL = cacheArtwork(data: data, id: id)
        }
        let track = Track(
            id: id,
            title: info.title, artist: info.artist, album: info.album, duration: info.duration,
            artworkURL: artworkURL
        )
        updateState(track: track, position: info.position, isPlaying: info.isPlaying, source: .appleMusic)
    }

    private func refreshSpotifyState() async {
        guard isAppRunning(Self.spotifyBundleID),
              let info = await AppleScriptBridge.spotifyNowPlaying() else {
            if sourceApp == .spotify {
                updateState(track: nil, position: 0, isPlaying: false, source: .spotify)
            }
            return
        }
        let track = Track(
            id: "spotify:\(Track.makeCacheKey(title: info.title, artist: info.artist))",
            title: info.title, artist: info.artist, album: info.album, duration: info.duration,
            artworkURL: info.artworkURL
        )
        updateState(track: track, position: info.position, isPlaying: info.isPlaying, source: .spotify)
    }

    /// Caches Apple Music's embedded artwork bytes to a temporary file so
    /// `AsyncImage` can load them via a `file://` URL (Music.app only
    /// exposes raw artwork data, not a hosted URL like Spotify).
    private func cacheArtwork(data: Data, id: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("IslandSoundArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let url = dir.appendingPathComponent(safeName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func isAppRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    // MARK: - Browser Bridge (Section 5.4)

    private func handleBrowserBridgeMessage(_ message: BrowserBridgeMessage) {
        let source: MusicSource = (message.source == "youtube") ? .youtubeMusic : .boomplay
        guard let title = message.title, !title.isEmpty else { return }

        let track = Track(
            id: "\(source.rawValue):\(Track.makeCacheKey(title: title, artist: message.artist ?? ""))",
            title: title,
            artist: message.artist ?? "Unknown Artist",
            duration: 0
        )
        updateState(track: track, position: message.position ?? 0, isPlaying: true, source: source)
    }

    // MARK: - State Update

    private func updateState(track: Track?, position: Double, isPlaying: Bool, source: MusicSource) {
        currentTrack = track
        sourceApp = source
        self.isPlaying = isPlaying
        positionAnchor = position
        anchorDate = Date()
        onTrackChanged?(track, position, isPlaying, source)
    }

    private func startTickTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        tickTimer = timer
    }

    private func tick() {
        guard isPlaying, currentTrack != nil else { return }
        onPositionTick?(currentPosition())
    }

    // MARK: - Handoff (Section 5.5)

    /// Hands the currently-playing track off to `target`, preserving
    /// playback position. Pauses the current source, asks the target app to
    /// locate and play the track, seeks to the saved position, then resumes.
    /// If the target can't find the track, sets `handoffStatusMessage` to
    /// the "Track not available" message described in Section 5.5.
    func handoff(to target: MusicSource) async {
        guard let track = currentTrack, target != sourceApp else { return }

        let position = currentPosition()
        let previousSource = sourceApp

        switch previousSource {
        case .appleMusic: await AppleScriptBridge.applePause()
        case .spotify: await AppleScriptBridge.spotifyPause()
        default: break
        }

        let success: Bool
        switch target {
        case .appleMusic:
            success = await AppleScriptBridge.applePlayTrack(title: track.title, artist: track.artist, position: position)
        case .spotify:
            success = await AppleScriptBridge.spotifyPlayTrack(title: track.title, artist: track.artist, position: position)
        case .boomplay, .youtubeMusic:
            success = browserBridge.requestPlay(title: track.title, artist: track.artist, position: position, source: target.rawValue)
        case .unknown:
            success = false
        }

        if success {
            handoffStatusMessage = nil
            await refreshFromActivePlayer()
        } else {
            handoffStatusMessage = "Track not available on \(target.displayName)"
            // Restore the previous source's playback since the handoff failed.
            switch previousSource {
            case .appleMusic: await AppleScriptBridge.applePlay()
            case .spotify: await AppleScriptBridge.spotifyPlay()
            default: break
            }
        }
    }
}

private extension Date {
    var milliseconds: Int64 {
        Int64(timeIntervalSince1970 * 1000)
    }
}
