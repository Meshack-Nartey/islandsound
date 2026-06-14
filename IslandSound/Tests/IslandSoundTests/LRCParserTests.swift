import XCTest
@testable import IslandSound

/// Verifies `LRCParser.parse` handles well-formed LRC lines, normalises
/// fractional-second timestamps, sorts by time, and silently skips malformed
/// or metadata lines (Section 7.4).
final class LRCParserTests: XCTestCase {
    func testParsesWellFormedLinesInOrder() {
        let raw = """
        [00:01.00] First line
        [00:05.50] Second line
        [00:12.25] Third line
        """

        let lines = LRCParser.parse(raw)

        XCTAssertEqual(lines.map(\.text), ["First line", "Second line", "Third line"])
        XCTAssertEqual(lines.map(\.timestamp), [1.0, 5.5, 12.25])
    }

    func testSortsOutOfOrderLinesByTimestamp() {
        let raw = """
        [00:10.00] Later
        [00:02.00] Earlier
        """

        let lines = LRCParser.parse(raw)

        XCTAssertEqual(lines.map(\.text), ["Earlier", "Later"])
    }

    func testNormalisesFractionalSecondsOfDifferentWidths() {
        let raw = """
        [00:01.5] half second
        [00:02.50] half second again
        [00:03.500] half second yet again
        """

        let lines = LRCParser.parse(raw)

        XCTAssertEqual(lines.map(\.timestamp), [1.5, 2.5, 3.5])
    }

    func testSkipsMetadataTagsThatArentTimestamps() {
        let raw = """
        [ar:Some Artist]
        [ti:Some Title]
        [offset:1000]
        [00:01.00] Real line
        """

        let lines = LRCParser.parse(raw)

        XCTAssertEqual(lines.map(\.text), ["Real line"])
    }

    func testSkipsLinesWithMalformedTimestamps() {
        let raw = """
        [1:2] too few digits
        [00:01.00] Valid line
        not a timestamp at all
        """

        let lines = LRCParser.parse(raw)

        XCTAssertEqual(lines.map(\.text), ["Valid line"])
    }

    func testEmptyInputProducesNoLines() {
        XCTAssertTrue(LRCParser.parse("").isEmpty)
    }

    func testLineWithTimestampButNoTextProducesEmptyString() {
        let lines = LRCParser.parse("[00:00.00]")
        XCTAssertEqual(lines.map(\.text), [""])
    }
}
