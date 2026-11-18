import Foundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
}

enum LRCParser {
    static func parse(content: String) -> [LyricLine] {
        var result: [LyricLine] = []
        let lines = content.components(separatedBy: .newlines)
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for rawLine in lines {
            let nsLine = rawLine as NSString
            let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }

            var lyricText = rawLine
            for match in matches.reversed() {
                if let range = Range(match.range, in: lyricText) {
                    lyricText.removeSubrange(range)
                }
            }
            let cleanedText = lyricText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedText.isEmpty else { continue }

            for match in matches {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let fracRange = match.range(at: 3)
                let fracStr = fracRange.location != NSNotFound ? nsLine.substring(with: fracRange) : "0"

                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                let fraction: Double
                if fracStr.count == 3 {
                    fraction = (Double(fracStr) ?? 0) / 1000.0
                } else {
                    fraction = (Double(fracStr) ?? 0) / 100.0
                }

                let totalSeconds = (minutes * 60.0) + seconds + fraction
                result.append(LyricLine(timestamp: totalSeconds, text: cleanedText))
            }
        }

        return result.sorted { $0.timestamp < $1.timestamp }
    }
}