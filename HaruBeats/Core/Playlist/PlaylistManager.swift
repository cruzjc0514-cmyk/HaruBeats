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

    // MARK: - Creación, Edición y Borrado de Playlists

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

    func renamePlaylist(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].name = trimmed
        savePlaylists()
    }

    func renamePlaylist(_ playlist: Playlist, newName: String) {
        renamePlaylist(id: playlist.id, newName: newName)
    }

    // MARK: - Gestión de Canciones en Playlists (Compatible v1.0 + relativePath v1.1)

    func addSongs(_ songs: [Song], to playlistID: UUID) {
        guard !songs.isEmpty,
              let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var existing = Set(playlists[idx].songFileNames)
        for song in songs {
            if existing.insert(song.relativePath).inserted {
                playlists[idx].songFileNames.append(song.relativePath)
            }
        }
        savePlaylists()
    }

    func addSong(_ song: Song, to playlist: Playlist) {
        addSongs([song], to: playlist.id)
    }

    func removeSongs(at offsets: IndexSet, from playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].songFileNames.remove(atOffsets: offsets)
        savePlaylists()
    }

    func removeSong(at offsets: IndexSet, from playlist: Playlist) {
        removeSongs(at: offsets, from: playlist.id)
    }

    func removeSongByFileName(_ keyOrFileName: String, from playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].songFileNames.removeAll { saved in
            saved == keyOrFileName || URL(fileURLWithPath: saved).lastPathComponent == keyOrFileName
        }
        savePlaylists()
    }

    func moveSongs(from source: IndexSet, to destination: Int, in playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].songFileNames.move(fromOffsets: source, toOffset: destination)
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
            addSongs(songs, to: playlists[idx].id)
        } else {
            createPlaylist(name: trimmed, songs: songs)
        }
    }

    // MARK: - Resolución y Migración (v1.0 lastPathComponent -> v1.1 relativePath)

    func resolvedSongs(for playlist: Playlist, in library: [Song]) -> [Song] {
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

    func songs(for playlist: Playlist, in library: [Song]) -> [Song] {
        resolvedSongs(for: playlist, in: library)
    }

    // MARK: - Importación M3U / M3U8

    @discardableResult
    func importM3U8(from url: URL, library: [Song]) -> Int {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        let matchedSongs = M3U8Parser.parseAndResolve(url: url, library: library)
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