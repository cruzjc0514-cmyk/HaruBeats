import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @StateObject private var wifiServer = WiFiTransferServer()

    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true

    @State private var showFolderImporter = false
    @State private var showM3U8Importer = false
    @State private var statusMessage: String? = nil

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        NavigationStack {
            Form {
                wifiSection
                importSection
                audioEngineSection
                appearanceSection
                statusSection
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Ajustes")
            .onAppear(perform: configureWiFiCallback)
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false,
                onCompletion: handleFolderImport
            )
            .fileImporter(
                isPresented: $showM3U8Importer,
                allowedContentTypes: [
                    UTType(filenameExtension: "m3u8") ?? .plainText,
                    UTType(filenameExtension: "m3u") ?? .plainText,
                    .plainText
                ],
                allowsMultipleSelection: false,
                onCompletion: handleM3U8Import
            )
        }
    }

    private var wifiSection: some View {
        Section("Transferencia Wi-Fi desde PC / Mac") {
            Toggle("Activar servidor Wi-Fi", isOn: Binding(
                get: { wifiServer.isRunning },
                set: { enabled in
                    if enabled {
                        wifiServer.start()
                    } else {
                        wifiServer.stop()
                    }
                }
            ))
            .tint(effectiveAccent)

            if wifiServer.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Abre esta dirección en el navegador de tu computadora:")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(wifiServer.serverURL)
                        .font(.headline.monospaced())
                        .foregroundStyle(effectiveAccent)
                        .textSelection(.enabled)

                    if !wifiServer.lastUploadedFile.isEmpty {
                        Text("Último recibido: \(wifiServer.lastUploadedFile)")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var importSection: some View {
        Section("Importación y Carpetas") {
            Button {
                showFolderImporter = true
            } label: {
                Label("Importar carpeta completa como playlist", systemImage: "folder.badge.plus")
            }

            Button {
                showM3U8Importer = true
            } label: {
                Label("Importar playlist .m3u / .m3u8", systemImage: "list.bullet.rectangle")
            }

            Button {
                Task {
                    let count = await audioManager.scanUSBSharedFiles()
                    statusMessage = count > 0
                        ? "Se importaron \(count) archivos desde iTunes / Finder."
                        : "No se encontraron archivos nuevos en la carpeta raíz."
                }
            } label: {
                Label("Escanear archivos compartidos por USB", systemImage: "cable.connector")
            }

            Button {
                Task {
                    await audioManager.loadStoredLibrary()
                    statusMessage = "Biblioteca reindexada (\(audioManager.library.count) canciones)."
                }
            } label: {
                Label("Reescanear biblioteca", systemImage: "arrow.clockwise")
            }
        }
    }

    private var audioEngineSection: some View {
        Section("Motor de Audio") {
            Toggle("Normalización ReplayGain", isOn: $audioManager.isReplayGainEnabled)
                .tint(effectiveAccent)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Crossfade entre pistas")
                    Spacer()
                    Text(crossfadeLabel)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Slider(value: $audioManager.crossfadeDuration, in: 0...8, step: 0.5)
                    .tint(effectiveAccent)
            }
        }
    }

    private var crossfadeLabel: String {
        if audioManager.crossfadeDuration == 0 {
            return "Apagado (Gapless)"
        }
        return String(format: "%.1f s", audioManager.crossfadeDuration)
    }

    private var appearanceSection: some View {
        Section("Apariencia") {
            Toggle("Color dinámico según carátula", isOn: $useDynamicColors)
                .tint(effectiveAccent)

            Picker("Color de acento base", selection: $accentRaw) {
                ForEach(AccentOption.allCases) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let statusMessage {
            Section {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(effectiveAccent)
            }
        }
    }

    private func configureWiFiCallback() {
        wifiServer.onFileReceived = { fileName, folderName, data in
            guard let saved = await audioManager.saveTransferredFile(
                fileName: fileName,
                folderName: folderName,
                data: data
            ) else { return }

            if let folderName, !folderName.isEmpty, let song = saved.song {
                playlistManager.addSongToNamedPlaylist(song: song, playlistName: folderName)
            }
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let folderURL = urls.first else { return }
        Task {
            let imported = await audioManager.importFolder(url: folderURL)
            if !imported.importedSongs.isEmpty {
                playlistManager.createOrAppendPlaylist(
                    name: imported.folderName,
                    songs: imported.importedSongs
                )
                statusMessage = "Carpeta '\(imported.folderName)' importada (\(imported.importedSongs.count) pistas)."
            } else {
                statusMessage = "No se encontraron audios compatibles en la carpeta."
            }
        }
    }

    private func handleM3U8Import(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let count = playlistManager.importM3U8(from: url, library: audioManager.library)
        statusMessage = "Playlist importada con \(count) canciones encontradas."
    }
}