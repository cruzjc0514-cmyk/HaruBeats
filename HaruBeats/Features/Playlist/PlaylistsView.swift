import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        NavigationStack {
            List {
                favoritesSection
                playlistsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPlaylistName = ""
                        showNewPlaylistAlert = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(effectiveAccent)
                    }
                }
            }
            .alert("Nueva Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Nombre", text: $newPlaylistName)
                Button("Crear") {
                    let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        playlistManager.createPlaylist(name: trimmed)
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    private var favoritesSection: some View {
        let favSongs = playlistManager.favoriteSongs(from: audioManager.library)
        return Section {
            Button {
                if let first = favSongs.first {
                    audioManager.play(song: first, inQueue: favSongs)
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(effectiveAccent.opacity(0.25))
                            .frame(width: 52, height: 52)
                        Image(systemName: "heart.fill")
                            .font(.title2)
                            .foregroundStyle(effectiveAccent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Canciones Favoritas")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(favSongs.count) canciones")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Spacer()

                    if !favSongs.isEmpty {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(effectiveAccent)
                    }
                }
                .padding(.vertical, 4)
            }
            .disabled(favSongs.isEmpty)
        }
    }

    private var playlistsSection: some View {
        Section("Tus Playlists") {
            if playlistManager.playlists.isEmpty {
                Text("Aún no has creado playlists. Toca + arriba o importa una carpeta en Ajustes.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(playlistManager.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlistID: playlist.id)
                    } label: {
                        playlistRow(for: playlist)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            playlistManager.deletePlaylist(playlist)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func playlistRow(for playlist: Playlist) -> some View {
        let resolved = playlistManager.resolvedSongs(for: playlist, in: audioManager.library)
        return HStack(spacing: 14) {
            Group {
                if let cover = resolved.first?.thumbnailImage {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        AppTheme.cardBackground
                        Image(systemName: "music.note.list")
                            .foregroundStyle(effectiveAccent)
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(resolved.count) canciones")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}