import Foundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum LRCParser {
    static func parse(content: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let rawLines = content.components(separatedBy: .newlines)

        for rawLine in rawLines {
            let nsRange = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = regex.matches(in: rawLine, range: nsRange)
            guard !matches.isEmpty else { continue }

            // Extraer el texto que queda después de la última marca de tiempo
            guard let lastMatch = matches.last,
                  let lastRange = Range(lastMatch.range, in: rawLine) else { continue }

            let lyricText = String(rawLine[lastRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Si una línea está vacía (pausa instrumental), conservamos "♪" sutil o espacio
            let displayText = lyricText.isEmpty ? "•••" : lyricText

            for match in matches {
                guard let minRange = Range(match.range(at: 1), in: rawLine),
                      let secRange = Range(match.range(at: 2), in: rawLine),
                      let minutes = Double(rawLine[minRange]),
                      let seconds = Double(rawLine[secRange]) else { continue }

                var fraction: Double = 0
                if match.range(at: 3).location != NSNotFound,
                   let fracRange = Range(match.range(at: 3), in: rawLine) {
                    let fracStr = String(rawLine[fracRange])
                    if let rawFrac = Double(fracStr) {
                        fraction = rawFrac / pow(10.0, Double(fracStr.count))
                    }
                }

                let totalSeconds = (minutes * 60.0) + seconds + fraction
                lines.append(LyricLine(time: totalSeconds, text: displayText))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }
}