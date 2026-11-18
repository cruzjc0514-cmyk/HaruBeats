import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue

    @State private var showFileImporter = false
    @State private var showFolderImporter = false
    @State private var searchText = ""
    @State private var folderImportMessage: String? = nil
    @State private var songToAddToPlaylist: Song? = nil
    @State private var songToDelete: Song? = nil

    private var accentColor: Color {
        (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var filteredSongs: [Song] {
        if searchText.isEmpty { return audioManager.library }
        return audioManager.library.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSongs) { song in
                    HStack(spacing: 12) {
                        Group {
                            if let img = song.artworkImage {
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
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(audioManager.currentSong?.fileURL == song.fileURL ? accentColor : .white)
                                .lineLimit(1)
                            Text("\(song.artist) · \(song.album)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.play(song: song, inQueue: filteredSongs)
                    }
                    .contextMenu {
                        Button {
                            audioManager.play(song: song, inQueue: filteredSongs)
                        } label: {
                            Label("Reproducir ahora", systemImage: "play.fill")
                        }

                        Button {
                            audioManager.enqueueNext(song)
                        } label: {
                            Label("Reproducir a continuación", systemImage: "text.insert")
                        }

                        Button {
                            songToAddToPlaylist = song
                        } label: {
                            Label("Agregar a playlist", systemImage: "text.badge.plus")
                        }

                        Divider()

                        Button {
                            searchText = song.album
                        } label: {
                            Label("Ir al álbum (\(song.album))", systemImage: "square.stack")
                        }

                        Button {
                            searchText = song.artist
                        } label: {
                            Label("Ir al artista (\(song.artist))", systemImage: "person.wave.2")
                        }

                        Divider()

                        Button(role: .destructive) {
                            songToDelete = song
                        } label: {
                            Label("Eliminar canción", systemImage: "trash")
                        }
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .searchable(text: $searchText, prompt: "Buscar canciones, artistas o álbumes")
            .navigationTitle("Biblioteca")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Importar archivos", systemImage: "doc.badge.plus")
                        }

                        Button {
                            showFolderImporter = true
                        } label: {
                            Label("Importar carpeta (crea playlist)", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(accentColor)
                    }
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
                        Task {
                            playlistManager.purgeSongFromAllPlaylists(fileName: target.fileURL.lastPathComponent)
                            await audioManager.deleteSong(target)
                        }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borrará '\(songToDelete?.title ?? "")' del almacenamiento de HaruBeats.")
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio, .plainText, UTType(filenameExtension: "lrc") ?? .data],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task {
                        await audioManager.importFiles(urls: urls)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let folderURL = urls.first {
                    Task {
                        let outcome = await audioManager.importFolder(url: folderURL)
                        if !outcome.importedSongs.isEmpty {
                            playlistManager.createPlaylist(
                                name: outcome.folderName,
                                songs: outcome.importedSongs
                            )
                            folderImportMessage = "Se importaron \(outcome.importedSongs.count) canciones y se creó la playlist '\(outcome.folderName)'."
                        } else {
                            folderImportMessage = "No se encontraron archivos de audio compatibles en '\(outcome.folderName)'."
                        }
                    }
                }
            }
            .alert("Importación de carpeta", isPresented: Binding(
                get: { folderImportMessage != nil },
                set: { if !$0 { folderImportMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(folderImportMessage ?? "")
            }
        }
    }
}