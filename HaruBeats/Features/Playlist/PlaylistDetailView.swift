import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var showAddSongsSheet = false
    @State private var showRenameAlert = false
    @State private var editedName = ""
    @State private var editMode: EditMode = .inactive

    private var playlist: Playlist? {
        playlistManager.playlists.first(where: { $0.id == playlistID })
    }

    private var songs: [Song] {
        guard let playlist else { return [] }
        return playlistManager.resolvedSongs(for: playlist, in: audioManager.library)
    }

    var body: some View {
        Group {
            if let playlist {
                List {
                    // Cabecera con botones de reproducción
                    Section {
                        VStack(spacing: 16) {
                            HStack(spacing: 14) {
                                Button {
                                    if let first = songs.first {
                                        audioManager.isShuffle = false
                                        audioManager.play(song: first, inQueue: songs)
                                    }
                                } label: {
                                    Label("Reproducir", systemImage: "play.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.indigo)
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(songs.isEmpty)

                                Button {
                                    if let random = songs.randomElement() {
                                        audioManager.isShuffle = true
                                        audioManager.play(song: random, inQueue: songs)
                                    }
                                } label: {
                                    Label("Aleatorio", systemImage: "shuffle")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(AppTheme.elevatedBackground)
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(songs.isEmpty)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }

                    // Lista de canciones
                    Section(header: Text("\(songs.count) canciones").foregroundStyle(AppTheme.secondaryText)) {
                        ForEach(songs) { song in
                            Button {
                                audioManager.play(song: song, inQueue: songs)
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
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(audioManager.currentSong == song ? .indigo : .white)
                                            .lineLimit(1)
                                        Text(song.artist)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .listRowBackground(AppTheme.cardBackground)
                        }
                        .onDelete { offsets in
                            playlistManager.removeSongs(at: offsets, from: playlist.id)
                        }
                        .onMove { source, destination in
                            playlistManager.moveSongs(from: source, to: destination, in: playlist.id)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
                .navigationTitle(playlist.name)
                .environment(\.editMode, $editMode)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showAddSongsSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }

                        Menu {
                            Button {
                                editedName = playlist.name
                                showRenameAlert = true
                            } label: {
                                Label("Renombrar playlist", systemImage: "pencil")
                            }

                            Button {
                                editMode = (editMode == .active) ? .inactive : .active
                            } label: {
                                Label(editMode == .active ? "Listo" : "Reordenar canciones", systemImage: "arrow.up.arrow.down")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .alert("Renombrar playlist", isPresented: $showRenameAlert) {
                    TextField("Nombre", text: $editedName)
                    Button("Guardar") {
                        playlistManager.renamePlaylist(id: playlist.id, newName: editedName)
                    }
                    Button("Cancelar", role: .cancel) {}
                }
                .sheet(isPresented: $showAddSongsSheet) {
                    AddSongsToPlaylistSheet(playlistID: playlist.id)
                }
            }
        }
    }
}

struct AddSongsToPlaylistSheet: View {
    let playlistID: UUID
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List(audioManager.library) { song in
                Button {
                    if selectedIDs.contains(song.id) {
                        selectedIDs.remove(song.id)
                    } else {
                        selectedIDs.insert(song.id)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(song.title)
                                .foregroundStyle(.white)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: selectedIDs.contains(song.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedIDs.contains(song.id) ? .indigo : .gray)
                    }
                }
                .listRowBackground(AppTheme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Agregar canciones")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir (\(selectedIDs.count))") {
                        let chosen = audioManager.library.filter { selectedIDs.contains($0.id) }
                        playlistManager.addSongs(chosen, to: playlistID)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }
}