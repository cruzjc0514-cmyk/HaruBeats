import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @State private var showLRCImporter = false

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var activeLineID: UUID? {
        let adjustedTime = audioManager.currentTime + audioManager.lyricsOffset
        return audioManager.currentLyrics.last(where: { $0.timestamp <= adjustedTime })?.id
    }

    var body: some View {
        VStack(spacing: 8) {
            if audioManager.currentLyrics.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 40))
                        .foregroundStyle(effectiveAccent)

                    Text("Sin letras sincronizadas")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Coloca un archivo .lrc con el mismo nombre junto a tu canción o selecciónalo manualmente.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Button {
                        showLRCImporter = true
                    } label: {
                        Label("Importar archivo .lrc", systemImage: "doc.text.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(effectiveAccent)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Barra discreta de sincronización en vivo y tamaño de letra
                HStack(spacing: 10) {
                    Button {
                        audioManager.adjustLyricsOffset(by: -0.5)
                    } label: {
                        Text("-0.5s")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.14))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Button {
                        audioManager.resetLyricsOffset()
                    } label: {
                        Text(String(format: "Sync %+.1fs", audioManager.lyricsOffset))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(audioManager.lyricsOffset == 0 ? Color.white.opacity(0.1) : effectiveAccent.opacity(0.45))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Button {
                        audioManager.adjustLyricsOffset(by: 0.5)
                    } label: {
                        Text("+0.5s")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.14))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Button {
                        audioManager.lyricsFontScale = max(0.85, audioManager.lyricsFontScale - 0.15)
                    } label: {
                        Text("A-")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.14))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Button {
                        audioManager.lyricsFontScale = min(1.45, audioManager.lyricsFontScale + 0.15)
                    } label: {
                        Text("A+")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.14))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            Spacer().frame(height: 16)

                            ForEach(audioManager.currentLyrics) { line in
                                let isActive = (line.id == activeLineID)
                                Text(line.text)
                                    .font(.system(
                                        size: (isActive ? 25 : 20) * audioManager.lyricsFontScale,
                                        weight: isActive ? .bold : .semibold,
                                        design: .rounded
                                    ))
                                    .foregroundStyle(isActive ? .white : Color.white.opacity(0.35))
                                    .scaleEffect(isActive ? 1.02 : 1.0, anchor: .leading)
                                    .animation(.easeOut(duration: 0.2), value: isActive)
                                    .id(line.id)
                                    .onTapGesture {
                                        audioManager.seek(to: max(line.timestamp - audioManager.lyricsOffset, 0))
                                    }
                            }

                            Spacer().frame(height: 120)
                        }
                        .padding(.horizontal, 28)
                    }
                    .onChange(of: activeLineID) { _, newID in
                        if let newID {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showLRCImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "lrc") ?? .plainText,
                .plainText,
                .data
            ],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                audioManager.attachManualLRC(from: url)
            }
        }
    }
}