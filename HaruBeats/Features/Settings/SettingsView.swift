import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @StateObject private var wifiServer = WiFiTransferServer()
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @State private var usbMessage: String? = nil
    @State private var showEQSheet = false

    var body: some View {
        NavigationStack {
            List {
                // Sección 1: Apariencia y Ecualizador
                Section("Apariencia y Audio") {
                    Picker("Color de sistema", selection: $accentRaw) {
                        ForEach(AccentOption.allCases) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
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

                // Sección 2: Transferencia inalámbrica por Wi-Fi
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
                    .tint(.indigo)
                    .listRowBackground(AppTheme.cardBackground)

                    if wifiServer.isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Abre esta dirección en el navegador de tu PC:")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)

                            Text(wifiServer.serverURL)
                                .font(.headline.monospaced())
                                .foregroundStyle(.indigo)
                                .textSelection(.enabled)

                            HStack {
                                Text(wifiServer.statusLog)
                                Spacer()
                                Text("Recibidos: \(wifiServer.transferredCount)")
                            }
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(AppTheme.cardBackground)
                    }
                } header: {
                    Text("Transferencia por Wi-Fi")
                } footer: {
                    Text("Mantén HaruBeats abierto mientras transfieres carpetas o canciones desde Windows 11.")
                }

                // Sección 3: Transferencia por cable USB
                Section {
                    Button {
                        Task {
                            let count = await audioManager.scanUSBSharedFiles()
                            if count > 0 {
                                usbMessage = "Se importaron \(count) archivos transferidos por cable USB."
                            } else {
                                usbMessage = "No se encontraron archivos nuevos en la carpeta compartida por USB. En Windows, abre iTunes → tu iPhone → Compartir archivos → HaruBeats y arrastra tus canciones ahí."
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

                // Sección 4: Resumen de biblioteca
                Section("Colección local") {
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