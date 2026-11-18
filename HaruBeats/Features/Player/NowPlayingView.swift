import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Fondo ambiental derivado de la portada
            if let song = audioManager.currentSong, let uiImage = song.artworkImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 70)
                    .overlay(Color.black.opacity(0.55))
            } else {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.45), AppTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            if let song = audioManager.currentSong {
                VStack(spacing: 26) {
                    // Indicador superior para deslizar hacia abajo
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    Spacer()

                    // Portada grande
                    Group {
                        if let uiImage = song.artworkImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                AppTheme.cardBackground
                                Image(systemName: "waveform")
                                    .font(.system(size: 72))
                                    .foregroundStyle(.indigo)
                            }
                        }
                    }
                    .frame(width: 310, height: 310)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                    // Título, artista y álbum
                    VStack(spacing: 6) {
                        Text(song.title)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Text("\(song.artist) · \(song.album)")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 24)

                    // Barra de progreso
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { audioManager.currentTime },
                                set: { audioManager.seek(to: $0) }
                            ),
                            in: 0...max(audioManager.duration, 1)
                        )
                        .tint(.white)

                        HStack {
                            Text(formatTime(audioManager.currentTime))
                            Spacer()
                            Text(formatTime(audioManager.duration))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, 28)

                    // Controles principales
                    HStack(spacing: 34) {
                        Button {
                            audioManager.isShuffle.toggle()
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.title3)
                                .foregroundStyle(audioManager.isShuffle ? .indigo : .white.opacity(0.7))
                        }

                        Button {
                            audioManager.playPrevious()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }

                        Button {
                            audioManager.togglePlayPause()
                        } label: {
                            Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.white)
                        }

                        Button {
                            audioManager.playNext()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }

                        Button {
                            audioManager.isRepeatOne.toggle()
                        } label: {
                            Image(systemName: audioManager.isRepeatOne ? "repeat.1" : "repeat")
                                .font(.title3)
                                .foregroundStyle(audioManager.isRepeatOne ? .indigo : .white.opacity(0.7))
                        }
                    }

                    Spacer()
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN, seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}