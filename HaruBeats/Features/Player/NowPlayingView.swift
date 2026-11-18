import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @State private var dragProgress: Double? = nil
    @State private var showLyrics: Bool = false

    var body: some View {
        ZStack {
            // Fondo ambiental
            GeometryReader { geo in
                if let song = audioManager.currentSong, let uiImage = song.artworkImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 65)
                        .overlay(Color.black.opacity(showLyrics ? 0.72 : 0.55))
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.45), AppTheme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()

            if let song = audioManager.currentSong {
                VStack(spacing: 18) {
                    // Indicador superior y botón de letras
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 40, height: 5)
                        Spacer()
                    }
                    .overlay(alignment: .trailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showLyrics.toggle()
                            }
                        } label: {
                            Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                                .font(.title3)
                                .foregroundStyle(showLyrics ? .white : .white.opacity(0.75))
                                .padding(8)
                                .background(showLyrics ? Color.white.opacity(0.22) : Color.clear)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 24)
                    }
                    .padding(.top, 12)

                    if showLyrics {
                        // Vista compacta arriba + Letras sincronizadas
                        HStack(spacing: 12) {
                            Group {
                                if let uiImage = song.artworkImage {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    AppTheme.cardBackground
                                }
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 28)

                        LyricsView()
                            .frame(maxHeight: .infinity)
                    } else {
                        Spacer()

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
                        .frame(width: 295, height: 295)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

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

                        Spacer()
                    }

                    // Barra de progreso táctil
                    VStack(spacing: 8) {
                        let safeDuration = max(audioManager.duration, 1)
                        let currentRatio = dragProgress ?? min(max(audioManager.currentTime / safeDuration, 0), 1)

                        GeometryReader { barGeo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.22))
                                    .frame(height: dragProgress != nil ? 8 : 5)

                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: barGeo.size.width * currentRatio, height: dragProgress != nil ? 8 : 5)
                            }
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        audioManager.isScrubbing = true
                                        let ratio = min(max(value.location.x / barGeo.size.width, 0), 1)
                                        dragProgress = ratio
                                    }
                                    .onEnded { value in
                                        let ratio = min(max(value.location.x / barGeo.size.width, 0), 1)
                                        let targetTime = ratio * safeDuration
                                        audioManager.seek(to: targetTime)
                                        dragProgress = nil
                                        audioManager.isScrubbing = false
                                    }
                            )
                            .animation(.easeOut(duration: 0.12), value: dragProgress != nil)
                        }
                        .frame(height: 24)

                        HStack {
                            let displayedTime = (dragProgress != nil) ? (dragProgress! * safeDuration) : audioManager.currentTime
                            Text(formatTime(displayedTime))
                            Spacer()
                            Text("-\(formatTime(max(safeDuration - displayedTime, 0)))")
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
                    .padding(.bottom, 18)
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