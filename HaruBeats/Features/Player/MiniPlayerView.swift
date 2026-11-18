import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @Binding var showFullPlayer: Bool

    var body: some View {
        if let song = audioManager.currentSong {
            Button {
                showFullPlayer = true
            } label: {
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
                                    .foregroundStyle(.indigo)
                            }
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

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
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .background(AppTheme.cardBackground.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        }
    }
}