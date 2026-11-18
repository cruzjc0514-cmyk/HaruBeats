import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue

    @State private var songToAddToPlaylist: Song? = nil
    @State private var albumCreatedMessage: String? = nil

    private var accentColor: Color {
        (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var groupedAlbums: [(album: String, songs: [Song])] {
        let dict = Dictionary(grouping: audioManager.library) { $0.album }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedAlbums, id: \.album) { group in
                    Section {
                        ForEach(group.songs) { song in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .foregroundStyle(audioManager.currentSong?.fileURL == song.fileURL ? accentColor : .white)
                                    Text(song.artist)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                audioManager.isShuffle = false
                                audioManager.play(song: song, inQueue: group.songs)
                            }
                            .contextMenu {
                                Button {
                                    audioManager.isShuffle = false
                                    audioManager.play(song: song, inQueue: group.songs)
                                } label: {
                                    Label("Reproducir canción", systemImage: "play.fill")
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
                                    if let first = group.songs.first {
                                        audioManager.isShuffle = false
                                        audioManager.play(song: first, inQueue: group.songs)
                                    }
                                } label: {
                                    Label("Reproducir álbum completo", systemImage: "square.stack.fill")
                                }
                            }
                            .listRowBackground(AppTheme.cardBackground)
                        }
                    } header: {
                        HStack(spacing: 10) {
                            if let art = group.songs.first?.artworkImage {
                                Image(uiImage: art)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Text(group.album)
                                .foregroundStyle(accentColor)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                if let first = group.songs.first {
                                    audioManager.isShuffle = false
                                    audioManager.play(song: first, inQueue: group.songs)
                                }
                            } label: {
                                Label("Reproducir álbum", systemImage: "play.fill")
                            }

                            Button {
                                if let random = group.songs.randomElement() {
                                    audioManager.isShuffle = true
                                    audioManager.play(song: random, inQueue: group.songs)
                                }
                            } label: {
                                Label("Álbum en aleatorio", systemImage: "shuffle")
                            }

                            Button {
                                playlistManager.createPlaylist(name: group.album, songs: group.songs)
                                albumCreatedMessage = "Se creó la playlist '\(group.album)' con \(group.songs.count) canciones."
                            } label: {
                                Label("Guardar álbum como playlist", systemImage: "music.note.list")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Álbumes")
            .sheet(item: $songToAddToPlaylist) { song in
                PickPlaylistForSongSheet(song: song)
            }
            .alert("Playlist creada", isPresented: Binding(
                get: { albumCreatedMessage != nil },
                set: { if !$0 { albumCreatedMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(albumCreatedMessage ?? "")
            }
        }
    }
}