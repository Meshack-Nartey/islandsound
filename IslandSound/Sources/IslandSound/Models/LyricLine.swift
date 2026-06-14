import Foundation

/// A single time-stamped line of synced lyrics, parsed from LRC format.
struct LyricLine: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Double // seconds
    let text: String

    init(id: UUID = UUID(), timestamp: Double, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}

/// Parses LRC-format synced lyrics into an array of `LyricLine`, sorted by timestamp.
///
/// LRC lines look like: `[00:12.50] In the beginning was the Word`
/// Malformed lines (no timestamp, unparsable numbers) are skipped rather than
/// throwing, so a partially-broken LRC file still yields whatever is usable.
enum LRCParser {
    private static let timestampRegex = try! NSRegularExpression(
        pattern: #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)"#
    )

    static func parse(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)

            guard let match = timestampRegex.firstMatch(in: line, range: nsRange) else {
                continue
            }

            guard
                let minutesRange = Range(match.range(at: 1), in: line),
                let secondsRange = Range(match.range(at: 2), in: line),
                let minutes = Double(line[minutesRange]),
                let seconds = Double(line[secondsRange])
            else {
                continue
            }

            var fraction: Double = 0
            if match.range(at: 3).location != NSNotFound,
               let fractionRange = Range(match.range(at: 3), in: line) {
                let fractionString = String(line[fractionRange])
                if let fractionValue = Double(fractionString) {
                    // Normalize ".5" -> 0.5s, ".50" -> 0.50s, ".500" -> 0.500s
                    let divisor = pow(10.0, Double(fractionString.count))
                    fraction = fractionValue / divisor
                }
            }

            let textRange = Range(match.range(at: 4), in: line) ?? line.endIndex..<line.endIndex
            let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)

            // Skip metadata tags like [ar:], [ti:], [al:] which match minutes:seconds
            // patterns only if they happen to look numeric -- guard against that by
            // requiring the captured "minutes" group to be purely numeric, which the
            // regex already guarantees, but metadata tags such as [offset:1000] won't
            // have a colon-separated mm:ss shape so they simply won't match at all.

            let timestamp = minutes * 60 + seconds + fraction
            lines.append(LyricLine(timestamp: timestamp, text: text))
        }

        return lines.sorted { $0.timestamp < $1.timestamp }
    }
}
