import XCTest
@testable import IslandSound

/// Verifies the CoreData-backed `LyricsCache` round-trips synced lyrics
/// purely from local storage (Section 7.5) -- no network involved, so a
/// cache hit costs zero LRCLIB requests.
final class LyricsCacheTests: XCTestCase {
    func testStoreThenFetchReturnsTheSameRawLRC() async {
        let cache = LyricsCache(inMemory: true)
        let raw = "[00:01.00] Hello\n[00:02.00] World"

        await cache.store(trackId: "artist|title", raw: raw, source: .lrclib)
        let fetched = await cache.fetch(trackId: "artist|title")

        XCTAssertEqual(fetched, raw)
    }

    func testFetchOnCacheMissReturnsNil() async {
        let cache = LyricsCache(inMemory: true)

        let fetched = await cache.fetch(trackId: "never-stored")

        XCTAssertNil(fetched)
    }

    func testStoreOverwritesPreviousEntryForSameTrack() async {
        let cache = LyricsCache(inMemory: true)

        await cache.store(trackId: "artist|title", raw: "[00:01.00] Old", source: .lrclib)
        await cache.store(trackId: "artist|title", raw: "[00:01.00] New", source: .userImported)

        let fetched = await cache.fetch(trackId: "artist|title")

        XCTAssertEqual(fetched, "[00:01.00] New")
    }
}
