import SwiftUI
import UniformTypeIdentifiers

enum LibraryBrowseMode: String, CaseIterable, Identifiable {
    case songs = "Canciones"
    case artists = "Artistas"
    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true

    @State private var browseMode: LibraryBrowseMode = .songs
    @State private var showFileImporter = false
    @State private var searchText = ""
    @State private var songToAddToPlaylist: Song? = nil
    @State private var songToDelete: Song? = nil

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var filteredSongs: [Song] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return audioManager.library }
        return audioManager.library.filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
            $0.artist.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
            $0.album.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var groupedArtists: [(artist: String, songs: [Song])] {
        let grouped = Dictionary(grouping: filteredSongs) { $0.artist }
        return grouped
            .map { (artist: $0.key, songs: $0.value) }
            .sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Modo", selection: $browseMode) {
                    ForEach(LibraryBrowseMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.background)

                if audioManager.isScanningLibrary && audioManager.library.isEmpty {
                    ProgressView("Indexando biblioteca...")
                        .tint(effectiveAccent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.background)
                } else if browseMode == .songs {
                    songsListView
                } else {
                    artistsListView
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Biblioteca")
            .searchable(text: $searchText, prompt: "Buscar título, artista o álbum")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(effectiveAccent)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio, .plainText, .data],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task { await audioManager.importFiles(urls: urls) }
                }
            }
            .sheet(item: $songToAddToPlaylist) { song in
                PickPlaylistForSongSheet(song: song)
            }
            .alert("Eliminar canción", isPresented: Binding(
                get: { songToDelete != nil },
                set: { if !$0 { songToDelete = nil } }
            )) {
                Button("Eliminar", role: .destructive) {
                    if let target = songToDelete {
                        playlistManager.purgeSongFromAllPlaylists(fileName: target.fileURL.lastPathComponent)
                        Task { await audioManager.deleteSong(target) }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se eliminará '\(songToDelete?.title ?? "")' del iPhone y de todas tus playlists.")
            }
        }
    }

    private var songsListView: some View {
        List {
            if filteredSongs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(effectiveAccent)
                    Text("No hay canciones todavía")
                        .font(.headline)
                    Text("Toca el botón + arriba a la derecha para importar tus archivos FLAC, MP3 o M4A.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredSongs) { song in
                    LibrarySongRow(
                        song: song,
                        isCurrent: audioManager.currentSong?.relativePath == song.relativePath,
                        hasLyrics: audioManager.songsWithLyrics.contains(song.relativePath),
                        accentColor: effectiveAccent,
                        onTap: {
                            audioManager.play(song: song, inQueue: filteredSongs)
                        },
                        onPlayNext: {
                            audioManager.enqueueNext(song)
                        },
                        onAddToPlaylist: {
                            songToAddToPlaylist = song
                        },
                        onDelete: {
                            songToDelete = song
                        }
                    )
                    .listRowBackground(AppTheme.cardBackground)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }

    private var artistsListView: some View {
        List {
            ForEach(groupedArtists, id: \.artist) { group in
                NavigationLink(destination: ArtistDetailView(artistName: group.artist, songs: group.songs)) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(AppTheme.elevatedBackground)
                            .frame(width: 44, height: 44)
                            .overlay {
                                if let img = group.songs.first?.thumbnailImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(effectiveAccent)
                                }
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.artist)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("\(group.songs.count) canciones")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                .listRowBackground(AppTheme.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }
}

private struct ArtistDetailView: View {
    let artistName: String
    let songs: [Song]
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        List {
            ForEach(songs) { song in
                let isCurrent = audioManager.currentSong?.relativePath == song.relativePath
                HStack(spacing: 12) {
                    Group {
                        if let img = song.thumbnailImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                AppTheme.elevatedBackground
                                Image(systemName: "music.note")
                                    .foregroundStyle(effectiveAccent)
                            }
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(isCurrent ? effectiveAccent : .white)
                            .lineLimit(1)
                        Text(song.album)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    audioManager.play(song: song, inQueue: songs)
                }
                .listRowBackground(AppTheme.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(artistName)
    }
}

private struct LibrarySongRow: View {
    let song: Song
    let isCurrent: Bool
    let hasLyrics: Bool
    let accentColor: Color
    let onTap: () -> Void
    let onPlayNext: () -> Void
    let onAddToPlaylist: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let img = song.thumbnailImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        AppTheme.elevatedBackground
                        Image(systemName: "music.note")
                            .foregroundStyle(accentColor)
                    }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isCurrent ? accentColor : .white)
                    .lineLimit(1)
                Text("\(song.artist) · \(song.album)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if hasLyrics {
                Image(systemName: "quote.bubble")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundStyle(accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(action: onTap) {
                Label("Reproducir ahora", systemImage: "play.fill")
            }
            Button(action: onPlayNext) {
                Label("Reproducir a continuación", systemImage: "text.insert")
            }
            Button(action: onAddToPlaylist) {
                Label("Agregar a playlist", systemImage: "text.badge.plus")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Eliminar canción", systemImage: "trash")
            }
        }
    }
}