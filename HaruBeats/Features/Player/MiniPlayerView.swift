import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @Binding var showNowPlaying: Bool

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
                    artworkView(for: song)
                    songInfoView(for: song)
                    Spacer(minLength: 4)
                    playbackButtonsView
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                MiniPlayerProgressBar(
                    progress: audioManager.progress,
                    accentColor: effectiveAccent
                )
            }
            .background(.ultraThinMaterial)
            .background(AppTheme.elevatedBackground.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .contentShape(Rectangle())
            .onTapGesture {
                showNowPlaying = true
            }
        }
    }

    private func artworkView(for song: Song) -> some View {
        Group {
            if let img = song.thumbnailImage {
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
    }

    private func songInfoView(for song: Song) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(song.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 5) {
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)

                if song.isHiRes {
                    Text(song.codec)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(effectiveAccent.opacity(0.25))
                        .foregroundStyle(effectiveAccent)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var playbackButtonsView: some View {
        HStack(spacing: 14) {
            Button {
                audioManager.togglePlayPause()
            } label: {
                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button {
                audioManager.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct MiniPlayerProgressBar: View {
    @ObservedObject var progress: PlaybackProgress
    let accentColor: Color

    var body: some View {
        let ratio = progress.duration > 0 ? min(max(progress.currentTime / progress.duration, 0), 1) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                Rectangle()
                    .fill(accentColor)
                    .frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: 2.5)
    }
}