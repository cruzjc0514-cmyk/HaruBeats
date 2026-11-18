import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @State private var showFileImporter = false
    @State private var showFolderImporter = false
    @State private var searchText = ""
    @State private var folderImportMessage: String? = nil

    var filteredSongs: [Song] {
        if searchText.isEmpty { return audioManager.library }
        return audioManager.library.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSongs) { song in
                    Button {
                        audioManager.play(song: song, inQueue: filteredSongs)
                    } label: {
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
                                            .foregroundStyle(.indigo)
                                    }
                                }
                            }
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(audioManager.currentSong == song ? .indigo : .white)
                                    .lineLimit(1)
                                Text("\(song.artist) · \(song.album)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .searchable(text: $searchText, prompt: "Buscar canciones o artistas")
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
                            .foregroundStyle(.indigo)
                    }
                }
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