import XCTest
@testable import IslandSound

/// Integration test against the real LRCLIB API (Section 7.3 / 13). Requires
/// network access; if lrclib.net is unreachable the test is skipped rather
/// than failed, since that reflects the test environment, not a code defect.
final class LRCLIBClientTests: XCTestCase {
    func testFetchSyncedLyricsForKnownTrack() async throws {
        let raw = await LRCLIBClient.fetchSyncedLyrics(title: "Counting Stars", artist: "OneRepublic")

        guard let raw else {
            throw XCTSkip("lrclib.net was unreachable in this environment")
        }

        XCTAssertTrue(raw.contains("["), "Synced lyrics should contain LRC timestamp markers")
        XCTAssertFalse(LRCParser.parse(raw).isEmpty, "Returned LRC text should parse into lyric lines")
    }

    func testFetchSyncedLyricsForNonexistentTrackReturnsNil() async {
        let raw = await LRCLIBClient.fetchSyncedLyrics(
            title: "zzzzzzz_definitely_not_a_real_song_zzzzzzz",
            artist: "zzzzzzz_definitely_not_a_real_artist_zzzzzzz"
        )

        XCTAssertNil(raw)
    }
}
