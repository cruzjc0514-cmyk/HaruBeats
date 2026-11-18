import Foundation
import Combine

@MainActor
final class PlaylistManager: ObservableObject {
    @Published var playlists: [Playlist] = []

    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("harubeats_playlists.json")
    }

    init() {
        loadPlaylists()
    }

    func loadPlaylists() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data) else {
            return
        }
        self.playlists = decoded
    }

    private func savePlaylists() {
        guard let encoded = try? JSONEncoder().encode(playlists) else { return }
        try? encoded.write(to: storageURL, options: .atomic)
    }

    func createPlaylist(name: String, songs: [Song] = []) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let fileNames = songs.map { $0.fileURL.lastPathComponent }
        let newPlaylist = Playlist(name: cleanName, songFileNames: fileNames)
        playlists.insert(newPlaylist, at: 0)
        savePlaylists()
    }

    func renamePlaylist(id: UUID, newName: String) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = cleanName
        savePlaylists()
    }

    func deletePlaylists(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        savePlaylists()
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
    }

    func addSongs(_ songs: [Song], to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        for song in songs {
            let fileName = song.fileURL.lastPathComponent
            if !playlists[index].songFileNames.contains(fileName) {
                playlists[index].songFileNames.append(fileName)
            }
        }
        savePlaylists()
    }

    func removeSongs(at offsets: IndexSet, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songFileNames.remove(atOffsets: offsets)
        savePlaylists()
    }

    func removeSongByFileName(_ fileName: String, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songFileNames.removeAll { $0 == fileName }
        savePlaylists()
    }

    func purgeSongFromAllPlaylists(fileName: String) {
        for idx in playlists.indices {
            playlists[idx].songFileNames.removeAll { $0 == fileName }
        }
        savePlaylists()
    }

    func moveSongs(from source: IndexSet, to destination: Int, in playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songFileNames.move(fromOffsets: source, toOffset: destination)
        savePlaylists()
    }

    func resolvedSongs(for playlist: Playlist, in library: [Song]) -> [Song] {
        playlist.songFileNames.compactMap { fileName in
            library.first(where: { $0.fileURL.lastPathComponent == fileName })
        }
    }
}