import SwiftUI
import UniformTypeIdentifiers

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case title = "Título"
    case artist = "Artista"
    case album = "Álbum"
    case recent = "Recientes"

    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true

    @State private var searchText = ""
    @State private var sortOption: LibrarySortOption = .title
    @State private var showFileImporter = false
    @State private var songToAddToPlaylist: Song? = nil

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    private var filteredSongs: [Song] {
        let base: [Song]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = audioManager.library
        } else {
            let query = searchText.lowercased()
            base = audioManager.library.filter {
                $0.title.lowercased().contains(query)
                || $0.artist.lowercased().contains(query)
                || $0.album.lowercased().contains(query)
            }
        }

        switch sortOption {
        case .title:
            return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            return base.sorted {
                if $0.artist != $1.artist {
                    return $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
                }
                return $0.trackNumber < $1.trackNumber
            }
        case .album:
            return base.sorted {
                if $0.album != $1.album {
                    return $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending
                }
                if $0.discNumber != $1.discNumber {
                    return $0.discNumber < $1.discNumber
                }
                return $0.trackNumber < $1.trackNumber
            }
        case .recent:
            return base
        }
    }

    var body: some View {
        NavigationStack {
            contentView
                .background(AppTheme.background)
                .navigationTitle("Biblioteca")
                .searchable(text: $searchText, prompt: "Buscar canción, artista o álbum")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        sortMenu
                        importButton
                    }
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [
                        .audio,
                        UTType(filenameExtension: "flac") ?? .audio,
                        UTType(filenameExtension: "lrc") ?? .plainText,
                        .plainText
                    ],
                    allowsMultipleSelection: true,
                    onCompletion: handleImportedFiles
                )
                .sheet(item: $songToAddToPlaylist) { song in
                    PickPlaylistForSongSheet(song: song)
                }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        let songs = filteredSongs
        if audioManager.isScanningLibrary && audioManager.library.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(effectiveAccent)
                Text("Escaneando biblioteca...")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if songs.isEmpty {
            emptyStateView
        } else {
            songsListView(songs: songs)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.house")
                .font(.system(size: 48))
                .foregroundStyle(effectiveAccent)
            Text(audioManager.library.isEmpty ? "Tu biblioteca está vacía" : "Sin resultados")
                .font(.headline)
                .foregroundStyle(.white)
            Text(audioManager.library.isEmpty
                 ? "Importa archivos FLAC, MP3, M4A o LRC con el botón + de arriba o desde Transferencia Wi-Fi en Ajustes."
                 : "Prueba con otro término de búsqueda.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func songsListView(songs: [Song]) -> some View {
        List {
            quickActionHeader(songs: songs)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            ForEach(songs) { song in
                songRow(song: song, songs: songs)
            }
            .onDelete { offsets in
                for index in offsets {
                    let target = songs[index]
                    Task {
                        await audioManager.deleteSong(target)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func quickActionHeader(songs: [Song]) -> some View {
        HStack(spacing: 12) {
            Button {
                if let first = songs.first {
                    audioManager.play(song: first, inQueue: songs)
                }
            } label: {
                Label("Reproducir todo", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(effectiveAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                audioManager.isShuffle = true
                if let randomSong = songs.randomElement() {
                    audioManager.play(song: randomSong, inQueue: songs)
                }
            } label: {
                Label("Aleatorio", systemImage: "shuffle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.cardBackground)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func songRow(song: Song, songs: [Song]) -> some View {
        let isCurrent = audioManager.currentSong?.relativePath == song.relativePath
        let hasLyrics = audioManager.songsWithLyrics.contains(song.relativePath)

        return SongRowItemView(
            song: song,
            isCurrent: isCurrent,
            isPlaying: isCurrent && audioManager.isPlaying,
            hasLyrics: hasLyrics,
            accentColor: effectiveAccent
        )
        .contentShape(Rectangle())
        .onTapGesture {
            audioManager.play(song: song, inQueue: songs)
        }
        .contextMenu {
            Button {
                audioManager.enqueueNext(song)
            } label: {
                Label("Reproducir a continuación", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                audioManager.appendToQueue(song)
            } label: {
                Label("Agregar a la cola", systemImage: "text.append")
            }

            Button {
                songToAddToPlaylist = song
            } label: {
                Label("Agregar a playlist...", systemImage: "plus.circle")
            }

            Button {
                playlistManager.toggleFavorite(song)
            } label: {
                let fav = playlistManager.isFavorite(song)
                Label(fav ? "Quitar de favoritos" : "Marcar como favorita", systemImage: fav ? "heart.slash" : "heart")
            }

            Divider()

            Button(role: .destructive) {
                Task {
                    await audioManager.deleteSong(song)
                }
            } label: {
                Label("Eliminar archivo", systemImage: "trash")
            }
        }
        .listRowBackground(Color.clear)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Ordenar por", selection: $sortOption) {
                ForEach(LibrarySortOption.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .foregroundStyle(effectiveAccent)
        }
    }

    private var importButton: some View {
        Button {
            showFileImporter = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(effectiveAccent)
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            Task {
                await audioManager.importFiles(urls: urls)
            }
        }
    }
}

struct SongRowItemView: View, Equatable {
    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool
    let hasLyrics: Bool
    let accentColor: Color

    static func == (lhs: SongRowItemView, rhs: SongRowItemView) -> Bool {
        lhs.song.relativePath == rhs.song.relativePath &&
        lhs.isCurrent == rhs.isCurrent &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.hasLyrics == rhs.hasLyrics &&
        lhs.accentColor == rhs.accentColor
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let img = song.thumbnailImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        AppTheme.cardBackground
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

                HStack(spacing: 6) {
                    Text(song.artist)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)

                    if song.isHiRes {
                        Text(song.codec)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(accentColor.opacity(0.2))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                    }

                    if hasLyrics {
                        Text("LRC")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Text(song.formattedDuration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 2)
    }
}