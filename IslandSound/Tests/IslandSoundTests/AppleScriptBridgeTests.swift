import XCTest
@testable import IslandSound

/// `AppleScriptBridge.escape` is the only thing standing between track
/// metadata (titles/artists from the network or user input) and string
/// interpolation into AppleScript source -- it must neutralise both quotes
/// and backslashes to prevent syntax breakage or command injection
/// (Section 11.2 / 13).
final class AppleScriptBridgeTests: XCTestCase {
    func testEscapesDoubleQuotes() {
        XCTAssertEqual(AppleScriptBridge.escape(#"Wendy's "Greatest Hits""#), #"Wendy's \"Greatest Hits\""#)
    }

    func testEscapesBackslashes() {
        XCTAssertEqual(AppleScriptBridge.escape(#"C:\Music\Track"#), #"C:\\Music\\Track"#)
    }

    func testBackslashesAreEscapedBeforeQuotes() {
        // A naive quote-first replacement would double-escape the backslash
        // introduced by quote-escaping. Backslashes must be handled first.
        XCTAssertEqual(AppleScriptBridge.escape(#"\""#), #"\\\""#)
    }

    func testStringWithoutSpecialCharactersIsUnchanged() {
        XCTAssertEqual(AppleScriptBridge.escape("Counting Stars"), "Counting Stars")
    }

    func testInjectionAttemptIsNeutralisedAsLiteralText() {
        let malicious = #"" & (do shell script "rm -rf ~") & ""#
        let escaped = AppleScriptBridge.escape(malicious)

        // The escaped form should contain no bare, unescaped double quotes,
        // so it can only be interpreted as inert literal text once
        // re-wrapped in an AppleScript string literal.
        let withoutEscapedQuotes = escaped.replacingOccurrences(of: #"\""#, with: "")
        XCTAssertFalse(withoutEscapedQuotes.contains("\""))
    }
}
