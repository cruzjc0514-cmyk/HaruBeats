import SwiftUI
import UIKit

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @Binding var showFullPlayer: Bool
    @State private var dragOffset: CGSize = .zero

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
                        if let uiImage = song.thumbnailImage {
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
                        triggerHaptic(.light)
                        audioManager.togglePlayPause()
                    } label: {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }

                    Button {
                        triggerHaptic(.light)
                        audioManager.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                GeometryReader { geo in
                    let progress = audioManager.duration > 0 ? min(max(audioManager.currentTime / audioManager.duration, 0), 1) : 0
                    Rectangle()
                        .fill(effectiveAccent)
                        .frame(width: geo.size.width * progress, height: 2.5)
                }
                .frame(height: 2.5)
            }
            .background(
                ZStack {
                    AppTheme.cardBackground
                    if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
                        dynamic.opacity(0.18)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(effectiveAccent.opacity(0.28), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .padding(.horizontal, 12)
            .offset(x: dragOffset.width * 0.25, y: min(0, dragOffset.height * 0.2))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Reproduciendo \(song.title) de \(song.artist)")
            .accessibilityHint("Toca o desliza hacia arriba para abrir el reproductor. Desliza a izquierda o derecha para cambiar de canción.")
            .onTapGesture {
                triggerHaptic(.soft)
                showFullPlayer = true
            }
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                        if dy < -35 && abs(dy) > abs(dx) {
                            triggerHaptic(.medium)
                            showFullPlayer = true
                        } else if dx < -55 && abs(dx) > abs(dy) {
                            triggerHaptic(.light)
                            audioManager.playNext()
                        } else if dx > 55 && abs(dx) > abs(dy) {
                            triggerHaptic(.light)
                            audioManager.playPrevious()
                        }
                    }
            )
        }
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}