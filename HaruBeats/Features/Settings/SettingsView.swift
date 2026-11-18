import SwiftUI
import CoreImage.CIFilterBuiltins

struct SettingsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @StateObject private var wifiServer = WiFiTransferServer()
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @State private var usbMessage: String? = nil
    @State private var showEQSheet = false

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Apariencia y Audio") {
                    Toggle(isOn: $useDynamicColors) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Color dinámico de portada")
                                .foregroundStyle(.white)
                            Text("Adapta la interfaz al color del álbum actual")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .tint(effectiveAccent)
                    .listRowBackground(AppTheme.cardBackground)

                    Picker("Color de sistema", selection: $accentRaw) {
                        ForEach(AccentOption.allCases) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                    .listRowBackground(AppTheme.cardBackground)

                    Picker("Transición entre canciones", selection: $audioManager.crossfadeDuration) {
                        Text("Gapless (Sin pausas)").tag(0.0)
                        Text("Crossfade 2 s").tag(2.0)
                        Text("Crossfade 4 s").tag(4.0)
                        Text("Crossfade 6 s").tag(6.0)
                    }
                    .listRowBackground(AppTheme.cardBackground)

                    Toggle(isOn: $audioManager.isReplayGainEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Normalización ReplayGain")
                                .foregroundStyle(.white)
                            Text("Nivela el volumen según las etiquetas FLAC")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .tint(effectiveAccent)
                    .listRowBackground(AppTheme.cardBackground)

                    Button {
                        showEQSheet = true
                    } label: {
                        HStack {
                            Label("Ecualizador de 5 bandas", systemImage: "slider.vertical.3")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(audioManager.isEQEnabled ? audioManager.selectedPreset.rawValue : "Desactivado")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { wifiServer.isRunning },
                        set: { shouldRun in
                            if shouldRun {
                                configureServerCallback()
                                wifiServer.start()
                            } else {
                                wifiServer.stop()
                            }
                        }
                    )) {
                        Label("Servidor Wi-Fi", systemImage: "wifi")
                            .foregroundStyle(.white)
                    }
                    .tint(effectiveAccent)
                    .listRowBackground(AppTheme.cardBackground)

                    Toggle(isOn: $wifiServer.isPinEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Proteger con PIN de 4 dígitos")
                                .foregroundStyle(.white)
                            if wifiServer.isPinEnabled {
                                Text("PIN activo: \(wifiServer.pinCode.isEmpty ? "Se generará al iniciar" : wifiServer.pinCode)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(effectiveAccent)
                            }
                        }
                    }
                    .tint(effectiveAccent)
                    .listRowBackground(AppTheme.cardBackground)

                    if wifiServer.isRunning {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Abre esta dirección en el navegador de tu PC o escanea el código:")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)

                            HStack(spacing: 14) {
                                if let qr = generateQRCode(from: wifiServer.serverURL) {
                                    Image(uiImage: qr)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 86, height: 86)
                                        .padding(6)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(wifiServer.serverURL)
                                        .font(.subheadline.monospaced().bold())
                                        .foregroundStyle(effectiveAccent)
                                        .textSelection(.enabled)

                                    if wifiServer.isPinEnabled {
                                        Text("PIN: \(wifiServer.pinCode)")
                                            .font(.caption.monospaced().bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(effectiveAccent.opacity(0.22))
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                    }

                                    Text("Recibidos: \(wifiServer.transferredCount)")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }

                            Text(wifiServer.statusLog)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(AppTheme.cardBackground)
                    }
                } header: {
                    Text("Transferencia por Wi-Fi")
                } footer: {
                    Text("Mientras el servidor esté activo, la pantalla del iPhone permanecerá encendida para evitar interrupciones.")
                }

                Section {
                    Button {
                        Task {
                            let count = await audioManager.scanUSBSharedFiles()
                            if count > 0 {
                                usbMessage = "Se importaron \(count) archivos transferidos por cable USB."
                            } else {
                                usbMessage = "No se encontraron archivos nuevos en la carpeta compartida por USB. En Windows, abre iTunes o Dispositivos Apple → tu iPhone → Compartir archivos → HaruBeats y arrastra tus canciones ahí."
                            }
                        }
                    } label: {
                        Label("Escanear archivos pasados por USB", systemImage: "cable.connector")
                            .foregroundStyle(.white)
                    }
                    .listRowBackground(AppTheme.cardBackground)
                } header: {
                    Text("Transferencia por cable USB")
                }

                Section("Colección y estadísticas") {
                    HStack {
                        Text("Canciones almacenadas")
                        Spacer()
                        Text("\(audioManager.library.count)")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .listRowBackground(AppTheme.cardBackground)

                    HStack {
                        Text("Playlists guardadas")
                        Spacer()
                        Text("\(playlistManager.playlists.count)")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .listRowBackground(AppTheme.cardBackground)

                    HStack {
                        Text("Reproducciones totales")
                        Spacer()
                        Text("\(audioManager.playCounts.values.reduce(0, +))")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Ajustes")
            .sheet(isPresented: $showEQSheet) {
                EqualizerSheetView()
            }
            .alert("Transferencia USB", isPresented: Binding(
                get: { usbMessage != nil },
                set: { if !$0 { usbMessage = nil } }
            )) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text(usbMessage ?? "")
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgimg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgimg)
    }

    private func configureServerCallback() {
        wifiServer.onFileReceived = { fileName, folderName, data in
            guard let saved = await audioManager.saveTransferredFile(fileName: fileName, data: data) else { return }

            if fileName.lowercased().hasSuffix(".m3u8") || fileName.lowercased().hasSuffix(".m3u") {
                let result = M3U8Parser.parseAndResolve(url: saved.destination, library: audioManager.library)
                playlistManager.createPlaylist(name: result.playlistName, songs: result.matchedSongs)
                return
            }

            if let folderName, !folderName.isEmpty, let song = saved.song {
                if let existing = playlistManager.playlists.first(where: { $0.name == folderName }) {
                    playlistManager.addSongs([song], to: existing.id)
                } else {
                    playlistManager.createPlaylist(name: folderName, songs: [song])
                }
            }
        }
    }
}