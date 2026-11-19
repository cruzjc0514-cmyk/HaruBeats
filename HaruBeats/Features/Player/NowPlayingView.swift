import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @Environment(\.dismiss) private var dismiss

    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var showQueue = false
    @State private var showSleepTimerSheet = false
    @State private var showAddToPlaylistSheet = false

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                topBar

                if let song = audioManager.currentSong {
                    if showLyrics {
                        LyricsView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    } else {
                        artworkSection(for: song)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    }

                    songHeaderSection(for: song)

                    NowPlayingTimelineView(
                        progress: audioManager.progress,
                        audioManager: audioManager,
                        accentColor: effectiveAccent
                    )

                    mainControlsSection
                    bottomActionsBar(for: song)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerSheetView()
        }
        .sheet(isPresented: $showQueue) {
            QueueSheetView()
        }
        .sheet(isPresented: $showAddToPlaylistSheet) {
            if let song = audioManager.currentSong {
                PickPlaylistForSongSheet(song: song)
            }
        }
        .confirmationDialog("Temporizador de apagado", isPresented: $showSleepTimerSheet, titleVisibility: .visible) {
            Button("15 minutos") { audioManager.startSleepTimer(minutes: 15) }
            Button("30 minutos") { audioManager.startSleepTimer(minutes: 30) }
            Button("45 minutos") { audioManager.startSleepTimer(minutes: 45) }
            Button("60 minutos") { audioManager.startSleepTimer(minutes: 60) }
            Button("Al terminar esta canción") { audioManager.enableStopAfterCurrentSong() }
            if audioManager.sleepTimerRemaining != nil || audioManager.stopAfterCurrentSong {
                Button("Desactivar temporizador", role: .destructive) {
                    audioManager.cancelSleepTimer()
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                effectiveAccent.opacity(0.45),
                AppTheme.background,
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("REPRODUCIENDO")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
                if let song = audioManager.currentSong {
                    Text(song.album)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
            }
        }
    }

    private func artworkSection(for song: Song) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 4)
            Group {
                if let img = song.artworkImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        AppTheme.cardBackground
                        Image(systemName: "music.note")
                            .font(.system(size: 72))
                            .foregroundStyle(effectiveAccent)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 320, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .scaleEffect(audioManager.isPlaying ? 1.0 : 0.93)
            .shadow(color: effectiveAccent.opacity(0.35), radius: 24, y: 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: audioManager.isPlaying)

            HStack(spacing: 8) {
                Text(song.audioQualityBadge)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white.opacity(0.9))
                    .clipShape(Capsule())

                if audioManager.isReplayGainEnabled, let rg = song.replayGainDB {
                    Text(String(format: "RG %+.1f dB", rg))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(effectiveAccent.opacity(0.25))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            Spacer(minLength: 4)
        }
    }

    private func songHeaderSection(for song: Song) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                playlistManager.toggleFavorite(song: song)
            } label: {
                let isFav = playlistManager.isFavorite(song: song)
                Image(systemName: isFav ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(isFav ? effectiveAccent : .white.opacity(0.7))
            }

            Button {
                showAddToPlaylistSheet = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var mainControlsSection: some View {
        HStack(spacing: 30) {
            Button {
                audioManager.isShuffle.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(audioManager.isShuffle ? effectiveAccent : .white.opacity(0.65))
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
                ZStack {
                    Circle()
                        .fill(effectiveAccent)
                        .frame(width: 68, height: 68)
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .offset(x: audioManager.isPlaying ? 0 : 2)
                }
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
                Image(systemName: "repeat.1")
                    .font(.title3)
                    .foregroundStyle(audioManager.isRepeatOne ? effectiveAccent : .white.opacity(0.65))
            }
        }
        .padding(.vertical, 4)
    }

    private func bottomActionsBar(for song: Song) -> some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showLyrics.toggle()
                }
            } label: {
                let hasLyr = audioManager.songsWithLyrics.contains(song.relativePath)
                Label("Letra", systemImage: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(showLyrics ? effectiveAccent : (hasLyr ? Color.white.opacity(0.16) : Color.white.opacity(0.08)))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            Spacer()

            Button {
                showEqualizer = true
            } label: {
                Label("EQ", systemImage: "slider.vertical.3")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(audioManager.isEQEnabled ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            Spacer()

            Button {
                showSleepTimerSheet = true
            } label: {
                let activeTimer = audioManager.sleepTimerRemaining != nil || audioManager.stopAfterCurrentSong
                Label(sleepTimerLabel, systemImage: activeTimer ? "moon.zzz.fill" : "moon.zzz")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(activeTimer ? effectiveAccent.opacity(0.45) : Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }

    private var sleepTimerLabel: String {
        if audioManager.stopAfterCurrentSong {
            return "Fin pista"
        }
        if let rem = audioManager.sleepTimerRemaining {
            let mins = Int(ceil(rem / 60))
            return "\(mins)m"
        }
        return "Timer"
    }
}

private struct NowPlayingTimelineView: View {
    @ObservedObject var progress: PlaybackProgress
    @ObservedObject var audioManager: AudioPlayerManager
    let accentColor: Color

    @State private var dragTime: TimeInterval = 0

    var body: some View {
        let safeDuration = max(progress.duration, 1)
        let displayedTime = audioManager.isScrubbing ? dragTime : progress.currentTime

        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { min(max(displayedTime, 0), safeDuration) },
                    set: { newValue in
                        dragTime = newValue
                        if !audioManager.isScrubbing {
                            audioManager.isScrubbing = true
                        }
                    }
                ),
                in: 0...safeDuration,
                onEditingChanged: { editing in
                    if editing {
                        dragTime = progress.currentTime
                        audioManager.isScrubbing = true
                    } else {
                        audioManager.seek(to: dragTime)
                        audioManager.isScrubbing = false
                    }
                }
            )
            .tint(accentColor)

            HStack {
                Text(formatTime(displayedTime))
                Spacer()
                Text("-\(formatTime(max(progress.duration - displayedTime, 0)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}