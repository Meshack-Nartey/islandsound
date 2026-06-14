import XCTest
@testable import IslandSound

/// Verifies `VoiceCommand.match` recognises each "Hey Island ..." command
/// phrase and resolves ambiguous overlaps (e.g. "replay" containing "play")
/// in the documented priority order (Section 8.2 / 13).
final class VoiceCommandTests: XCTestCase {
    func testSkipAndNext() {
        XCTAssertEqual(VoiceCommand.match(in: "skip this song"), .skip)
        XCTAssertEqual(VoiceCommand.match(in: "next track"), .skip)
    }

    func testPreviousAndBack() {
        XCTAssertEqual(VoiceCommand.match(in: "go back"), .previous)
        XCTAssertEqual(VoiceCommand.match(in: "previous track"), .previous)
    }

    func testPauseAndStop() {
        XCTAssertEqual(VoiceCommand.match(in: "pause"), .pause)
        XCTAssertEqual(VoiceCommand.match(in: "stop the music"), .pause)
    }

    func testPlayAndResume() {
        XCTAssertEqual(VoiceCommand.match(in: "play"), .play)
        XCTAssertEqual(VoiceCommand.match(in: "resume"), .play)
        XCTAssertEqual(VoiceCommand.match(in: "continue"), .play)
    }

    func testReplayTakesPriorityOverPlay() {
        // "replay" and "play it again" both contain "play"/"again", but
        // should resolve to .replay, not .play.
        XCTAssertEqual(VoiceCommand.match(in: "replay this song"), .replay)
        XCTAssertEqual(VoiceCommand.match(in: "play it again"), .replay)
        XCTAssertEqual(VoiceCommand.match(in: "repeat that"), .replay)
    }

    func testWhoSingsThis() {
        XCTAssertEqual(VoiceCommand.match(in: "who sings this"), .whoSingsThis)
        XCTAssertEqual(VoiceCommand.match(in: "what song is this"), .whoSingsThis)
        XCTAssertEqual(VoiceCommand.match(in: "who is this"), .whoSingsThis)
    }

    func testShowLyrics() {
        XCTAssertEqual(VoiceCommand.match(in: "show lyrics"), .showLyrics)
        XCTAssertEqual(VoiceCommand.match(in: "lyrics please"), .showLyrics)
    }

    func testWhoSingsThisTakesPriorityOverShowLyrics() {
        // "who sings this" is checked before "lyrics", so it wins when both
        // phrases appear together.
        XCTAssertEqual(VoiceCommand.match(in: "who sings this, show lyrics"), .whoSingsThis)
    }

    func testStartRoom() {
        XCTAssertEqual(VoiceCommand.match(in: "start a room"), .startRoom)
        XCTAssertEqual(VoiceCommand.match(in: "let's start a listening room"), .startRoom)
    }

    func testVolumeUpAndDown() {
        XCTAssertEqual(VoiceCommand.match(in: "volume up"), .volumeUp)
        XCTAssertEqual(VoiceCommand.match(in: "turn it up"), .volumeUp)
        XCTAssertEqual(VoiceCommand.match(in: "louder"), .volumeUp)

        XCTAssertEqual(VoiceCommand.match(in: "volume down"), .volumeDown)
        XCTAssertEqual(VoiceCommand.match(in: "turn it down"), .volumeDown)
        XCTAssertEqual(VoiceCommand.match(in: "quieter"), .volumeDown)
    }

    func testUnrecognisedPhraseReturnsNil() {
        XCTAssertNil(VoiceCommand.match(in: "what's the weather today"))
        XCTAssertNil(VoiceCommand.match(in: ""))
    }
}
