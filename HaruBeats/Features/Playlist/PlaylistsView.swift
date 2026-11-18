import SwiftUI
import UniformTypeIdentifiers

struct PlaylistsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var showM3UImporter = false
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
                        Text("Crea una playlist nueva o importa tu archivo descargas.m3u8 desde la carpeta James Gunn VIBES.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        HStack(spacing: 12) {
                            Button {
                                newPlaylistName = ""
                                showNewPlaylistAlert = true
                            } label: {
                                Label("Nueva playlist", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.indigo)
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showM3UImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }

                    Button {
                        newPlaylistName = ""
                        showNewPlaylistAlert = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
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
            .alert("Importación M3U8", isPresented: Binding(
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