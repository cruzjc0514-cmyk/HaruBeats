import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @Binding var showFullPlayer: Bool

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        if let song = audioManager.currentSong {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Group {
                        if let uiImage = song.artworkImage {
                            Image(uiImage: uiImage)
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
                        Text(song.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        audioManager.togglePlayPause()
                    } label: {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }

                    Button {
                        audioManager.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                // Barra de progreso fina con el color dinámico de la portada
                GeometryReader { geo in
                    let progress = audioManager.duration > 0 ? min(max(audioManager.currentTime / audioManager.duration, 0), 1) : 0
                    Rectangle()
                        .fill(effectiveAccent)
                        .frame(width: geo.size.width * progress, height: 2.5)
                }
                .frame(height: 2.5)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(effectiveAccent.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .onTapGesture {
                showFullPlayer = true
            }
        }
    }
}