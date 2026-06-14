import Foundation

/// Client for LRCLIB (lrclib.net) — a free, no-auth synced-lyrics API
/// (Section 7.3 / FEATURE 4).
enum LRCLIBClient {
    /// Result of an LRCLIB lookup. `plain` is included as a fallback for
    /// tracks (e.g. live recordings) that only have unsynced lyrics on LRCLIB.
    struct LyricsResult {
        let synced: String?
        let plain: String?
    }

    private struct SearchResult: Decodable {
        let id: Int
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private struct GetResult: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    /// All network calls use a 10-second timeout (Section 11.3).
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// Searches LRCLIB for `title`/`artist` and returns both synced (LRC) and
    /// plain lyrics for the best match, or `nil` if nothing was found.
    ///
    /// `GET https://lrclib.net/api/search?track_name=...&artist_name=...`
    /// falling back to `GET https://lrclib.net/api/get/{id}` if the search
    /// result doesn't inline lyrics.
    static func fetchLyrics(title: String, artist: String) async -> LyricsResult? {
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            let results = try JSONDecoder().decode([SearchResult].self, from: data)
            guard let best = results.first(where: { $0.syncedLyrics?.isEmpty == false }) ?? results.first else {
                return nil
            }

            if let synced = best.syncedLyrics, !synced.isEmpty {
                return LyricsResult(synced: synced, plain: best.plainLyrics)
            }

            return await fetchById(best.id) ?? LyricsResult(synced: nil, plain: best.plainLyrics)
        } catch {
            return nil
        }
    }

    /// Convenience for callers that only care about synced (LRC) lyrics.
    static func fetchSyncedLyrics(title: String, artist: String) async -> String? {
        await fetchLyrics(title: title, artist: artist)?.synced
    }

    private static func fetchById(_ id: Int) async -> LyricsResult? {
        guard let url = URL(string: "https://lrclib.net/api/get/\(id)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(GetResult.self, from: data)
            return LyricsResult(synced: result.syncedLyrics, plain: result.plainLyrics)
        } catch {
            return nil
        }
    }
}
