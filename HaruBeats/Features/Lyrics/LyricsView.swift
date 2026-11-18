import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @State private var showManualLRCImporter = false

    private var activeLineID: UUID? {
        guard !audioManager.currentLyrics.isEmpty else { return nil }
        let current = audioManager.currentTime + 0.15 // ligero adelanto visual
        return audioManager.currentLyrics.last(where: { $0.time <= current })?.id
            ?? audioManager.currentLyrics.first?.id
    }

    var body: some View {
        VStack {
            if audioManager.currentLyrics.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white.opacity(0.6))

                    Text("Sin letras sincronizadas")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Importa un archivo .lrc con el mismo nombre que la canción o vincúlalo manualmente aquí.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        showManualLRCImporter = true
                    } label: {
                        Label("Importar archivo .lrc", systemImage: "doc.text.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.18))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            Spacer().frame(height: 60)

                            ForEach(audioManager.currentLyrics) { line in
                                let isActive = (line.id == activeLineID)
                                Text(line.text)
                                    .font(isActive ? .title2.bold() : .title3.weight(.semibold))
                                    .foregroundStyle(isActive ? .white : .white.opacity(0.35))
                                    .scaleEffect(isActive ? 1.02 : 0.98, anchor: .leading)
                                    .animation(.easeInOut(duration: 0.25), value: isActive)
                                    .id(line.id)
                                    .onTapGesture {
                                        audioManager.seek(to: line.time)
                                    }
                            }

                            Spacer().frame(height: 120)
                        }
                        .padding(.horizontal, 28)
                    }
                    .onChange(of: activeLineID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.45)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showManualLRCImporter,
            allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                audioManager.attachManualLRC(from: url)
            }
        }
    }
}