import Foundation
import AppKit

/// Thin async/await wrapper around `NSAppleScript`, used by `PlaybackEngine`
/// to query and control Apple Music ("Music") and Spotify.
///
/// `NSAppleScript` is synchronous and not safe to hammer from the main
/// thread, so every call hops to a dedicated serial queue and resumes a
/// continuation when the script finishes.
enum AppleScriptBridge {
    private static let queue = DispatchQueue(label: "com.aethelis.islandsound.applescript")

    /// Runs `source` and returns its string result, or `nil` if the script
    /// failed (e.g. the target app isn't running).
    static func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = script.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result.stringValue)
                }
            }
        }
    }

    /// Runs `source` purely for its side effect (play/pause/next/etc).
    /// Returns `true` if it executed without an AppleScript error.
    @discardableResult
    static func runCommand(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: false)
                    return
                }
                _ = script.executeAndReturnError(&error)
                continuation.resume(returning: error == nil)
            }
        }
    }

    // MARK: - Escaping

    /// Escapes a string for safe interpolation inside an AppleScript string
    /// literal (`"..."`). Prevents both syntax breakage and command
    /// injection when track titles/artists contain quotes or backslashes.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Now Playing

    /// Snapshot of the current track + transport state for one app, returned
    /// by `appleNowPlaying()` / `spotifyNowPlaying()` in a single round-trip.
    struct NowPlayingInfo {
        let title: String
        let artist: String
        let album: String?
        let duration: Double // seconds
        let position: Double // seconds
        let isPlaying: Bool
        let artworkURL: URL?
    }

    /// Queries Apple Music in one round-trip. Returns `nil` if nothing is
    /// loaded (player state is "stopped"). Caller is responsible for first
    /// checking the app is actually running (querying a non-running app via
    /// AppleScript silently launches it).
    static func appleNowPlaying() async -> NowPlayingInfo? {
        let source = """
        tell application "Music"
            if player state is stopped then return ""
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to duration of current track
            set p to player position
            set isPlaying to (player state is playing)
            return t & "\u{0001}" & a & "\u{0001}" & al & "\u{0001}" & (d as string) & "\u{0001}" & (p as string) & "\u{0001}" & (isPlaying as string)
        end tell
        """
        guard let result = await run(source), !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "\u{0001}")
        guard parts.count == 6 else { return nil }
        return NowPlayingInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2].isEmpty ? nil : parts[2],
            duration: Double(parts[3]) ?? 0,
            position: Double(parts[4]) ?? 0,
            isPlaying: parts[5] == "true",
            artworkURL: nil // Music.app has no artwork URL; see `appleArtworkData()`.
        )
    }

    /// Fetches the embedded artwork for Apple Music's current track as raw
    /// image data (PNG/JPEG/TIFF, depending on the source file). Returns
    /// `nil` if the track has no artwork or the script fails.
    static func appleArtworkData() async -> Data? {
        let source = """
        tell application "Music"
            if (count of artworks of current track) > 0 then
                return data of artwork 1 of current track
            else
                return ""
            end if
        end tell
        """
        return await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = script.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result.data)
                }
            }
        }
    }

    /// Queries Spotify in one round-trip. `duration of current track` is in
    /// milliseconds in Spotify's AppleScript dictionary, so it's normalised
    /// to seconds here for `NowPlayingInfo`. Spotify exposes a hosted artwork
    /// URL directly, unlike Apple Music.
    static func spotifyNowPlaying() async -> NowPlayingInfo? {
        let source = """
        tell application "Spotify"
            if player state is stopped then return ""
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to duration of current track
            set p to player position
            set isPlaying to (player state is playing)
            set au to artwork url of current track
            return t & "\u{0001}" & a & "\u{0001}" & al & "\u{0001}" & (d as string) & "\u{0001}" & (p as string) & "\u{0001}" & (isPlaying as string) & "\u{0001}" & au
        end tell
        """
        guard let result = await run(source), !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "\u{0001}")
        guard parts.count == 7 else { return nil }
        return NowPlayingInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2].isEmpty ? nil : parts[2],
            duration: (Double(parts[3]) ?? 0) / 1000.0,
            position: Double(parts[4]) ?? 0,
            isPlaying: parts[5] == "true",
            artworkURL: URL(string: parts[6])
        )
    }

    // MARK: - Apple Music ("Music")

    static func applePlayerPosition() async -> Double? {
        guard let result = await run(#"tell application "Music" to get player position"#) else { return nil }
        return Double(result)
    }

    static func appleNext() async { await runCommand(#"tell application "Music" to next track"#) }
    static func applePrevious() async { await runCommand(#"tell application "Music" to previous track"#) }
    static func applePause() async { await runCommand(#"tell application "Music" to pause"#) }
    static func applePlay() async { await runCommand(#"tell application "Music" to play"#) }

    static func appleSeek(to position: Double) async {
        await runCommand(#"tell application "Music" to set player position to \#(position)"#)
    }

    /// Attempts to find and play `title`/`artist` in the user's Apple Music
    /// library or catalogue, then seek to `position`. Returns `false` if no
    /// match could be played (caller should show the "not available" message
    /// per Section 5.5's LIMITATION note).
    static func applePlayTrack(title: String, artist: String, position: Double) async -> Bool {
        let t = escape(title)
        let a = escape(artist)
        let source = """
        tell application "Music"
            activate
            try
                play (first track of (every track of library playlist 1 whose name is "\(t)" and artist is "\(a)"))
            on error
                try
                    play (first track of (search library playlist 1 for "\(t) \(a)"))
                on error
                    return "not_found"
                end try
            end try
            delay 0.3
            set player position to \(position)
            return "ok"
        end tell
        """
        return await run(source) == "ok"
    }

    // MARK: - Spotify

    static func spotifyPlayerPosition() async -> Double? {
        guard let result = await run(#"tell application "Spotify" to get player position"#) else { return nil }
        return Double(result)
    }

    static func spotifyNext() async { await runCommand(#"tell application "Spotify" to next track"#) }
    static func spotifyPrevious() async { await runCommand(#"tell application "Spotify" to previous track"#) }
    static func spotifyPause() async { await runCommand(#"tell application "Spotify" to pause"#) }
    static func spotifyPlay() async { await runCommand(#"tell application "Spotify" to play"#) }

    static func spotifySeek(to position: Double) async {
        await runCommand(#"tell application "Spotify" to set player position to \#(position)"#)
    }

    /// Searches Spotify for `title`/`artist`, plays the first match, then
    /// seeks to `position`. Returns `false` if Spotify reports nothing
    /// playable for the query.
    static func spotifyPlayTrack(title: String, artist: String, position: Double) async -> Bool {
        let query = escape("\(title) \(artist)")
        let source = """
        tell application "Spotify"
            activate
            try
                play track ("spotify:search:\(query)")
            on error
                return "not_found"
            end try
            delay 0.3
            set player position to \(position)
            return "ok"
        end tell
        """
        return await run(source) == "ok"
    }
}
