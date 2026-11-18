import SwiftUI

struct HomeView: View {
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Tarjeta principal de colección
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tu colección local")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(audioManager.library.count) canciones disponibles sin conexión")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)

                        if !audioManager.library.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    if let first = audioManager.library.first {
                                        audioManager.isShuffle = false
                                        audioManager.play(song: first, inQueue: audioManager.library)
                                    }
                                } label: {
                                    Label("Reproducir todo", systemImage: "play.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(effectiveAccent)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }

                                Button {
                                    if let random = audioManager.library.randomElement() {
                                        audioManager.isShuffle = true
                                        audioManager.play(song: random, inQueue: audioManager.library)
                                    }
                                } label: {
                                    Label("Aleatorio", systemImage: "shuffle")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(AppTheme.elevatedBackground)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    // Escuchadas recientemente (historial real)
                    if !audioManager.recentSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Escuchadas recientemente")
                                .font(.title3.bold())
                                .foregroundStyle(.white)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(audioManager.recentSongs.prefix(12)) { song in
                                        Button {
                                            audioManager.play(song: song, inQueue: audioManager.recentSongs)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Group {
                                                    if let img = song.artworkImage {
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
                                                .frame(width: 120, height: 120)
                                                .clipShape(RoundedRectangle(cornerRadius: 14))

                                                Text(song.title)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)

                                                Text(song.artist)
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.secondaryText)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 120, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Tus más escuchadas (estadísticas de reproducción)
                    if !audioManager.topPlayedSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tus más escuchadas")
                                .font(.title3.bold())
                                .foregroundStyle(.white)

                            ForEach(Array(audioManager.topPlayedSongs.prefix(5).enumerated()), id: \.element.song.id) { index, item in
                                HStack(spacing: 12) {
                                    Text("#\(index + 1)")
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundStyle(effectiveAccent)
                                        .frame(width: 26, alignment: .leading)

                                    Group {
                                        if let img = item.song.artworkImage {
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
                                        Text(item.song.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(item.song.artist)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text("\(item.count)x")
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.elevatedBackground)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .clipShape(Capsule())
                                }
                                .padding(10)
                                .background(AppTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onTapGesture {
                                    let topQueue = audioManager.topPlayedSongs.map { $0.song }
                                    audioManager.play(song: item.song, inQueue: topQueue)
                                }
                            }
                        }
                    }

                    // Agregadas recientemente
                    if !audioManager.library.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("En tu biblioteca")
                                .font(.title3.bold())
                                .foregroundStyle(.white)

                            ForEach(audioManager.library.prefix(8)) { song in
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
                                                    .foregroundStyle(effectiveAccent)
                                            }
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(song.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(song.artist)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(AppTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onTapGesture {
                                    audioManager.play(song: song, inQueue: audioManager.library)
                                }
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 90)
            }
            .background(AppTheme.background)
            .navigationTitle("HaruBeats")
        }
    }
}