import Foundation

/// A music source IslandSound can read playback state from.
enum MusicSource: String, Codable, CaseIterable, Identifiable {
    case appleMusic
    case spotify
    case boomplay
    case youtubeMusic
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .boomplay: return "Boomplay"
        case .youtubeMusic: return "YouTube Music"
        case .unknown: return "Unknown"
        }
    }

    /// Sources that post DistributedNotificationCenter playback updates natively.
    var isNativeSource: Bool {
        self == .appleMusic || self == .spotify
    }
}

/// Unified representation of the track currently playing on any source.
struct Track: Identifiable, Codable, Equatable {
    /// Stable identifier for caching (lyrics, etc). Falls back to title+artist hash
    /// when the source app does not provide a persistent id.
    var id: String
    var title: String
    var artist: String
    var album: String?
    var duration: Double // seconds
    var artworkURL: URL?

    init(id: String? = nil, title: String, artist: String, album: String? = nil, duration: Double, artworkURL: URL? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        if let id {
            self.id = id
        } else {
            self.id = Track.makeCacheKey(title: title, artist: artist)
        }
    }

    /// Deterministic cache key used for the lyrics CoreData store.
    static func makeCacheKey(title: String, artist: String) -> String {
        let normalized = "\(title)|\(artist)"
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
    }
}
