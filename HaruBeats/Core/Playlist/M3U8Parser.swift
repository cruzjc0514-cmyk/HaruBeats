import Foundation

struct M3U8ImportResult {
    let playlistName: String
    let matchedSongs: [Song]
    let unmatchedEntries: [String]
}

enum M3U8Parser {
    static func parseAndResolve(url: URL, library: [Song]) -> M3U8ImportResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let defaultName = url.deletingPathExtension().lastPathComponent
        guard let rawContent = try? String(contentsOf: url, encoding: .utf8)
                ?? String(contentsOf: url, encoding: .isoLatin1) else {
            return M3U8ImportResult(playlistName: defaultName, matchedSongs: [], unmatchedEntries: [])
        }

        var playlistName = defaultName
        var matchedSongs: [Song] = []
        var unmatchedEntries: [String] = []
        var pendingExtInfTitle: String? = nil

        let lines = rawContent.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                if line.hasPrefix("#PLAYLIST:") {
                    let customTitle = line.replacingOccurrences(of: "#PLAYLIST:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !customTitle.isEmpty { playlistName = customTitle }
                } else if line.hasPrefix("#EXTINF:") {
                    if let commaIndex = line.firstIndex(of: ",") {
                        pendingExtInfTitle = String(line[line.index(after: commaIndex)...])
                            .trimmingCharacters(in: .whitespaces)
                    }
                }
                continue
            }

            // Es una ruta de archivo (puede venir con barras de Windows '\' o URL encoded '%20')
            if let song = resolveSong(fromPath: line, extInfTitle: pendingExtInfTitle, in: library) {
                if !matchedSongs.contains(song) {
                    matchedSongs.append(song)
                }
            } else {
                let displayName = extractFileName(from: line)
                unmatchedEntries.append(displayName)
            }
            pendingExtInfTitle = nil
        }

        return M3U8ImportResult(
            playlistName: playlistName,
            matchedSongs: matchedSongs,
            unmatchedEntries: unmatchedEntries
        )
    }

    private static func extractFileName(from rawPath: String) -> String {
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        let normalized = decoded.replacingOccurrences(of: "\\", with: "/")
        return URL(fileURLWithPath: normalized).lastPathComponent
    }

    private static func resolveSong(fromPath rawPath: String, extInfTitle: String?, in library: [Song]) -> Song? {
        let targetFileName = extractFileName(from: rawPath)
        let targetBaseName = (targetFileName as NSString).deletingPathExtension

        // Nivel 1: Coincidencia exacta por nombre de archivo (ej. "01 - Song.flac")
        if let exact = library.first(where: { $0.fileURL.lastPathComponent == targetFileName }) {
            return exact
        }

        // Nivel 2: Coincidencia ignorando mayúsculas/minúsculas o cambio de extensión
        if let byBaseName = library.first(where: {
            $0.fileURL.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(targetBaseName) == .orderedSame
        }) {
            return byBaseName
        }

        // Nivel 3: Coincidencia por título en metadatos o línea #EXTINF
        if let byTitle = library.first(where: {
            $0.title.localizedCaseInsensitiveCompare(targetBaseName) == .orderedSame ||
            (extInfTitle != nil && extInfTitle!.localizedCaseInsensitiveContains($0.title))
        }) {
            return byTitle
        }

        return nil
    }
}