import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct PrototypePlayerView: View {
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var trackName = "Ningún archivo cargado"
    @State private var statusMessage = "Selecciona un archivo FLAC para probar el motor"
    @State private var showFilePicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("HaruBeats")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("Prototipo 0 · Validación FLAC")
                    .font(.subheadline)
                    .foregroundStyle(.gray)

                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.indigo)

                    Text(trackName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 24)

                HStack(spacing: 24) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Abrir FLAC", systemImage: "folder.fill")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.indigo)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 54, height: 54)
                            .background(audioPlayer == nil ? Color.gray.opacity(0.3) : Color.white)
                            .foregroundStyle(.black)
                            .clipShape(Circle())
                    }
                    .disabled(audioPlayer == nil)
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let gotAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gotAccess { url.stopAccessingSecurityScopedResource() }
            }

            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)

                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: url, to: tempURL)

                audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()

                trackName = url.lastPathComponent
                isPlaying = true
                statusMessage = "Reproduciendo correctamente vía AVFoundation"
            } catch {
                statusMessage = "Error al reproducir: \(error.localizedDescription)"
                isPlaying = false
            }

        case .failure(let error):
            statusMessage = "Error al seleccionar archivo: \(error.localizedDescription)"
        }
    }

    private func togglePlayback() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
}