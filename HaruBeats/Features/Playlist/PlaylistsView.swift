import SwiftUI
import UniformTypeIdentifiers

struct PlaylistsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var showM3UImporter = false
    @State private var showFolderImporter = false
    @State private var importSummaryMessage: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if playlistManager.playlists.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundStyle(.indigo)
                        Text("Sin playlists todavía")
                            .font(.headline)
                        Text("Crea una playlist, importa una carpeta completa o carga tu archivo descargas.m3u8.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        VStack(spacing: 10) {
                            Button {
                                showFolderImporter = true
                            } label: {
                                Label("Importar carpeta como playlist", systemImage: "folder.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 11)
                                    .background(Color.indigo)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }

                            HStack(spacing: 12) {
                                Button {
                                    newPlaylistName = ""
                                    showNewPlaylistAlert = true
                                } label: {
                                    Label("Nueva", systemImage: "plus")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(AppTheme.elevatedBackground)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }

                                Button {
                                    showM3UImporter = true
                                } label: {
                                    Label("Importar .m3u8", systemImage: "square.and.arrow.down")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(AppTheme.elevatedBackground)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
                } else {
                    List {
                        ForEach(playlistManager.playlists) { playlist in
                            let resolved = playlistManager.resolvedSongs(for: playlist, in: audioManager.library)
                            NavigationLink(destination: PlaylistDetailView(playlistID: playlist.id)) {
                                HStack(spacing: 14) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(AppTheme.elevatedBackground)
                                        .frame(width: 50, height: 50)
                                        .overlay {
                                            if let firstArt = resolved.first?.artworkImage {
                                                Image(uiImage: firstArt)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                            } else {
                                                Image(systemName: "music.note.list")
                                                    .foregroundStyle(.indigo)
                                            }
                                        }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.white)
                                        Text("\(resolved.count) canciones")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                }
                            }
                            .listRowBackground(AppTheme.cardBackground)
                        }
                        .onDelete { offsets in
                            playlistManager.deletePlaylists(at: offsets)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.background)
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newPlaylistName = ""
                            showNewPlaylistAlert = true
                        } label: {
                            Label("Nueva playlist vacía", systemImage: "plus")
                        }

                        Button {
                            showFolderImporter = true
                        } label: {
                            Label("Importar carpeta como playlist", systemImage: "folder.badge.plus")
                        }

                        Button {
                            showM3UImporter = true
                        } label: {
                            Label("Importar archivo .m3u8", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .alert("Nueva playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Nombre de la playlist", text: $newPlaylistName)
                Button("Crear") {
                    playlistManager.createPlaylist(name: newPlaylistName)
                }
                Button("Cancelar", role: .cancel) {}
            }
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let folderURL = urls.first {
                    Task {
                        let outcome = await audioManager.importFolder(url: folderURL)
                        if outcome.importedSongs.isEmpty {
                            importSummaryMessage = "No se encontraron archivos de audio compatibles dentro de '\(outcome.folderName)'."
                        } else {
                            playlistManager.createPlaylist(
                                name: outcome.folderName,
                                songs: outcome.importedSongs
                            )
                            importSummaryMessage = "Se creó la playlist '\(outcome.folderName)' con \(outcome.importedSongs.count) canciones (y sus letras .lrc disponibles)."
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showM3UImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "m3u8") ?? .plainText,
                    UTType(filenameExtension: "m3u") ?? .plainText,
                    .plainText
                ],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let importResult = M3U8Parser.parseAndResolve(url: url, library: audioManager.library)
                    playlistManager.createPlaylist(
                        name: importResult.playlistName,
                        songs: importResult.matchedSongs
                    )
                    if importResult.unmatchedEntries.isEmpty {
                        importSummaryMessage = "Se importó '\(importResult.playlistName)' con \(importResult.matchedSongs.count) canciones."
                    } else {
                        importSummaryMessage = "Se importaron \(importResult.matchedSongs.count) canciones. \(importResult.unmatchedEntries.count) aún no están en tu biblioteca."
                    }
                }
            }
            .alert("Importación completada", isPresented: Binding(
                get: { importSummaryMessage != nil },
                set: { if !$0 { importSummaryMessage = nil } }
            )) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text(importSummaryMessage ?? "")
            }
        }
    }
}