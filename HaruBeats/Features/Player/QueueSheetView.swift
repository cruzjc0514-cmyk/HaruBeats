import SwiftUI

struct QueueSheetView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @Environment(\.dismiss) private var dismiss

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("A continuación")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("\(audioManager.playbackQueue.count) canciones en cola")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                EditButton()
                    .foregroundStyle(effectiveAccent)
                Button("Listo") {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(effectiveAccent)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            List {
                ForEach(audioManager.playbackQueue) { song in
                    let isCurrent = audioManager.currentSong?.fileURL == song.fileURL
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
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.body.weight(isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? effectiveAccent : .white)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer()

                        if isCurrent {
                            Image(systemName: "waveform")
                                .foregroundStyle(effectiveAccent)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.play(song: song, inQueue: audioManager.playbackQueue)
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }
                .onMove { source, destination in
                    audioManager.moveInQueue(from: source, to: destination)
                }
                .onDelete { offsets in
                    audioManager.removeFromQueue(at: offsets)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}