import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @State private var dragProgress: Double? = nil
    @State private var showLyrics: Bool = false
    @State private var showEQSheet: Bool = false
    @State private var showQueueSheet: Bool = false

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        ZStack {
            // Fondo ambiental dinámico
            GeometryReader { geo in
                if let song = audioManager.currentSong, let uiImage = song.artworkImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 65)
                        .overlay(
                            LinearGradient(
                                colors: [
                                    effectiveAccent.opacity(useDynamicColors ? 0.32 : 0.12),
                                    Color.black.opacity(showLyrics ? 0.78 : 0.62)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [effectiveAccent.opacity(0.45), AppTheme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()

            if let song = audioManager.currentSong {
                VStack(spacing: 14) {
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 40, height: 5)
                        .padding(.top, 14)

                    if showLyrics {
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

                            lyricsToggleButton
                        }
                        .padding(.horizontal, 26)
                        .padding(.top, 4)

                        LyricsView()
                            .frame(maxHeight: .infinity)
                    } else {
                        HStack {
                            AudioVisualizerView(isPlaying: audioManager.isPlaying, accentColor: effectiveAccent)
                            Spacer()
                            lyricsToggleButton
                        }
                        .padding(.horizontal, 26)

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
                                        .foregroundStyle(effectiveAccent)
                                }
                            }
                        }
                        .frame(width: 280, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: effectiveAccent.opacity(0.35), radius: 24, y: 12)

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

                    // Barra de progreso fluida a 120 Hz
                    VStack(spacing: 6) {
                        let safeDuration = max(audioManager.duration, 1)

                        Slider(
                            value: Binding(
                                get: {
                                    dragProgress ?? min(max(audioManager.currentTime, 0), safeDuration)
                                },
                                set: { newValue in
                                    audioManager.isScrubbing = true
                                    dragProgress = newValue
                                }
                            ),
                            in: 0...safeDuration,
                            onEditingChanged: { editing in
                                if !editing {
                                    if let target = dragProgress {
                                        audioManager.seek(to: target)
                                    }
                                    dragProgress = nil
                                    audioManager.isScrubbing = false
                                }
                            }
                        )
                        .tint(.white)

                        HStack {
                            let displayedTime = dragProgress ?? audioManager.currentTime
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
                                .foregroundStyle(audioManager.isShuffle ? effectiveAccent : .white.opacity(0.7))
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
                                .font(.system(size: 70))
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
                                .foregroundStyle(audioManager.isRepeatOne ? effectiveAccent : .white.opacity(0.7))
                        }
                    }

                    // Herramientas inferiores: Ecualizador, Temporizador y Cola interactiva
                    HStack(spacing: 14) {
                        Button {
                            showEQSheet = true
                        } label: {
                            Label(audioManager.isEQEnabled ? audioManager.selectedPreset.rawValue : "EQ Off", systemImage: "slider.vertical.3")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.14))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }

                        Menu {
                            Button("15 minutos") { audioManager.startSleepTimer(minutes: 15) }
                            Button("30 minutos") { audioManager.startSleepTimer(minutes: 30) }
                            Button("45 minutos") { audioManager.startSleepTimer(minutes: 45) }
                            Button("60 minutos") { audioManager.startSleepTimer(minutes: 60) }
                            Button("Al terminar esta canción") { audioManager.enableStopAfterCurrentSong() }
                            if audioManager.sleepTimerRemaining != nil || audioManager.stopAfterCurrentSong {
                                Divider()
                                Button("Desactivar temporizador", role: .destructive) {
                                    audioManager.cancelSleepTimer()
                                }
                            }
                        } label: {
                            Label(sleepTimerLabel, systemImage: "moon.zzz.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isSleepTimerActive ? effectiveAccent.opacity(0.45) : Color.white.opacity(0.14))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }

                        Button {
                            showQueueSheet = true
                        } label: {
                            Label("Cola", systemImage: "list.bullet")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.14))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .sheet(isPresented: $showEQSheet) {
            EqualizerSheetView()
        }
        .sheet(isPresented: $showQueueSheet) {
            QueueSheetView()
        }
    }

    private var isSleepTimerActive: Bool {
        audioManager.sleepTimerRemaining != nil || audioManager.stopAfterCurrentSong
    }

    private var sleepTimerLabel: String {
        if audioManager.stopAfterCurrentSong { return "Fin pista" }
        if let rem = audioManager.sleepTimerRemaining {
            let mins = Int(rem) / 60
            let secs = Int(rem) % 60
            return String(format: "%d:%02d", mins, secs)
        }
        return "Timer"
    }

    private var lyricsToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showLyrics.toggle()
            }
        } label: {
            Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                .font(.body.weight(.semibold))
                .foregroundStyle(showLyrics ? .white : .white.opacity(0.85))
                .frame(width: 38, height: 38)
                .background(showLyrics ? effectiveAccent.opacity(0.45) : Color.white.opacity(0.12))
                .clipShape(Circle())
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN, seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}