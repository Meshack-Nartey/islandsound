import Foundation

/// Offline, time-synced karaoke lyrics (FEATURE 4 / Section 7).
///
/// On track change, `loadLyrics(for:)` first checks the local `LyricsCache`
/// (CoreData), falling back to a single LRCLIB network request. The result
/// is parsed via `LRCParser` and cached for future offline playback. As
/// `PlaybackEngine` ticks the playhead forward, `tick(position:)` walks the
/// parsed lines to find the currently-active one and reports it via
/// `onActiveLineChanged`.
@MainActor
final class LyricsEngine: ObservableObject {
    /// All parsed lines for the current track, sorted by timestamp. For
    /// tracks with real LRC timing this is exact; for tracks where LRCLIB
    /// only has unsynced ("plain") lyrics, timestamps are approximated by
    /// evenly spacing each line across the track's duration (see
    /// `approximateLines`), so the single-line karaoke view still progresses
    /// line-by-line.
    @Published var lines: [LyricLine] = []

    /// Human-readable status shown in the karaoke view while `lines` is empty
    /// (e.g. "Loading lyrics…", "No lyrics found").
    @Published var statusMessage: String = "No lyrics"

    /// Fired whenever the active line changes, or when lyric availability for
    /// the current track changes. `(line, available)`.
    var onActiveLineChanged: ((LyricLine?, Bool) -> Void)?

    private let cache = LyricsCache()
    private var currentTrackId: String?
    private var activeIndex: Int?

    func start(appState: AppState) {
        cache.purgeExpiredEntries()
    }

    /// Loads lyrics for `track`: cache hit first, then a single LRCLIB
    /// request (Section 7.2-7.3). Safe to call repeatedly -- a stale
    /// in-flight request for a previous track is discarded if the track
    /// changes again before it resolves.
    func loadLyrics(for track: Track) async {
        currentTrackId = track.id
        activeIndex = nil
        lines = []
        statusMessage = "Loading lyrics\u{2026}"
        onActiveLineChanged?(nil, false)

        if let cached = await cache.fetch(trackId: track.id) {
            applyParsedLyrics(cached, for: track.id)
            return
        }

        guard let result = await LRCLIBClient.fetchLyrics(title: track.title, artist: track.artist) else {
            guard currentTrackId == track.id else { return }
            statusMessage = "No lyrics found"
            return
        }
        guard currentTrackId == track.id else { return }

        if let synced = result.synced, !synced.isEmpty {
            await cache.store(trackId: track.id, raw: synced, source: .lrclib)
            applyParsedLyrics(synced, for: track.id)
        } else if let plain = result.plain, !plain.isEmpty {
            lines = Self.approximateLines(from: plain, duration: track.duration)
            statusMessage = lines.isEmpty ? "No lyrics found" : ""
            onActiveLineChanged?(nil, !lines.isEmpty)
        } else {
            statusMessage = "No lyrics found"
        }
    }

    /// Updates `activeIndex` for the given playhead `position` (seconds) and
    /// notifies `onActiveLineChanged` if the active line changed. Called from
    /// `PlaybackEngine.onPositionTick` at the 100ms cadence (Section 11.3).
    func tick(position: Double) {
        guard !lines.isEmpty else { return }

        let newIndex = LRCParser.activeIndex(in: lines, at: position)

        guard newIndex != activeIndex else { return }
        activeIndex = newIndex
        let line = newIndex.map { lines[$0] }
        onActiveLineChanged?(line, true)
    }

    /// Resets to the "no track" state, e.g. when playback stops entirely.
    func clear() {
        currentTrackId = nil
        lines = []
        activeIndex = nil
        statusMessage = "No lyrics"
        onActiveLineChanged?(nil, false)
    }

    /// Stores user-supplied LRC text for `track` and, if it's still the
    /// current track, applies it immediately.
    func importLRC(text: String, for track: Track) async {
        await cache.store(trackId: track.id, raw: text, source: .userImported)
        if currentTrackId == track.id {
            applyParsedLyrics(text, for: track.id)
        }
    }

    private func applyParsedLyrics(_ raw: String, for trackId: String) {
        guard currentTrackId == trackId else { return }

        let parsed = LRCParser.parse(raw)
        lines = parsed
        activeIndex = nil

        if parsed.isEmpty {
            statusMessage = "No lyrics found"
            onActiveLineChanged?(nil, false)
        } else {
            statusMessage = ""
            onActiveLineChanged?(nil, true)
        }
    }

    /// Approximates per-line timestamps for unsynced ("plain") lyrics by
    /// evenly spacing each non-empty line across the track's `duration`, so
    /// the single-line karaoke view can still progress line-by-line even
    /// without real LRC timing data. Falls back to 3 seconds per line if
    /// `duration` is unknown.
    private static func approximateLines(from plain: String, duration: Double) -> [LyricLine] {
        let textLines = plain
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !textLines.isEmpty else { return [] }

        let segment = duration > 0 ? duration / Double(textLines.count) : 3.0
        return textLines.enumerated().map { index, text in
            LyricLine(timestamp: Double(index) * segment, text: text)
        }
    }
}
