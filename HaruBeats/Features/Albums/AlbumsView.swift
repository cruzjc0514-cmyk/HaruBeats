import SwiftUI

struct AlbumGroup: Identifiable {
    var id: String { "\(albumArtist)__\(title)" }
    let title: String
    let albumArtist: String
    let year: String?
    let songs: [Song]
    var coverImage: UIImage? { songs.first?.thumbnailImage }
}

struct AlbumsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var albums: [AlbumGroup] {
        let grouped = Dictionary(grouping: audioManager.library) { song in
            "\(song.albumArtist.lowercased())__\(song.album.lowercased())"
        }
        return grouped.values.compactMap { groupSongs -> AlbumGroup? in
            guard let first = groupSongs.first else { return nil }
            let sortedTracks = groupSongs.sorted {
                if $0.discNumber != $1.discNumber {
                    return $0.discNumber < $1.discNumber
                }
                if $0.trackNumber != $1.trackNumber {
                    return $0.trackNumber < $1.trackNumber
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            let year = sortedTracks.compactMap { $0.year }.first
            return AlbumGroup(
                title: first.album,
                albumArtist: first.albumArtist,
                year: year,
                songs: sortedTracks
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if albums.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(effectiveAccent)
                        Text("Sin álbumes aún")
                            .font(.headline)
                        Text("Importa tus canciones desde Biblioteca o Ajustes.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.top, 120)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(albums) { album in
                            NavigationLink(destination: AlbumDetailView(album: album)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Group {
                                        if let img = album.coverImage {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            ZStack {
                                                AppTheme.cardBackground
                                                Image(systemName: "opticaldisc")
                                                    .font(.system(size: 42))
                                                    .foregroundStyle(effectiveAccent)
                                            }
                                        }
                                    }
                                    .frame(height: 165)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))

                                    Text(album.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Text(album.albumArtist)
                                        if let year = album.year {
                                            Text("· \(year)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 90)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Álbumes")
        }
    }
}

struct AlbumDetailView: View {
    let album: AlbumGroup
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
            Section {
                HStack(spacing: 12) {
                    Button {
                        if let first = album.songs.first {
                            audioManager.isShuffle = false
                            audioManager.play(song: first, inQueue: album.songs)
                        }
                    } label: {
                        Label("Reproducir álbum", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(effectiveAccent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let random = album.songs.randomElement() {
                            audioManager.isShuffle = true
                            audioManager.play(song: random, inQueue: album.songs)
                        }
                    } label: {
                        Label("Aleatorio", systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(AppTheme.elevatedBackground)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }

            Section {
                ForEach(album.songs) { song in
                    let isCurrent = audioManager.currentSong?.fileURL == song.fileURL
                    HStack(spacing: 12) {
                        Text(song.trackNumber > 0 ? "\(song.trackNumber)" : "•")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(isCurrent ? effectiveAccent : AppTheme.secondaryText)
                            .frame(width: 22, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(isCurrent ? effectiveAccent : .white)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer()

                        if audioManager.hasLyrics(for: song) {
                            Image(systemName: "quote.bubble")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.play(song: song, inQueue: album.songs)
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle(album.title)
    }
}