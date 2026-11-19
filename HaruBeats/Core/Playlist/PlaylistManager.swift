import Foundation
import SwiftUI

@MainActor
final class PlaylistManager: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var favoriteRelativePaths: Set<String> = []

    private let playlistsKey = "hb_playlists_v2"
    private let legacyPlaylistsKey = "hb_playlists_v1"
    private let favoritesKey = "hb_favorites_v2"
    private let legacyFavoritesKey = "hb_favorites_v1"

    init() {
        loadFromStorage()
    }

    // MARK: - Favoritos

    func isFavorite(_ song: Song) -> Bool {
        favoriteRelativePaths.contains(song.relativePath)
            || favoriteRelativePaths.contains(song.fileURL.lastPathComponent)
    }

    func toggleFavorite(_ song: Song) {
        let key = song.relativePath
        let legacyKey = song.fileURL.lastPathComponent
        if favoriteRelativePaths.contains(key) || favoriteRelativePaths.contains(legacyKey) {
            favoriteRelativePaths.remove(key)
            favoriteRelativePaths.remove(legacyKey)
        } else {
            favoriteRelativePaths.insert(key)
        }
        saveFavorites()
    }

    func favoriteSongs(from library: [Song]) -> [Song] {
        library.filter { isFavorite($0) }
    }

    // MARK: - Gestión de Playlists

    @discardableResult
    func createPlaylist(name: String, songs: [Song] = []) -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Nueva Playlist" : trimmed
        let newPlaylist = Playlist(
            name: finalName,
            songFileNames: songs.map(\.relativePath)
        )
        playlists.append(newPlaylist)
        savePlaylists()
        return newPlaylist
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
    }

    func deletePlaylists(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        savePlaylists()
    }

    func renamePlaylist(_ playlist: Playlist, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].name = trimmed
        savePlaylists()
    }

    func addSong(_ song: Song, to playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let key = song.relativePath
        if !playlists[idx].songFileNames.contains(key) {
            playlists[idx].songFileNames.append(key)
            savePlaylists()
        }
    }

    func removeSong(at offsets: IndexSet, from playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].songFileNames.remove(atOffsets: offsets)
        savePlaylists()
    }

    func addSongToNamedPlaylist(song: Song, playlistName: String) {
        let trimmed = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let idx = playlists.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            let key = song.relativePath
            if !playlists[idx].songFileNames.contains(key) {
                playlists[idx].songFileNames.append(key)
                savePlaylists()
            }
        } else {
            createPlaylist(name: trimmed, songs: [song])
        }
    }

    func createOrAppendPlaylist(name: String, songs: [Song]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !songs.isEmpty else { return }

        if let idx = playlists.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            var existing = Set(playlists[idx].songFileNames)
            for song in songs {
                if existing.insert(song.relativePath).inserted {
                    playlists[idx].songFileNames.append(song.relativePath)
                }
            }
            savePlaylists()
        } else {
            createPlaylist(name: trimmed, songs: songs)
        }
    }

    // MARK: - Resolución y Migración (v1.0 lastPathComponent -> v1.1 relativePath)

    func songs(for playlist: Playlist, in library: [Song]) -> [Song] {
        var byRelativePath: [String: Song] = [:]
        var byFileName: [String: Song] = [:]

        for song in library {
            byRelativePath[song.relativePath] = song
            if byFileName[song.fileURL.lastPathComponent] == nil {
                byFileName[song.fileURL.lastPathComponent] = song
            }
        }

        var resolved: [Song] = []
        for savedKey in playlist.songFileNames {
            if let match = byRelativePath[savedKey] ?? byFileName[savedKey] {
                resolved.append(match)
            }
        }
        return resolved
    }

    // MARK: - Importación M3U / M3U8

    @discardableResult
    func importM3U8(from url: URL, library: [Song]) -> Int {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        let entries = M3U8Parser.parse(url: url)
        guard !entries.isEmpty else { return 0 }

        var byRelativePath: [String: Song] = [:]
        var byFileName: [String: Song] = [:]

        for song in library {
            byRelativePath[song.relativePath.lowercased()] = song
            let fname = song.fileURL.lastPathComponent.lowercased()
            if byFileName[fname] == nil {
                byFileName[fname] = song
            }
        }

        var matchedSongs: [Song] = []
        var seenIDs = Set<String>()

        for entry in entries {
            let normalized = entry.replacingOccurrences(of: "\\", with: "/")
            let fileNameOnly = URL(fileURLWithPath: normalized).lastPathComponent.lowercased()
            let lowerFull = normalized.lowercased()

            let found = byRelativePath[lowerFull]
                ?? library.first(where: { lowerFull.hasSuffix($0.relativePath.lowercased()) })
                ?? byFileName[fileNameOnly]

            if let song = found, seenIDs.insert(song.relativePath).inserted {
                matchedSongs.append(song)
            }
        }

        let playlistName = url.deletingPathExtension().lastPathComponent
        if !matchedSongs.isEmpty {
            createOrAppendPlaylist(name: playlistName, songs: matchedSongs)
        }
        return matchedSongs.count
    }

    // MARK: - Persistencia

    private func loadFromStorage() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: playlistsKey) ?? defaults.data(forKey: legacyPlaylistsKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }

        if let favArray = defaults.stringArray(forKey: favoritesKey) ?? defaults.stringArray(forKey: legacyFavoritesKey) {
            favoriteRelativePaths = Set(favArray)
        }
    }

    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: playlistsKey)
        }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteRelativePaths), forKey: favoritesKey)
    }
}